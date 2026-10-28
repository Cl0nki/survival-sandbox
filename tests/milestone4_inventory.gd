extends SceneTree

## Headless checks for Milestone 4 inventories, pickups, and crates.
## godot --headless --path <project> --script res://tests/milestone4_inventory.gd

var _port := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	var code := await _body()
	quit(code)


func _body() -> int:
	var rules := _rules()
	if rules != "":
		return _fail(rules)
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

	var scrap := net.debug_pickup("scrap_pile")
	var cloth := net.debug_pickup("cloth_pile")
	var crate := net.debug_container("supply_crate")
	if scrap == null or scrap.quantity != 8:
		return _fail("scrap pile missing")
	if cloth == null or cloth.quantity != 6:
		return _fail("cloth pile missing")
	if crate == null or crate.inventory.count_item("medical_supplies") != 2:
		return _fail("crate contents missing")
	if crate.inventory.count_item("ammunition") != 20:
		return _fail("crate ammo missing")

	net.debug_place(2, Vector3(0.0, 0.15, 0.0))
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, "scrap_pile") == "":
		return _fail("far pickup was collected")
	if scrap.quantity != 8:
		return _fail("far pickup changed")

	net.debug_place(2, Vector3(10.0, 0.15, 12.0))
	net.debug_place(3, Vector3(10.2, 0.15, 12.0))
	net.debug_reset_item_rate(2)
	net.debug_reset_item_rate(3)
	if net.debug_collect(2, "scrap_pile") != "":
		return _fail("near pickup failed")
	if net.debug_inventory(2).count_item("scrap_metal") != Inventory.STARTING_SCRAP + 8:
		return _fail("collector did not receive scrap")
	if net.debug_collect(3, "scrap_pile") == "":
		return _fail("second player duplicated the scrap pile")
	if scrap.quantity != 0 or not scrap.visible == false:
		return _fail("collected pile still in the world qty=%s" % scrap.quantity)
	if net.debug_inventory(3).count_item("scrap_metal") != Inventory.STARTING_SCRAP:
		return _fail("second player gained scrap")
	var scrap_slot := _slot_with_qty(net.debug_inventory(2), "scrap_metal", 8)
	if scrap_slot < 0:
		return _fail("scrap did not land in a slot")
	net.debug_reset_item_rate(2)
	if net.debug_click(2, 0, scrap_slot, true, false, false) != "":
		return _fail("right click did not pick up half the stack")
	if int(net.debug_cursor(2)["qty"]) != 4 or int(net.debug_inventory(2).slots[scrap_slot]["qty"]) != 4:
		return _fail("half stack split was wrong")
	if int(net.debug_cursor(3)["qty"]) != 0:
		return _fail("peer 3 received peer 2 cursor")
	net.debug_reset_item_rate(2)
	if net.debug_click(2, 0, scrap_slot, false, false, false) != "":
		return _fail("click did not put the stack back")
	if int(net.debug_cursor(2)["qty"]) != 0 or net.debug_inventory(2).count_item("scrap_metal") != Inventory.STARTING_SCRAP + 8:
		return _fail("placed stack was not restored")

	var bag := net.debug_inventory(2)
	if not bag.add_exact("scrap_metal", 42):
		return _fail("stacking more scrap failed")
	scrap_slot = _slot_of(bag, "scrap_metal")
	if scrap_slot < 0 or int(bag.slots[scrap_slot]["qty"]) != 50:
		return _fail("first stack did not stop at 50, got %s" % bag.slots[scrap_slot]["qty"])
	if bag.count_item("scrap_metal") != Inventory.STARTING_SCRAP + 50:
		return _fail("scrap total after the stack limit was %s" % bag.count_item("scrap_metal"))
	if bag.remove_from_slot(scrap_slot, 51):
		return _fail("remove produced a negative stack")
	if int(bag.slots[scrap_slot]["qty"]) != 50:
		return _fail("failed remove changed the stack")

	bag.resize(1)
	if not bag.add_exact("cloth", 20):
		return _fail("could not fill the only slot")
	net.debug_place(2, Vector3(12.0, 0.15, 10.0))
	net.debug_reset_item_rate(2)
	var before_cloth := cloth.quantity
	if net.debug_collect(2, "cloth_pile") == "":
		return _fail("full inventory accepted cloth")
	if cloth.quantity != before_cloth:
		return _fail("failed pickup destroyed cloth")

	bag.resize(NetConfig.INVENTORY_SLOTS)
	net.debug_place(2, Vector3(-12.0, 0.15, 12.0))
	net.debug_place(3, Vector3(-12.2, 0.15, 12.0))
	net.debug_reset_item_rate(2)
	net.debug_reset_item_rate(3)
	if net.debug_open(2, "supply_crate") != "":
		return _fail("could not open the crate")
	if net.debug_transfer(2, "supply_crate", false, 0, 0, 1) != "":
		return _fail("could not take one medical supply")
	if bag.count_item("medical_supplies") != 1 or crate.inventory.count_item("medical_supplies") != 1:
		return _fail("partial take split medical wrong")
	if net.debug_transfer(2, "supply_crate", true, 0, 0, 1) != "":
		return _fail("could not store the medical supply back")
	if bag.count_item("medical_supplies") != 0 or crate.inventory.count_item("medical_supplies") != 2:
		return _fail("store did not restore the crate")
	if not bag.add_exact("scrap_metal", 4):
		return _fail("could not keep a private scrap stack")
	if not bag.add_exact("ammunition", 50):
		return _fail("could not add an ammo stack")
	var ammo_before := bag.count_item("ammunition")
	var crate_ammo := crate.inventory.count_item("ammunition")
	net.debug_reset_item_rate(2)
	if net.debug_transfer(2, "supply_crate", true, 1, 1, 50) == "":
		return _fail("transfer exceeded the ammo stack limit")
	if bag.count_item("ammunition") != ammo_before or crate.inventory.count_item("ammunition") != crate_ammo:
		return _fail("rejected stack-limit transfer changed items")
	net.debug_reset_item_rate(2)
	if net.debug_transfer(2, "supply_crate", false, 9, 0, 1) == "":
		return _fail("bad slot was accepted")
	if net.debug_transfer(2, "supply_crate", false, 0, 0, 0) == "":
		return _fail("zero quantity was accepted")
	bag.slots[2] = {"id": "ghost", "qty": 1}
	var ghost_qty := 1
	if net.debug_transfer(2, "supply_crate", true, 2, 3, 1) == "":
		return _fail("unknown item id was stored")
	if int(bag.slots[2]["qty"]) != ghost_qty:
		return _fail("rejected unknown item changed the slot")

	var blocked := ItemDefinition.new()
	blocked.id = "bolted_plate"
	blocked.display_name = "Bolted Plate"
	blocked.max_stack = 4
	blocked.can_pickup = false
	blocked.can_store = false
	ItemCatalog.debug_register(blocked)
	var food := net.debug_pickup("food_pile")
	var saved_food := food.item_id
	var saved_qty := food.quantity
	food.item_id = "bolted_plate"
	net.debug_place(2, food.global_position)
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, "food_pile") == "":
		return _fail("non-pickup item was collected")
	if food.quantity != saved_qty:
		return _fail("rejected pickup changed the world item")
	food.item_id = saved_food
	bag.slots[3] = {"id": "bolted_plate", "qty": 2}
	net.debug_place(2, Vector3(-12.0, 0.15, 12.0))
	net.debug_reset_item_rate(2)
	if net.debug_open(2, "supply_crate") != "":
		return _fail("could not reopen the crate")
	if net.debug_transfer(2, "supply_crate", true, 3, 4, 2) == "":
		return _fail("unstorable item entered the crate")
	if int(bag.slots[3]["qty"]) != 2:
		return _fail("rejected store changed the player stack")

	var ammo_slot := -1
	for index in crate.inventory.capacity:
		if str(crate.inventory.slots[index]["id"]) == "ammunition" and int(crate.inventory.slots[index]["qty"]) >= 20:
			ammo_slot = index
	if ammo_slot < 0:
		return _fail("crate lost its ammo before the concurrent transfer")
	crate.inventory.slots[ammo_slot] = {"id": "ammunition", "qty": 20}
	for index in bag.capacity:
		if str(bag.slots[index]["id"]) == "ammunition":
			bag.slots[index] = {"id": "", "qty": 0}
	net.debug_inventory(3).slots[0] = {"id": "", "qty": 0}
	if net.debug_open(3, "supply_crate") != "":
		return _fail("second player could not open the crate")
	net.debug_reset_item_rate(2)
	net.debug_reset_item_rate(3)
	var first := net.debug_transfer(2, "supply_crate", false, ammo_slot, 5, 20)
	var second := net.debug_transfer(3, "supply_crate", false, ammo_slot, 0, 20)
	var held := bag.count_item("ammunition") + net.debug_inventory(3).count_item("ammunition")
	var left := crate.inventory.count_item("ammunition")
	if first != "" or second == "":
		return _fail("concurrent ammo transfer result first=%s second=%s" % [first, second])
	if held + left != 20:
		return _fail("concurrent transfer duplicated or lost ammo held=%s left=%s" % [held, left])

	if net.debug_inventory(3).count_item("scrap_metal") != Inventory.STARTING_SCRAP:
		return _fail("peer 3 payload included peer 2 scrap")
	if not net.debug_inventory_ids(2).has("scrap_metal") and not net.debug_inventory_ids(2).has("cloth"):
		return _fail("owner payload lost their own items")
	if net.last_container_recipients.has(3) and net.debug_inventory(3).count_item("medical_supplies") > 0:
		return _fail("container sync gave peer 3 another player's items")
	if net.last_container_recipients.has(99):
		return _fail("container sync included an unknown peer")

	net._item_lock = true
	net.debug_reset_item_rate(2)
	if net.debug_collect(2, "cloth_pile") != "busy":
		return _fail("overlapping item operation was not rejected")
	net._item_lock = false

	var held_start := net.debug_position(2)
	for step in 8:
		net._handle_input(2, 100 + step, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		await physics_frame
	if net.debug_position(2).distance_to(held_start) > 0.2:
		return _fail("player walked while the crate was open")
	net._handle_close_container(2)

	var moved := false
	var start := net.debug_position(2)
	for step in 8:
		net._handle_input(2, 200 + step, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
		await physics_frame
	if net.debug_position(2).distance_to(start) > 0.2:
		moved = true
	if not moved:
		return _fail("closing the crate did not restore movement")

	print("MILESTONE4_INVENTORY_OK")
	return 0


func _rules() -> String:
	var bag := Inventory.new(4)
	if not bag.add_exact("scrap_metal", 30):
		return "catalog add failed"
	if not bag.add_exact("scrap_metal", 25):
		return "second stack add failed"
	if int(bag.slots[0]["qty"]) != 50 or int(bag.slots[1]["qty"]) != 5:
		return "stacks did not combine to 50 then 5"
	if bag.add_exact("not_an_item", 1):
		return "unknown item was added"
	var other := Inventory.new(2)
	if Inventory.move(bag, 1, other, 0, 3, true) != "":
		return "partial move of 3 failed"
	if int(bag.slots[1]["qty"]) != 2 or int(other.slots[0]["qty"]) != 3:
		return "partial move amounts were wrong"
	if Inventory.move(bag, -1, other, 0, 1, true) == "":
		return "negative slot accepted"
	if Inventory.move(bag, 0, other, 0, -4, true) == "":
		return "negative quantity accepted"
	var total := bag.count_item("scrap_metal") + other.count_item("scrap_metal")
	if Inventory.move(bag, 0, other, 0, 50, true) == "":
		return "move into a full stack of a different remainder should fail at limit"
	if bag.count_item("scrap_metal") + other.count_item("scrap_metal") != total:
		return "failed move changed item totals"
	if Inventory.drop(bag, 0, other, 1, 10, true) != "":
		return "drag onto an empty slot failed"
	if int(other.slots[1]["qty"]) != 10:
		return "drag did not fill the empty slot"
	other.slots[0] = {"id": "cloth", "qty": 2}
	var swapped := Inventory.drop(other, 0, other, 1, 2, false)
	if swapped != "":
		return "drag swap failed: %s" % swapped
	if str(other.slots[0]["id"]) != "scrap_metal" or str(other.slots[1]["id"]) != "cloth":
		return "drag swap did not exchange the slots"
	var held := {"id": "", "qty": 0}
	var pocket := Inventory.new(18)
	pocket.slots[0] = {"id": "scrap_metal", "qty": 5}
	if SlotOps.click(pocket, null, held, SlotOps.AREA_PLAYER, 0, true, false) != "":
		return "minecraft half click failed"
	if int(held["qty"]) != 3 or int(pocket.slots[0]["qty"]) != 2:
		return "minecraft half split was %s / %s" % [held["qty"], pocket.slots[0]["qty"]]
	if SlotOps.quick_move(pocket, null, SlotOps.AREA_PLAYER, 0) != "":
		return "shift into the hotbar failed"
	if int(pocket.slots[0]["qty"]) != 0 or pocket.count_item("scrap_metal") != 2:
		return "shift click did not move the remaining scrap"
	return ""


func _listen() -> ENetMultiplayerPeer:
	for port in range(25310, 25340):
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(port, 8)
		if err == OK:
			_port = port
			return peer
		peer.close()
	return null


func _slot_with_qty(bag: Inventory, item_id: String, quantity: int) -> int:
	for index in bag.capacity:
		if str(bag.slots[index]["id"]) == item_id and int(bag.slots[index]["qty"]) == quantity:
			return index
	return -1


func _slot_of(bag: Inventory, item_id: String) -> int:
	for index in bag.capacity:
		if str(bag.slots[index]["id"]) == item_id:
			return index
	return -1


func _fail(message: String) -> int:
	push_error(message)
	print("MILESTONE4_INVENTORY_FAIL: ", message)
	return 1
