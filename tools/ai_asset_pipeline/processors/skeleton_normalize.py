"""Rename Meshy/Mixamo-style bones to the Godot humanoid profile inside a GLB."""

from __future__ import annotations

import json
import struct
from pathlib import Path

from processors.gltf_write import read_glb_json


def load_skeleton_profile(path: Path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _normalize_key(name: str) -> str:
    return "".join(ch for ch in (name or "").lower() if ch.isalnum())


def mapped_bone_name(name: str, rename_map: dict) -> str | None:
    key = _normalize_key(name)
    if not key:
        return None
    if key in rename_map:
        return rename_map[key]
    if name in set(rename_map.values()):
        return name
    return None


def plan_renames(joint_names: list[str], profile: dict) -> dict:
    rename_map = profile.get("rename_map") or {}
    planned = {}
    used = set()
    for name in joint_names:
        target = mapped_bone_name(name, rename_map)
        if not target:
            continue
        if target in used and planned.get(name) != target:
            continue
        planned[name] = target
        used.add(target)
    required = list(profile.get("required_bones") or [])
    present = {planned.get(name, name) for name in joint_names}
    present.update(planned.values())
    missing = [bone for bone in required if bone not in present]
    return {"renames": planned, "missing_required": missing, "present": sorted(present)}


def _split_glb(raw: bytes) -> tuple[dict, bytes]:
    if raw[:4] != b"glTF":
        raise ValueError("Not a GLB file.")
    offset = 12
    document = None
    bin_chunk = b""
    while offset + 8 <= len(raw):
        length, ctype = struct.unpack_from("<I4s", raw, offset)
        offset += 8
        payload = raw[offset : offset + length]
        offset += length
        if ctype == b"JSON":
            document = json.loads(payload.decode("utf-8"))
        elif ctype == b"BIN\x00":
            bin_chunk = struct.pack("<I4s", length, b"BIN\x00") + payload
    if document is None:
        raise ValueError("GLB has no JSON chunk.")
    return document, bin_chunk


def _write_glb(destination: Path, document: dict, bin_chunk: bytes) -> None:
    encoded = json.dumps(document, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    pad = (4 - (len(encoded) % 4)) % 4
    encoded = encoded + (b" " * pad)
    total = 12 + 8 + len(encoded) + len(bin_chunk)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(encoded), b"JSON")
    out += encoded
    out += bin_chunk
    Path(destination).parent.mkdir(parents=True, exist_ok=True)
    Path(destination).write_bytes(bytes(out))


def normalize_glb_skeleton(source: Path, destination: Path, profile: dict) -> dict:
    raw = Path(source).read_bytes()
    document, bin_chunk = _split_glb(raw)
    nodes = document.get("nodes") or []
    joint_names = []
    for skin in document.get("skins") or []:
        for joint in skin.get("joints") or []:
            if 0 <= joint < len(nodes):
                joint_names.append(nodes[joint].get("name", f"joint_{joint}"))
    plan = plan_renames(joint_names, profile)
    renamed = 0
    for node in nodes:
        old = node.get("name", "")
        new = plan["renames"].get(old)
        if new and new != old:
            node["name"] = new
            renamed += 1
    aliases = profile.get("animation_aliases") or {}
    clip_renames = {}
    for anim in document.get("animations") or []:
        current = str(anim.get("name") or "")
        lowered = current.lower()
        matched = None
        for standard, patterns in aliases.items():
            for pattern in patterns:
                token = pattern.lower()
                if token and token in lowered:
                    matched = standard
                    break
            if matched:
                break
        if matched:
            anim["name"] = matched
            clip_renames[current] = matched
    _write_glb(Path(destination), document, bin_chunk)
    report = inspect_after(Path(destination))
    return {
        "ok": len(plan["missing_required"]) == 0,
        "renamed_bones": renamed,
        "renames": plan["renames"],
        "missing_required": plan["missing_required"],
        "clip_renames": clip_renames,
        "report": report,
    }


def inspect_after(path: Path) -> dict:
    from processors.validate import inspect_glb

    return inspect_glb(path)


def required_coverage(joint_names: list[str], profile: dict) -> dict:
    plan = plan_renames(joint_names, profile)
    required = list(profile.get("required_bones") or [])
    present = set(plan["present"])
    return {
        "matched": [bone for bone in required if bone in present],
        "missing": [bone for bone in required if bone not in present],
        "renames": plan["renames"],
    }
