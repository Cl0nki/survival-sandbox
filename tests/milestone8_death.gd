extends SceneTree

## Headless checks for Milestone 8: death, drops, and respawn.
## godot --headless --path <project> --script res://tests/milestone8_death.gd

const DEAD_TOKEN := "deadtoken01"
const KILLER_POS := Vector3(-6.0, 0.15, 16.0)


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(40.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
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
	var net := arena.get_node("GameNet") as GameNet
	var building := arena.get_node("BuildingSystem") as BuildingSystem
	if net == null or building == null:
		return _fail("server arena missing GameNet or BuildingSystem")

	# Phase 0: the systems exist and do nothing yet.
	var vitals := net.vitals()
	if vitals == null or net.enemies() == null:
		return _fail("server did not create VitalsSystem and EnemySystem")
	if net.enemies().enemy_count() != 0:
		return _fail("EnemySystem spawned something")

	if net.debug_spawn(2, DEAD_TOKEN) != "" or net.debug_spawn(3, "bystander01") != "":
		return _fail("could not admit two players")
	var victim := net.debug_player(2)
	var bystander := net.debug_player(3)
	net.debug_place(2, KILLER_POS)
	net.debug_place(3, KILLER_POS + Vector3(1.5, 0.0, 0.0))
	net.debug_grant(2, "scrap_metal", 20)
	net.debug_grant(2, "cloth", 5)
	net.debug_reset_item_rate(2)
	var bag := net.debug_inventory(2)
	if bag.count_item("scrap_metal") != 20 or bag.count_item("debugweapon") != 1:
		return _fail("setup: victim bag is wrong")

	# A health value can never raise health. Only revive does.
	victim.receive_damage(30, Vector3.ZERO)
	victim.apply_authoritative_health(100)
	if victim.health != 70:
		return _fail("a stale health value healed the player (%d)" % victim.health)

	# Death.
	var death_pos := victim.global_position
	if not victim.receive_damage(500, Vector3.ZERO) or victim.health != 0 or not victim.is_down():
		return _fail("lethal damage did not down the player")
	vitals.advance(0.0)
	if net.deaths != 1 or not vitals.is_dead(2):
		return _fail("death was not noticed (deaths=%d)" % net.deaths)
	if absf(vitals.respawn_in(2) - VitalsSystem.RESPAWN_DELAY_SEC) > 0.01:
		return _fail("respawn timer is %.2f" % vitals.respawn_in(2))
	vitals.advance(0.0)
	if net.deaths != 1:
		return _fail("one death was counted twice")

	# Everything but the loadout is on the ground; the bag and cursor are empty.
	if bag.count_item("scrap_metal") != 0 or bag.count_item("cloth") != 0:
		return _fail("the dead player still holds their items")
	if bag.count_item("debugweapon") != 0:
		return _fail("the dead player kept the loadout")
	if net.last_death_drops != 2:
		return _fail("expected 2 dropped stacks, got %d" % net.last_death_drops)
	var scrap_drop := ""
	var cloth_drop := ""
	for key in net._pickups.keys():
		var pickup := net._pickups[key] as WorldPickup
		if pickup == null or not str(key).begins_with("drop_") or pickup.quantity <= 0:
			continue
		if pickup.global_position.distance_to(death_pos) > 3.0:
			return _fail("a drop landed %.1f m from the body" % pickup.global_position.distance_to(death_pos))
		if pickup.item_id == "scrap_metal" and pickup.quantity == 20:
			scrap_drop = str(key)
		elif pickup.item_id == "cloth" and pickup.quantity == 5:
			cloth_drop = str(key)
	if scrap_drop.is_empty() or cloth_drop.is_empty():
		return _fail("scrap or cloth drop is missing (%s, %s)" % [scrap_drop, cloth_drop])

	# A dead player cannot act.
	if net.hotbar_item(2) != "":
		return _fail("a dead player still holds a hotbar item")
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, cloth_drop) != "dead":
		return _fail("a dead player picked something up")
	if net.debug_pickup(cloth_drop).quantity != 5:
		return _fail("the pickup changed anyway")
	var rejected_before := net.rejected_shots
	net._handle_fire(2, 1, Vector3(0.0, 0.0, -1.0), 0.0, 0.0, 0.0)
	if net.rejected_shots != rejected_before + 1:
		return _fail("a dead player's shot was not rejected")
	var refused := building.relay.handle_place(2, 1, RoomPlacer.make_request("room", Vector2i(2, 2), 0, 0, 0, 0, Vector2i(2, 2)))
	if bool(refused.get("ok", true)) or str(refused.get("reason", "")) != "You are down":
		return _fail("a dead player's build was not refused: %s" % str(refused))
	victim.apply_authoritative_health(100)
	if victim.health != 0:
		return _fail("a stale value revived the body")

	# Someone else can loot the body.
	net.debug_reset_item_rate(3)
	if net.debug_collect(3, scrap_drop) != "":
		return _fail("the bystander could not loot the drop")
	if net.debug_inventory(3).count_item("scrap_metal") != 20:
		return _fail("the bystander did not get the scrap")

	# Wait out the timer. Move the bystander onto pad 0: the respawn must avoid them.
	net.debug_place(3, SpawnPoints.POINTS[0])
	vitals.advance(VitalsSystem.RESPAWN_DELAY_SEC - 1.0)
	if net.respawns != 0 or victim.health != 0:
		return _fail("respawned before the timer ran out")
	vitals.advance(1.5)
	if net.respawns != 1 or victim.health != victim.max_health or victim.is_down():
		return _fail("did not respawn (respawns=%d hp=%d)" % [net.respawns, victim.health])
	if vitals.is_dead(2):
		return _fail("still marked dead after respawn")
	var landed := net.debug_position(2)
	if _nearest_pad(landed) > 0.05:
		return _fail("respawned off the pads at %s" % landed)
	if landed.distance_to(bystander.global_position) < 6.0:
		return _fail("respawned %.1f m from another player" % landed.distance_to(bystander.global_position))
	if bag.count_item("debugweapon") != 1 or bag.count_item("scrap_metal") != 0:
		return _fail("respawn bag is wrong")
	net.debug_place(2, death_pos)
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, cloth_drop) != "":
		return _fail("a respawned player could not pick things up")

	# Dying again works, and a bare loadout drops nothing.
	if not victim.receive_damage(500, Vector3.ZERO):
		return _fail("could not kill the respawned player")
	vitals.advance(0.0)
	if net.deaths != 2 or net.last_death_drops != 1:
		return _fail("second death: deaths=%d drops=%d (cloth only)" % [net.deaths, net.last_death_drops])

	# Leaving while dead, then coming back, is a fresh spawn and not a corpse.
	net.debug_disconnect(2)
	if vitals.is_dead(2):
		return _fail("a disconnected peer is still on the death list")
	var profile := net.debug_profile(DEAD_TOKEN)
	if profile.is_empty() or int(profile.get("health", 1)) != 0:
		return _fail("profile should record the death: %s" % str(profile))
	if net.debug_spawn(4, DEAD_TOKEN) != "":
		return _fail("reconnect after death was refused")
	var back := net.debug_player(4)
	if back == null or back.health != back.max_health or back.is_down():
		return _fail("reconnected as a corpse")
	if net.debug_inventory(4).count_item("debugweapon") != 1:
		return _fail("reconnect after death has no loadout")

	# Client side: a puppet ignores stale heals and stands up only through revive.
	var puppet := net._make_player(77, Vector3(4.0, 0.15, 4.0), 0.0, PlayerController.NetRole.PUPPET)
	await physics_frame
	var downs := [0]
	var revives := [0]
	puppet.downed.connect(func() -> void: downs[0] += 1)
	puppet.revived.connect(func() -> void: revives[0] += 1)
	puppet.apply_authoritative_health(0)
	if not puppet.is_down() or downs[0] != 1:
		return _fail("puppet did not go down")
	if absf(puppet._character_model.rotation.x + PI * 0.5) > 0.01:
		return _fail("a downed body is not lying down (%.2f)" % puppet._character_model.rotation.x)
	puppet.apply_authoritative_health(100)
	if not puppet.is_down():
		return _fail("a stale snapshot stood the puppet up")
	puppet.revive(Vector3(9.0, 0.15, 9.0), 1.0)
	if puppet.is_down() or puppet.health != puppet.max_health or revives[0] != 1:
		return _fail("revive did not restore the puppet")
	if puppet.global_position.distance_to(Vector3(9.0, 0.15, 9.0)) > 0.01:
		return _fail("revive did not move the puppet")
	if absf(puppet._character_model.rotation.x) > 0.01:
		return _fail("a revived body is still lying down")
	puppet.apply_authoritative_health(0)
	if not puppet.is_down() or downs[0] != 2:
		return _fail("a revived puppet could not go down again")

	# The owner's HUD follows the body: bar, death screen, countdown, and the
	# flash. An owner pawn is the only role that gets one.
	var owner_pawn := net._make_player(78, Vector3(-4.0, 0.15, 4.0), 0.0, PlayerController.NetRole.OWNER)
	await physics_frame
	var hud := owner_pawn.get_node_or_null("VitalsHud") as VitalsHud
	if hud == null:
		return _fail("an owner pawn has no VitalsHud")
	if puppet.get_node_or_null("VitalsHud") != null:
		return _fail("a puppet got a VitalsHud")
	var bar := _find_progress_bar(hud)
	var death_screen := _find_death_screen(hud)
	if bar == null or death_screen == null:
		return _fail("HUD is missing its bar or death screen")
	await process_frame
	if int(bar.value) != 100 or death_screen.visible:
		return _fail("fresh HUD: bar=%d death_screen=%s" % [int(bar.value), death_screen.visible])
	owner_pawn.apply_authoritative_health(40)
	await process_frame
	if int(bar.value) != 40:
		return _fail("HUD bar did not follow health (%d)" % int(bar.value))
	owner_pawn.apply_authoritative_health(0)
	owner_pawn.respawn_eta = 3.2
	await process_frame
	if not death_screen.visible:
		return _fail("death screen is not shown for a downed owner")
	if owner_pawn.respawn_eta >= 3.2:
		return _fail("the respawn countdown does not tick")
	owner_pawn.revive(Vector3(-4.0, 0.15, 4.0), 0.0)
	await process_frame
	if death_screen.visible or int(bar.value) != 100:
		return _fail("HUD did not clear after revive")

	print("MILESTONE8_DEATH_OK")
	return 0


func _find_progress_bar(node: Node) -> ProgressBar:
	for child in node.find_children("*", "ProgressBar", true, false):
		return child as ProgressBar
	return null


func _find_death_screen(node: Node) -> ColorRect:
	for child in node.find_children("*", "ColorRect", true, false):
		return child as ColorRect
	return null


func _nearest_pad(pos: Vector3) -> float:
	var best := 1000.0
	for point in SpawnPoints.POINTS:
		best = minf(best, Vector2(point.x - pos.x, point.z - pos.z).length())
	return best


func _listen() -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	for port in range(39100, 39140):
		if peer.create_server(port, 4) == OK:
			return peer
	return null


func _fail(message: String) -> int:
	printerr("FAIL ", message)
	print("FAIL ", message)
	return 1
