extends SceneTree

## Headless checks for Milestone 2.
## Run:
## godot --headless --path <project> --script res://tests/milestone2_net.gd
##
## Godot 4.7 has no script API for a second MultiplayerAPI inside one process,
## so this file drives the authoritative server directly. The two-process
## connection check is tools/start_multiplayer.ps1 -Automated.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _port := 0
var _fire_seq := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	var guard := _check_guards()
	if guard != 0:
		return guard
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("test arena failed to load")
	var server_peer := _listen()
	if server_peer == null:
		return _fail("could not bind a server port")
	print("test_port=", _port)
	root.get_multiplayer().multiplayer_peer = server_peer

	var arena := packed.instantiate()
	arena.force_mode = NetConfig.MODE_SERVER
	root.add_child(arena)
	var net := arena.get_node("GameNet") as GameNet
	if net == null:
		return _fail("server arena did not create GameNet")
	if not net.multiplayer.is_server():
		return _fail("arena is not running as the server")
	if arena.get_node_or_null("Player") != null:
		return _fail("server kept the baked local player")
	if arena.get_node_or_null("DebugOverlay") != null:
		return _fail("server instantiated the HUD")

	net._spawn_authority(2)
	net._spawn_authority(3)
	var settled: bool = await _wait_until(120, func() -> bool:
		var pawn_a := net.debug_player(2)
		var pawn_b := net.debug_player(3)
		return pawn_a != null and pawn_b != null and pawn_a.is_on_floor() and pawn_b.is_on_floor()
	)
	if not settled:
		return _fail("server players did not settle %s %s" % [net.debug_position(2), net.debug_position(3)])
	await physics_frame
	if net.debug_player(2).get_node_or_null("CameraRig") != null:
		return _fail("server pawn kept a camera")
	if net.debug_player(2).net_role != PlayerController.NetRole.SERVER:
		return _fail("spawned pawn is not server-owned")

	var spawn_a := net.debug_position(2)
	var spawn_b := net.debug_position(3)
	print("spawn_a=", spawn_a, " spawn_b=", spawn_b)
	if spawn_a.distance_to(spawn_b) < SpawnPoints.MIN_SEPARATION:
		return _fail("spawn positions overlap")

	var owner_view := _make_view(arena, 2, PlayerController.NetRole.OWNER, spawn_a)
	var puppet_view := _make_view(arena, 2, PlayerController.NetRole.PUPPET, spawn_a)
	var move_seq := 0
	for _step in 50:
		move_seq += 1
		net._handle_input(2, move_seq, 0.0, -1.0, 0.0, 0.0, 0.0)
		await physics_frame
		_push_view(owner_view, net.debug_player(2), move_seq)
		_push_view(puppet_view, net.debug_player(2), move_seq)
	for _step in 12:
		await physics_frame
		_push_view(owner_view, net.debug_player(2), move_seq)
		_push_view(puppet_view, net.debug_player(2), move_seq)
	var moved_a := net.debug_position(2)
	var still_b := net.debug_position(3)
	print("moved_a=", moved_a, " still_b=", still_b)
	if moved_a.z > spawn_a.z - 1.0:
		return _fail("movement was not simulated %s -> %s" % [spawn_a, moved_a])
	if absf(still_b.x - spawn_b.x) > 0.4 or absf(still_b.z - spawn_b.z) > 0.4:
		return _fail("peer 2 input moved peer 3")
	if owner_view.global_position.distance_to(moved_a) > 1.6:
		return _fail("owner correction missed the server pose")
	if puppet_view.remote_sample_count() < 2:
		return _fail("remote player has no interpolation buffer")
	if puppet_view.global_position.distance_to(spawn_a) < 0.45:
		return _fail("remote player did not leave the spawn pose")
	if puppet_view.global_position.distance_to(moved_a) > 2.2:
		return _fail("remote player is far from the server pose %s vs %s" % [puppet_view.global_position, moved_a])
	var smoother := _make_view(arena, 2, PlayerController.NetRole.OWNER, Vector3(0.0, 0.15, 0.0))
	smoother.consume_snapshot(10.0, Vector3(0.0, 0.15, 0.0), 0.0, 0.0, 100, Vector3.ZERO, 1)
	smoother.consume_snapshot(10.1, Vector3(0.0, 0.15, -0.4), 0.0, 0.0, 100, Vector3.ZERO, 2)
	smoother.present_at(10.05)
	if absf(smoother.global_position.z - -0.2) > 0.05:
		return _fail("owner presentation snapped instead of blending %s" % smoother.global_position)
	smoother.queue_free()

	net.debug_place(2, Vector3(0.0, 0.15, -14.0))
	for _step in 8:
		await physics_frame
	for _step in 45:
		move_seq += 1
		net._handle_input(2, move_seq, 0.0, -1.0, 0.0, 0.0, 0.0)
		await physics_frame
	for _step in 8:
		await physics_frame
	var blocked := net.debug_position(2)
	print("wall_stop=", blocked)
	if blocked.z > -16.5:
		return _fail("player did not reach the north wall from %s" % blocked)
	if blocked.z < -17.6:
		return _fail("player walked through the north wall to %s" % blocked)

	var before_invalid := net.debug_position(2)
	var rejected_before := net.rejected_inputs
	net._handle_input(2, move_seq, NAN, 0.0, 0.0, 0.0, 0.0)
	net._handle_input(2, move_seq + 1, 40.0, 0.0, 0.0, 0.0, 0.0)
	net._handle_input(2, 1, 0.0, -1.0, 0.0, 0.0, 0.0)
	net._handle_input(999, 1, 0.0, -1.0, 0.0, 0.0, 0.0)
	for _step in 8:
		await physics_frame
	if net.debug_position(2).distance_to(before_invalid) > 1.0:
		return _fail("invalid input teleported the player")
	if net.rejected_inputs < rejected_before + 4:
		return _fail("invalid input was not rejected (%s)" % net.rejected_inputs)

	var open_server := arena.get_node("OpenDummy") as Damageable
	var covered_server := arena.get_node("CoveredDummy") as Damageable
	var open_mirror := _mirror_dummy(arena, "OpenMirror")
	var covered_mirror := _mirror_dummy(arena, "CoveredMirror")
	net.debug_place(2, Vector3(0.0, 0.15, 8.0))
	for _step in 5:
		await physics_frame
	var open_aim := _aim_from_server(net.debug_player(2), open_server.global_position)
	var accepted_before := net.accepted_shots
	_fire(net, 2, open_aim)
	var open_hit: bool = await _wait_until(20, func() -> bool:
		return open_server.health == open_server.max_health - 34
	)
	if not open_hit:
		return _fail("open dummy health stayed %s" % open_server.health)
	if net.accepted_shots != accepted_before + 1 or net.confirmed_hits < 1:
		return _fail("valid shot was not counted")
	net._apply_network_health(0, 0, open_server.health)
	open_mirror.apply_authoritative_health(open_server.health)
	if open_mirror.health != open_server.health:
		return _fail("mirrored dummy did not take the authoritative health")

	var health_after_one := open_server.health
	var rejected_shots := net.rejected_shots
	for _burst in 16:
		_fire(net, 2, open_aim)
	_fire(net, 2, {"direction": Vector3(NAN, NAN, NAN), "yaw": 0.0})
	_fire(net, 2, {"direction": Vector3(8.0, 0.75, -6.0), "yaw": 0.0})
	if open_server.health != health_after_one:
		return _fail("cooldown or invalid aim changed health to %s" % open_server.health)
	if net.rejected_shots <= rejected_shots + 8:
		return _fail("rapid and invalid shots were not rejected (%s)" % net.rejected_shots)
	if net.accepted_shots != accepted_before + 1:
		return _fail("extra shots were accepted")

	var weapon := net.debug_player(2).get_node("HitscanWeapon") as HitscanWeapon
	weapon.try_fire(Vector3(0.0, 1.2, 8.0), open_aim.direction)
	if weapon.last_feedback != "rejected local fire" or open_server.health != health_after_one:
		return _fail("local try_fire applied damage on a server pawn")

	await create_timer(0.45).timeout
	net.debug_reset_cooldown(2)
	net.debug_place(2, Vector3(0.0, 0.15, -16.0))
	for _step in 3:
		await physics_frame
	var covered_before := covered_server.health
	var covered_aim := _aim_from_server(net.debug_player(2), Vector3(0.0, 1.2, -22.0))
	var origin_before := net.debug_player(2).shot_origin()
	var blocked_accepted := net.accepted_shots
	_fire(net, 2, covered_aim)
	await physics_frame
	if net.accepted_shots != blocked_accepted + 1:
		return _fail("shot into the north wall was rejected")
	if covered_server.health != covered_before:
		return _fail("covered dummy took damage through the north wall")
	var shot_origin := net.debug_player(2).shot_origin()
	print("blocked_origin=", shot_origin)
	if shot_origin.distance_to(origin_before) > 2.5:
		return _fail("shot origin moved away from the pawn")
	if shot_origin.z < -17.7:
		return _fail("shot origin crossed the north wall %s" % shot_origin)
	if shot_origin.distance_to(net.debug_position(2)) > 2.5:
		return _fail("shot origin was not taken from the player %s" % shot_origin)

	net.debug_reset_cooldown(2)
	net.debug_place(2, Vector3(-12.0, 0.15, 0.0))
	for _step in 5:
		await physics_frame
	var side_aim := _aim_from_server(net.debug_player(2), covered_server.global_position)
	_fire(net, 2, side_aim)
	var side_hit: bool = await _wait_until(20, func() -> bool:
		return covered_server.health == covered_before - 34
	)
	if not side_hit:
		return _fail("covered dummy was not hit in the open yard, health=%s" % covered_server.health)
	covered_mirror.apply_authoritative_health(covered_server.health)
	if covered_mirror.health != covered_server.health:
		return _fail("covered health mirror diverged")

	net.debug_reset_cooldown(2)
	net.debug_place(2, Vector3(0.0, 0.15, -16.0))
	net.debug_place(3, Vector3(0.0, 0.15, -20.5))
	for _step in 5:
		await physics_frame
	var hidden := net.debug_player(3)
	var hidden_health := hidden.health
	var wall_aim := _aim_from_server(net.debug_player(2), hidden.global_position + Vector3(0.0, 1.0, 0.0))
	_fire(net, 2, wall_aim)
	await physics_frame
	if hidden.health != hidden_health:
		return _fail("player took damage through the north wall")

	net.debug_reset_cooldown(2)
	net.debug_place(2, Vector3(-2.0, 0.15, 8.0))
	net.debug_place(3, Vector3(2.0, 0.15, 8.0))
	for _step in 5:
		await physics_frame
	var victim := net.debug_player(3)
	var victim_before := victim.health
	var victim_aim := _aim_from_server(net.debug_player(2), victim.global_position + Vector3(0.0, 1.0, 0.0))
	_fire(net, 2, victim_aim)
	var player_hit: bool = await _wait_until(20, func() -> bool:
		return victim.health == victim_before - 34
	)
	if not player_hit:
		return _fail("player shot missed, health=%s" % victim.health)
	var health_view := _make_view(arena, 3, PlayerController.NetRole.PUPPET, victim.global_position)
	net._visuals[3] = health_view
	net._apply_network_health(1, 3, victim.health)
	if health_view.health != victim.health:
		return _fail("player health was not applied to the remote view")

	var shooter := net.debug_player(2)
	var stand_muzzle := shooter.shot_origin().y
	shooter.snap_stance_for_shot(1.0)
	if shooter.shot_origin().y > stand_muzzle - 0.25:
		return _fail("server crouch left the muzzle at %s" % shooter.shot_origin())
	var crouch_shape := (shooter.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	if absf(crouch_shape.height - PlayerController.CROUCH_HEIGHT) > 0.05:
		return _fail("server crouch hitbox is %s" % crouch_shape.height)
	shooter.snap_stance_for_shot(0.0)
	victim.snap_stance_for_shot(1.0)
	net.debug_reset_cooldown(2)
	var over_head := _aim_3d(shooter, victim.global_position + Vector3(0.0, 1.45, 0.0))
	var crouched_health := victim.health
	_fire(net, 2, over_head)
	if victim.health != crouched_health:
		return _fail("shot over a crouched player dealt damage")
	net.debug_reset_cooldown(2)
	var into_body := _aim_3d(shooter, victim.global_position + Vector3(0.0, 0.55, 0.0))
	_fire(net, 2, into_body)
	if victim.health != crouched_health - 34:
		return _fail("shot into a crouched player missed, health=%s" % victim.health)
	victim.snap_stance_for_shot(0.0)
	shooter.snap_stance_for_shot(0.0)
	var shooter_bag := net.debug_inventory(2)
	if shooter_bag.count_item("debugweapon") != 1 or shooter_bag.count_item("ammunition") != 0:
		return _fail("debug weapon changed ammo or itself during shots")
	var gun_slot := -1
	for index in shooter_bag.capacity:
		if str(shooter_bag.slots[index]["id"]) == "debugweapon":
			gun_slot = index
			shooter_bag.slots[index] = {"id": "", "qty": 0}
	net.debug_reset_cooldown(2)
	var unarmed_health := victim.health
	_fire(net, 2, into_body)
	if victim.health != unarmed_health:
		return _fail("shot without the debug weapon dealt damage")
	if gun_slot >= 0:
		shooter_bag.slots[gun_slot] = {"id": "debugweapon", "qty": 1}

	var peers_before := net.debug_player_count()
	net._on_peer_disconnected(3)
	if net.debug_player(3) != null or net.debug_player_count() != peers_before - 1:
		return _fail("disconnect did not remove the player")
	net._handle_fire(3, 80, Vector3(0.0, 0.0, -1.0), 0.0, 0.0)
	if server_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return _fail("server peer dropped after a disconnect")
	if net.debug_player(2) == null:
		return _fail("disconnect removed the remaining player")

	net.debug_reset_cooldown(2)
	net.debug_place(2, Vector3(0.0, 0.15, 8.0))
	for _step in 5:
		await physics_frame
	var survivor_health := open_server.health
	var again := _aim_from_server(net.debug_player(2), open_server.global_position)
	_fire(net, 2, again)
	var still_shooting: bool = await _wait_until(20, func() -> bool:
		return open_server.health == survivor_health - 34
	)
	if not still_shooting:
		return _fail("server stopped resolving shots after disconnect, health=%s" % open_server.health)

	print("MILESTONE2_NET_OK")
	return 0


func _check_guards() -> int:
	if not SpawnPoints.separated():
		return _fail("spawn points overlap")
	var parsed := NetConfig.parse(PackedStringArray(["--server", "--port", "7777", "--status-file", "server.txt"]))
	if int(parsed.mode) != NetConfig.MODE_SERVER or int(parsed.port) != 7777:
		return _fail("server args parsed as %s" % parsed)
	var client_args := NetConfig.parse(PackedStringArray([
		"--client", "--address", "127.0.0.1", "--port", "7777", "--window-x", "40", "--window-y", "80", "--bot",
	]))
	if int(client_args.mode) != NetConfig.MODE_CLIENT or not bool(client_args.bot):
		return _fail("client args parsed as %s" % client_args)
	if str(NetConfig.parse(PackedStringArray(["--server", "--client"])).error) == "":
		return _fail("conflicting mode was accepted")

	var bad_move := InputGuard.sanitize_move(NAN, 0.0, 0.0, 0.0, 0.0)
	if bool(bad_move.get("ok", true)):
		return _fail("non-finite movement was accepted")
	var huge_move := InputGuard.sanitize_move(40.0, 0.0, 0.0, 0.0, 0.0)
	if bool(huge_move.get("ok", true)):
		return _fail("huge movement axis was accepted")
	var clamped := InputGuard.sanitize_move(1.2, -0.25, 0.0, 0.0, 0.0)
	if not bool(clamped.get("ok", false)) or float((clamped["axes"] as Vector2).x) != 1.0:
		return _fail("legal axis was not clamped %s" % clamped)
	if clamped.has("position"):
		return _fail("movement command included a position")
	var world_point := InputGuard.sanitize_aim(Vector3(8.0, 0.75, -6.0), 0.0, 0.0)
	if bool(world_point.get("ok", true)):
		return _fail("world position was accepted as an aim")
	var vertical := InputGuard.sanitize_aim(Vector3(0.0, 1.0, 0.0), 0.0, 0.0)
	if bool(vertical.get("ok", true)):
		return _fail("vertical aim was accepted")
	var nan_aim := InputGuard.sanitize_aim(Vector3(NAN, 0.0, 0.0), 0.0, 0.0)
	if bool(nan_aim.get("ok", true)):
		return _fail("non-finite aim was accepted")
	var aim := InputGuard.sanitize_aim(Vector3(0.0, 0.0, -1.0), 0.2, 0.0)
	if not bool(aim.get("ok", false)):
		return _fail("unit aim was rejected %s" % aim)
	var high_aim := InputGuard.sanitize_aim(Vector3(0.0, 0.5, -0.8660254), 0.0, 0.0)
	if not bool(high_aim.get("ok", false)) or float((high_aim["direction"] as Vector3).y) < 0.4:
		return _fail("high aim was rejected %s" % high_aim)
	var low_aim := InputGuard.sanitize_aim(Vector3(0.0, -0.5, -0.8660254), 0.0, 0.0)
	if not bool(low_aim.get("ok", false)) or float((low_aim["direction"] as Vector3).y) > -0.4:
		return _fail("low aim was rejected %s" % low_aim)
	var steep := Vector3(0.0, sin(deg_to_rad(70.0)), -cos(deg_to_rad(70.0)))
	var clamped_pitch := InputGuard.sanitize_aim(steep, 0.0, 0.0)
	if not bool(clamped_pitch.get("ok", false)):
		return _fail("steep aim was rejected %s" % clamped_pitch)
	if float((clamped_pitch["direction"] as Vector3).y) > sin(InputGuard.MAX_AIM_PITCH) + 0.02:
		return _fail("steep aim was not clamped %s" % clamped_pitch["direction"])
	var bad_crouch := InputGuard.sanitize_move(0.0, 0.0, 0.0, 0.0, 0.0, 4.0, 0.0)
	if bool(bad_crouch.get("ok", true)):
		return _fail("crouch value 4 was accepted")

	var buffer := MotionBuffer.new()
	buffer.push(0.0, Vector3(0.0, 0.0, 0.0), 0.0, 0.0)
	buffer.push(0.1, Vector3(0.0, 0.0, -4.0), 0.4, 0.4)
	var mid := buffer.sample(0.05)
	var mid_pos: Vector3 = mid["position"]
	if absf(mid_pos.z - -2.0) > 0.05 or bool(mid["snapped"]):
		return _fail("interpolation sample was %s" % mid)
	var snap_buffer := MotionBuffer.new()
	snap_buffer.push(0.0, Vector3.ZERO, 0.0, 0.0)
	snap_buffer.push(0.1, Vector3(0.0, 0.0, -20.0), 0.0, 0.0)
	var snapped := snap_buffer.sample(0.05)
	var snapped_pos: Vector3 = snapped["position"]
	if absf(snapped_pos.z - -20.0) > 0.01 or not bool(snapped["snapped"]):
		return _fail("large gap should snap, got %s" % snapped)
	return 0


func _listen() -> ENetMultiplayerPeer:
	for port in range(25110, 25140):
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, 8)
		if err == OK:
			_port = port
			return peer
		peer.close()
	return null


func _make_view(arena: Node, peer_id: int, role: PlayerController.NetRole, pos: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.name = "View_%d_%d" % [peer_id, role]
	player.configure_net(role, peer_id)
	arena.add_child(player)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	if role == PlayerController.NetRole.OWNER:
		player.mark_authoritative_pose()
	else:
		player.seed_motion(pos, 0.0)
	return player


func _push_view(view: PlayerController, source: PlayerController, seq: int) -> void:
	if view == null or source == null:
		return
	view.consume_snapshot(
		Time.get_ticks_msec() / 1000.0,
		source.global_position,
		source.get_facing_yaw(),
		source.get_lean_offset(),
		source.health,
		source.velocity,
		seq
	)


func _mirror_dummy(arena: Node, node_name: String) -> Damageable:
	var packed := load("res://scenes/world/target_dummy.tscn") as PackedScene
	var dummy := packed.instantiate() as Damageable
	dummy.name = node_name
	dummy.position = Vector3(0.0, -20.0, 0.0)
	arena.add_child(dummy)
	return dummy


func _fire(net: GameNet, peer_id: int, aim: Dictionary) -> void:
	_fire_seq += 1
	net._handle_fire(peer_id, _fire_seq, aim.direction, float(aim.yaw), 0.0)


func _aim_3d(shooter: PlayerController, target: Vector3) -> Dictionary:
	var yaw := _yaw_toward(shooter.global_position, target)
	shooter.apply_facing_yaw(yaw)
	shooter.snap_lean_for_shot(0.0)
	shooter.set_aim_pitch(0.0)
	var origin := shooter.shot_origin()
	var toward := target - origin
	if toward.length_squared() < 0.0001:
		toward = Vector3(0.0, 0.0, -1.0)
	return {"direction": toward.normalized(), "yaw": yaw}


func _aim_from_server(shooter: PlayerController, target: Vector3) -> Dictionary:
	var yaw := _yaw_toward(shooter.global_position, target)
	shooter.apply_facing_yaw(yaw)
	shooter.snap_lean_for_shot(0.0)
	var origin := shooter.shot_origin()
	var flat := Vector3(target.x, 0.0, target.z) - Vector3(origin.x, 0.0, origin.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, -1.0)
	return {"direction": flat.normalized(), "yaw": yaw}


func _yaw_toward(from_pos: Vector3, to_pos: Vector3) -> float:
	var flat := Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return atan2(-flat.x, -flat.z)


func _wait_until(max_frames: int, predicate: Callable) -> bool:
	for _frame in max_frames:
		if bool(predicate.call()):
			return true
		await physics_frame
	return false


func _fail(message: String) -> int:
	push_error(message)
	print("MILESTONE2_NET_FAIL: ", message)
	return 1
