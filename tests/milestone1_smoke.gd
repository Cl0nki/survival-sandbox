extends SceneTree

## Headless checks for Milestone 1. Run with:
## godot --headless --path <project> --script res://tests/milestone1_smoke.gd

func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	print("physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("test arena failed to load")
	var arena := packed.instantiate()
	root.add_child(arena)
	for _i in 60:
		await physics_frame

	var player := arena.get_node("Player") as PlayerController
	if player == null:
		return _fail("player missing")
	if not player.is_on_floor():
		return _fail("player is not on the floor at %s" % player.global_position)
	if player.global_position.y < -0.05 or player.global_position.y > 0.3:
		return _fail("player height looks wrong: %s" % player.global_position)

	var forward := PlayerController.wish_direction(Vector2(0, -1), 0.0)
	if forward.dot(Vector3(0, 0, -1)) < 0.99:
		return _fail("forward wish is %s" % forward)
	var right := PlayerController.wish_direction(Vector2(1, 0), 0.0)
	if right.dot(Vector3(1, 0, 0)) < 0.99:
		return _fail("right wish is %s" % right)
	var yawed := PlayerController.wish_direction(Vector2(0, -1), PI * 0.5)
	if yawed.dot(Vector3(-1, 0, 0)) < 0.99:
		return _fail("yawed forward wish is %s" % yawed)

	var rig := player.get_node("CameraRig") as OrbitCamera
	var offset := OrbitCamera.camera_offset(0.0, 14.0)
	if offset.y < 5.0 or offset.z < 1.0:
		return _fail("camera offset is not above and behind: %s" % offset)
	if rig.get_camera() == null or not rig.get_camera().current:
		return _fail("camera is not current")
	if rig.get_camera().global_position.y < player.global_position.y + 2.0:
		return _fail("camera is too low: %s" % rig.get_camera().global_position)

	var screen_center := rig.get_camera().get_viewport().get_visible_rect().size * 0.5
	print("viewport_center=", screen_center)
	if screen_center.x > 2.0 and screen_center.y > 2.0:
		var aim := AimProjector.project(rig.get_camera(), screen_center, 0.0)
		print("center_aim=", aim)
		if absf(aim.y) > 0.02:
			return _fail("screen-center aim left the floor: %s" % aim)
		if aim.z >= player.global_position.z:
			return _fail("screen-center aim is not in front of the camera look: %s" % aim)

	player.set_physics_process(false)
	var space := player.get_world_3d().direct_space_state
	var spawn_chest := Vector3(0, 1.2, 8)
	var covered := arena.get_node("CoveredDummy") as Damageable
	var open := arena.get_node("OpenDummy") as Damageable
	var to_covered := Vector3(covered.global_position.x, spawn_chest.y, covered.global_position.z) - spawn_chest
	var covered_hit := HitscanWeapon.resolve_shot(space, spawn_chest, to_covered)
	if covered_hit["collider"] == covered:
		return _fail("covered dummy was hit through the divider")
	if covered_hit["collider"] == null or str((covered_hit["collider"] as Node).name) != "Divider":
		return _fail("expected Divider, got %s" % _node_name(covered_hit["collider"]))

	var to_open := Vector3(open.global_position.x, spawn_chest.y, open.global_position.z) - spawn_chest
	var open_hit := HitscanWeapon.resolve_shot(space, spawn_chest, to_open)
	if open_hit["collider"] != open:
		return _fail("expected Open Dummy, got %s at %s" % [_node_name(open_hit["collider"]), open_hit["point"]])

	var over_low := HitscanWeapon.resolve_shot(space, Vector3(5, 1.2, 8), Vector3(0, 0, -1))
	if over_low["collider"] == null or str((over_low["collider"] as Node).name) == "LowCover":
		return _fail("chest-height ray should clear LowCover, got %s" % _node_name(over_low["collider"]))
	var into_high := HitscanWeapon.resolve_shot(space, Vector3(-6, 1.2, 8), Vector3(0, 0, -1))
	if into_high["collider"] == null or str((into_high["collider"] as Node).name) != "HighCover":
		return _fail("expected HighCover, got %s" % _node_name(into_high["collider"]))

	player.global_position = Vector3(0, 0.2, 1.0)
	player.velocity = Vector3.ZERO
	await physics_frame
	for _step in 30:
		player.velocity = Vector3(0, -4, -10)
		player.move_and_slide()
		await physics_frame
	print("collision_stop=", player.global_position)
	if player.global_position.z > 0.2:
		return _fail("player did not move into the divider from %s" % player.global_position)
	if player.global_position.z < -0.7:
		return _fail("player walked through the divider to %s" % player.global_position)

	player.global_position = Vector3(-4.4, 0.1, 4.0)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	var visual := player.get_node("VisualRoot") as Node3D
	visual.rotation = Vector3.ZERO
	await physics_frame
	var lean_right := player.clamped_lean_offset(0.45)
	var lean_left := player.clamped_lean_offset(-0.45)
	print("lean_right=", lean_right, " lean_left=", lean_left, " basis_x=", visual.global_basis.x)
	if absf(lean_right - 0.45) > 0.02:
		return _fail("open-side lean should stay 0.45, got %s" % lean_right)
	if lean_left >= -0.05 or lean_left <= -0.45:
		return _fail("lean into HighCover was not clamped: %s" % lean_left)
	player.set_lean_visual(0.0)
	var neutral_origin := player.shot_origin()
	player.set_lean_visual(0.45)
	var leaned_origin := player.shot_origin()
	var origin_shift := leaned_origin - neutral_origin
	print("shot_neutral=", neutral_origin, " shot_leaned=", leaned_origin)
	if origin_shift.dot(visual.global_basis.x) < 0.35:
		return _fail("lean did not move the shot origin sideways: %s" % origin_shift)
	player.set_lean_visual(lean_left)
	var blocked_origin := player.shot_origin()
	print("shot_into_cover=", blocked_origin)
	if blocked_origin.x < -5.05:
		return _fail("leaned shot origin crossed HighCover: %s" % blocked_origin)
	player.set_lean_visual(0.0)

	player.global_position = Vector3(0, 0.1, -0.2)
	await physics_frame
	rig.set_yaw(PI)
	var cam_pos := rig.get_camera().global_position
	print("clipped_camera=", cam_pos)
	if cam_pos.z < -1.0:
		return _fail("camera passed through the divider to %s" % cam_pos)
	if cam_pos.y < 1.5:
		return _fail("clipped camera is too low: %s" % cam_pos)

	var weapon := player.get_node("HitscanWeapon") as HitscanWeapon
	weapon.try_fire(spawn_chest, to_open.normalized())
	if open.health != open.max_health - weapon.damage:
		return _fail("open dummy health is %s after a hit, feedback=%s" % [open.health, weapon.last_feedback])
	if weapon.last_feedback.find("Open Dummy") < 0:
		return _fail("feedback missing Open Dummy: %s" % weapon.last_feedback)
	var health_after_one := open.health
	weapon.try_fire(spawn_chest, to_open.normalized())
	if open.health != health_after_one:
		return _fail("cooldown did not block the second shot")
	await create_timer(weapon.cooldown_seconds + 0.05).timeout
	var covered_before := covered.health
	weapon.try_fire(spawn_chest, to_covered.normalized())
	if covered.health != covered_before:
		return _fail("covered dummy took damage through the wall")
	if weapon.last_feedback.find("Divider") < 0:
		return _fail("blocked shot feedback was %s" % weapon.last_feedback)

	print("MILESTONE1_SMOKE_OK")
	return 0


func _node_name(collider: Object) -> String:
	if collider == null:
		return "null"
	if collider is Node:
		return (collider as Node).name
	return str(collider)


func _fail(message: String) -> int:
	push_error(message)
	print("MILESTONE1_SMOKE_FAIL: ", message)
	return 1
