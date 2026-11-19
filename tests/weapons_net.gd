extends SceneTree

## The authoritative server firing the new weapons: ammo per shot, pellets,
## the melee arc, the fire interval, and what other players are told is in hand.
## Also the client's own held-weapon handling.
## godot --headless --path <project> --script res://tests/weapons_net.gd

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fire_seq := 0
var _failure := ""
var _shooter: PlayerController


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	var server_peer := _listen()
	if packed == null or server_peer == null:
		return _fail("arena or port unavailable")
	root.get_multiplayer().multiplayer_peer = server_peer
	var arena := packed.instantiate()
	arena.force_mode = NetConfig.MODE_SERVER
	root.add_child(arena)
	var net := arena.get_node("GameNet") as GameNet
	net._spawn_authority(2)
	net._spawn_authority(3)
	var settled: bool = await _wait_until(120, func() -> bool:
		var a := net.debug_player(2)
		var b := net.debug_player(3)
		return a != null and b != null and a.is_on_floor() and b.is_on_floor()
	)
	if not settled:
		return _fail("players did not settle")

	var shooter := net.debug_player(2)
	var victim := net.debug_player(3)
	var bag := net.debug_inventory(2)
	_shooter = shooter
	shooter.hotbar_index = 0

	# --- What the server tells other players is in hand.
	_hold(bag, "")
	if not is_zero_approx(net._weapon_style(2)):
		return _fail("an empty hand should draw nothing")
	_hold(bag, "hornet_pdw")
	if not is_equal_approx(net._weapon_style(2), 1.0):
		return _fail("a gun should draw as 1")
	_hold(bag, "sword")
	if not is_equal_approx(net._weapon_style(2), 2.0):
		return _fail("a sword should draw as 2")

	# --- A new gun spends its own ammunition and does its own damage.
	_hold(bag, "hornet_pdw")
	_stock(bag, "ammo_9mm", 5)
	_place_pair(net, 4.0)
	await _settle()
	var before := victim.health
	var rounds := bag.count_item("ammo_9mm")
	_fire_at(net, shooter, victim)
	await physics_frame
	if rounds - bag.count_item("ammo_9mm") != 1:
		return _fail("one shot should spend one 9mm round (%d -> %d)" % [rounds, bag.count_item("ammo_9mm")])
	if before - victim.health != 15:
		return _fail("the PDW should do 15, health went %d -> %d" % [before, victim.health])
	if bag.count_item("ammo_45acp") != 0:
		return _fail("a 9mm gun touched other ammunition")

	# --- Wrong ammunition does not fire it.
	_hold(bag, "rattler_smg")
	net.debug_reset_cooldown(2)
	victim.health = 100
	var accepted := net.accepted_shots
	_fire_at(net, shooter, victim)
	if net.accepted_shots != accepted or victim.health != 100:
		return _fail("a .45 gun fired with only 9mm in the bag")
	_stock(bag, "ammo_45acp", 3)
	_fire_at(net, shooter, victim)
	await physics_frame
	if bag.count_item("ammo_45acp") != 2 or 100 - victim.health != 24:
		return _fail("the SMG should spend a .45 round for 24 (ammo %d, health %d)" % [bag.count_item("ammo_45acp"), victim.health])

	# --- The interval: an immediate second pull is refused, a later one is not.
	_hold(bag, "hornet_pdw")
	net.debug_reset_cooldown(2)
	victim.health = 100
	_fire_at(net, shooter, victim)
	var after_first := victim.health
	var rejected := net.rejected_shots
	_fire_at(net, shooter, victim)
	if victim.health != after_first or net.rejected_shots != rejected + 1:
		return _fail("a second shot inside the interval was not refused")
	# The server times shots on the wall clock, and a headless run's own timers
	# are not tied to it, so wait on the wall clock too.
	var waited_from := Time.get_ticks_msec()
	while Time.get_ticks_msec() - waited_from < 160:
		await physics_frame
	_fire_at(net, shooter, victim)
	if victim.health >= after_first:
		return _fail("a shot after the interval was refused")

	# --- A shotgun throws every pellet for one shell.
	_hold(bag, "breacher_shotgun")
	_stock(bag, "ammo_12gauge", 4)
	net.debug_reset_cooldown(2)
	_place_pair(net, 7.0)
	await _settle()
	var weapon := shooter.get_node("HitscanWeapon") as HitscanWeapon
	weapon._rng.seed = 11
	victim.health = 100
	var shells := bag.count_item("ammo_12gauge")
	_fire_at(net, shooter, victim)
	await physics_frame
	var dealt := 100 - victim.health
	if shells - bag.count_item("ammo_12gauge") != 1:
		return _fail("a shotgun pull should spend one shell")
	if dealt < 28 or (dealt % 14 != 0 and victim.health > 0):
		return _fail("shotgun damage should be whole pellets of 14, dealt %d" % dealt)
	if weapon.pellets != 8:
		return _fail("the server weapon was not configured for eight pellets")
	# The same server weapon node returns to the pistol numbers on the next gun.
	_hold(bag, "pistol")
	_stock(bag, "ammo_9mm", 2)
	net.debug_reset_cooldown(2)
	victim.health = 100
	_place_pair(net, 4.0)
	await _settle()
	_fire_at(net, shooter, victim)
	await physics_frame
	if 100 - victim.health != 34 or weapon.pellets != 1:
		return _fail("swapping guns kept the shotgun's numbers (dealt %d, pellets %d)" % [100 - victim.health, weapon.pellets])

	# --- The sword: no ammunition, short reach.
	_hold(bag, "sword")
	net.debug_reset_cooldown(2)
	victim.health = 100
	_place_pair(net, 2.0)
	await _settle()
	var stock_before := bag.count_item("ammo_9mm")
	_fire_at(net, shooter, victim)
	await physics_frame
	if 100 - victim.health != 48:
		return _fail("the sword should do 48 up close, dealt %d" % [100 - victim.health])
	if bag.count_item("ammo_9mm") != stock_before:
		return _fail("the sword spent ammunition")
	net.debug_reset_cooldown(2)
	victim.health = 100
	_place_pair(net, 7.0)
	await _settle()
	_fire_at(net, shooter, victim)
	await physics_frame
	if victim.health != 100:
		return _fail("the sword hit something 7 m away")

	# --- Held weapons on the client.
	var client := PLAYER_SCENE.instantiate() as PlayerController
	arena.add_child(client)
	client.global_position = Vector3(10.0, 0.15, 30.0)
	if client.inventory == null:
		client.inventory = Inventory.new_player()
	client.hotbar_index = 0
	# The stand-in moves onto the hand bone once the character model is ready.
	var mesh := client.find_child("WeaponMesh", true, false) as MeshInstance3D
	_put_in_hand(client.inventory, client, "titan_hmg")
	client.refresh_weapon_visual()
	if not client.holds_firearm() or client.holds_melee() or client.held_weapon().item_id != "titan_hmg":
		return _fail("the client does not see the heavy machine gun in hand")
	if mesh == null or not mesh.visible or mesh.scale.z < 3.0:
		return _fail("the held heavy machine gun is not a long stand-in (scale %s)" % [mesh.scale if mesh != null else "none"])
	_put_in_hand(client.inventory, client, "sword")
	client.refresh_weapon_visual()
	if not client.holds_melee() or client.holds_firearm() or mesh.scale.x > 0.7:
		return _fail("the client does not see a thin blade for the sword (scale %s)" % mesh.scale)
	_put_in_hand(client.inventory, client, "pistol")
	client.refresh_weapon_visual()
	if not is_equal_approx(mesh.scale.z, 1.0) or not is_equal_approx(mesh.scale.x, 1.0):
		return _fail("the pistol did not return the stand-in to pistol size (scale %s)" % mesh.scale)
	_put_in_hand(client.inventory, client, "")
	client.refresh_weapon_visual()
	if mesh.visible or client.held_weapon() != null:
		return _fail("an empty hand still draws a weapon")
	# A weapon in the hotbar is not in hand, on the client or on the server.
	client.inventory.slots[0] = {"id": "pistol", "qty": 1}
	client.select_hotbar(0)
	if client.held_weapon() != null or client.holds_firearm() or client.held_item_id() != "":
		return _fail("a pistol in the hotbar must not be held")
	bag.slots[0] = {"id": "pistol", "qty": 1}
	_shooter.hotbar_index = 0
	if not is_zero_approx(net._weapon_style(2)) or net._held_item_id(2) != "":
		return _fail("the server must not see a hotbar weapon in hand")
	bag.slots[0] = Inventory._empty()
	client.queue_free()

	print("WEAPONS_NET_OK")
	return 0


## Puts the weapon in its own slot and takes it into the shooter's hand. A weapon is
## only held from a weapon slot. An empty id empties all three and selects hotbar slot 0.
func _hold(bag: Inventory, item_id: String) -> void:
	_put_in_hand(bag, _shooter, item_id)


func _put_in_hand(bag: Inventory, player: PlayerController, item_id: String) -> void:
	for slot_name in WeaponSpec.SLOTS:
		bag.slots[bag.weapon_slot_index(slot_name)] = Inventory._empty()
	if item_id.is_empty():
		player.hotbar_index = 0
		return
	var index := bag.weapon_slot_index(WeaponSpec.slot_of(item_id))
	bag.slots[index] = {"id": item_id, "qty": 1}
	player.hotbar_index = index


func _stock(bag: Inventory, ammo: String, quantity: int) -> void:
	var have := bag.count_item(ammo)
	if have > 0:
		bag.take_item(ammo, have)
	bag.add_exact(ammo, quantity)


func _place_pair(net: GameNet, gap: float) -> void:
	net.debug_place(2, Vector3(-gap * 0.5, 0.15, 8.0))
	net.debug_place(3, Vector3(gap * 0.5, 0.15, 8.0))


func _settle() -> void:
	for _step in 6:
		await physics_frame


func _fire_at(net: GameNet, shooter: PlayerController, target: PlayerController) -> void:
	var goal := target.global_position + Vector3(0.0, 1.0, 0.0)
	var yaw := atan2(-(goal.x - shooter.global_position.x), -(goal.z - shooter.global_position.z))
	shooter.apply_facing_yaw(yaw)
	shooter.snap_lean_for_shot(0.0)
	var origin := shooter.shot_origin()
	var flat := Vector3(goal.x - origin.x, 0.0, goal.z - origin.z)
	_fire_seq += 1
	net._handle_fire(2, _fire_seq, flat.normalized(), yaw, 0.0)


func _listen() -> ENetMultiplayerPeer:
	for port in range(25140, 25170):
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(port, 8) == OK:
			return peer
		peer.close()
	return null


func _wait_until(max_frames: int, predicate: Callable) -> bool:
	for _frame in max_frames:
		if bool(predicate.call()):
			return true
		await physics_frame
	return false


func _fail(message: String) -> int:
	_failure = message
	push_error(message)
	print("WEAPONS_NET_FAIL: ", message)
	return 1
