extends Node
class_name GameNet

## RPC surface for one arena.
## Client methods send requests. Server methods validate the sender, simulate,
## and replicate results. Shot events are visual only; health is a separate
## absolute value so a tracer cannot apply damage.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const _Sight = preload("res://scripts/networking/line_of_sight.gd")
const DUMMY_NAMES: Array[String] = ["OpenDummy", "CoveredDummy"]
const SNAPSHOT_STRIDE := 11

var rejected_inputs := 0
var rejected_shots := 0
var accepted_shots := 0
var confirmed_hits := 0
var last_shot_text := "none"
var last_shot_origin := Vector3.ZERO
var last_shot_end := Vector3.ZERO

var _players: Dictionary = {}
var _visuals: Dictionary = {}
var _connected_peers: Dictionary = {}
var _commands: Dictionary = {}
var _command_time: Dictionary = {}
var _move_seq: Dictionary = {}
var _fire_seq: Dictionary = {}
var _next_fire_msec: Dictionary = {}
var _spawn_by_peer: Dictionary = {}
var _spawn_seen: Dictionary = {}
var _rate_hits: Dictionary = {}
var _log_budget: Dictionary = {}
var _pending_player_health: Dictionary = {}
var _move_seq_out := 0
var _fire_seq_out := 0
var _tick := 0
var _snapshot_every := 3
var _local_confirmed := false
var _weapon_logged := false
var _bot_time := 0.0
var _bot_finished := false
var _ready_timer: Timer
var _snapshot_clock_origin := -1.0
var _view_distance := NetConfig.VISIBILITY_DISTANCE
var _vis_accum := 0.0
## observer peer id -> { target peer id: bool }. Self is not stored.
var _seen: Dictionary = {}
## Last filtered snapshot built for an observer. Not an RPC.
var _outbound: Dictionary = {}
var _pickups: Dictionary = {}
var _containers: Dictionary = {}
var _inventories: Dictionary = {}
var _open_container: Dictionary = {}
var _cursors: Dictionary = {}
var _drop_seq := 1
var _item_lock := false
var last_item_notice := {}
var last_container_recipients: Array[int] = []


func _ready() -> void:
	set_multiplayer_authority(1)
	var ticks := maxi(Engine.physics_ticks_per_second, 1)
	_snapshot_every = maxi(1, int(round(float(ticks) / float(NetConfig.SNAPSHOT_HZ))))
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		if _session_mode() == NetConfig.MODE_SERVER:
			_server_log("error peer missing before arena boot")
		return
	if multiplayer.is_server():
		_boot_server()
	else:
		_boot_client()
	_index_loot()


func _physics_process(delta: float) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return
	if multiplayer.is_server():
		_server_physics(delta)
	elif _is_bot() and _local_confirmed:
		_bot_move_seq_send()


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server() or not _is_bot() or _bot_finished:
		return
	_bot_time += delta
	if _bot_time > 12.0:
		_finish_bot(false, "timeout players=%d" % _visuals.size())
		return
	if not _local_confirmed or _visuals.size() < _expect_peers():
		return
	if _bot_time < 2.0 or not _remote_moved():
		return
	_finish_bot(true, "players=%d" % _visuals.size())


func send_owner_input(
	move: Vector2,
	camera_yaw: float,
	aim_yaw: float,
	lean: float,
	crouch: float,
	aim_pitch: float
) -> void:
	if not _client_connected():
		return
	_move_seq_out += 1
	submit_input.rpc_id(1, _move_seq_out, move.x, move.y, camera_yaw, aim_yaw, lean, crouch, aim_pitch)


func send_owner_fire(direction: Vector3, aim_yaw: float, lean: float, crouch: float) -> void:
	if not _client_connected():
		return
	_fire_seq_out += 1
	submit_fire.rpc_id(1, _fire_seq_out, direction, aim_yaw, lean, crouch)


func send_pickup(pickup_id: String) -> void:
	if not _client_connected():
		return
	request_pickup.rpc_id(1, pickup_id)


func send_open_container(container_id: String) -> void:
	if not _client_connected():
		return
	request_open_container.rpc_id(1, container_id)


func send_close_container() -> void:
	if not _client_connected():
		return
	request_close_container.rpc_id(1)


func send_item_transfer(container_id: String, to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not _client_connected():
		return
	request_transfer.rpc_id(1, container_id, to_container, source_slot, dest_slot, quantity)


func send_item_drop(container_id: String, to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not _client_connected():
		return
	request_drop.rpc_id(1, container_id, to_container, source_slot, dest_slot, quantity)


func send_item_rearrange(in_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not _client_connected():
		return
	request_rearrange.rpc_id(1, in_container, source_slot, dest_slot, quantity)


func send_slot_click(area: int, index: int, right: bool, shift: bool, collect: bool) -> void:
	if not _client_connected():
		return
	request_slot_click.rpc_id(1, area, index, right, shift, collect)


func send_slot_spread(areas: PackedInt32Array, indices: PackedInt32Array, right: bool) -> void:
	if not _client_connected():
		return
	request_slot_spread.rpc_id(1, areas, indices, right)


func send_slot_throw(area: int, index: int, whole: bool) -> void:
	if not _client_connected():
		return
	request_slot_throw.rpc_id(1, area, index, whole)


func send_hotbar_select(index: int) -> void:
	if not _client_connected():
		return
	request_hotbar_select.rpc_id(1, index)


func send_hotbar_swap(area: int, index: int, hotbar_index: int) -> void:
	if not _client_connected():
		return
	request_hotbar_swap.rpc_id(1, area, index, hotbar_index)


@rpc("any_peer", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		_server_log("client ready rejected sender=%d" % sender)
		return
	if not _connected_peers.has(sender):
		_note_peer(sender)
	if _players.has(sender):
		_sync_world_to(sender)
		return
	_server_log("client ready id=%d" % sender)
	_spawn_authority(sender)


@rpc("any_peer", "unreliable_ordered")
func submit_input(
	seq: int,
	move_x: float,
	move_y: float,
	camera_yaw: float,
	aim_yaw: float,
	lean: float,
	crouch: float,
	aim_pitch: float
) -> void:
	if not multiplayer.is_server():
		return
	_handle_input(
		multiplayer.get_remote_sender_id(),
		seq,
		move_x,
		move_y,
		camera_yaw,
		aim_yaw,
		lean,
		crouch,
		aim_pitch
	)


@rpc("any_peer", "reliable")
func submit_fire(seq: int, aim: Vector3, aim_yaw: float, lean: float, crouch: float) -> void:
	if not multiplayer.is_server():
		return
	_handle_fire(multiplayer.get_remote_sender_id(), seq, aim, aim_yaw, lean, crouch)


@rpc("any_peer", "reliable")
func request_pickup(pickup_id: String) -> void:
	if not multiplayer.is_server():
		return
	_handle_pickup(multiplayer.get_remote_sender_id(), pickup_id)


@rpc("any_peer", "reliable")
func request_open_container(container_id: String) -> void:
	if not multiplayer.is_server():
		return
	_handle_open_container(multiplayer.get_remote_sender_id(), container_id)


@rpc("any_peer", "reliable")
func request_close_container() -> void:
	if not multiplayer.is_server():
		return
	_handle_close_container(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func request_transfer(container_id: String, to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_transfer(multiplayer.get_remote_sender_id(), container_id, to_container, source_slot, dest_slot, quantity)


@rpc("any_peer", "reliable")
func request_drop(container_id: String, to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_drop(multiplayer.get_remote_sender_id(), container_id, to_container, source_slot, dest_slot, quantity)


@rpc("any_peer", "reliable")
func request_rearrange(in_container: bool, source_slot: int, dest_slot: int, quantity: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_rearrange(multiplayer.get_remote_sender_id(), in_container, source_slot, dest_slot, quantity)


@rpc("any_peer", "reliable")
func request_slot_click(area: int, index: int, right: bool, shift: bool, collect: bool) -> void:
	if not multiplayer.is_server():
		return
	_handle_slot_click(multiplayer.get_remote_sender_id(), area, index, right, shift, collect)


@rpc("any_peer", "reliable")
func request_slot_spread(areas: PackedInt32Array, indices: PackedInt32Array, right: bool) -> void:
	if not multiplayer.is_server():
		return
	_handle_slot_spread(multiplayer.get_remote_sender_id(), areas, indices, right)


@rpc("any_peer", "reliable")
func request_slot_throw(area: int, index: int, whole: bool) -> void:
	if not multiplayer.is_server():
		return
	_handle_slot_throw(multiplayer.get_remote_sender_id(), area, index, whole)


@rpc("any_peer", "reliable")
func request_hotbar_select(index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := _players.get(sender) as PlayerController
	if player == null or index < 0 or index >= NetConfig.HOTBAR_SLOTS:
		return
	player.hotbar_index = index


@rpc("any_peer", "reliable")
func request_hotbar_swap(area: int, index: int, hotbar_index: int) -> void:
	if not multiplayer.is_server():
		return
	_handle_hotbar_swap(multiplayer.get_remote_sender_id(), area, index, hotbar_index)


@rpc("authority", "reliable")
func inventory_sync(item_ids: PackedStringArray, item_qtys: PackedInt32Array) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player := _owner_visual()
	if player == null:
		return
	player.apply_confirmed_inventory(item_ids, item_qtys)


@rpc("authority", "reliable")
func cursor_sync(item_id: String, quantity: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player := _owner_visual()
	if player == null:
		return
	player.apply_confirmed_cursor(item_id, quantity)


@rpc("authority", "reliable")
func container_sync(container_id: String, item_ids: PackedStringArray, item_qtys: PackedInt32Array) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player := _owner_visual()
	if player == null:
		return
	player.apply_confirmed_container(container_id, item_ids, item_qtys)


@rpc("authority", "reliable")
func container_closed() -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player := _owner_visual()
	if player == null:
		return
	player.clear_container_view()


@rpc("authority", "reliable")
func inventory_notice(text: String) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player := _owner_visual()
	if player == null:
		return
	player.show_item_notice(text)


@rpc("authority", "reliable")
func loot_state(pickup_id: String, quantity: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var pickup := _find_pickup(pickup_id)
	if pickup == null:
		return
	pickup.apply_network_quantity(quantity)


@rpc("authority", "reliable")
func loot_spawn(pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if pickup_id.is_empty() or quantity <= 0 or not NetConfig.finite_vector(pos):
		return
	_ensure_pickup(pickup_id, item_id, quantity, pos)


@rpc("authority", "reliable")
func spawn_player(peer_id: int, pos: Vector3, yaw: float) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not NetConfig.finite_vector(pos) or not is_finite(yaw):
		return
	_spawn_visual(peer_id, pos, yaw)


@rpc("authority", "reliable")
func despawn_player(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_remove_visual(peer_id)


@rpc("authority", "reliable")
func hide_player(peer_id: int) -> void:
	## Visibility loss. The payload is only an id, never a transform.
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if peer_id == multiplayer.get_unique_id():
		return
	if not _visuals.has(peer_id):
		return
	_remove_visual(peer_id)


@rpc("authority", "reliable")
func health_update(kind: int, id: int, current: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	_apply_network_health(kind, id, current)


@rpc("authority", "reliable")
func shot_event(shooter: int, origin: Vector3, end_point: Vector3, damaged: bool) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not NetConfig.finite_vector(origin) or not NetConfig.finite_vector(end_point):
		return
	# Visual only. Damage arrives through health_update / snapshots.
	last_shot_origin = origin
	last_shot_end = end_point
	last_shot_text = "peer %d %s" % [shooter, "hit" if damaged else "impact"]
	ShotVisual.spawn(get_parent(), origin, end_point, damaged)


@rpc("authority", "unreliable_ordered")
func receive_snapshot(tick: int, ids: PackedInt32Array, seqs: PackedInt32Array, data: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if tick < 0 or ids.size() != seqs.size() or data.size() != ids.size() * SNAPSHOT_STRIDE:
		return
	for index in ids.size():
		var offset := index * SNAPSHOT_STRIDE
		var pos := Vector3(data[offset], data[offset + 1], data[offset + 2])
		if not NetConfig.finite_vector(pos):
			continue
		var yaw := data[offset + 3]
		var lean := data[offset + 4]
		var hp := int(round(data[offset + 5]))
		var velocity := Vector3(data[offset + 6], 0.0, data[offset + 7])
		var crouch := data[offset + 8]
		var pitch := data[offset + 9]
		if not is_finite(yaw) or not is_finite(lean) or not NetConfig.finite_vector(velocity):
			continue
		if not is_finite(crouch) or not is_finite(pitch):
			continue
		var drawn := data[offset + 10]
		if not is_finite(drawn):
			continue
		var player: PlayerController = _visuals.get(ids[index]) as PlayerController
		if player == null or not is_instance_valid(player):
			continue
		player.consume_snapshot(_snapshot_stamp(tick), pos, yaw, lean, hp, velocity, seqs[index], crouch, pitch)
		if player.net_role == PlayerController.NetRole.PUPPET:
			player.set_weapon_drawn(drawn > 0.5)


func debug_set_view_distance(meters: float) -> void:
	_view_distance = maxf(meters, 0.1)
	_refresh_visibility()


func debug_visible(observer: int, target: int) -> bool:
	return _is_visible(observer, target)


func debug_known_positions(observer: int) -> Dictionary:
	## Positions that observer's snapshot actually contains. Hidden enemies are absent.
	var packet := _snapshot_for(observer)
	_outbound[observer] = packet
	var ids: PackedInt32Array = packet["ids"]
	var data: PackedFloat32Array = packet["data"]
	var known := {}
	for index in ids.size():
		var offset := index * SNAPSHOT_STRIDE
		known[int(ids[index])] = Vector3(data[offset], data[offset + 1], data[offset + 2])
	return known


func debug_snapshot_has_value(observer: int, value: float, epsilon: float = 0.02) -> bool:
	var packet := _snapshot_for(observer)
	var data: PackedFloat32Array = packet["data"]
	for sample in data:
		if absf(float(sample) - value) <= epsilon:
			return true
	return false


func debug_player_count() -> int:
	return _players.size() if multiplayer.is_server() else _visuals.size()


func debug_ids() -> Array:
	if multiplayer.is_server():
		return _players.keys()
	return _visuals.keys()


func debug_player(peer_id: int) -> PlayerController:
	var source: Dictionary = _players if multiplayer.is_server() else _visuals
	return source.get(peer_id) as PlayerController


func debug_position(peer_id: int) -> Vector3:
	var player := debug_player(peer_id)
	if player == null:
		return Vector3(INF, INF, INF)
	return player.global_position


func debug_place(peer_id: int, pos: Vector3) -> void:
	## In-process test hook. Not an RPC, so a remote client cannot call it.
	if not multiplayer.is_server():
		return
	var player := _players.get(peer_id) as PlayerController
	if player == null:
		return
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.force_update_transform()
	_commands.erase(peer_id)
	_command_time.erase(peer_id)
	_refresh_visibility()


func debug_reset_cooldown(peer_id: int) -> void:
	## Test hook. Clears the server fire gate so the next scenario is not
	## waiting on the previous shot. Not an RPC.
	_next_fire_msec.erase(peer_id)
	_rate_hits.erase("fire:%d" % peer_id)


func _boot_server() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	for id in multiplayer.get_peers():
		_note_peer(int(id))
	var port := 0
	if _session_mode() == NetConfig.MODE_SERVER:
		port = _session_port()
	var line := "SERVER_READY port=%d" % port
	print(line)
	if _session_mode() == NetConfig.MODE_SERVER:
		NetConfig.append_line(_status_path(), line)
	_server_log("arena ready tick_hz=%d snapshot_every=%d" % [Engine.physics_ticks_per_second, _snapshot_every])


func _boot_client() -> void:
	_strip_client_container_secrets()
	_ready_timer = Timer.new()
	_ready_timer.wait_time = 0.2
	add_child(_ready_timer)
	_ready_timer.timeout.connect(_try_client_ready)
	_ready_timer.start()
	_try_client_ready()


func _on_peer_connected(id: int) -> void:
	_note_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not _connected_peers.has(id) and not _players.has(id):
		return
	_connected_peers.erase(id)
	_server_log("peer disconnected id=%d" % id)
	if _players.has(id):
		_release_player(id)
		_server_log("despawned player id=%d" % id)
	else:
		_clear_peer_limits(id)


func _note_peer(id: int) -> void:
	if id <= 1 or _connected_peers.has(id):
		return
	_connected_peers[id] = true
	_server_log("peer connected id=%d" % id)


func _try_client_ready() -> void:
	if _local_confirmed:
		if _ready_timer != null:
			_ready_timer.stop()
		return
	if not _client_connected():
		return
	client_ready.rpc_id(1)


func _server_physics(delta: float) -> void:
	_tick += 1
	var now := _now_sec()
	for key in _players.keys():
		var id := int(key)
		var player := _players[id] as PlayerController
		if player == null or not is_instance_valid(player):
			continue
		if not _position_sane(player):
			_server_log("error non-finite position peer=%d" % id)
			var recover: Vector3 = _spawn_by_peer.get(id, Vector3(0.0, 0.15, 8.0))
			player.global_position = recover
			player.velocity = Vector3.ZERO
			continue
		var axes := Vector2.ZERO
		var camera_yaw := 0.0
		var aim_yaw := player.get_facing_yaw()
		var lean := 0.0
		var crouch := 0.0
		var aim_pitch := 0.0
		var cmd: Dictionary = _commands.get(id, {})
		var stamp := float(_command_time.get(id, 0.0))
		if not cmd.is_empty() and now - stamp <= NetConfig.STALE_INPUT_SEC:
			axes = cmd["axes"]
			camera_yaw = float(cmd["camera_yaw"])
			aim_yaw = float(cmd["aim_yaw"])
			lean = float(cmd["lean"])
			crouch = float(cmd["crouch"])
			aim_pitch = float(cmd["aim_pitch"])
		if player.health <= 0:
			axes = Vector2.ZERO
			crouch = 0.0
		if _open_container.has(id):
			axes = Vector2.ZERO
		player.simulate_authored_motion(delta, axes, camera_yaw, aim_yaw, lean, crouch, aim_pitch)
	_vis_accum += delta
	if NetConfig.VISIBILITY_INTERVAL_SEC <= 0.0 or _vis_accum >= NetConfig.VISIBILITY_INTERVAL_SEC:
		_vis_accum = 0.0
		_refresh_visibility()
	if _tick % _snapshot_every == 0:
		_publish_snapshots()


func _handle_input(
	sender: int,
	seq: int,
	move_x: float,
	move_y: float,
	camera_yaw: float,
	aim_yaw: float,
	lean: float,
	crouch: float = 0.0,
	aim_pitch: float = 0.0
) -> void:
	if sender <= 1 or not _players.has(sender):
		_reject_input(sender, "sender")
		return
	if not _rate_ok(sender, "move", NetConfig.INPUT_RATE_PER_SEC):
		_reject_input(sender, "rate")
		return
	var clean := InputGuard.sanitize_move(move_x, move_y, camera_yaw, aim_yaw, lean, crouch, aim_pitch)
	if not bool(clean.get("ok", false)):
		_reject_input(sender, str(clean.get("reason", "invalid")))
		return
	if not _accept_seq(_move_seq, sender, seq):
		_reject_input(sender, "sequence")
		return
	_commands[sender] = clean
	_command_time[sender] = _now_sec()


func _weapon_drawn(peer_id: int) -> bool:
	var bag := _inventories.get(peer_id) as Inventory
	var player := _players.get(peer_id) as PlayerController
	if bag == null or player == null:
		return false
	var index := player.hotbar_index
	if index < 0 or index >= bag.capacity:
		return false
	var slot: Dictionary = bag.slots[index]
	return str(slot["id"]) == "debugweapon" and int(slot["qty"]) > 0


func _handle_fire(sender: int, seq: int, aim: Vector3, aim_yaw: float, lean: float, crouch: float = 0.0) -> void:
	if sender <= 1:
		_reject_shot(sender, "sender")
		return
	var player := _players.get(sender) as PlayerController
	if player == null or not is_instance_valid(player):
		_reject_shot(sender, "no_player")
		return
	if player.health <= 0:
		_reject_shot(sender, "down")
		return
	if not _weapon_drawn(sender):
		_reject_shot(sender, "unarmed")
		return
	if not _rate_ok(sender, "fire", NetConfig.FIRE_RATE_PER_SEC):
		_reject_shot(sender, "rate")
		return
	var clean := InputGuard.sanitize_aim(aim, aim_yaw, lean, crouch)
	if not bool(clean.get("ok", false)):
		_reject_shot(sender, str(clean.get("reason", "invalid_aim")))
		return
	if not _accept_seq(_fire_seq, sender, seq):
		_reject_shot(sender, "sequence")
		return
	var weapon := player.get_node_or_null("HitscanWeapon") as HitscanWeapon
	if weapon == null:
		_reject_shot(sender, "weapon")
		return
	_log_weapon_once(weapon)
	var now := Time.get_ticks_msec()
	var next_fire := int(_next_fire_msec.get(sender, 0))
	if now < next_fire:
		_reject_shot(sender, "cooldown")
		return
	var world := player.get_world_3d()
	if world == null or world.direct_space_state == null:
		_reject_shot(sender, "world")
		return
	player.snap_stance_for_shot(float(clean["crouch"]))
	player.apply_facing_yaw(float(clean["aim_yaw"]))
	player.snap_lean_for_shot(float(clean["lean"]))
	var direction: Vector3 = clean["direction"]
	player.set_aim_pitch(asin(clampf(direction.y, -1.0, 1.0)))
	_refresh_visibility()
	var origin := player.shot_origin()
	var result := HitscanWeapon.resolve_shot(
		world.direct_space_state,
		origin,
		direction,
		weapon.range_meters,
		[player.get_rid()]
	)
	var damaged := false
	var collider: Object = result["collider"]
	if collider != null and collider != player and collider.has_method("receive_damage"):
		damaged = bool(collider.call("receive_damage", weapon.damage, result["point"]))
	var cooldown_ms := int(round(weapon.cooldown_seconds * 1000.0))
	_next_fire_msec[sender] = now + maxi(cooldown_ms, 1)
	accepted_shots += 1
	var target := _collider_name(collider)
	var health_left := _health_of(collider)
	if damaged:
		confirmed_hits += 1
		_replicate_collider_health(collider)
	var end_point: Vector3 = result["point"]
	_server_log(
		"shot peer=%d origin=%s dir=%s result=%s damaged=%s health=%s"
		% [sender, origin, direction, target, damaged, health_left]
	)
	_send_shot_event(sender, origin, end_point, damaged, collider)


func _snapshot_for(observer: int) -> Dictionary:
	var ids := PackedInt32Array()
	var seqs := PackedInt32Array()
	var data := PackedFloat32Array()
	for key in _players.keys():
		var id := int(key)
		if id != observer and not _is_visible(observer, id):
			continue
		var player := _players[id] as PlayerController
		if player == null or not is_instance_valid(player):
			continue
		var pos := player.global_position
		if not NetConfig.finite_vector(pos):
			continue
		ids.append(id)
		seqs.append(int(_move_seq.get(id, 0)))
		data.append(pos.x)
		data.append(pos.y)
		data.append(pos.z)
		data.append(player.get_facing_yaw())
		data.append(player.get_lean_offset())
		data.append(float(player.health))
		data.append(player.velocity.x)
		data.append(player.velocity.z)
		data.append(player.get_crouch())
		data.append(player.get_aim_pitch())
		data.append(1.0 if _weapon_drawn(id) else 0.0)
	return {"ids": ids, "seqs": seqs, "data": data}


func _publish_snapshots() -> void:
	for key in _players.keys():
		var observer := int(key)
		var packet := _snapshot_for(observer)
		_outbound[observer] = packet
		if not multiplayer.get_peers().has(observer):
			continue
		var ids: PackedInt32Array = packet["ids"]
		if ids.is_empty():
			continue
		receive_snapshot.rpc_id(
			observer,
			_tick,
			ids,
			packet["seqs"],
			packet["data"]
		)


func _is_visible(observer: int, target: int) -> bool:
	if observer == target:
		return true
	var row: Dictionary = _seen.get(observer, {})
	return bool(row.get(target, false))


func _player_visible(observer: PlayerController, target: PlayerController) -> bool:
	var world := observer.get_world_3d()
	if world == null or world.direct_space_state == null:
		return false
	var space := world.direct_space_state
	var points: Array[Vector3] = []
	for point in target.visibility_points():
		points.append(point)
	var flat := target.global_position - observer.global_position
	flat.y = 0.0
	if flat.length_squared() > 0.04 and points.size() > 2:
		var side := flat.cross(Vector3.UP).normalized()
		var toward := (-flat).normalized()
		var reach := PlayerController.BODY_RADIUS + NetConfig.VISIBILITY_LEAD
		var chest: Vector3 = points[1]
		var head: Vector3 = points[0]
		var hip: Vector3 = points[2]
		for sample in [head, chest, hip]:
			points.append(sample + toward * reach)
			points.append(sample + side * reach)
			points.append(sample - side * reach)
	for origin in observer.visibility_origins():
		for point in points:
			if _Sight.can_see(space, origin, point, _view_distance):
				return true
	return false


func _refresh_visibility() -> void:
	if not multiplayer.is_server():
		return
	var ids: Array[int] = []
	for key in _players.keys():
		ids.append(int(key))
	for observer_id in ids:
		var observer := _players.get(observer_id) as PlayerController
		if observer == null or not is_instance_valid(observer):
			continue
		var row: Dictionary = _seen.get(observer_id, {})
		for target_id in ids:
			if target_id == observer_id:
				continue
			var target := _players.get(target_id) as PlayerController
			if target == null or not is_instance_valid(target):
				continue
			var was := bool(row.get(target_id, false))
			var now := _player_visible(observer, target)
			if now != was:
				_server_log("sight observer=%d target=%d %s" % [observer_id, target_id, "gained" if now else "lost"])
				_push_visibility(observer_id, target, now)
			row[target_id] = now
		_seen[observer_id] = row


func _push_visibility(observer_id: int, target: PlayerController, visible: bool) -> void:
	if not multiplayer.get_peers().has(observer_id):
		return
	if visible:
		spawn_player.rpc_id(observer_id, target.network_id, target.global_position, target.get_facing_yaw())
		health_update.rpc_id(observer_id, 1, target.network_id, target.health)
	else:
		hide_player.rpc_id(observer_id, target.network_id)


func _send_shot_event(shooter: int, origin: Vector3, end_point: Vector3, damaged: bool, collider: Object) -> void:
	var struck := -1
	if collider is PlayerController:
		struck = (collider as PlayerController).network_id
	for peer_key in multiplayer.get_peers():
		var peer_id := int(peer_key)
		var sees_shooter := peer_id == shooter or _is_visible(peer_id, shooter)
		if not sees_shooter:
			continue
		if struck > 1 and peer_id != shooter and not _is_visible(peer_id, struck):
			continue
		shot_event.rpc_id(peer_id, shooter, origin, end_point, damaged)


func _spawn_authority(peer_id: int) -> void:
	var pos := _allocate_spawn(peer_id)
	var player := _make_player(peer_id, pos, 0.0, PlayerController.NetRole.SERVER)
	_players[peer_id] = player
	var bag := Inventory.new(NetConfig.INVENTORY_SLOTS)
	bag.grant_loadout()
	_inventories[peer_id] = bag
	_server_log("spawned player id=%d at=%s" % [peer_id, pos])
	_refresh_visibility()
	_sync_world_to(peer_id)
	_push_inventory(peer_id)


func _sync_world_to(peer_id: int) -> void:
	if not multiplayer.get_peers().has(peer_id):
		return
	for key in _players.keys():
		var id := int(key)
		if id != peer_id and not _is_visible(peer_id, id):
			continue
		var player := _players[id] as PlayerController
		if player == null or not is_instance_valid(player):
			continue
		spawn_player.rpc_id(peer_id, id, player.global_position, player.get_facing_yaw())
		health_update.rpc_id(peer_id, 1, id, player.health)
	var arena := get_parent()
	if arena == null:
		return
	for index in DUMMY_NAMES.size():
		var dummy := arena.get_node_or_null(DUMMY_NAMES[index]) as Damageable
		if dummy == null:
			continue
		health_update.rpc_id(peer_id, 0, index, dummy.health)
	for pickup_key in _pickups.keys():
		var pickup := _pickups[pickup_key] as WorldPickup
		if pickup == null:
			continue
		loot_state.rpc_id(peer_id, pickup.pickup_id, pickup.quantity)


func _spawn_visual(peer_id: int, pos: Vector3, yaw: float) -> void:
	if peer_id <= 1:
		return
	var existing := _visuals.get(peer_id) as PlayerController
	if existing != null and is_instance_valid(existing):
		return
	var role := PlayerController.NetRole.PUPPET
	if peer_id == multiplayer.get_unique_id():
		role = PlayerController.NetRole.OWNER
		_local_confirmed = true
	var player := _make_player(peer_id, pos, yaw, role)
	_visuals[peer_id] = player
	_spawn_seen[peer_id] = pos
	if _pending_player_health.has(peer_id):
		player.apply_authoritative_health(int(_pending_player_health[peer_id]))
		_pending_player_health.erase(peer_id)
	if role == PlayerController.NetRole.OWNER:
		if _ready_timer != null:
			_ready_timer.stop()
		_set_title("Survival Sandbox — player %d" % peer_id)
		_client_log("spawned local player id=%d" % peer_id)
	else:
		_client_log("spawned remote player id=%d" % peer_id)


func _make_player(peer_id: int, pos: Vector3, yaw: float, role: PlayerController.NetRole) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.name = "Player_%d" % peer_id
	player.configure_net(role, peer_id)
	player.bind_session_node(self)
	var folder := _players_folder()
	player.position = pos
	folder.add_child(player)
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.apply_facing_yaw(yaw)
	player.seed_motion(pos, yaw)
	if role == PlayerController.NetRole.OWNER:
		player.mark_authoritative_pose()
	return player


func _release_player(peer_id: int) -> void:
	var player: PlayerController = _players.get(peer_id) as PlayerController
	_players.erase(peer_id)
	_inventories.erase(peer_id)
	var leftover: Dictionary = _cursors.get(peer_id, {"id": "", "qty": 0})
	if int(leftover.get("qty", 0)) > 0 and player != null and is_instance_valid(player):
		_spawn_drop(str(leftover["id"]), int(leftover["qty"]), player.global_position)
	_cursors.erase(peer_id)
	_open_container.erase(peer_id)
	_spawn_by_peer.erase(peer_id)
	_outbound.erase(peer_id)
	_seen.erase(peer_id)
	for seen_key in _seen.keys():
		var row: Dictionary = _seen[seen_key]
		row.erase(peer_id)
	_clear_peer_limits(peer_id)
	if player != null and is_instance_valid(player):
		player.queue_free()
	if multiplayer.get_peers().is_empty():
		return
	despawn_player.rpc(peer_id)


func _remove_visual(peer_id: int) -> void:
	var player: PlayerController = _visuals.get(peer_id) as PlayerController
	_visuals.erase(peer_id)
	_spawn_seen.erase(peer_id)
	_pending_player_health.erase(peer_id)
	if player != null and is_instance_valid(player):
		player.queue_free()
	_client_log("despawned player id=%d" % peer_id)


func _clear_peer_limits(peer_id: int) -> void:
	_commands.erase(peer_id)
	_command_time.erase(peer_id)
	_move_seq.erase(peer_id)
	_fire_seq.erase(peer_id)
	_next_fire_msec.erase(peer_id)
	_rate_hits.erase("move:%d" % peer_id)
	_rate_hits.erase("fire:%d" % peer_id)
	_rate_hits.erase("item:%d" % peer_id)


func _replicate_collider_health(collider: Object) -> void:
	if multiplayer.get_peers().is_empty():
		return
	if collider is PlayerController:
		var player := collider as PlayerController
		for peer_key in multiplayer.get_peers():
			var peer_id := int(peer_key)
			if peer_id != player.network_id and not _is_visible(peer_id, player.network_id):
				continue
			health_update.rpc_id(peer_id, 1, player.network_id, player.health)
	elif collider is Damageable:
		var index := DUMMY_NAMES.find(String((collider as Node).name))
		if index >= 0:
			health_update.rpc(0, index, (collider as Damageable).health)


func _apply_network_health(kind: int, id: int, current: int) -> void:
	if kind == 1:
		var player := _visuals.get(id) as PlayerController
		if player == null or not is_instance_valid(player):
			_pending_player_health[id] = current
			return
		player.apply_authoritative_health(current)
	elif kind == 0:
		var dummy := _dummy_node(id)
		if dummy != null:
			dummy.apply_authoritative_health(current)


func _allocate_spawn(peer_id: int) -> Vector3:
	var used: Array[Vector3] = []
	for key in _spawn_by_peer.keys():
		used.append(_spawn_by_peer[key])
	for point in SpawnPoints.POINTS:
		if _min_distance(point, used) >= SpawnPoints.MIN_SEPARATION:
			_spawn_by_peer[peer_id] = point
			return point
	var angle := float(used.size()) * 0.9
	var extra := Vector3(cos(angle) * 7.0, 0.15, 8.0 + sin(angle) * 3.0)
	_spawn_by_peer[peer_id] = extra
	return extra


func _players_folder() -> Node3D:
	var arena := get_parent()
	var existing := arena.get_node_or_null("Players")
	if existing is Node3D:
		return existing as Node3D
	var folder := Node3D.new()
	folder.name = "Players"
	arena.add_child(folder)
	return folder


func _dummy_node(index: int) -> Damageable:
	if index < 0 or index >= DUMMY_NAMES.size():
		return null
	var arena := get_parent()
	if arena == null:
		return null
	return arena.get_node_or_null(DUMMY_NAMES[index]) as Damageable


func _accept_seq(store: Dictionary, peer_id: int, seq: int) -> bool:
	if seq <= 0 or seq > 1_000_000_000:
		return false
	var last := int(store.get(peer_id, 0))
	if seq <= last:
		return false
	if last > 0 and seq > last + 240:
		return false
	store[peer_id] = seq
	return true


func _rate_ok(peer_id: int, bucket: String, limit: int) -> bool:
	var key := "%s:%d" % [bucket, peer_id]
	var now := Time.get_ticks_msec()
	var kept: Array[int] = []
	var stamps: Array = _rate_hits.get(key, [])
	for stamp in stamps:
		if now - int(stamp) < 1000:
			kept.append(int(stamp))
	if kept.size() >= limit:
		_rate_hits[key] = kept
		return false
	kept.append(now)
	_rate_hits[key] = kept
	return true


func _reject_input(peer_id: int, reason: String) -> void:
	rejected_inputs += 1
	_throttled_log("input", peer_id, reason)


func _reject_shot(peer_id: int, reason: String) -> void:
	rejected_shots += 1
	_throttled_log("shot", peer_id, reason)


func _throttled_log(kind: String, peer_id: int, reason: String) -> void:
	var key := "%s:%d:%s" % [kind, peer_id, reason]
	var now := Time.get_ticks_msec()
	var last := int(_log_budget.get(key, -10000))
	if now - last < 1000:
		return
	_log_budget[key] = now
	_server_log("%s peer=%d rejected reason=%s" % [kind, peer_id, reason])


func _log_weapon_once(weapon: HitscanWeapon) -> void:
	if _weapon_logged:
		return
	_weapon_logged = true
	_server_log(
		"weapon damage=%d range=%.1f cooldown=%.2f"
		% [weapon.damage, weapon.range_meters, weapon.cooldown_seconds]
	)


func _index_loot() -> void:
	_pickups.clear()
	_containers.clear()
	for node in _loot_nodes(&"loot_pickup"):
		var pickup := node as WorldPickup
		if pickup == null or pickup.pickup_id.is_empty():
			continue
		_pickups[pickup.pickup_id] = pickup
	for node in _loot_nodes(&"loot_container"):
		var crate := node as LootContainer
		if crate == null or crate.container_id.is_empty():
			continue
		_containers[crate.container_id] = crate


func _strip_client_container_secrets() -> void:
	for node in _loot_nodes(&"loot_container"):
		var crate := node as LootContainer
		if crate != null:
			crate.clear_contents()


func _loot_nodes(group_name: StringName) -> Array:
	var found: Array = []
	var arena := get_parent()
	if arena == null:
		return found
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node and arena.is_ancestor_of(node):
			found.append(node)
	return found


func _find_pickup(pickup_id: String) -> WorldPickup:
	if _pickups.is_empty() and _containers.is_empty():
		_index_loot()
	return _pickups.get(pickup_id) as WorldPickup


func _owner_visual() -> PlayerController:
	var player := _visuals.get(multiplayer.get_unique_id()) as PlayerController
	if player != null and is_instance_valid(player):
		return player
	return null


func _handle_pickup(sender: int, pickup_id: String) -> String:
	var reason := _begin_item(sender)
	if reason != "":
		return reason
	var player := _players.get(sender) as PlayerController
	var bag := _inventories.get(sender) as Inventory
	var pickup := _find_pickup(pickup_id)
	if player == null or bag == null:
		_item_lock = false
		return _fail_item(sender, "no_player")
	if pickup == null or pickup.quantity <= 0:
		_item_lock = false
		return _fail_item(sender, "missing")
	if _flat_distance(player.global_position, pickup.global_position) > NetConfig.INTERACT_RANGE:
		_item_lock = false
		return _fail_item(sender, "too_far")
	var taken := pickup.take_into(bag)
	_item_lock = false
	if taken <= 0:
		return _fail_item(sender, "full")
	_push_inventory(sender)
	_push_pickup(pickup)
	var definition := ItemCatalog.get_item(pickup.item_id)
	var label := pickup.item_id if definition == null else definition.display_name
	_notice(sender, "Picked up %s x%d." % [label, taken])
	_server_log("pickup peer=%d id=%s qty=%d left=%d" % [sender, pickup_id, taken, pickup.quantity])
	return ""


func _handle_open_container(sender: int, container_id: String) -> String:
	var reason := _begin_item(sender)
	if reason != "":
		return reason
	var player := _players.get(sender) as PlayerController
	var crate := _containers.get(container_id) as LootContainer
	_item_lock = false
	if player == null or crate == null:
		return _fail_item(sender, "missing")
	if _flat_distance(player.global_position, crate.global_position) > NetConfig.INTERACT_RANGE:
		return _fail_item(sender, "too_far")
	_open_container[sender] = container_id
	_push_container(crate)
	_notice(sender, "Opened crate.")
	return ""


func _handle_close_container(sender: int) -> void:
	if sender <= 1 or not _players.has(sender):
		return
	_open_container.erase(sender)
	if multiplayer.get_peers().has(sender):
		container_closed.rpc_id(sender)


func _handle_transfer(
	sender: int,
	container_id: String,
	to_container: bool,
	source_slot: int,
	dest_slot: int,
	quantity: int
) -> String:
	var reason := _begin_item(sender)
	if reason != "":
		return reason
	var player := _players.get(sender) as PlayerController
	var bag := _inventories.get(sender) as Inventory
	var crate := _containers.get(container_id) as LootContainer
	if player == null or bag == null or crate == null:
		_item_lock = false
		return _fail_item(sender, "missing")
	if str(_open_container.get(sender, "")) != container_id:
		_item_lock = false
		return _fail_item(sender, "closed")
	if _flat_distance(player.global_position, crate.global_position) > NetConfig.INTERACT_RANGE:
		_open_container.erase(sender)
		_item_lock = false
		_close_remote(sender)
		return _fail_item(sender, "too_far")
	var source := bag if to_container else crate.inventory
	var dest := crate.inventory if to_container else bag
	reason = Inventory.move(source, source_slot, dest, dest_slot, quantity, to_container)
	_item_lock = false
	if reason != "":
		return _fail_item(sender, reason)
	_push_inventory(sender)
	_push_container(crate)
	_notice(sender, "Moved x%d." % quantity)
	_server_log("transfer peer=%d container=%s to_box=%s qty=%d" % [sender, container_id, to_container, quantity])
	return ""


func _handle_drop(
	sender: int,
	container_id: String,
	to_container: bool,
	source_slot: int,
	dest_slot: int,
	quantity: int
) -> String:
	var access := _crate_for(sender, container_id)
	if str(access["reason"]) != "":
		return str(access["reason"])
	var bag := _inventories.get(sender) as Inventory
	var crate := access["crate"] as LootContainer
	var source := bag if to_container else crate.inventory
	var dest := crate.inventory if to_container else bag
	var reason := Inventory.drop(source, source_slot, dest, dest_slot, quantity, to_container)
	_item_lock = false
	if reason != "":
		return _fail_item(sender, reason)
	_push_inventory(sender)
	_push_container(crate)
	_notice(sender, "Moved x%d." % quantity)
	return ""


func _handle_rearrange(sender: int, in_container: bool, source_slot: int, dest_slot: int, quantity: int) -> String:
	var crate: LootContainer = null
	var bag: Inventory = null
	if in_container:
		var access := _crate_for(sender, str(_open_container.get(sender, "")))
		if str(access["reason"]) != "":
			return str(access["reason"])
		crate = access["crate"] as LootContainer
		bag = crate.inventory
	else:
		var reason := _begin_item(sender)
		if reason != "":
			return reason
		bag = _inventories.get(sender) as Inventory
		if bag == null:
			_item_lock = false
			return _fail_item(sender, "missing")
	var placed := Inventory.drop(bag, source_slot, bag, dest_slot, quantity, false)
	_item_lock = false
	if placed != "":
		return _fail_item(sender, placed)
	_push_inventory(sender)
	if crate != null:
		_push_container(crate)
	_notice(sender, "Moved x%d." % quantity)
	return ""


func _handle_slot_click(sender: int, area: int, index: int, right: bool, shift: bool, collect: bool) -> String:
	var ready := _bags_for(sender, area == SlotOps.AREA_CONTAINER)
	if str(ready["reason"]) != "":
		return str(ready["reason"])
	var cursor := _cursor(sender)
	var reason := ""
	if collect:
		reason = SlotOps.collect_same(ready["bag"], ready["crate_bag"], cursor, area, index)
	else:
		reason = SlotOps.click(ready["bag"], ready["crate_bag"], cursor, area, index, right, shift)
	_item_lock = false
	if reason != "":
		return _fail_item(sender, reason)
	_publish_items(sender, ready["crate"] as LootContainer)
	return ""


func _handle_slot_spread(sender: int, areas: PackedInt32Array, indices: PackedInt32Array, right: bool) -> String:
	if areas.size() > 80 or indices.size() > 80:
		return _fail_item(sender, "bad_qty")
	var needs_crate := false
	for slot_area in areas:
		if int(slot_area) == SlotOps.AREA_CONTAINER:
			needs_crate = true
	var ready := _bags_for(sender, needs_crate)
	if str(ready["reason"]) != "":
		return str(ready["reason"])
	var reason := SlotOps.spread(ready["bag"], ready["crate_bag"], _cursor(sender), areas, indices, right)
	_item_lock = false
	if reason != "":
		return _fail_item(sender, reason)
	_publish_items(sender, ready["crate"] as LootContainer)
	return ""


func _handle_slot_throw(sender: int, area: int, index: int, whole: bool) -> String:
	var ready := _bags_for(sender, area == SlotOps.AREA_CONTAINER)
	if str(ready["reason"]) != "":
		return str(ready["reason"])
	var player := _players.get(sender) as PlayerController
	var thrown := SlotOps.throw_stack(ready["bag"], ready["crate_bag"], _cursor(sender), area, index, whole)
	_item_lock = false
	if int(thrown.get("qty", 0)) <= 0:
		return _fail_item(sender, "short")
	_spawn_drop(str(thrown["id"]), int(thrown["qty"]), _drop_position(player))
	_publish_items(sender, ready["crate"] as LootContainer)
	_notice(sender, "Dropped x%d." % int(thrown["qty"]))
	return ""


func _handle_hotbar_swap(sender: int, area: int, index: int, hotbar_index: int) -> String:
	var ready := _bags_for(sender, area == SlotOps.AREA_CONTAINER)
	if str(ready["reason"]) != "":
		return str(ready["reason"])
	var reason := SlotOps.swap_hotbar(ready["bag"], ready["crate_bag"], area, index, hotbar_index)
	_item_lock = false
	if reason != "":
		return _fail_item(sender, reason)
	_publish_items(sender, ready["crate"] as LootContainer)
	return ""


func _bags_for(sender: int, needs_crate: bool) -> Dictionary:
	var reason := _begin_item(sender)
	if reason != "":
		return {"reason": reason, "bag": null, "crate": null, "crate_bag": null}
	var bag := _inventories.get(sender) as Inventory
	if bag == null:
		_item_lock = false
		return {"reason": _fail_item(sender, "missing"), "bag": null, "crate": null, "crate_bag": null}
	var crate: LootContainer = null
	var crate_bag: Inventory = null
	if needs_crate:
		var access := _crate_for_open(sender, str(_open_container.get(sender, "")))
		if str(access["reason"]) != "":
			return {"reason": str(access["reason"]), "bag": null, "crate": null, "crate_bag": null}
		crate = access["crate"] as LootContainer
		crate_bag = crate.inventory
	return {"reason": "", "bag": bag, "crate": crate, "crate_bag": crate_bag}


func _crate_for_open(sender: int, container_id: String) -> Dictionary:
	var player := _players.get(sender) as PlayerController
	var crate := _containers.get(container_id) as LootContainer
	if player == null or crate == null:
		_item_lock = false
		return {"reason": _fail_item(sender, "closed"), "crate": null}
	if str(_open_container.get(sender, "")) != container_id:
		_item_lock = false
		return {"reason": _fail_item(sender, "closed"), "crate": null}
	if _flat_distance(player.global_position, crate.global_position) > NetConfig.INTERACT_RANGE:
		_open_container.erase(sender)
		_item_lock = false
		_close_remote(sender)
		return {"reason": _fail_item(sender, "too_far"), "crate": null}
	return {"reason": "", "crate": crate}


func _cursor(peer_id: int) -> Dictionary:
	if not _cursors.has(peer_id):
		_cursors[peer_id] = {"id": "", "qty": 0}
	return _cursors[peer_id]


func _publish_items(sender: int, crate: LootContainer) -> void:
	_push_inventory(sender)
	if crate != null:
		_push_container(crate)


func _drop_position(player: PlayerController) -> Vector3:
	if player == null:
		return Vector3(0, 0.15, 8)
	var forward := -Basis(Vector3.UP, player.get_facing_yaw()).z
	return player.global_position + forward * 0.9


func _spawn_drop(item_id: String, quantity: int, pos: Vector3) -> void:
	if quantity <= 0 or item_id.is_empty():
		return
	var pickup := WorldPickup.new()
	pickup.pickup_id = "drop_%d" % _drop_seq
	_drop_seq += 1
	pickup.item_id = item_id
	pickup.quantity = quantity
	var folder := get_parent().get_node_or_null("Loot")
	if folder == null:
		folder = get_parent()
	folder.add_child(pickup)
	pickup.global_position = Vector3(pos.x, 0.15, pos.z)
	_pickups[pickup.pickup_id] = pickup
	if not multiplayer.get_peers().is_empty():
		loot_spawn.rpc(pickup.pickup_id, pickup.item_id, pickup.quantity, pickup.global_position)


func _ensure_pickup(pickup_id: String, item_id: String, quantity: int, pos: Vector3) -> void:
	var existing := _find_pickup(pickup_id)
	if existing != null:
		existing.item_id = item_id
		existing.apply_network_quantity(quantity)
		existing.global_position = pos
		return
	var pickup := WorldPickup.new()
	pickup.pickup_id = pickup_id
	pickup.item_id = item_id
	pickup.quantity = quantity
	var folder := get_parent().get_node_or_null("Loot")
	if folder == null:
		folder = get_parent()
	folder.add_child(pickup)
	pickup.global_position = pos
	_pickups[pickup_id] = pickup


func _crate_for(sender: int, container_id: String) -> Dictionary:
	var reason := _begin_item(sender)
	if reason != "":
		return {"reason": reason, "crate": null}
	var player := _players.get(sender) as PlayerController
	var crate := _containers.get(container_id) as LootContainer
	if player == null or crate == null or _inventories.get(sender) == null:
		_item_lock = false
		return {"reason": _fail_item(sender, "missing"), "crate": null}
	if str(_open_container.get(sender, "")) != container_id:
		_item_lock = false
		return {"reason": _fail_item(sender, "closed"), "crate": null}
	if _flat_distance(player.global_position, crate.global_position) > NetConfig.INTERACT_RANGE:
		_open_container.erase(sender)
		_item_lock = false
		_close_remote(sender)
		return {"reason": _fail_item(sender, "too_far"), "crate": null}
	return {"reason": "", "crate": crate}


func _begin_item(sender: int) -> String:
	if not multiplayer.is_server():
		return "not_server"
	if sender <= 1 or not _players.has(sender):
		return "sender"
	if _item_lock:
		return _fail_item(sender, "busy")
	if not _rate_ok(sender, "item", NetConfig.ITEM_RATE_PER_SEC):
		return _fail_item(sender, "rate")
	_item_lock = true
	return ""


func _fail_item(sender: int, reason: String) -> String:
	_throttled_log("item", sender, reason)
	_notice(sender, "Item action failed (%s)." % reason)
	return reason


func _notice(sender: int, text: String) -> void:
	last_item_notice[sender] = text
	if multiplayer.get_peers().has(sender):
		inventory_notice.rpc_id(sender, text)


func _close_remote(sender: int) -> void:
	if multiplayer.get_peers().has(sender):
		container_closed.rpc_id(sender)


func _push_inventory(peer_id: int) -> void:
	var bag := _inventories.get(peer_id) as Inventory
	if bag == null or not multiplayer.get_peers().has(peer_id):
		return
	inventory_sync.rpc_id(peer_id, bag.ids(), bag.quantities())
	var cursor := _cursor(peer_id)
	cursor_sync.rpc_id(peer_id, str(cursor["id"]), int(cursor["qty"]))


func _push_pickup(pickup: WorldPickup) -> void:
	if multiplayer.get_peers().is_empty():
		return
	loot_state.rpc(pickup.pickup_id, pickup.quantity)


func _push_container(crate: LootContainer) -> void:
	var recipients: Array[int] = []
	var drop: Array[int] = []
	for key in _open_container.keys():
		var peer_id := int(key)
		if str(_open_container[key]) != crate.container_id:
			continue
		var player := _players.get(peer_id) as PlayerController
		if player == null or not is_instance_valid(player):
			drop.append(peer_id)
			continue
		if _flat_distance(player.global_position, crate.global_position) > NetConfig.INTERACT_RANGE:
			drop.append(peer_id)
			continue
		recipients.append(peer_id)
		if multiplayer.get_peers().has(peer_id):
			container_sync.rpc_id(peer_id, crate.container_id, crate.inventory.ids(), crate.inventory.quantities())
	for peer_id in drop:
		_open_container.erase(peer_id)
		_close_remote(peer_id)
	last_container_recipients = recipients


func _flat_distance(from_pos: Vector3, to_pos: Vector3) -> float:
	return Vector2(from_pos.x - to_pos.x, from_pos.z - to_pos.z).length()


func debug_inventory(peer_id: int) -> Inventory:
	return _inventories.get(peer_id) as Inventory


func debug_pickup(pickup_id: String) -> WorldPickup:
	return _find_pickup(pickup_id)


func debug_container(container_id: String) -> LootContainer:
	if _containers.is_empty():
		_index_loot()
	return _containers.get(container_id) as LootContainer


func debug_collect(peer_id: int, pickup_id: String) -> String:
	return _handle_pickup(peer_id, pickup_id)


func debug_open(peer_id: int, container_id: String) -> String:
	return _handle_open_container(peer_id, container_id)


func debug_transfer(peer_id: int, container_id: String, to_container: bool, source_slot: int, dest_slot: int, quantity: int) -> String:
	return _handle_transfer(peer_id, container_id, to_container, source_slot, dest_slot, quantity)


func debug_grant(peer_id: int, item_id: String, quantity: int) -> bool:
	var bag := _inventories.get(peer_id) as Inventory
	if bag == null:
		return false
	return bag.add_exact(item_id, quantity)


func debug_inventory_ids(peer_id: int) -> PackedStringArray:
	var bag := _inventories.get(peer_id) as Inventory
	if bag == null:
		return PackedStringArray()
	return bag.ids()


func debug_reset_item_rate(peer_id: int) -> void:
	_rate_hits.erase("item:%d" % peer_id)


func debug_cursor(peer_id: int) -> Dictionary:
	return _cursor(peer_id).duplicate()


func debug_click(peer_id: int, area: int, index: int, right: bool, shift: bool, collect: bool) -> String:
	return _handle_slot_click(peer_id, area, index, right, shift, collect)


func _bot_move_seq_send() -> void:
	_move_seq_out += 1
	submit_input.rpc_id(1, _move_seq_out, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0)


func _remote_moved() -> bool:
	var me := multiplayer.get_unique_id()
	for key in _visuals.keys():
		if int(key) == me:
			continue
		var player := _visuals[key] as PlayerController
		if player == null:
			continue
		var origin: Vector3 = _spawn_seen.get(key, player.global_position)
		if player.global_position.distance_to(origin) > 0.45:
			return true
	return false


func _finish_bot(ok: bool, detail: String) -> void:
	if _bot_finished:
		return
	_bot_finished = true
	var line := ("BOT_OK %s" % detail) if ok else ("BOT_FAIL %s" % detail)
	_client_log(line)
	if not ok:
		get_tree().quit(1)
		return
	# Stay up briefly so the other bot can observe this pawn, then disconnect cleanly.
	var hold := Timer.new()
	hold.one_shot = true
	hold.wait_time = 1.0
	hold.timeout.connect(func() -> void: get_tree().quit(0))
	add_child(hold)
	hold.start()


func _client_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or multiplayer.is_server():
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _position_sane(player: PlayerController) -> bool:
	return NetConfig.finite_vector(player.global_position)


func _collider_name(collider: Object) -> String:
	if collider == null:
		return "none"
	var named: Variant = collider.get("display_name")
	if named != null and str(named) != "":
		return str(named)
	if collider is Node:
		return String((collider as Node).name)
	return "object"


func _health_of(collider: Object) -> String:
	if collider == null or collider.get("health") == null:
		return "-"
	return str(collider.get("health"))


func _min_distance(point: Vector3, others: Array[Vector3]) -> float:
	var best := 1000000.0
	for other in others:
		best = minf(best, point.distance_to(other))
	return best


func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0


func _snapshot_stamp(tick: int) -> float:
	# Map the server tick onto the client clock once, then keep even spacing.
	# Arrival time bunches two packets into one frame and the body pops.
	var seconds := float(tick) / float(maxi(Engine.physics_ticks_per_second, 1))
	var now := _now_sec()
	if _snapshot_clock_origin < 0.0:
		_snapshot_clock_origin = now - seconds
	var stamped := _snapshot_clock_origin + seconds
	var lead := now - stamped
	if lead > NetConfig.INTERP_DELAY_SEC:
		_snapshot_clock_origin += lead
		stamped = now
	return stamped


func _session() -> Node:
	return get_node_or_null("/root/NetSession")


func _session_mode() -> int:
	var session := _session()
	if session == null:
		return NetConfig.MODE_LOCAL
	return int(session.get("mode"))


func _session_port() -> int:
	var session := _session()
	if session == null:
		return 0
	return int(session.get("port"))


func _status_path() -> String:
	var session := _session()
	if session == null:
		return ""
	return str(session.get("status_file"))


func _is_bot() -> bool:
	var session := _session()
	return session != null and bool(session.get("bot"))


func _expect_peers() -> int:
	var session := _session()
	if session == null:
		return 2
	return int(session.get("expect_peers"))


func _server_log(message: String) -> void:
	var line := "[server] " + message
	print(line)
	if _session_mode() == NetConfig.MODE_SERVER:
		NetConfig.append_line(_status_path(), line)


func _client_log(message: String) -> void:
	var line := "[client] " + message
	print(line)
	if _session_mode() == NetConfig.MODE_CLIENT:
		NetConfig.append_line(_status_path(), line)


func _set_title(title: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_title(title)
