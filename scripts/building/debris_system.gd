extends Node3D
class_name DebrisSystem

## Short-lived chips spawned when a piece is destroyed. They are visual only:
## one MultiMesh for the break chips and one for collapse dust, no collision
## bodies, a hard cap, and a lifetime. Committed building pieces stay
## individually addressable; only this repeated visual is instanced.

var lifetime_sec := 1.5
var cap := 24

var _mesh: BoxMesh
var _ash_mesh: BoxMesh
var _chips: MultiMeshInstance3D
var _ash_view: MultiMeshInstance3D
var _chip_pos: Array[Vector3] = []
var _chip_age: Array[float] = []
var _ash_pos: Array[Vector3] = []
var _ash_vel: Array[Vector3] = []
var _ash_age: Array[float] = []
var spawned_total := 0
const ASH_CAP := 72


func setup(config: BuildingConfig) -> void:
	lifetime_sec = config.debris_lifetime_sec
	cap = config.debris_cap
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.12, 0.08, 0.16)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.38, 0.32)
	material.roughness = 0.95
	_mesh.material = material
	_chips = _make_view(_mesh, cap)
	add_child(_chips)


func alive() -> int:
	return _chip_pos.size()


## Scatters up to `count` chips around `origin`, stopping at the cap.
## Positions come from the component id, so the same piece breaks the same way.
func spawn(origin: Vector3, count: int, component_id: int) -> int:
	var made := 0
	for i in count:
		if _chip_pos.size() >= cap:
			break
		_chip_pos.append(origin + _offset(component_id, i))
		_chip_age.append(0.0)
		spawned_total += 1
		made += 1
	_write_chips()
	return made


## Fast dust from a pancaking storey. Separate from the small chip cap so a
## tower can throw a cloud without silencing ordinary break chips.
func spawn_collapse(origin: Vector3, component_id: int) -> void:
	if _ash_view == null:
		_ash_mesh = BoxMesh.new()
		_ash_mesh.size = Vector3(0.28, 0.1, 0.28)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.52, 0.48)
		material.roughness = 1.0
		_ash_mesh.material = material
		_ash_view = _make_view(_ash_mesh, ASH_CAP)
		add_child(_ash_view)
	for i in 3:
		if _ash_pos.size() >= ASH_CAP:
			_ash_pos.pop_front()
			_ash_vel.pop_front()
			_ash_age.pop_front()
		var angle := float(posmod(component_id * 3 + i * 5, 10)) / 10.0 * TAU
		var outward := 1.4 + float(i) * 0.45
		_ash_pos.append(origin + Vector3(cos(angle) * 0.15, 0.25, sin(angle) * 0.15))
		_ash_vel.append(Vector3(cos(angle) * outward, -3.5 - float(i) * 1.2, sin(angle) * outward))
		_ash_age.append(0.0)
	_write_ash()


func _process(delta: float) -> void:
	var index := 0
	while index < _chip_pos.size():
		_chip_age[index] += delta
		var pos := _chip_pos[index]
		pos.y -= delta * 1.2
		_chip_pos[index] = pos
		if _chip_age[index] >= lifetime_sec:
			_chip_pos.remove_at(index)
			_chip_age.remove_at(index)
			continue
		index += 1
	_write_chips()
	index = 0
	while index < _ash_pos.size():
		_ash_age[index] += delta
		var velocity := _ash_vel[index]
		velocity.y -= 26.0 * delta
		_ash_vel[index] = velocity
		_ash_pos[index] = _ash_pos[index] + velocity * delta
		if _ash_age[index] >= 0.55:
			_ash_pos.remove_at(index)
			_ash_vel.remove_at(index)
			_ash_age.remove_at(index)
			continue
		index += 1
	_write_ash()


func _write_chips() -> void:
	if _chips == null or _chips.multimesh == null:
		return
	var mesh := _chips.multimesh
	mesh.visible_instance_count = _chip_pos.size()
	for i in _chip_pos.size():
		mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, _chip_pos[i]))


func _write_ash() -> void:
	if _ash_view == null or _ash_view.multimesh == null:
		return
	var mesh := _ash_view.multimesh
	mesh.visible_instance_count = _ash_pos.size()
	for i in _ash_pos.size():
		var shrink := maxf(0.15, 1.0 - _ash_age[i] / 0.55)
		var basis := Basis.IDENTITY.scaled(Vector3(shrink, shrink * 0.45, shrink))
		mesh.set_instance_transform(i, Transform3D(basis, _ash_pos[i]))


func _make_view(source: Mesh, count: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = source
	multi.instance_count = maxi(count, 1)
	multi.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.multimesh = multi
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


static func _offset(component_id: int, index: int) -> Vector3:
	var angle := float(posmod(component_id * 3 + index * 2, 8)) / 8.0 * TAU
	return Vector3(cos(angle) * 0.28, 0.35 + float(index) * 0.05, sin(angle) * 0.28)
