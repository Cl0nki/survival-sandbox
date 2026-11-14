"""Write Godot 4 .import sidecars for humanoid retargeting / AnimationLibrary."""

from __future__ import annotations

import hashlib
from pathlib import Path


def _stable_token(text: str, size: int = 8) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:size]


def _res(path: Path, project_root: Path | None = None) -> str:
    text = str(path).replace("\\", "/")
    if text.startswith("res://"):
        return text
    if project_root is not None:
        try:
            return "res://" + path.resolve().relative_to(project_root.resolve()).as_posix()
        except ValueError:
            pass
    lowered = text.lower()
    if "assets/" in lowered:
        return "res://assets/" + text[lowered.index("assets/") + len("assets/") :]
    return "res://" + Path(path).as_posix().lstrip("/")


def write_quaternius_animation_import(glb_path: Path, bone_map_path: Path, project_root: Path | None = None) -> Path:
    """Mark Quaternius pack as AnimationLibrary. Assign BoneMap in Godot Advanced Import if needed."""
    glb_path = Path(glb_path)
    import_path = Path(str(glb_path) + ".import")
    source = _res(glb_path, project_root)
    token = _stable_token(source)
    bone_res = _res(bone_map_path, project_root) if bone_map_path else ""
    # Keep params conservative: Godot rewrites dest paths / uids on first open.
    content = f"""[remap]

importer="scene"
type="AnimationLibrary"
uid="uid://qal{token}"

[deps]

source_file="{source}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
_subresources={{}}
gltf/naming_version=1
gltf/embedded_image_handling=1
; bone_map={bone_res}
; Open Advanced Import → Skeleton → Retarget → assign QuaterniusBoneMap.tres, then Reimport.
"""
    import_path.write_text(content, encoding="utf-8")
    return import_path


def write_static_glb_import(glb_path: Path, project_root: Path | None = None) -> Path:
    """Write a PackedScene import stub for props / deployables (no retargeting)."""
    glb_path = Path(glb_path)
    import_path = Path(str(glb_path) + ".import")
    source = _res(glb_path, project_root)
    token = _stable_token(source)
    content = f"""[remap]

importer="scene"
type="PackedScene"
uid="uid://dep{token}"

[deps]

source_file="{source}"

[params]

nodes/root_type="Node3D"
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
_subresources={{}}
gltf/naming_version=1
gltf/embedded_image_handling=1
"""
    import_path.write_text(content, encoding="utf-8")
    return import_path


def write_character_glb_import(glb_path: Path, bone_map_path: Path, *, fix_silhouette: bool = True, project_root: Path | None = None) -> Path:
    """Write a PackedScene import stub. Assign GodotHumanoidBoneMap + Fix Silhouette in the editor once."""
    glb_path = Path(glb_path)
    import_path = Path(str(glb_path) + ".import")
    source = _res(glb_path, project_root)
    token = _stable_token(source)
    bone_res = _res(bone_map_path, project_root) if bone_map_path else ""
    fix = "true" if fix_silhouette else "false"
    content = f"""[remap]

importer="scene"
type="PackedScene"
uid="uid://chr{token}"

[deps]

source_file="{source}"

[params]

nodes/root_type="Node3D"
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
_subresources={{}}
gltf/naming_version=1
gltf/embedded_image_handling=1
; bone_map={bone_res}
; fix_silhouette={fix}
; Open Advanced Import → Skeleton → Retarget → GodotHumanoidBoneMap.tres, enable Fix Silhouette, Reimport.
"""
    import_path.write_text(content, encoding="utf-8")
    return import_path
