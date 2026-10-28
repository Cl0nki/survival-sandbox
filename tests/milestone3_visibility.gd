extends SceneTree

## Headless checks for Milestone 3 visibility filtering.
## Run:
## godot --headless --path <project> --script res://tests/milestone3_visibility.gd
##
## The snapshot encoder is the same function the server sends with rpc_id.
## A hidden enemy must be absent from that payload, not merely hidden on screen.

var _port := 0
var _fire_seq := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("test arena failed to load")
	var server_peer := _listen()
	if server_peer == null:
		return _fail("could not bind a server port")
	root.get_multiplayer().multiplayer_peer = server_peer
	var arena := packed.instantiate()
	arena.force_mode = NetConfig.MODE_SERVER
	root.add_child(arena)
	var net := arena.get_node("GameNet") as GameNet
	if net == null or not net.multiplayer.is_server():
		return _fail("server arena missing")
	for _frame in 20:
		await physics_frame
	net._spawn_authority(2)
	net._spawn_authority(3)
	for _frame in 8:
		await physics_frame

	net.debug_place(2, Vector3(-6.0, 0.15, 10.0))
	net.debug_place(3, Vector3(6.0, 0.15, 10.0))
	await physics_frame
	if not net.debug_visible(2, 3) or not net.debug_visible(3, 2):
		return _fail("open yard did not have mutual sight")
	var open_known: Dictionary = net.debug_known_positions(2)
	if not open_known.has(2) or not open_known.has(3):
		return _fail("open snapshot missing a visible player %s" % open_known.keys())
	var seen_remote: Vector3 = open_known[3]
	if seen_remote.distance_to(net.debug_position(3)) > 0.4:
		return _fail("visible snapshot pose was wrong %s" % seen_remote)

	net.debug_place(2, Vector3(0.0, 0.15, -15.5))
	net.debug_place(3, Vector3(0.0, 0.15, -20.5))
	await physics_frame
	if net.debug_visible(2, 3) or net.debug_visible(3, 2):
		return _fail("north wall did not block sight")

	net.debug_place(2, Vector3(-8.0, 0.15, -15.0))
	net.debug_place(3, Vector3(8.0, 0.15, -15.0))
	await physics_frame
	if not net.debug_visible(2, 3):
		return _fail("players along the inside of the wall stayed hidden")

	net.debug_place(2, Vector3(0.0, 0.15, -14.0))
	net.debug_place(3, Vector3(11.25, 0.15, -20.5))
	await physics_frame
	var hidden: Dictionary = net.debug_known_positions(2)
	if hidden.has(3):
		return _fail("hidden enemy was still in the snapshot %s" % hidden[3])
	if not hidden.has(2):
		return _fail("observer lost their own snapshot")
	if net.debug_snapshot_has_value(2, 11.25) or net.debug_snapshot_has_value(2, -20.5):
		return _fail("hidden coordinates were present in the outbound snapshot")
	var moved_hidden := net.debug_position(3)
	if not net.debug_visible(2, 3) and hidden.has(3):
		return _fail("moved hidden player became known %s" % moved_hidden)

	net.debug_place(2, Vector3(0.0, 0.15, -12.0))
	net.debug_place(3, Vector3(9.0, 0.15, -8.0))
	await physics_frame
	if not net.debug_visible(2, 3):
		return _fail("line of sight did not return inside the yard")
	var revealed: Dictionary = net.debug_known_positions(2)
	if not revealed.has(3):
		return _fail("revealed player was left out of the snapshot")

	net.debug_place(2, Vector3(-16.0, 0.15, 14.0))
	net.debug_place(3, Vector3(16.0, 0.15, 14.0))
	await physics_frame
	if not net.debug_visible(2, 3) or not net.debug_visible(3, 2):
		return _fail("open pair inside gun range stayed hidden")

	var peeker := net.debug_player(2)
	net.debug_place(2, Vector3(0.0, 0.15, -16.2))
	net.debug_place(3, Vector3(0.4, 0.15, -20.2))
	peeker.apply_facing_yaw(0.0)
	peeker.set_lean_visual(0.45)
	net._refresh_visibility()
	await physics_frame
	if net.debug_visible(2, 3):
		return _fail("lean revealed a player through the north wall")
	peeker.set_lean_visual(0.0)
	net._refresh_visibility()
	await physics_frame
	if net.debug_visible(2, 3):
		return _fail("player beyond the north wall was visible")

	net.debug_set_view_distance(4.0)
	net.debug_place(2, Vector3(-6.0, 0.15, 10.0))
	net.debug_place(3, Vector3(6.0, 0.15, 10.0))
	await physics_frame
	if net.debug_visible(2, 3):
		return _fail("players beyond the view distance stayed visible")
	var far: Dictionary = net.debug_known_positions(2)
	if far.has(3):
		return _fail("out-of-range player was still replicated")
	net.debug_set_view_distance(NetConfig.VISIBILITY_DISTANCE)

	net.debug_place(2, Vector3(-4.0, 0.15, 8.0))
	net.debug_place(3, Vector3(4.0, 0.15, 8.0))
	await physics_frame
	if not net.debug_visible(2, 3):
		return _fail("sight did not recover inside the view distance")
	var before := net.debug_player(3).health
	var shooter := net.debug_player(2)
	var victim := net.debug_player(3)
	var flat := victim.global_position - shooter.global_position
	var yaw := atan2(-flat.x, -flat.z)
	shooter.apply_facing_yaw(yaw)
	shooter.snap_lean_for_shot(0.0)
	var aim := (victim.global_position + Vector3(0.0, 1.0, 0.0)) - shooter.shot_origin()
	_fire_seq += 1
	net._handle_fire(2, _fire_seq, aim.normalized(), yaw, 0.0, 0.0)
	await physics_frame
	if net.debug_player(3).health != before - 34:
		return _fail("visible shot did no damage, health=%s" % net.debug_player(3).health)

	var move_seq := 0
	var start_z := net.debug_position(2).z
	for _step in 20:
		move_seq += 1
		net._handle_input(2, move_seq, 0.0, -1.0, 0.0, 0.0, 0.0)
		await physics_frame
	if net.debug_position(2).z > start_z - 0.4:
		return _fail("visibility filtering stopped movement")

	net._on_peer_disconnected(3)
	if net.debug_player(3) != null:
		return _fail("disconnect left the hidden-capable pawn on the server")
	var after: Dictionary = net.debug_known_positions(2)
	if after.has(3):
		return _fail("disconnected player remained in the snapshot")

	print("MILESTONE3_VISIBILITY_OK")
	return 0


func _listen() -> ENetMultiplayerPeer:
	for port in range(25210, 25240):
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, 8)
		if err == OK:
			_port = port
			return peer
		peer.close()
	return null


func _fail(message: String) -> int:
	push_error(message)
	print("MILESTONE3_VISIBILITY_FAIL: ", message)
	return 1
