extends CharacterBody3D
class_name PlayerController

## LOCAL-ONLY movement, facing, lean, and fire trigger.
## Milestone 2: the server owns position, whether a lean is legal for gameplay,
## and whether a shot is accepted. This node can keep reading input and playing
## a predicted pose, but it must not stay authoritative.
## Shots start at the weapon muzzle, which is parented to the lean pivot.
## If the barrel would begin inside a wall, the origin is pulled back to the
## near side of that wall. Lean can shoot around a corner. It cannot start a
## shot on the far side of solid cover.

const AIM_PLANE_Y := 0.0
const CHEST_HEIGHT := 1.2
const BODY_RADIUS := 0.35
const LEAN_DISTANCE := 0.45
const LEAN_MARGIN := 0.12
const LEAN_BLEND_SPEED := 8.0
const WALK_SPEED := 5.0
const ACCELERATION := 28.0
const GRAVITY := 24.0

@onready var _visual_root: Node3D = $VisualRoot
@onready var _lean_pivot: Node3D = $VisualRoot/LeanPivot
@onready var _muzzle: Marker3D = $VisualRoot/LeanPivot/Muzzle
@onready var _camera: OrbitCamera = $CameraRig
@onready var _weapon: HitscanWeapon = $HitscanWeapon
@onready var _aim_marker: MeshInstance3D = $AimMarker

var _lean_offset := 0.0


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = PhysicsLayers.PLAYER
	collision_mask = PhysicsLayers.WORLD
	floor_snap_length = 0.4
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _physics_process(delta: float) -> void:
	rotation = Vector3.ZERO
	var aim := get_aim_point()
	_face_toward(aim)
	_move(delta)
	_update_lean(delta)
	_aim_marker.global_position = Vector3(aim.x, 0.04, aim.z)
	if Input.is_action_just_pressed(&"fire"):
		_weapon.try_fire(shot_origin(), _shot_direction(aim))


func get_aim_point() -> Vector3:
	var camera := _camera.get_camera()
	if camera == null:
		return global_position + Vector3(0.0, 0.0, -2.0)
	return AimProjector.project(camera, get_viewport().get_mouse_position(), AIM_PLANE_Y)


func get_lean_offset() -> float:
	return _lean_offset


func clamped_lean_offset(desired: float) -> float:
	## Largest visual sideways shift that keeps the body mesh on the near side
	## of world geometry. Two heights so a low crate and a tall wall both count.
	if is_zero_approx(desired):
		return 0.0
	var sign_dir := 1.0 if desired > 0.0 else -1.0
	var direction := _visual_root.global_basis.x * sign_dir
	var reach := absf(desired) + BODY_RADIUS + LEAN_MARGIN
	var allowance := absf(desired)
	var sample_heights: Array[float] = [0.7, 1.35]
	for sample_height: float in sample_heights:
		var origin := global_position + Vector3(0.0, sample_height, 0.0)
		var hit := _raycast_world(origin, origin + direction * reach)
		if hit.is_empty():
			continue
		var hit_position := hit["position"] as Vector3
		var clear := origin.distance_to(hit_position) - BODY_RADIUS - LEAN_MARGIN
		allowance = minf(allowance, maxf(clear, 0.0))
	return sign_dir * allowance


static func wish_direction(input_2d: Vector2, camera_yaw: float) -> Vector3:
	## input_2d matches Input.get_vector(left, right, forward, back):
	## +x is right, -y is forward. The result is camera-relative on the XZ plane.
	var planar := Basis(Vector3.UP, camera_yaw)
	var forward := -planar.z
	var right := planar.x
	var direction := right * input_2d.x + forward * (-input_2d.y)
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


func shot_origin() -> Vector3:
	## Muzzle after the current lean. A blocked segment from the chest to the
	## muzzle means the barrel is inside cover, so the shot starts on the near face.
	var muzzle := _muzzle.global_position
	var chest := global_position + Vector3(0.0, CHEST_HEIGHT, 0.0)
	if muzzle.distance_squared_to(chest) < 0.0001:
		return chest
	var hit := _raycast_world(chest, muzzle)
	if hit.is_empty():
		return muzzle
	var hit_position := hit["position"] as Vector3
	var toward_chest := chest - muzzle
	if toward_chest.length_squared() < 0.0001:
		return chest
	return hit_position + toward_chest.normalized() * 0.06


func _shot_direction(aim: Vector3) -> Vector3:
	var origin := shot_origin()
	var toward := Vector3(aim.x, origin.y, aim.z) - origin
	if toward.length_squared() < 0.04:
		toward = -_visual_root.global_basis.z
		toward.y = 0.0
	return toward.normalized()


func _face_toward(aim: Vector3) -> void:
	var flat := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if flat.length_squared() < 0.04:
		return
	# Node forward is -Z. This yaw is the aim, not the camera orbit.
	_visual_root.rotation.y = atan2(-flat.x, -flat.z)


func _move(delta: float) -> void:
	var input_2d := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := wish_direction(input_2d, _camera.get_yaw())
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * WALK_SPEED, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _update_lean(delta: float) -> void:
	var lean_input := Input.get_action_strength(&"lean_right") - Input.get_action_strength(&"lean_left")
	var allowed := clamped_lean_offset(lean_input * LEAN_DISTANCE)
	set_lean_visual(move_toward(_lean_offset, allowed, LEAN_BLEND_SPEED * delta))


func set_lean_visual(offset: float) -> void:
	_lean_offset = offset
	var ratio := 0.0 if is_zero_approx(LEAN_DISTANCE) else clampf(offset / LEAN_DISTANCE, -1.0, 1.0)
	_lean_pivot.position = Vector3(offset, 0.9 + absf(ratio) * 0.04, 0.0)
	_lean_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(-6.0) * ratio)
	_lean_pivot.force_update_transform()


func _raycast_world(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsLayers.WORLD
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return world.direct_space_state.intersect_ray(query)
