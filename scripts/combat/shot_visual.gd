extends RefCounted
class_name ShotVisual

## LOCAL-ONLY tracer and impact flash. Presentation, not a hit result.
## Milestone 2 spawns this from a server-confirmed shot, not from the local query.

static func spawn(parent: Node, start: Vector3, end_point: Vector3, damaged: bool) -> void:
	if parent == null:
		return
	var length := start.distance_to(end_point)
	if length < 0.05:
		return

	var root := Node3D.new()
	root.name = "ShotTracer"
	root.top_level = true
	parent.add_child(root)
	root.global_position = (start + end_point) * 0.5
	var aim_dir := start.direction_to(end_point)
	var up := Vector3.UP
	if absf(aim_dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	root.look_at(end_point, up)

	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, length)
	box.material = _unshaded(Color(1.0, 0.55, 0.22) if damaged else Color(0.82, 0.9, 1.0))
	beam.mesh = box
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)

	var impact := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.material = _unshaded(Color(1.0, 0.28, 0.16) if damaged else Color(1.0, 0.95, 0.75))
	impact.mesh = sphere
	impact.position = Vector3(0.0, 0.0, -length * 0.5)
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(impact)

	var timer := parent.get_tree().create_timer(0.1)
	timer.timeout.connect(root.queue_free)


static func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
