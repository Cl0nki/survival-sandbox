"""Shared humanoid animation library index and AnimationTree wiring helpers."""

from __future__ import annotations

import json
from pathlib import Path

from core.settings import PIPELINE_ROOT, PROJECT_ROOT


def load_meshy_actions(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_shared_animation_library(path: Path | None = None) -> dict:
    target = path or (PIPELINE_ROOT / "config" / "shared_animation_library.json")
    if not target.is_file():
        return {}
    return json.loads(target.read_text(encoding="utf-8"))


def clip_set(actions: dict, set_name: str | None = None) -> dict:
    name = set_name or actions.get("default_set") or "locomotion_basic"
    sets = actions.get("sets") or {}
    block = sets.get(name) or {}
    return dict(block.get("clips") or {})


def shared_clip_name(clip_key: str, clip_meta: dict) -> str:
    return str(clip_meta.get("shared_name") or clip_key)


def resolve_shared_library(project_root: Path | None = None, config: dict | None = None) -> dict | None:
    """Return Quaternius (or configured) shared library info if the GLB is present."""
    cfg = config if config is not None else load_shared_animation_library()
    if not cfg:
        return None
    root = project_root or PROJECT_ROOT
    relative = str(cfg.get("path") or "").strip()
    if not relative:
        return None
    glb = root / relative
    if not glb.is_file():
        return None
    clips = dict(cfg.get("clips") or {})
    return {
        "config": cfg,
        "path": glb,
        "relative": relative.replace("\\", "/"),
        "res_path": f"res://{relative.replace(chr(92), '/')}",
        "library_name": str(cfg.get("library_name") or ""),
        "clips": clips,
        "logical_names": list(clips.keys()),
        "animation_names": list(clips.values()),
        "bone_map": str(cfg.get("bone_map") or ""),
        "character_bone_map": str(cfg.get("character_bone_map") or ""),
        "fix_silhouette": bool(cfg.get("fix_silhouette_on_characters", True)),
        "animation_tree": cfg.get("animation_tree") or {},
    }


def animation_ref(library_name: str, clip_name: str) -> str:
    if library_name:
        return f"{library_name}/{clip_name}"
    return clip_name


def update_library_index(index_path: Path, clips: dict[str, dict], skeleton_profile: str = "godot_humanoid") -> dict:
    existing = {}
    if index_path.is_file():
        try:
            existing = json.loads(index_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            existing = {}
    payload = {
        "skeleton_profile": skeleton_profile or existing.get("skeleton_profile", "godot_humanoid"),
        "clips": dict(existing.get("clips") or {}),
        "shared_library": existing.get("shared_library"),
    }
    for name, meta in clips.items():
        payload["clips"][name] = {
            **(payload["clips"].get(name) or {}),
            **meta,
        }
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def write_quaternius_library_index(project_root: Path, shared: dict | None = None) -> Path:
    shared = shared or resolve_shared_library(project_root)
    index_path = project_root / "assets" / "characters" / "Shared" / "library_index.json"
    if not shared:
        return index_path
    clips = {}
    for logical, anim_name in (shared.get("clips") or {}).items():
        clips[logical] = {
            "path": shared["relative"],
            "animation": anim_name,
            "source": "quaternius",
            "provider": "quaternius",
        }
    payload = update_library_index(index_path, clips, skeleton_profile="godot_humanoid")
    payload["shared_library"] = {
        "provider": "quaternius",
        "path": shared["relative"],
        "bone_map": shared.get("bone_map") or "",
        "character_bone_map": shared.get("character_bone_map") or "",
        "clips": shared.get("clips") or {},
    }
    index_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return index_path


def animation_tree_lines(actions: dict, clip_names: list[str], *, animation_names: dict[str, str] | None = None, library_name: str = "") -> list[str]:
    """Emit Godot 4 AnimationTree subresources for locomotion (1D or 2D blend)."""
    tree = (actions or {}).get("animation_tree") or {}
    tree_type = str(tree.get("type") or "blend_space_1d")
    aliases = animation_names or {}
    if tree_type == "blend_space_2d":
        return _animation_tree_lines_2d(tree, clip_names, aliases=aliases, library_name=library_name)
    points = tree.get("points") or {"idle": 0.0, "walk": 1.0, "run": 2.0}
    available = [name for name in ("idle", "walk", "run") if name in clip_names or name in aliases]
    if not available:
        available = list(clip_names)[:3]
    if not available and aliases:
        available = [name for name in ("idle", "walk", "run") if name in aliases]
    if not available:
        return [
            '[node name="AnimationTree" type="AnimationTree" parent="."]',
            'anim_player = NodePath("../AnimationPlayer")',
            "active = false",
            "",
        ]
    lines: list[str] = []
    for name in available:
        anim = aliases.get(name) or name
        ref = animation_ref(library_name, anim)
        lines.append(f'[sub_resource type="AnimationNodeAnimation" id="anim_{name}"]')
        lines.append(f'animation = &"{ref}"')
        lines.append("")
    lines.append('[sub_resource type="AnimationNodeBlendSpace1D" id="blend_loco"]')
    for index, name in enumerate(available):
        pos = float(points.get(name, float(index)))
        lines.append(f'blend_point_{index}/node = SubResource("anim_{name}")')
        lines.append(f"blend_point_{index}/pos = {pos}")
    lines.append("min_space = 0.0")
    lines.append("max_space = 2.0")
    lines.append("")
    lines.append('[sub_resource type="AnimationNodeBlendTree" id="tree_root"]')
    lines.append("graph_offset = Vector2(-80, -40)")
    lines.append("nodes/output/position = Vector2(400, 0)")
    lines.append('nodes/loco/node = SubResource("blend_loco")')
    lines.append("nodes/loco/position = Vector2(140, 0)")
    lines.append('node_connections = [&"output", 0, &"loco"]')
    lines.append("")
    lines.append('[node name="AnimationTree" type="AnimationTree" parent="."]')
    lines.append('tree_root = SubResource("tree_root")')
    lines.append('anim_player = NodePath("../AnimationPlayer")')
    lines.append("active = true")
    lines.append("parameters/loco/blend_position = 0.0")
    lines.append("")
    return lines


def _animation_tree_lines_2d(tree: dict, clip_names: list[str], *, aliases: dict[str, str], library_name: str) -> list[str]:
    """Aim-facing locomotion BlendSpace2D: idle + fwd/bwd/strafe."""
    points = tree.get("points") or {
        "idle": [0.0, 0.0],
        "walk": [0.0, 1.0],
        "walk_bwd": [0.0, -1.0],
        "walk_l": [-1.0, 0.0],
        "walk_r": [1.0, 0.0],
    }
    order = ("idle", "walk", "walk_bwd", "walk_l", "walk_r")
    available = [name for name in order if name in clip_names or name in aliases or name in points]
    if "idle" not in available and ("idle" in aliases or "Idle" in aliases.values()):
        available.insert(0, "idle")
    if not available:
        available = [name for name in order if name in aliases]
    if not available:
        return [
            '[node name="AnimationTree" type="AnimationTree" parent="."]',
            'anim_player = NodePath("../AnimationPlayer")',
            "active = false",
            "",
        ]
    lines: list[str] = []
    for name in available:
        anim = aliases.get(name) or name
        ref = animation_ref(library_name, anim)
        lines.append(f'[sub_resource type="AnimationNodeAnimation" id="anim_{name}"]')
        lines.append(f'animation = &"{ref}"')
        lines.append("")
    lines.append('[sub_resource type="AnimationNodeBlendSpace2D" id="blend_loco"]')
    for index, name in enumerate(available):
        raw = points.get(name, [0.0, 0.0])
        if isinstance(raw, (list, tuple)) and len(raw) >= 2:
            x, y = float(raw[0]), float(raw[1])
        else:
            x, y = 0.0, float(raw)
        lines.append(f'blend_point_{index}/node = SubResource("anim_{name}")')
        lines.append(f"blend_point_{index}/pos = Vector2({x}, {y})")
    lines.append("min_space = Vector2(-1, -1)")
    lines.append("max_space = Vector2(1, 1)")
    lines.append("")
    lines.append('[sub_resource type="AnimationNodeBlendTree" id="tree_root"]')
    lines.append("graph_offset = Vector2(-80, -40)")
    lines.append("nodes/output/position = Vector2(400, 0)")
    lines.append('nodes/loco/node = SubResource("blend_loco")')
    lines.append("nodes/loco/position = Vector2(140, 0)")
    lines.append('node_connections = [&"output", 0, &"loco"]')
    lines.append("")
    lines.append('[node name="AnimationTree" type="AnimationTree" parent="."]')
    lines.append('tree_root = SubResource("tree_root")')
    lines.append('anim_player = NodePath("../AnimationPlayer")')
    lines.append("active = true")
    lines.append("parameters/loco/blend_position = Vector2(0, 0)")
    lines.append("")
    return lines


def relative_project_path(project_root: Path, file_path: Path) -> str:
    return file_path.resolve().relative_to(project_root.resolve()).as_posix()
