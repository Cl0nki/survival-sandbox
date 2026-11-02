extends SceneTree

## Headless checks for Milestone 7 world save and reconnect.
## godot --headless --path <project> --script res://tests/milestone7_persist.gd

var _port := 0
var _path := ""


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	if not _path.is_empty() and FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)
		DirAccess.remove_absolute(_path + ".tmp")
	quit(code)


func _body() -> int:
	if not WorldStore.valid_token("persist01"):
		return _fail("persist01 should be a valid token")
	if WorldStore.valid_token("short") or WorldStore.valid_token("bad token!!"):
		return _fail("invalid tokens were accepted")
	if WorldStore.new_token().length() != 32:
		return _fail("new tokens should be 32 hex characters")

	_path = OS.get_cache_dir().path_join("survival-sandbox-m7-%d.json" % Time.get_ticks_msec())
	var packed := load("res://scenes/world/test_arena.tscn") as PackedScene
	if packed == null:
		return _fail("test arena failed to load")
	var peer := _listen()
	if peer == null:
		return _fail("could not bind a server port")
	root.get_multiplayer().multiplayer_peer = peer

	var first := packed.instantiate()
	first.force_mode = NetConfig.MODE_SERVER
	root.add_child(first)
	for _frame in 12:
		await physics_frame
	var net := first.get_node("GameNet") as GameNet
	var system := first.get_node("BuildingSystem") as BuildingSystem
	if net == null or system == null:
		return _fail("server arena missing GameNet or BuildingSystem")
	if net.save_world():
		return _fail("empty world_path still wrote a file")
	net.world_path = _path
	if net.debug_spawn(2, "no") != "token":
		return _fail("short token was admitted")
	if net.debug_spawn(2, "persist01") != "":
		return _fail("first claim failed")
	if net.debug_spawn(3, "persist01") != "online":
		return _fail("a second live peer reused the token")
	if net.debug_spawn(3, "persist02") != "":
		return _fail("second token failed")

	net.debug_place(2, Vector3(-6.0, 0.15, 16.0))
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, "scrap_pile") != "":
		return _fail("scrap collect failed")
	if net.debug_inventory(2).count_item("scrap_metal") != 8:
		return _fail("scrap was not on the collector")
	var built: Dictionary = system.authority.request_place(
		RoomPlacer.make_request("room", Vector2i(2, 2), 0, 0, 0, 0, Vector2i(2, 2)),
		0
	)
	if not bool(built.get("ok", false)):
		return _fail("room place failed: %s" % built.get("reason", ""))
	var checksum := system.state.checksum()
	if checksum == 0 or system.state.component_count() < 8:
		return _fail("placed room was empty")

	var dummy := first.get_node_or_null("OpenDummy") as Damageable
	if dummy == null or not dummy.receive_damage(34, Vector3.ZERO):
		return _fail("dummy was not damaged")
	var dummy_hp := dummy.health

	var crate := net.debug_container("woods_crate")
	if crate == null or not crate.inventory.take_item("logs", 1):
		return _fail("crate logs were missing")
	net._spawn_drop("cloth", 3, Vector3(4.0, 0.15, 4.0))
	if net.debug_pickup("drop_1") == null or net.debug_pickup("drop_1").quantity != 3:
		return _fail("dropped cloth was missing")

	if not net.debug_save():
		return _fail("save failed: %s" % net.last_world_error)
	net.debug_disconnect(2)
	if net.debug_profile("persist01").is_empty():
		return _fail("disconnect did not keep the profile")
	if net.debug_inventory(2) != null:
		return _fail("disconnected inventory stayed live")

	first.queue_free()
	await physics_frame
	await physics_frame

	var second := packed.instantiate()
	second.force_mode = NetConfig.MODE_SERVER
	root.add_child(second)
	for _frame in 12:
		await physics_frame
	var net2 := second.get_node("GameNet") as GameNet
	var system2 := second.get_node("BuildingSystem") as BuildingSystem
	if net2 == null or system2 == null:
		return _fail("second arena missing GameNet")
	if system2.state.component_count() != 0:
		return _fail("a new server already had buildings")
	var scrap := net2.debug_pickup("scrap_pile")
	if scrap == null or scrap.quantity != 8:
		return _fail("fresh arena did not start with the scrap pile")
	net2.world_path = _path
	if not net2.debug_load():
		return _fail("load failed: %s" % net2.last_world_error)
	if system2.state.checksum() != checksum:
		return _fail("loaded buildings did not match the save")
	if net2.debug_pickup("scrap_pile") == null or net2.debug_pickup("scrap_pile").quantity != 0:
		return _fail("collected scrap pile came back")
	if net2.debug_pickup("drop_1") == null or net2.debug_pickup("drop_1").quantity != 3:
		return _fail("dropped cloth did not reload")
	var crate2 := net2.debug_container("woods_crate")
	if crate2 == null or crate2.inventory.count_item("logs") != 19:
		return _fail("crate contents did not reload")
	var dummy2 := second.get_node_or_null("OpenDummy") as Damageable
	if dummy2 == null or dummy2.health != dummy_hp:
		return _fail("dummy health did not reload")
	if not net2.debug_load():
		return _fail("a second load failed")
	if system2.state.checksum() != checksum:
		return _fail("loading twice changed the buildings")

	if net2.debug_spawn(4, "persist01") != "":
		return _fail("reconnect was refused")
	var bag := net2.debug_inventory(4)
	if bag == null or bag.count_item("scrap_metal") != 8:
		return _fail("reconnect lost scrap")
	if bag.count_item("debugweapon") != 1:
		return _fail("reconnect lost the loadout")
	if net2.debug_spawn(5, "persist03") != "":
		return _fail("a new token was refused")
	if net2.debug_inventory(5).count_item("scrap_metal") != 0:
		return _fail("a new token inherited scrap")

	var garbage := FileAccess.open(_path, FileAccess.WRITE)
	if garbage == null:
		return _fail("could not overwrite the save")
	garbage.store_string("{not json")
	garbage.close()
	if net2.debug_load():
		return _fail("a corrupt save was treated as valid")
	if system2.state.checksum() != checksum:
		return _fail("a corrupt load changed the live world")

	print("MILESTONE7_PERSIST_OK")
	return 0


func _listen() -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	for port in range(39000, 39040):
		if peer.create_server(port, 4) == OK:
			_port = port
			return peer
	return null


func _fail(message: String) -> int:
	printerr("FAIL ", message)
	print("FAIL ", message)
	return 1
