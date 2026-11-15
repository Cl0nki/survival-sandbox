extends RefCounted
class_name DeployableArt

## Approved Meshy meshes land at res://assets/deployables/<id>.glb.
## Spawn code attaches them when present; otherwise stations keep the colored box.


static func path_for(kind: String) -> String:
	if kind.is_empty():
		return ""
	var glb := "res://assets/deployables/%s.glb" % kind
	if ResourceLoader.exists(glb) or FileAccess.file_exists(glb):
		return glb
	var scene := "res://assets/deployables/%s.tscn" % kind
	if ResourceLoader.exists(scene) or FileAccess.file_exists(scene):
		return scene
	return ""


static func has_art(kind: String) -> bool:
	return not path_for(kind).is_empty()


## Instance the published mesh under host. Host keeps its own BoxShape collision.
## When body_size is set, the mesh is stretched to fill that box.
## Returns false when no mesh is available or the scene fails to load.
static func attach(host: Node3D, kind: String, body_size: Vector3 = Vector3.ZERO) -> bool:
	return attach_path(host, path_for(kind), body_size)


## Same as attach for a mesh that lives somewhere else (world props reuse this).
static func attach_path(host: Node3D, path: String, body_size: Vector3 = Vector3.ZERO) -> bool:
	if path.is_empty() or host == null:
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate() as Node3D
	if root == null:
		return false
	root.name = "WorldArt"
	_strip_imported_collision(root)
	host.add_child(root)
	if body_size.x > 0.0 and body_size.y > 0.0 and body_size.z > 0.0:
		_fit_to_body(root, body_size)
	else:
		_seat_on_ground(root)
	host.set_meta(&"deployable_art", true)
	return true


static func _strip_imported_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.free()
		else:
			_strip_imported_collision(child)


static func _fit_to_body(root: Node3D, body_size: Vector3) -> void:
	var bounds := _visual_aabb(root, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return
	root.scale = Vector3(
		body_size.x / maxf(bounds.size.x, 0.001),
		body_size.y / maxf(bounds.size.y, 0.001),
		body_size.z / maxf(bounds.size.z, 0.001)
	)
	bounds = _visual_aabb(root, Transform3D.IDENTITY)
	var center := bounds.get_center()
	root.position.x -= center.x
	root.position.z -= center.z
	root.position.y -= bounds.position.y


static func _seat_on_ground(root: Node3D) -> void:
	var bounds := _visual_aabb(root, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return
	root.position.y -= bounds.position.y


static func _visual_aabb(node: Node, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var merged := AABB()
	var found := false
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			merged = _xform_aabb(xf, mesh_node.get_aabb())
			found = true
	for child in node.get_children():
		var child_bounds := _visual_aabb(child, xf)
		if child_bounds.size == Vector3.ZERO:
			continue
		if found:
			merged = merged.merge(child_bounds)
		else:
			merged = child_bounds
			found = true
	return merged


static func _xform_aabb(xf: Transform3D, local: AABB) -> AABB:
	var points: Array[Vector3] = [
		xf * local.position,
		xf * (local.position + Vector3(local.size.x, 0.0, 0.0)),
		xf * (local.position + Vector3(0.0, local.size.y, 0.0)),
		xf * (local.position + Vector3(0.0, 0.0, local.size.z)),
		xf * (local.position + Vector3(local.size.x, local.size.y, 0.0)),
		xf * (local.position + Vector3(local.size.x, 0.0, local.size.z)),
		xf * (local.position + Vector3(0.0, local.size.y, local.size.z)),
		xf * (local.position + local.size),
	]
	var mn := points[0]
	var mx := points[0]
	for index in range(1, points.size()):
		mn = mn.min(points[index])
		mx = mx.max(points[index])
	return AABB(mn, mx - mn)
