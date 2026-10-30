extends Node3D
class_name ImpactMarks

## Bullet holes live here, not in the building mesh. A shot never rebuilds a
## wall to draw a mark. Marks are capped and expire.

var lifetime_sec := 8.0
var cap := 32

var _marks: Array[MeshInstance3D] = []
var _mesh: QuadMesh


func setup(config: BuildingConfig) -> void:
	lifetime_sec = config.impact_lifetime_sec
	cap = config.impact_cap
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.12, 0.09)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material = material


func alive() -> int:
	return _marks.size()


## `normal` points out of the surface. The quad sits a hair off it so the mark
## itself does not z-fight; the building mesh is not moved.
func add_hole(point: Vector3, normal: Vector3) -> void:
	while _marks.size() >= cap and not _marks.is_empty():
		var old := _marks.pop_front() as MeshInstance3D
		if old != null:
			old.queue_free()
	var mark := MeshInstance3D.new()
	mark.mesh = _mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.top_level = true
	add_child(mark)
	var outward := normal
	if outward.length_squared() < 0.000001:
		outward = Vector3.UP
	outward = outward.normalized()
	mark.global_position = point + outward * 0.012
	var up := Vector3.UP if absf(outward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mark.look_at(mark.global_position + outward, up)
	_marks.append(mark)


func _process(delta: float) -> void:
	var index := 0
	while index < _marks.size():
		var mark := _marks[index]
		var age := float(mark.get_meta(&"age", 0.0)) + delta
		mark.set_meta(&"age", age)
		if age >= lifetime_sec:
			_marks.remove_at(index)
			mark.queue_free()
			continue
		index += 1
