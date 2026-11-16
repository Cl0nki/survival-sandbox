extends RefCounted
class_name HeldToolArt

## Mount for a Meshy tool mesh. The pipeline publishes it at
## res://assets/props/<item_id>.glb. equipment/ and weapons/ are also checked,
## then a shared res://assets/props/<harvest_kind>.glb for every tier.
## Nothing is drawn until that file exists.
## A shaft tool's long axis becomes the handle. The butt is the origin and the
## head points along local +Y, which is along the fingers on the right hand.
## A firearm keeps the muzzle along those fingers, but the hand holds the grip.
## RightHand local -X is the palm (Quaternius rest pose, palms down).

const FOLDERS: PackedStringArray = ["props", "equipment", "weapons"]

enum Pose { HAND, GROUND }

const LENGTH_BY_KIND := {
	"crowbar": 0.72,
}
const DEFAULT_LENGTH := 0.7
## Overall barrel length for a pistol-sized gun. Shaft tools stay at 0.7 m.
const FIREARM_LENGTH := 0.30
## Grip center in the palm: a little into the hand, and forward of the wrist.
const FIREARM_IN_PALM := Vector3(-0.02, 0.06, 0.0)


static func path_for(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	var names: PackedStringArray = [item_id]
	var definition := ItemCatalog.get_item(item_id)
	if definition != null and not definition.harvest_kind.is_empty() and definition.harvest_kind != item_id:
		names.append(definition.harvest_kind)
	for name in names:
		for folder in FOLDERS:
			for suffix in [".glb", ".tscn"]:
				var path := "res://assets/%s/%s%s" % [folder, name, suffix]
				if ResourceLoader.exists(path) or FileAccess.file_exists(path):
					return path
	return ""


static func mount(host: Node3D, item_id: String, pose: Pose = Pose.HAND) -> bool:
	if host == null:
		return false
	var previous := host.get_node_or_null("ToolArt")
	if previous != null:
		host.remove_child(previous)
		previous.free()
	var path := path_for(item_id)
	if path.is_empty():
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var root := packed.instantiate() as Node3D
	if root == null:
		return false
	root.name = "ToolArt"
	_strip_collision(root)
	host.add_child(root)
	if _is_firearm(item_id):
		_fit_firearm(root, FIREARM_LENGTH)
	else:
		_fit(root, _length_for(item_id))
	if pose == Pose.GROUND:
		root.rotate_x(PI * 0.5)
		var bounds := _bounds(root)
		root.position.y -= bounds.position.y
		root.position.y += 0.04
	return true


static func _is_firearm(item_id: String) -> bool:
	var id := item_id.to_lower()
	if id == "build_tool":
		return true
	for word in ["gun", "pistol", "rifle", "revolver", "shotgun", "firearm", "sidearm", "carbine", "blaster"]:
		if id.contains(word):
			return true
	var definition := ItemCatalog.get_item(item_id)
	return definition != null and definition.category == "weapon"


static func _length_for(item_id: String) -> float:
	var definition := ItemCatalog.get_item(item_id)
	var kind := "" if definition == null else definition.harvest_kind
	return float(LENGTH_BY_KIND.get(kind, DEFAULT_LENGTH))


static func _fit(root: Node3D, length: float) -> void:
	root.transform = Transform3D.IDENTITY
	var bounds := _bounds(root)
	var axis := _longest_axis(bounds.size)
	if axis.dot(Vector3.UP) < 0.999:
		if axis.dot(Vector3.UP) < -0.999:
			root.rotate_x(PI)
		else:
			root.basis = Basis(Quaternion(axis, Vector3.UP))
	bounds = _bounds(root)
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	root.scale = Vector3.ONE * (length / maxf(span, 0.001))
	bounds = _bounds(root)
	var center := bounds.get_center()
	root.position = Vector3(-center.x, -bounds.position.y, -center.z)


## Muzzle along the fingers (+Y). Grip hangs into the palm (-X).
static func _fit_firearm(root: Node3D, length: float) -> void:
	root.transform = Transform3D.IDENTITY
	var points := _vertices(root)
	if points.size() < 8:
		_fit(root, length)
		return
	var bounds := _bounds_of(points)
	var axis := _axis_index(bounds.size)
	var span := bounds.size[axis]
	if span < 0.001:
		_fit(root, length)
		return
	var min_a := bounds.position[axis]
	var low := _end_points(points, axis, min_a + span * 0.22, true)
	var high := _end_points(points, axis, min_a + span * 0.78, false)
	if low.is_empty() or high.is_empty():
		_fit(root, length)
		return
	var low_radius := _end_radius(low, axis)
	var high_radius := _end_radius(high, axis)
	var muzzle: PackedVector3Array = low if low_radius < high_radius else high
	var butt: PackedVector3Array = high if low_radius < high_radius else low
	var toward_muzzle := -1.0 if low_radius < high_radius else 1.0
	var muzzle_center := _centroid(muzzle)
	var axis_dir := _axis_vector(axis) * toward_muzzle
	var muzzle_radius := minf(low_radius, high_radius)
	var extra := PackedVector3Array()
	for point in butt:
		if _perp(point, muzzle_center, axis_dir).length() > muzzle_radius * 1.15:
			extra.append(point)
	if extra.size() < 8:
		_fit(root, length)
		return
	var grip_dir := Vector3.ZERO
	for point in extra:
		grip_dir += _perp(point, muzzle_center, axis_dir)
	grip_dir /= float(extra.size())
	if grip_dir.length_squared() < 0.000001:
		_fit(root, length)
		return
	grip_dir = grip_dir.normalized()
	var peak := -1.0e9
	for point in extra:
		peak = maxf(peak, (point - muzzle_center).dot(grip_dir))
	var held := PackedVector3Array()
	for point in extra:
		if (point - muzzle_center).dot(grip_dir) > peak * 0.45:
			held.append(point)
	var grip_center := _centroid(held if not held.is_empty() else extra)
	var from_y := axis_dir
	var from_x := -grip_dir
	from_x = from_x - from_y * from_x.dot(from_y)
	if from_x.length_squared() < 0.0001:
		_fit(root, length)
		return
	from_x = from_x.normalized()
	var from_z := from_x.cross(from_y).normalized()
	from_x = from_y.cross(from_z).normalized()
	var rotation := Basis(Vector3.RIGHT, Vector3.UP, Vector3.RIGHT.cross(Vector3.UP)) * Basis(from_x, from_y, from_z).inverse()
	var fitted := rotation.scaled(Vector3.ONE * (length / span))
	root.transform = Transform3D(fitted, FIREARM_IN_PALM - fitted * grip_center)


static func _vertices(root: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var pending: Array[Dictionary] = [{"node": root, "xform": Transform3D.IDENTITY}]
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		var node := item["node"] as Node
		var xform: Transform3D = item["xform"]
		if _is_collision_visual(node):
			continue
		if node is MeshInstance3D:
			var mesh := (node as MeshInstance3D).mesh
			if mesh != null:
				for surface in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(surface)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					for vertex in verts:
						points.append(xform * vertex)
		for child in node.get_children():
			var child_xform := xform
			if child is Node3D:
				child_xform = xform * (child as Node3D).transform
			pending.append({"node": child, "xform": child_xform})
	return points


static func _axis_index(size: Vector3) -> int:
	if size.x >= size.y and size.x >= size.z:
		return 0
	if size.z >= size.x and size.z >= size.y:
		return 2
	return 1


static func _axis_vector(axis: int) -> Vector3:
	match axis:
		0:
			return Vector3.RIGHT
		2:
			return Vector3(0.0, 0.0, 1.0)
		_:
			return Vector3.UP


static func _end_points(points: PackedVector3Array, axis: int, cut: float, below: bool) -> PackedVector3Array:
	var end := PackedVector3Array()
	for point in points:
		var on_end := point[axis] <= cut if below else point[axis] >= cut
		if on_end:
			end.append(point)
	return end


static func _end_radius(points: PackedVector3Array, axis: int) -> float:
	var center := _centroid(points)
	var radius := 0.0
	for point in points:
		var delta := point - center
		delta[axis] = 0.0
		radius = maxf(radius, delta.length())
	return radius


static func _perp(point: Vector3, origin: Vector3, axis_dir: Vector3) -> Vector3:
	var delta := point - origin
	return delta - axis_dir * delta.dot(axis_dir)


static func _bounds_of(points: PackedVector3Array) -> AABB:
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


static func _is_collision_visual(node: Node) -> bool:
	var node_name := String(node.name).to_lower()
	return node_name.contains("colonly") or node_name.ends_with("-col") or node_name.ends_with("_col")


static func _centroid(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for point in points:
		sum += point
	return sum / float(maxi(points.size(), 1))


static func _longest_axis(size: Vector3) -> Vector3:
	if size.x >= size.y and size.x >= size.z:
		return Vector3.RIGHT
	if size.z >= size.x and size.z >= size.y:
		return Vector3.FORWARD
	return Vector3.UP


static func _bounds(root: Node3D) -> AABB:
	return DeployableArt._visual_aabb(root, Transform3D.IDENTITY)


static func _strip_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.free()
		else:
			_strip_collision(child)
