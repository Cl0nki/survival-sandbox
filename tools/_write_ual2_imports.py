"""Write Godot .import sidecars for UAL2 walk directional GLBs."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "assets" / "characters" / "Shared" / "Quaternius" / "ual2"


def main() -> None:
	for glb in sorted(FOLDER.glob("*.glb")):
		source = "res://" + glb.relative_to(ROOT).as_posix()
		token = hashlib.md5(source.encode()).hexdigest()[:8]
		full = hashlib.md5(source.encode()).hexdigest()
		dest = f"res://.godot/imported/{glb.name}-{full}.scn"
		content = f"""[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="uid://ual2{token}"
path="{dest}"

[deps]

source_file="{source}"
dest_files=["{dest}"]

[params]

nodes/root_type="Node3D"
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
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
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
gltf/naming_version=1
gltf/embedded_image_handling=1
gltf/texture_map_mode=0
"""
		path = Path(str(glb) + ".import")
		path.write_text(content, encoding="utf-8")
		print(path)


if __name__ == "__main__":
	main()
