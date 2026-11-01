extends RefCounted
class_name ShootingRange

## One compact east-side range: two lanes, one backstop. The rest of the
## yard stays empty for building. Loot sits south-east of this pad.

const OPEN := Vector3(15.0, 0.0, 2.0)
const COVERED := Vector3(15.0, 0.0, -2.0)
const FIRE_X := 9.0
const COVER_X := 12.0


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("ShootingRange") != null:
		return
	_place_dummy(arena, "OpenDummy", OPEN)
	_place_dummy(arena, "CoveredDummy", COVERED)
	var root := Node3D.new()
	root.name = "ShootingRange"
	arena.add_child(root)
	_mat(root)
	_label(root, "RANGE", Vector3(11.0, 2.6, -4.2), 52, Color(0.92, 0.86, 0.55))
	_label(root, "OPEN", Vector3(OPEN.x, 2.15, OPEN.z + 1.15), 28, Color(0.85, 0.35, 0.28))
	_label(root, "COVERED", Vector3(COVERED.x, 2.15, COVERED.z - 1.15), 28, Color(0.92, 0.62, 0.22))
	_pad(root, Vector3(FIRE_X, 0.0, OPEN.z), Color(0.55, 0.28, 0.22))
	_pad(root, Vector3(FIRE_X, 0.0, COVERED.z), Color(0.58, 0.40, 0.18))
	_cover(root, Vector3(COVER_X, 0.9, COVERED.z))
	_backstop(root)
	for meters in [2, 4]:
		var x := FIRE_X + float(meters)
		_mark(root, Vector3(x, 0.045, 0.0), "%dm" % meters)


static func _place_dummy(arena: Node3D, node_name: String, at: Vector3) -> void:
	var dummy := arena.get_node_or_null(node_name) as Node3D
	if dummy != null:
		dummy.position = Vector3(at.x, 0.75, at.z)


static func _mat(root: Node3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 0.02, 10.0)
	mesh.mesh = box
	mesh.position = Vector3(11.0, 0.012, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.40, 0.26, 0.16)
	material.roughness = 1.0
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)
	var open_lane := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(6.4, 0.02, 1.7)
	open_lane.mesh = strip
	open_lane.position = Vector3(12.2, 0.04, OPEN.z)
	var open_mat := StandardMaterial3D.new()
	open_mat.albedo_color = Color(0.48, 0.22, 0.18)
	open_lane.set_surface_override_material(0, open_mat)
	root.add_child(open_lane)
	var covered_lane := MeshInstance3D.new()
	covered_lane.mesh = strip
	covered_lane.position = Vector3(12.2, 0.04, COVERED.z)
	var covered_mat := StandardMaterial3D.new()
	covered_mat.albedo_color = Color(0.50, 0.34, 0.16)
	covered_lane.set_surface_override_material(0, covered_mat)
	root.add_child(covered_lane)


static func _pad(root: Node3D, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(at.x, 0.06, at.z)
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.12, 1.5)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.set_surface_override_material(0, material)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size
	shape.shape = hull
	body.add_child(shape)
	root.add_child(body)
	_label(root, "FIRE", Vector3(at.x, 1.1, at.z), 26, Color(0.95, 0.92, 0.8))


static func _cover(root: Node3D, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "RangeCover"
	body.position = at
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 1.8, 2.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.50, 0.46, 0.40)
	material.roughness = 0.92
	mesh.set_surface_override_material(0, material)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size
	shape.shape = hull
	body.add_child(shape)
	root.add_child(body)
	_label(root, "COVER", Vector3(at.x, 2.1, at.z), 24, Color(0.9, 0.82, 0.6))


static func _backstop(root: Node3D) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 2.2, 6.2)
	mesh.mesh = box
	mesh.position = Vector3(16.6, 1.1, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.26, 0.24)
	material.roughness = 1.0
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)


static func _mark(root: Node3D, at: Vector3, text: String) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.03, 6.0)
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.82, 0.55)
	mesh.set_surface_override_material(0, material)
	root.add_child(mesh)
	_label(root, text, Vector3(at.x, 0.5, 3.15), 20, Color(0.9, 0.88, 0.7))


static func _label(root: Node3D, text: String, at: Vector3, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.pixel_size = 0.012
	label.font_size = size
	label.outline_size = 8
	label.text = text
	label.modulate = color
	root.add_child(label)
