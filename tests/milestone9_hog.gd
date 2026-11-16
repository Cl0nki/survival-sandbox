extends SceneTree

## Headless checks for Milestone 9a: the hog.
## godot --headless --path <project> --script res://tests/milestone9_hog.gd
##
## Creatures are driven by hand (hog.advance) so the test is fast and exact.

const STEP := 1.0 / 60.0

var _net: GameNet
var _enemies: EnemySystem
var _probe: Hog


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("test arena failed to load")
	var peer := _listen()
	if peer == null:
		return _fail("could not bind a server port")
	root.get_multiplayer().multiplayer_peer = peer
	var arena := packed.instantiate()
	arena.force_mode = NetConfig.MODE_SERVER
	root.add_child(arena)
	for _frame in 12:
		await physics_frame
	_net = arena.get_node("GameNet") as GameNet
	if _net == null or _net.enemies() == null:
		return _fail("server arena has no EnemySystem")
	_enemies = _net.enemies()
	# The test steps the simulation itself, so the frame loop must not.
	_enemies.set_physics_process(false)
	if _enemies.auto_spawn:
		return _fail("tests must not auto-spawn")
	if _net.debug_spawn(2, "hogtoken0001") != "" or _net.debug_spawn(3, "hogtoken0002") != "":
		return _fail("could not admit two players")
	var shot_player := _net.debug_player(2)
	var runner := _net.debug_player(3)
	_net.debug_place(2, Vector3(-15.0, 0.15, 14.6))
	_net.debug_place(3, Vector3(-12.0, 0.15, 14.6))

	# A probe hog finds open corridors in the arena.
	_probe = _enemies.spawn_hog(Vector3(0.0, 0.05, 0.0))
	if _probe == null:
		return _fail("could not spawn a hog")
	await physics_frame
	var open: Variant = _scan(false)
	var blocked: Variant = _scan(true)
	if open == null or blocked == null:
		return _fail("no open corridor (%s) or obstacle corridor (%s) in the arena" % [open, blocked])
	_enemies._remove(_probe)
	_probe = null
	print("open spot ", open, " obstacle spot ", blocked)

	# --- Grazing: wanders near home, ignores far players.
	var hog := _enemies.spawn_hog(open as Vector3)
	await physics_frame
	if hog == null or not hog.is_inside_tree() or _enemies.enemy_count() != 1:
		return _fail("hog did not spawn")
	if hog.state != Creature.S_IDLE or hog.health != Hog.MAX_HEALTH:
		return _fail("new hog should be idle at full health (state %d hp %d)" % [hog.state, hog.health])
	var start := hog.global_position
	var farthest := 0.0
	var walked := false
	for _i in 720:
		hog.advance(STEP)
		farthest = maxf(farthest, _flat(hog.global_position, start))
		walked = walked or hog.state == Hog.S_WALK
		if hog.state in [Hog.S_WINDUP, Hog.S_CHARGE]:
			return _fail("an unprovoked hog attacked")
	if not walked or farthest < 0.5:
		return _fail("hog never wandered (farthest %.2f)" % farthest)
	if farthest > Hog.WANDER_RADIUS + 1.5:
		return _fail("hog wandered too far from home (%.2f)" % farthest)
	if absf(hog.global_position.y - start.y) > 0.4:
		return _fail("hog left the ground")

	# --- Crouching halves the trigger distance.
	shot_player.snap_stance_for_shot(1.0)
	_net.debug_place(2, hog.global_position + Vector3(0.0, 0.0, 3.2))
	for _i in 48:
		hog.advance(STEP)
	if hog.state in [Hog.S_WINDUP, Hog.S_CHARGE]:
		return _fail("a crouching player 3.2 m away should not provoke the hog")
	shot_player.snap_stance_for_shot(0.0)
	_net.debug_place(2, hog.global_position + Vector3(0.0, 0.0, 2.8))
	hog.advance(STEP)
	hog.advance(STEP)
	if hog.state != Hog.S_WINDUP:
		return _fail("a standing player 2.8 m away should provoke the hog (state %d)" % hog.state)

	# --- Gore: the telegraph, then one hit per charge.
	var order: Array[int] = []
	var gored := false
	var before := shot_player.health
	for _i in 240:
		hog.advance(STEP)
		if order.is_empty() or order[-1] != hog.state:
			order.append(hog.state)
		if shot_player.health < before:
			gored = true
			break
	if not gored:
		return _fail("the charge never hit a player who stood still (states %s)" % [order])
	if order.find(Hog.S_WINDUP) < 0 or order.find(Hog.S_CHARGE) < 0 or order.find(Hog.S_WINDUP) > order.find(Hog.S_CHARGE):
		return _fail("expected WINDUP before CHARGE, got %s" % [order])
	if shot_player.health != before - Hog.GORE_DAMAGE:
		return _fail("gore should deal %d, health went %d -> %d" % [Hog.GORE_DAMAGE, before, shot_player.health])
	if hog.state != Hog.S_RECOVER:
		return _fail("hog should recover after goring (state %d)" % hog.state)
	for _i in 40:
		hog.advance(STEP)
	if shot_player.health != before - Hog.GORE_DAMAGE or _enemies.hurt_count != 1:
		return _fail("one charge hit more than once")
	_enemies._remove(hog)
	_net.debug_place(2, Vector3(-15.0, 0.15, 14.6))

	# --- Shots: the hitscan reaches the hog and provokes it.
	var shot_hog := _enemies.spawn_hog(open as Vector3)
	await physics_frame
	var space := shot_hog.get_world_3d().direct_space_state
	var origin := shot_hog.global_position + Vector3(0.0, 0.5, -2.0)
	var hit := HitscanWeapon.resolve_shot(space, origin, Vector3(0.0, 0.0, 1.0), 40.0, [])
	if hit["collider"] != shot_hog:
		return _fail("a shot at the hog hit %s" % [hit["collider"]])
	shot_hog.advance(STEP)
	if shot_hog.state in [Hog.S_WINDUP, Hog.S_CHARGE]:
		return _fail("hog attacked before being provoked")
	_net.debug_place(3, shot_hog.global_position + Vector3(0.0, 0.0, -6.0))
	shot_hog.note_attacker(3)
	if not shot_hog.receive_damage(10, Vector3.ZERO) or shot_hog.health != Hog.MAX_HEALTH - 10:
		return _fail("shot damage did not land")
	shot_hog.advance(STEP)
	if shot_hog.state != Hog.S_WINDUP or not shot_hog.is_angry():
		return _fail("a shot hog should wind up (state %d)" % shot_hog.state)

	# --- Dodge: sidestep once it commits and the charge misses.
	var runner_before := runner.health
	var committed := false
	for _i in 120:
		shot_hog.advance(STEP)
		if shot_hog.state == Hog.S_CHARGE:
			committed = true
			_net.debug_place(3, shot_hog.global_position + Vector3(4.0, 0.0, -3.0))
			break
	if not committed:
		return _fail("shot hog never charged")
	var ended := false
	for _i in 240:
		shot_hog.advance(STEP)
		if shot_hog.state == Hog.S_RECOVER or shot_hog.state == Hog.S_STUNNED:
			ended = true
			break
	if not ended:
		return _fail("charge never ended (state %d)" % shot_hog.state)
	if runner.health != runner_before:
		return _fail("a dodged charge still hurt the player")
	_enemies._remove(shot_hog)

	# --- Wall: charging into an obstacle stuns the hog.
	var wall_hog := _enemies.spawn_hog(blocked as Vector3)
	await physics_frame
	_net.debug_place(3, wall_hog.global_position + Vector3(0.0, 0.0, -2.5))
	var wall_states: Array[int] = []
	var stunned := false
	var moved_away := false
	for _i in 600:
		wall_hog.advance(STEP)
		if wall_hog.state == Hog.S_CHARGE and not moved_away:
			moved_away = true
			_net.debug_place(3, wall_hog.global_position + Vector3(6.0, 0.0, 0.0))
		if wall_hog.state == Hog.S_STUNNED:
			stunned = true
			break
	if not stunned:
		return _fail("hog did not stun on an obstacle (charged=%s state=%d)" % [moved_away, wall_hog.state])
	var stun_at := wall_hog.global_position
	for _i in int((Hog.STUN_SEC - 0.3) / STEP):
		wall_hog.advance(STEP)
	if wall_hog.state != Hog.S_STUNNED or _flat(wall_hog.global_position, stun_at) > 0.05:
		return _fail("a stunned hog should stand still")
	if not wall_hog.receive_damage(5, Vector3.ZERO):
		return _fail("a stunned hog should take damage")
	for _i in 30:
		wall_hog.advance(STEP)
	if wall_hog.state == Hog.S_STUNNED:
		return _fail("stun never ended")
	_enemies._remove(wall_hog)
	_net.debug_place(3, Vector3(-12.0, 0.15, 14.6))

	# --- Replication payloads (no remote peers in-process).
	var seen_hog := _enemies.spawn_hog(open as Vector3)
	await physics_frame
	_net.debug_place(2, seen_hog.global_position + Vector3(0.0, 0.0, -6.0))
	var ids := _enemies.visible_ids_for(shot_player)
	if not ids.has(seen_hog.creature_id):
		return _fail("a player 6 m away in the open cannot see the hog")
	_net.debug_set_view_distance(4.0)
	if _enemies.visible_ids_for(shot_player).has(seen_hog.creature_id):
		return _fail("a hog beyond the view distance is still replicated")
	_net.debug_set_view_distance(NetConfig.VISIBILITY_DISTANCE)
	var packet := _enemies.pack(ids)
	var pdata: PackedFloat32Array = packet["data"]
	var pids: PackedInt32Array = packet["ids"]
	if pids.size() != 1 or pdata.size() != EnemySystem.SNAPSHOT_STRIDE:
		return _fail("snapshot packet has the wrong shape")
	if absf(pdata[0] - seen_hog.global_position.x) > 0.001 or int(pdata[4]) != seen_hog.state:
		return _fail("snapshot packet does not match the hog")

	# Client puppet: spawn, smooth, state, health, despawn.
	var now := Time.get_ticks_msec() / 1000.0
	var from_pos := Vector3(2.0, 0.0, 2.0)
	_enemies.client_spawn(77, Creature.KIND_HOG, from_pos, 0.0, 80, 80, Creature.S_IDLE)
	var puppet := _enemies.view(77)
	if puppet == null:
		return _fail("client_spawn made no puppet")
	_enemies.client_spawn(78, 1, Vector3(NAN, 0, 0), 0.0, 80, 80, 0)
	if _enemies.view(78) != null:
		return _fail("client accepted a non-finite spawn")
	var to_pos := Vector3(4.0, 0.0, 2.0)
	_enemies.client_snapshot(now - 0.3, PackedInt32Array([77]), PackedFloat32Array([2.0, 0.0, 2.0, 0.0, float(Creature.S_IDLE)]))
	_enemies.client_snapshot(now + 0.1, PackedInt32Array([77]), PackedFloat32Array([4.0, 0.0, 2.0, 0.0, float(Hog.S_CHARGE)]))
	_enemies.client_snapshot(now, PackedInt32Array([99]), PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	_enemies.client_snapshot(now, PackedInt32Array([77]), PackedFloat32Array([1.0]))
	puppet._process(0.016)
	if absf(puppet.position.x - 3.0) > 0.25 or puppet.state != Hog.S_CHARGE:
		return _fail("puppet did not interpolate (x=%.2f state=%d)" % [puppet.position.x, puppet.state])
	_enemies.client_health(77, 30)
	if puppet.hp != 30 or puppet.is_dead():
		return _fail("puppet health did not update")
	_enemies.client_health(77, 0)
	if not puppet.is_dead():
		return _fail("puppet did not die at 0 health")
	for _i in 30:
		puppet._process(0.016)
	_enemies.client_despawn(77)
	await physics_frame
	if _enemies.view(77) != null or _enemies.view_count() != 0:
		return _fail("puppet was not removed")
	_enemies._remove(seen_hog)

	# --- Death: loot, corpse, respawn bookkeeping.
	_net.debug_place(2, Vector3(-15.0, 0.15, 14.6))
	var dying := _enemies.spawn_hog(open as Vector3)
	await physics_frame
	var meat_before := _meat_on_ground()
	var deaths: Array[int] = []
	dying.died.connect(func(_c: Creature) -> void: deaths.append(1))
	var landed := 0
	for _i in 4:
		if dying.receive_damage(34, Vector3.ZERO):
			landed += 1
	if landed != 3 or dying.health != 0 or not dying.is_dead() or deaths.size() != 1:
		return _fail("hog should die on the third 34 damage hit (landed %d hp %d deaths %d)" % [landed, dying.health, deaths.size()])
	var meat := _meat_on_ground() - meat_before
	if meat < 2 or meat > 3:
		return _fail("dead hog should drop 2-3 raw meat, dropped %d" % meat)
	if _enemies.enemy_count() != 0 or _enemies.pending_respawns() != 1:
		return _fail("death bookkeeping is wrong (alive %d, respawns %d)" % [_enemies.enemy_count(), _enemies.pending_respawns()])
	var corpse_at := dying.global_position
	dying.advance(1.0)
	if _flat(dying.global_position, corpse_at) > 0.001:
		return _fail("a corpse moved")
	_enemies.advance(EnemySystem.CORPSE_SEC + 0.5)
	await physics_frame
	if _enemies.creatures().size() != 0 or is_instance_valid(dying):
		return _fail("corpse was not removed")

	# --- Targets that go down are left alone.
	var chaser := _enemies.spawn_hog(open as Vector3)
	await physics_frame
	_net.debug_place(3, chaser.global_position + Vector3(0.0, 0.0, -2.5))
	chaser.advance(STEP)
	chaser.advance(STEP)
	if chaser.state != Hog.S_WINDUP:
		return _fail("setup: chaser did not wind up")
	runner.apply_authoritative_health(0)
	_net.debug_place(2, Vector3(-15.0, 0.15, 14.6))
	for _i in 180:
		chaser.advance(STEP)
		if chaser.state == Hog.S_CHARGE:
			return _fail("hog charged a player who was already down")
	if not (chaser.state in [Hog.S_IDLE, Hog.S_WALK]) or chaser.is_angry():
		return _fail("hog should calm down when its target is down (state %d)" % chaser.state)
	_enemies._remove(chaser)

	# --- Dedicated-server spawner keeps the world stocked.
	# The earlier kill left a respawn timer running; the world is stocked
	# from scratch here.
	_enemies._respawns.clear()
	_enemies.auto_spawn = true
	for _i in 8:
		_enemies.advance(1.1)
	var stocked := _enemies.enemy_count()
	if stocked != EnemySystem.HOGS_DEBUG_MAP:
		return _fail("auto spawn should stock %d hogs, found %d" % [EnemySystem.HOGS_DEBUG_MAP, stocked])
	for creature in _enemies.creatures():
		var c := creature as Creature
		for player in _enemies.players():
			if _flat(player.global_position, c.global_position) < EnemySystem.SPAWN_AWAY_FROM_PLAYERS - 0.5:
				return _fail("a hog spawned on top of a player")
		for pad in SpawnPoints.POINTS:
			if _flat(pad, c.global_position) < EnemySystem.SPAWN_AWAY_FROM_PADS - 0.5:
				return _fail("a hog spawned on a spawn pad")
	var victim := _enemies.creatures()[0] as Creature
	victim.receive_damage(1000, Vector3.ZERO)
	if _enemies.enemy_count() != stocked - 1 or _enemies.pending_respawns() != 1:
		return _fail("kill did not queue a respawn")
	_enemies.advance(EnemySystem.RESPAWN_SEC + 1.1)
	if _enemies.enemy_count() != stocked or _enemies.pending_respawns() != 0:
		return _fail("respawn did not refill (alive %d, pending %d)" % [_enemies.enemy_count(), _enemies.pending_respawns()])

	print("MILESTONE9_HOG_OK")
	return 0


## Looks for a spot where a hog can run 9 m north (open) or where something
## stands 2-7 m ahead of it (blocked).
func _scan(want_blocked: bool) -> Variant:
	var rows := [-9.0, -6.0, -3.0, 0.0, 3.0, -12.0, -15.0]
	for z in rows:
		for x in range(-16, 17, 2):
			var origin := Vector3(float(x), 0.05, float(z))
			var at := Transform3D(Basis.IDENTITY, origin)
			if _probe.test_move(at, Vector3(0.0, 0.0, -0.05)) or _probe.test_move(at, Vector3(0.0, 0.0, 0.05)):
				continue
			if _probe.test_move(at, Vector3(0.05, 0.0, 0.0)) or _probe.test_move(at, Vector3(-0.05, 0.0, 0.0)):
				continue
			if want_blocked:
				if _probe.test_move(at, Vector3(0.0, 0.0, -7.0)) and not _probe.test_move(at, Vector3(0.0, 0.0, -2.5)):
					return origin
			elif not _probe.test_move(at, Vector3(0.0, 0.0, -9.5)) and not _probe.test_move(at, Vector3(0.0, 0.0, 3.0)):
				return origin
	return null


func _meat_on_ground() -> int:
	var total := 0
	for pickup in _net._pickups.values():
		var item := pickup as WorldPickup
		if item != null and is_instance_valid(item) and item.item_id == "raw_meat":
			total += item.quantity
	return total


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _listen() -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	for port in range(39140, 39180):
		if peer.create_server(port, 4) == OK:
			return peer
	return null


func _fail(message: String) -> int:
	printerr("FAIL ", message)
	print("FAIL ", message)
	return 1
