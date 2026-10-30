extends Node3D
class_name DebrisSystem

## Short-lived chips spawned when a piece is destroyed. They are visual only:
## no collision bodies, a hard cap, and a lifetime. Nothing here touches a
## committed building node.

var lifetime_sec := 1.5
var cap := 24

var _chunks: Array[MeshInstance3D] = []
var _ash: Array[MeshInstance3D] = []
var _mesh: BoxMesh
var _ash_mesh: BoxMesh
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


func alive() -> int:
	return _chunks.size()


## Scatters up to `count` chips around `origin`, stopping at the cap.
## Positions come from the component id, so the same piece breaks the same way.
func spawn(origin: Vector3, count: int, component_id: int) -> int:
	var made := 0
	for i in count:
		if _chunks.size() >= cap:
			break
		var chip := MeshInstance3D.new()
		chip.mesh = _mesh
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chip.position = origin + _offset(component_id, i)
		add_child(chip)
		_chunks.append(chip)
		spawned_total += 1
		made += 1
	return made


## Fast dust from a pancaking storey. Separate from the small chip cap so a
## tower can throw a cloud without silencing ordinary break chips.
func spawn_collapse(origin: Vector3, component_id: int) -> void:
	if _ash_mesh == null:
		_ash_mesh = BoxMesh.new()
		_ash_mesh.size = Vector3(0.28, 0.1, 0.28)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.52, 0.48)
		material.roughness = 1.0
		_ash_mesh.material = material
	for i in 3:
		if _ash.size() >= ASH_CAP:
			var old := _ash.pop_front() as MeshInstance3D
			if old != null:
				old.queue_free()
		var chip := MeshInstance3D.new()
		chip.mesh = _ash_mesh
		chip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := float(posmod(component_id * 3 + i * 5, 10)) / 10.0 * TAU
		var outward := 1.4 + float(i) * 0.45
		chip.position = origin + Vector3(cos(angle) * 0.15, 0.25, sin(angle) * 0.15)
		chip.set_meta(&"velocity", Vector3(cos(angle) * outward, -3.5 - float(i) * 1.2, sin(angle) * outward))
		chip.set_meta(&"age", 0.0)
		add_child(chip)
		_ash.append(chip)


func _process(delta: float) -> void:
	var index := 0
	while index < _chunks.size():
		var chip := _chunks[index]
		var age := float(chip.get_meta(&"age", 0.0)) + delta
		chip.set_meta(&"age", age)
		chip.position.y -= delta * 1.2
		if age >= lifetime_sec:
			_chunks.remove_at(index)
			chip.queue_free()
			continue
		index += 1
	index = 0
	while index < _ash.size():
		var chip := _ash[index]
		var age := float(chip.get_meta(&"age", 0.0)) + delta
		chip.set_meta(&"age", age)
		var velocity: Vector3 = chip.get_meta(&"velocity", Vector3.ZERO)
		velocity.y -= 26.0 * delta
		chip.set_meta(&"velocity", velocity)
		chip.position += velocity * delta
		var shrink := maxf(0.15, 1.0 - age / 0.55)
		chip.scale = Vector3(shrink, shrink * 0.45, shrink)
		if age >= 0.55:
			_ash.remove_at(index)
			chip.queue_free()
			continue
		index += 1


static func _offset(component_id: int, index: int) -> Vector3:
	var angle := float(posmod(component_id * 3 + index * 2, 8)) / 8.0 * TAU
	return Vector3(cos(angle) * 0.28, 0.35 + float(index) * 0.05, sin(angle) * 0.28)
