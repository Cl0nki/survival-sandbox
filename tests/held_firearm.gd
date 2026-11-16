extends SceneTree

## The building gun is held by the grip, muzzle along the fingers, pistol length.
## godot --headless --path <project> --script res://tests/held_firearm.gd

var _failed := false


func _initialize() -> void:
	var host := Node3D.new()
	root.add_child(host)
	if not HeldToolArt.mount(host, "build_tool"):
		_fail("build_tool mesh did not mount")
	else:
		_check_gun(host.get_node("ToolArt") as Node3D)
	if not _failed and not HeldToolArt.mount(host, "crowbar_scrap"):
		_fail("crowbar mesh did not mount")
	elif not _failed:
		_check_crowbar(_bounds(host.get_node("ToolArt") as Node3D))
	if _failed:
		quit(1)
		return
	print("PASS held firearm")
	quit(0)


func _check_gun(art: Node3D) -> void:
	var bounds := _bounds(art)
	if bounds.size.y < 0.26 or bounds.size.y > 0.34:
		_fail("barrel length %.3f is not a handheld gun" % bounds.size.y)
	if bounds.size.y < bounds.size.x or bounds.size.y < bounds.size.z:
		_fail("barrel is not the long axis %s" % bounds.size)
	var muzzle_y := _mean_y(art, true)
	var butt_y := _mean_y(art, false)
	if muzzle_y <= butt_y:
		_fail("muzzle is not past the grip along the fingers")
	if bounds.position.x > -0.03:
		_fail("grip does not enter the palm, min x %.3f" % bounds.position.x)
	var grip_y := _mean_y_of_palm_side(art)
	if grip_y > bounds.position.y + bounds.size.y * 0.55:
		_fail("palm-side mass is up at the muzzle, y %.3f" % grip_y)


func _check_crowbar(crowbar: AABB) -> void:
	if absf(crowbar.size.y - 0.72) > 0.05:
		_fail("crowbar length changed to %.3f" % crowbar.size.y)
	if crowbar.position.y < -0.02 or crowbar.position.y > 0.04:
		_fail("crowbar butt is not in the hand")


func _fail(message: String) -> void:
	print("FAIL %s" % message)
	_failed = true


func _bounds(node: Node3D) -> AABB:
	return DeployableArt._visual_aabb(node, Transform3D.IDENTITY)


func _points(node: Node3D, parent: Transform3D, into: PackedVector3Array) -> void:
	var xform := parent * node.transform
	if node is MeshInstance3D and not String(node.name).to_lower().contains("colonly"):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex in verts:
					into.append(xform * vertex)
	for child in node.get_children():
		if child is Node3D:
			_points(child, xform, into)


func _mean_y(art: Node3D, high: bool) -> float:
	var points := PackedVector3Array()
	_points(art, Transform3D.IDENTITY, points)
	var bounds := _bounds(art)
	var cut := bounds.position.y + bounds.size.y * 0.5
	var sum := 0.0
	var count := 0
	for point in points:
		var keep := point.y >= cut if high else point.y <= bounds.position.y + bounds.size.y * 0.35
		if keep:
			sum += point.y
			count += 1
	return sum / float(maxi(count, 1))


func _mean_y_of_palm_side(art: Node3D) -> float:
	var points := PackedVector3Array()
	_points(art, Transform3D.IDENTITY, points)
	var sum := 0.0
	var count := 0
	for point in points:
		if point.x < -0.02:
			sum += point.y
			count += 1
	return sum / float(maxi(count, 1))
