extends StaticBody3D
class_name Damageable

## Health for arena targets.
## Local play changes it through receive_damage(). Clients in a network game
## apply the server's absolute value and ignore stale higher values. There is
## no healing in this milestone, so an older snapshot cannot restore health.

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100
@export var display_name: String = "Target"
@export var tint: Color = Color(0.8, 0.22, 0.18, 1)

var health: int = 100
var _dead := false
var _material: StandardMaterial3D
var _alive_color: Color

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label3D


func _ready() -> void:
	health = max_health
	add_to_group(&"damageable")
	collision_layer = PhysicsLayers.WORLD | PhysicsLayers.DAMAGEABLE
	collision_mask = 0
	_material = StandardMaterial3D.new()
	_material.roughness = 0.78
	_alive_color = tint
	_material.albedo_color = tint
	_mesh.set_surface_override_material(0, _material)
	_refresh_label()


func receive_damage(amount: int, _point: Vector3) -> bool:
	if _dead or amount <= 0:
		return false
	var next := maxi(health - amount, 0)
	if next >= health:
		return false
	apply_authoritative_health(next)
	return true


func apply_authoritative_health(current: int) -> void:
	current = clampi(current, 0, max_health)
	if current >= health:
		return
	health = current
	health_changed.emit(health, max_health)
	if health == 0:
		_dead = true
		if _material != null:
			_material.albedo_color = Color(0.16, 0.15, 0.15, 1)
		_refresh_label()
		died.emit()
		return
	_refresh_label()
	_flash()


func _flash() -> void:
	_material.albedo_color = Color(1.0, 0.95, 0.85, 1)
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", _alive_color, 0.12)


func _refresh_label() -> void:
	if _dead:
		_label.text = "%s\nDESTROYED" % display_name
	else:
		_label.text = "%s\n%d HP" % [display_name, health]
