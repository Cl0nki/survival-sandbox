"""Modular clothing slot detection and naming helpers."""

from __future__ import annotations

import json
from pathlib import Path

from processors.gltf_write import read_glb_json


def load_clothing_slots(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _mesh_names_from_glb(glb_path: Path) -> list[str]:
    if not glb_path.is_file():
        return []
    try:
        document = read_glb_json(glb_path)
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        return []
    names = []
    for node in document.get("nodes") or []:
        name = str(node.get("name") or "").strip()
        if name and "mesh" in node:
            names.append(name)
    for mesh in document.get("meshes") or []:
        name = str(mesh.get("name") or "").strip()
        if name:
            names.append(name)
    return list(dict.fromkeys(names))


def match_slots(mesh_names: list[str], slots_config: dict) -> dict:
    slots = slots_config.get("slots") or {}
    matched = {}
    unused = list(mesh_names)
    for slot_name, meta in slots.items():
        aliases = [str(item).lower() for item in (meta.get("mesh_names") or [])]
        found = None
        for candidate in list(unused):
            if candidate.lower() in aliases:
                found = candidate
                unused.remove(candidate)
                break
        if found is None:
            for candidate in list(unused):
                lowered = candidate.lower()
                if any(alias in lowered for alias in aliases):
                    found = candidate
                    unused.remove(candidate)
                    break
        matched[slot_name] = {
            "mesh_name": found,
            "present": found is not None,
            "required": bool(meta.get("required")),
            "attach_bone": meta.get("attach_bone") or "",
        }
    return {"slots": matched, "unmatched_meshes": unused}


def analyze_clothing_glb(glb_path: Path, slots_config: dict) -> dict:
    names = _mesh_names_from_glb(glb_path)
    result = match_slots(names, slots_config)
    missing_required = [
        name
        for name, meta in result["slots"].items()
        if meta.get("required") and not meta.get("present")
    ]
    equipment = {
        name: meta
        for name, meta in result["slots"].items()
        if name != "body" and meta.get("present")
    }
    result["mesh_names"] = names
    result["missing_required"] = missing_required
    result["equipment_slots"] = equipment
    result["ok"] = not missing_required
    return result


def clothing_export_plan(analysis: dict, output_dir: Path) -> list[dict]:
    plan = []
    for slot_name, meta in (analysis.get("slots") or {}).items():
        if not meta.get("present"):
            continue
        plan.append(
            {
                "slot": slot_name,
                "mesh_name": meta["mesh_name"],
                "output": str((output_dir / f"{slot_name}.glb").as_posix()),
                "attach_bone": meta.get("attach_bone") or "",
            }
        )
    return plan
