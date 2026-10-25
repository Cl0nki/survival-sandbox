extends Node3D

## Scene glue for the milestone 1 arena. Geometry lives in the scene file.

@onready var _sun: DirectionalLight3D = $Sun


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	_sun.shadow_enabled = true
	_sun.light_energy = 1.15
	_sun.directional_shadow_max_distance = 70.0


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
