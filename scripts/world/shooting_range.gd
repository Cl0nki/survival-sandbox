extends RefCounted
class_name ShootingRange

## East-side range: open dummy, distance marks, and a 3 m height gauge for scale checks.
## Military loot sits on the south-west corner via LootLayout.

const OPEN := Vector3(19.0, 0.0, -3.0)
const GAUGE := Vector3(19.0, 0.0, -7.0)
const FIRE_X := 13.0
const GAUGE_HEIGHT := 3.0


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("ShootingRange") != null:
		return
	_place_dummy(arena, "OpenDummy", OPEN)
	_discard(arena, "CoveredDummy")
	var root := Node3D.new()
	root.name = "ShootingRange"
	arena.add_child(root)
	for meters in [2, 4]:
		var x := FIRE_X + float(meters)
		_mark(root, Vector3(x, 0.045, -5.0), "%dm" % meters)
	_height_gauge(root, GAUGE)


static func _place_dummy(arena: Node3D, node_name: String, at: Vector3) -> void:
	var dummy := arena.get_node_or_null(node_name) as Node3D
	if dummy != null:
		dummy.position = Vector3(at.x, 0.75, at.z)


static func _discard(arena: Node3D, node_name: String) -> void:
	var node := arena.get_node_or_null(node_name)
	if node != null:
		node.queue_free()


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
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(at.x, 0.5, at.z + 3.15)
	label.pixel_size = 0.012
	label.font_size = 20
	label.outline_size = 8
	label.text = text
	label.modulate = Color(0.9, 0.88, 0.7)
	root.add_child(label)


## Vertical ruler to 3 m with 0.5 m ticks for character / prop scale checks.
static func _height_gauge(root: Node3D, at: Vector3) -> void:
	var body := MeshInstance3D.new()
	var pillar := BoxMesh.new()
	pillar.size = Vector3(0.12, GAUGE_HEIGHT, 0.04)
	body.mesh = pillar
	body.position = Vector3(at.x, GAUGE_HEIGHT * 0.5, at.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.76, 0.68)
	mat.roughness = 0.9
	body.set_surface_override_material(0, mat)
	root.add_child(body)
	var title := Label3D.new()
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(at.x, GAUGE_HEIGHT + 0.28, at.z)
	title.pixel_size = 0.01
	title.font_size = 28
	title.outline_size = 8
	title.text = "HEIGHT 0–3m"
	title.modulate = Color(0.95, 0.92, 0.78)
	root.add_child(title)
	var tick := 0.5
	while tick <= GAUGE_HEIGHT + 0.001:
		var y := tick
		var bar := MeshInstance3D.new()
		var lip := BoxMesh.new()
		var major := is_equal_approx(tick, roundf(tick))
		lip.size = Vector3(0.55 if major else 0.32, 0.03, 0.03)
		bar.mesh = lip
		bar.position = Vector3(at.x + lip.size.x * 0.5 - 0.06, y, at.z)
		var tick_mat := StandardMaterial3D.new()
		tick_mat.albedo_color = Color(0.95, 0.55, 0.22) if major else Color(0.88, 0.84, 0.72)
		bar.set_surface_override_material(0, tick_mat)
		root.add_child(bar)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(at.x + 0.85, y, at.z)
		label.pixel_size = 0.008
		label.font_size = 22 if major else 16
		label.outline_size = 6
		label.text = "%.1fm" % tick
		label.modulate = Color(0.95, 0.9, 0.7) if major else Color(0.82, 0.8, 0.7)
		root.add_child(label)
		tick += 0.5
