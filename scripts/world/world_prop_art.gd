extends RefCounted
class_name WorldPropArt

## Approved Meshy meshes for world props land at res://assets/resources/<id>.glb
## (the pipeline's "resources" folder). A mesh made in the Surfaces tab at
## res://assets/environment/<id>.glb works too, for tree_oak and the like.
## Without a file the builders keep their primitive meshes.

const FOLDERS: PackedStringArray = ["resources", "environment"]


static func path_for(prop_id: String) -> String:
	if prop_id.is_empty():
		return ""
	for folder in FOLDERS:
		for suffix in [".glb", ".tscn"]:
			var path := "res://assets/%s/%s%s" % [folder, prop_id, suffix]
			if ResourceLoader.exists(path) or FileAccess.file_exists(path):
				return path
	return ""


static func has_art(prop_id: String) -> bool:
	return not path_for(prop_id).is_empty()


## Instance the mesh under host as a child named WorldArt, fitted to the
## prop's body box. Host keeps its own collision. Returns the root or null.
static func attach(host: Node3D, prop_id: String) -> Node3D:
	var path := path_for(prop_id)
	if path.is_empty() or host == null:
		return null
	if not DeployableArt.attach_path(host, path, WorldPropCatalog.body_size(prop_id)):
		return null
	return host.get_node_or_null("WorldArt") as Node3D
