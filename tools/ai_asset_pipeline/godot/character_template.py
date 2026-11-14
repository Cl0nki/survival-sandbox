"""Write a reusable Godot 4 character scene around an approved humanoid GLB."""

from __future__ import annotations

import json
from pathlib import Path

from godot.animation_library import animation_tree_lines, resolve_shared_library


def _res_path(project_root: Path, file_path: Path) -> str:
    relative = file_path.resolve().relative_to(project_root.resolve()).as_posix()
    return f"res://{relative}"


def write_character_scene(
    path: Path,
    node_name: str,
    glb_path: Path,
    project_root: Path,
    profile: dict | None = None,
    *,
    actions: dict | None = None,
    clip_names: list[str] | None = None,
    equipment_slots: dict | None = None,
    shared_library: dict | None = None,
) -> None:
    attachments = (profile or {}).get("attachment_points") or {
        "PrimaryWeapon": {"bone": "RightHand"},
        "SecondaryWeapon": {"bone": "LeftHand"},
        "Backpack": {"bone": "Chest"},
        "HeadEquipment": {"bone": "Head"},
        "HandEquipment": {"bone": "RightHand"},
    }
    shared = shared_library if shared_library is not None else resolve_shared_library(project_root)
    aliases = dict((shared or {}).get("clips") or {})
    clips = list(clip_names or [])
    if shared and not clips:
        clips = list(shared.get("logical_names") or aliases.keys())
    tree_cfg = actions or {}
    if shared and shared.get("animation_tree"):
        tree_cfg = {**(actions or {}), "animation_tree": shared["animation_tree"]}
    library_name = str((shared or {}).get("library_name") or "")
    tree_lines = animation_tree_lines(
        tree_cfg,
        clips,
        animation_names=aliases or None,
        library_name=library_name,
    )
    sub_lines: list[str] = []
    tree_node_lines: list[str] = []
    saw_tree_node = False
    for line in tree_lines:
        if line.startswith('[node name="AnimationTree"'):
            saw_tree_node = True
        if saw_tree_node:
            tree_node_lines.append(line)
        else:
            sub_lines.append(line)

    ext_resources = [
        f'[ext_resource type="PackedScene" path="{_res_path(project_root, glb_path)}" id="1_model"]',
    ]
    library_ext_id = ""
    if shared:
        library_ext_id = "2_ual"
        ext_resources.append(
            f'[ext_resource type="AnimationLibrary" path="{shared["res_path"]}" id="{library_ext_id}"]'
        )

    load_steps = 1 + len(ext_resources) + sum(1 for line in sub_lines if line.startswith("[sub_resource"))
    lines = [
        f"[gd_scene load_steps={load_steps} format=3]",
        "",
        *ext_resources,
        "",
    ]
    lines.extend(sub_lines)
    lines.extend(
        [
            f'[node name="{node_name}" type="CharacterBody3D"]',
            "",
            '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
            "",
            '[node name="VisualRoot" type="Node3D" parent="."]',
            "",
            '[node name="Model" parent="VisualRoot" instance=ExtResource("1_model")]',
            "",
            '[node name="Equipment" type="Node3D" parent="VisualRoot"]',
            "",
        ]
    )
    for slot_name, meta in (equipment_slots or {}).items():
        bone = (meta or {}).get("attach_bone") or ""
        mesh_name = (meta or {}).get("mesh_name") or ""
        lines.append(f'[node name="{slot_name}" type="Node3D" parent="VisualRoot/Equipment"]')
        note_parts = []
        if bone:
            note_parts.append(f"bone {bone}")
        if mesh_name:
            note_parts.append(f"mesh {mesh_name}")
        if note_parts:
            lines.append(f'editor_description = "Clothing slot: {" / ".join(note_parts)}"')
        lines.append("")

    if library_ext_id:
        lib_key = f'&"{library_name}"' if library_name else '&""'
        libraries_line = f"libraries = {{\n{lib_key}: ExtResource(\"{library_ext_id}\")\n}}"
        clip_note = ", ".join(f"{key}→{value}" for key, value in aliases.items()) or "Quaternius UAL"
    else:
        libraries_line = 'libraries = { "": null }'
        clip_note = ", ".join(clips) if clips else "none yet — assign Shared AnimationLibrary clips"
    lines.extend(
        [
            '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]',
            libraries_line,
            f'editor_description = "Shared locomotion: {clip_note}"',
            "",
        ]
    )
    lines.extend(tree_node_lines)
    lines.extend(
        [
            '[node name="AttachmentPoints" type="Node3D" parent="."]',
            "",
        ]
    )
    for name, meta in attachments.items():
        bone = (meta or {}).get("bone", "")
        lines.append(f'[node name="{name}" type="Marker3D" parent="AttachmentPoints"]')
        if bone:
            lines.append(f'editor_description = "Attach to bone {bone}"')
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def write_shared_skeleton_note(path: Path, profile: dict) -> None:
    payload = {
        "profile": profile.get("profile", "godot_humanoid"),
        "required_bones": profile.get("required_bones", []),
        "optional_bones": profile.get("optional_bones", []),
        "attachment_points": profile.get("attachment_points", {}),
        "notes": "Humanoid characters approved by the pipeline should share this bone profile for animation retargeting. Prefer Quaternius Shared library for basic locomotion.",
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
