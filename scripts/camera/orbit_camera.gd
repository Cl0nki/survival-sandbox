extends Node3D
class_name OrbitCamera

## Client presentation. Orbits a fixed pitch around the player.
## Character facing is independent of this yaw. Movement reads get_yaw()
## and builds its own horizontal axes from it.
## Pitch of -52 degrees was checked on Godot 4.7.2: the offset is above
## and behind the focus (+Y, +Z at yaw 0).

const MIN_DISTANCE := 6.0
const MAX_DISTANCE := 22.0
const ZOOM_STEP := 1.35
const KEY_YAW_SPEED := 1.6
const MOUSE_YAW_SPEED := 0.005
const PITCH_DEGREES := -52.0
const FOCUS_HEIGHT := 1.2
const CLIP_MARGIN := 0.45

@onready var _camera: Camera3D = $Camera3D

var _yaw := 0.0
var _distance := 13.0


func _ready() -> void:
	_camera.current = true
	_camera.fov = 55.0
	_camera.near = 0.08
	_camera.far = 250.0
	_apply_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_yaw -= (event as InputEventMouseMotion).relative.x * MOUSE_YAW_SPEED
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - ZOOM_STEP, MIN_DISTANCE)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + ZOOM_STEP, MAX_DISTANCE)


func _process(delta: float) -> void:
	var key_yaw := Input.get_action_strength(&"camera_yaw_right") - Input.get_action_strength(&"camera_yaw_left")
	_yaw += key_yaw * KEY_YAW_SPEED * delta
	_apply_pose()


func get_yaw() -> float:
	return _yaw


func get_distance() -> float:
	return _distance


func get_camera() -> Camera3D:
	return _camera


func set_yaw(yaw: float) -> void:
	_yaw = yaw
	_apply_pose()


static func camera_offset(yaw: float, distance: float) -> Vector3:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(PITCH_DEGREES))
	return basis * Vector3(0.0, 0.0, distance)


func _apply_pose() -> void:
	if _camera == null:
		return
	var focus := global_position + Vector3.UP * FOCUS_HEIGHT
	var desired := focus + camera_offset(_yaw, _distance)
	_camera.global_position = _pull_in(focus, desired)
	if _camera.global_position.distance_squared_to(focus) > 0.0001:
		_camera.look_at(focus, Vector3.UP)


func _pull_in(focus: Vector3, desired: Vector3) -> Vector3:
	## Single ray from the focus to the desired camera spot. Corners can still
	## graze the near plane; a sphere cast can replace this later if it shows up.
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return desired
	var query := PhysicsRayQueryParameters3D.create(focus, desired)
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	var hit_position := hit["position"] as Vector3
	var focus_to_hit := hit_position - focus
	var gap := focus_to_hit.length()
	if gap < 0.05:
		return focus + Vector3.UP * 0.6
	# Stay on the focus side of the impact. A fixed minimum arm would push
	# the camera through a wall that is closer than that arm.
	var travel := minf(CLIP_MARGIN, gap - 0.15)
	return hit_position - focus_to_hit.normalized() * maxf(travel, 0.05)
