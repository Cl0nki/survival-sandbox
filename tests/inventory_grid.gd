extends SceneTree

## Headless check of item footprints: primary weapons and small deployables cover two
## cells, big deployables four, in the storage grid and in chests. The hotbar, the weapon
## slots and stations keep one cell per slot.
## godot --headless --path <project> --script res://tests/inventory_grid.gd

const BIG := ["armory", "foundry", "kiln_shed", "kitchen", "machine_shop", "pump_jack_gas",
	"pump_jack_oil", "refinery", "sawmill", "smelter_iron", "smelter_steel"]
# Rifles, the anti-materiel rifle and the machine guns are three cells long. Other primaries are 2x1.
const LONG_GUNS := {
	"kodiak_rifle": Vector2i(3, 1), "falconer_rifle": Vector2i(3, 1), "ridgeback_rifle": Vector2i(3, 1),
	"goliath_amr": Vector2i(3, 1), "titan_hmg": Vector2i(3, 1), "hailstorm_lmg": Vector2i(3, 1),
}


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("INVENTORY_GRID_OK")
	quit(code)


func _fail(message: String) -> int:
	print("FAIL %s" % message)
	return 1


func _cells(bag: Inventory, anchor: int, item_id: String) -> Array:
	return Array(bag.cells_for(anchor, item_id))


func _run() -> int:
	# Sizes come from the item files.
	for item_id in ItemCatalog.all_ids():
		var definition := ItemCatalog.get_item(item_id)
		var size := Inventory.footprint_of(item_id)
		var expect := Vector2i.ONE
		if WeaponSpec.slot_of(item_id) == WeaponSpec.SLOT_PRIMARY:
			expect = LONG_GUNS.get(item_id, Vector2i(2, 1))
		elif DeployableCatalog.known(item_id):
			expect = Vector2i(2, 2) if BIG.has(item_id) else Vector2i(2, 1)
		if size != expect:
			return _fail("%s should cover %s, covers %s" % [item_id, expect, size])
		if definition.weapon_kind != "" and WeaponSpec.slot_of(item_id) != WeaponSpec.SLOT_PRIMARY and size != Vector2i.ONE:
			return _fail("%s is a sidearm or blade and should be one cell" % item_id)

	var bag := Inventory.new_player()
	if bag.grid_columns != NetConfig.GRID_COLUMNS or bag.grid_start() != NetConfig.HOTBAR_SLOTS:
		return _fail("the player grid should start after the hotbar")
	if bag.in_grid(0) or bag.in_grid(8) or not bag.in_grid(9) or not bag.in_grid(NetConfig.BAG_SLOTS - 1) or bag.in_grid(NetConfig.BAG_SLOTS):
		return _fail("only the storage slots are in the grid")

	# Which cells a stack covers.
	if _cells(bag, 9, "rattler_smg") != [9, 10]:
		return _fail("a rifle at 9 should cover 9 and 10, covers %s" % [_cells(bag, 9, "rattler_smg")])
	if _cells(bag, 17, "rattler_smg") != []:
		return _fail("a rifle on the last column runs off the grid")
	if _cells(bag, 9, "armory") != [9, 10, 18, 19]:
		return _fail("an armory at 9 should cover a 2x2 block, covers %s" % [_cells(bag, 9, "armory")])
	if _cells(bag, 27, "armory") != []:
		return _fail("a 2x2 on the bottom row runs off the grid")
	if _cells(bag, 27, "workbench") != [27, 28]:
		return _fail("a workbench on the bottom row covers two cells")
	if _cells(bag, 0, "armory") != [0]:
		return _fail("a hotbar slot is one cell whatever the item")
	if _cells(bag, NetConfig.BAG_SLOTS, "rattler_smg") != [NetConfig.BAG_SLOTS]:
		return _fail("a weapon slot is one cell")

	# Which item covers a cell.
	bag.slots[12] = {"id": "rattler_smg", "qty": 1}
	bag.slots[20] = {"id": "armory", "qty": 1}
	if bag.anchor_at(12) != 12 or bag.anchor_at(13) != 12 or bag.anchor_at(14) != -1:
		return _fail("a rifle at 12 covers 12 and 13 only")
	if bag.anchor_at(20) != 20 or bag.anchor_at(21) != 20 or bag.anchor_at(29) != 20 or bag.anchor_at(30) != 20 or bag.anchor_at(22) != -1:
		return _fail("an armory at 20 covers the block 20, 21, 29, 30")
	if bag.anchor_at(12, [12]) != -1:
		return _fail("an ignored item counts as gone")
	if bag.can_place(13, "sword") or not bag.can_place(14, "sword") or not bag.can_place(13, "sword", [12]):
		return _fail("placement should see the cells a rifle covers")
	if bag.can_place(11, "rattler_smg") or not bag.can_place(14, "rattler_smg"):
		return _fail("a rifle next to a rifle needs both cells free")

	# Room for new stacks counts footprints, not slots.
	bag = Inventory.new_player()
	if bag.space_for("armory") != 4:
		return _fail("27 cells hold four 2x2 armories (two rows of them), was %d" % bag.space_for("armory"))
	for _n in 4:
		if not bag.add_exact("armory", 1):
			return _fail("an armory should fit")
	if bag.space_for("armory") != 0 or bag.add_exact("armory", 1):
		return _fail("no fifth armory fits in three rows")
	if bag.space_for("workbench") != 4 or bag.space_for("rattler_smg") != 4:
		return _fail("the third row takes four 2-wide items, was %d / %d" % [bag.space_for("workbench"), bag.space_for("rattler_smg")])
	var placed := _anchors(bag, "armory")
	if placed != [9, 11, 13, 15]:
		return _fail("armories should fill from the top left, were at %s" % [placed])
	# Single cells still fill the gaps and the hotbar.
	var room := bag.space_for("log")
	if room < 2 + 9 + 9:
		return _fail("single-cell items should use the leftover cells, room %d" % room)

	# Clicking with a held stack.
	bag = Inventory.new_player()
	var cursor := {"id": "rattler_smg", "qty": 1}
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 17, false, false) != "occupied":
		return _fail("a rifle on the last column should be refused")
	if int(cursor["qty"]) != 1:
		return _fail("a refused click keeps the cursor")
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 12, false, false) != "":
		return _fail("a rifle on a free cell should be placed")
	if str(bag.slots[12]["id"]) != "rattler_smg" or bag.anchor_at(13) != 12 or int(cursor["qty"]) != 0:
		return _fail("the rifle should sit at 12 covering 13")
	# Any covered cell picks the item up.
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 13, false, false) != "":
		return _fail("clicking a covered cell should pick the item up")
	if str(cursor["id"]) != "rattler_smg" or str(bag.slots[12]["id"]) != "" or bag.anchor_at(13) != -1:
		return _fail("the whole rifle should come off its cells")
	# A held rifle may not land half on another item.
	bag.slots[14] = {"id": "log", "qty": 3}
	bag.slots[15] = {"id": "stick", "qty": 2}
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 14, false, false) != "occupied":
		return _fail("a rifle over two different items should be refused")
	if str(cursor["id"]) != "rattler_smg" or str(bag.slots[14]["id"]) != "log" or str(bag.slots[15]["id"]) != "stick":
		return _fail("a refused click changes nothing")
	bag.slots[15] = Inventory._empty()
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 13, false, false) != "":
		return _fail("a rifle that overlaps one item swaps with it")
	if str(cursor["id"]) != "log" or int(cursor["qty"]) != 3 or str(bag.slots[13]["id"]) != "rattler_smg" or bag.anchor_at(14) != 13:
		return _fail("the rifle should take the log's place and the log go to the cursor")
	# A big stack that would land on two items is refused.
	bag.slots[22] = {"id": "stick", "qty": 1}
	var other := {"id": "armory", "qty": 1}
	if SlotOps.click(bag, null, other, SlotOps.AREA_PLAYER, 13, false, false) != "occupied":
		return _fail("an armory cannot swap in where it would cover two items")
	if str(bag.slots[13]["id"]) != "rattler_smg" or str(other["id"]) != "armory":
		return _fail("a refused swap changes nothing")
	# Same-id stacks merge through any covered cell. Cells hold the stack, so use a stackable.
	bag = Inventory.new_player()
	bag.slots[10] = {"id": "log", "qty": 5}
	var logs := {"id": "log", "qty": 4}
	if SlotOps.click(bag, null, logs, SlotOps.AREA_PLAYER, 10, false, false) != "" or int(bag.slots[10]["qty"]) != 9:
		return _fail("matching stacks should merge")

	# Shift-click moves a big item from any of its cells and finds room for its footprint.
	bag = Inventory.new_player()
	var crate := Inventory.new(27)
	crate.grid_columns = NetConfig.GRID_COLUMNS
	bag.slots[12] = {"id": "workbench", "qty": 1}
	if SlotOps.quick_move(bag, crate, SlotOps.AREA_PLAYER, 13) != "":
		return _fail("shift-click on a covered cell should move the item")
	if str(crate.slots[0]["id"]) != "workbench" or crate.anchor_at(1) != 0 or bag.anchor_at(12) != -1:
		return _fail("the workbench should land in the chest at 0 covering 1")
	crate.slots[2] = {"id": "log", "qty": 1}
	crate.slots[4] = {"id": "log", "qty": 1}
	crate.slots[6] = {"id": "log", "qty": 1}
	crate.slots[8] = {"id": "log", "qty": 1}
	bag.slots[12] = {"id": "workbench", "qty": 1}
	if SlotOps.quick_move(bag, crate, SlotOps.AREA_PLAYER, 12) != "" or crate.anchor_at(10) != 9:
		return _fail("a 2-wide item should skip gaps that are too small, and land at 9")
	var tiny := Inventory.new(3)
	tiny.grid_columns = 3
	tiny.slots[1] = {"id": "log", "qty": 1}
	bag.slots[12] = {"id": "workbench", "qty": 1}
	if SlotOps.quick_move(bag, tiny, SlotOps.AREA_PLAYER, 12) == "" or str(bag.slots[12]["id"]) != "workbench":
		return _fail("a chest with no room for the footprint should refuse and keep the item")
	# A station's slots are single cells whatever the item.
	var station := Inventory.new(4)
	station.slots[0] = {"id": "workbench", "qty": 1}
	if station.anchor_at(1) != -1 or not station.can_place(1, "armory"):
		return _fail("a bag without a grid covers one cell per item")

	# The hotbar holds a deployable in one slot, and swapping goes through any covered cell.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "workbench", "qty": 1}
	bag.slots[3] = {"id": "log", "qty": 2}
	if SlotOps.swap_hotbar(bag, null, SlotOps.AREA_PLAYER, 13, 3) != "":
		return _fail("swapping through a covered cell failed")
	if str(bag.slots[3]["id"]) != "workbench" or str(bag.slots[12]["id"]) != "log" or bag.anchor_at(13) != -1:
		return _fail("the workbench should go to the hotbar and the logs to its top-left cell")
	bag.slots[4] = {"id": "armory", "qty": 1}
	bag.slots[9] = {"id": "log", "qty": 1}
	bag.slots[18] = {"id": "stick", "qty": 1}
	if SlotOps.swap_hotbar(bag, null, SlotOps.AREA_PLAYER, 9, 4) != "occupied":
		return _fail("an armory swapped into a spot where it does not fit should be refused")
	if str(bag.slots[4]["id"]) != "armory" or str(bag.slots[9]["id"]) != "log":
		return _fail("a refused hotbar swap changes nothing")
	bag.slots[18] = Inventory._empty()
	if SlotOps.swap_hotbar(bag, null, SlotOps.AREA_PLAYER, 9, 4) != "" or bag.anchor_at(19) != 9:
		return _fail("an armory should swap into the grid when it fits")
	if str(bag.slots[4]["id"]) != "log":
		return _fail("the swapped-out log should go to the hotbar")
	# A weapon cannot be swapped into the hotbar.
	bag.slots[30] = {"id": "rattler_smg", "qty": 1}
	if SlotOps.swap_hotbar(bag, null, SlotOps.AREA_PLAYER, 31, 5) != "wrong_slot":
		return _fail("a weapon must not swap into the hotbar")
	cursor = {"id": "rattler_smg", "qty": 1}
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, 6, false, false) != "wrong_slot":
		return _fail("a weapon must not be placed in the hotbar")

	# Throwing picks the whole item up from any of its cells.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "workbench", "qty": 1}
	var thrown := SlotOps.throw_stack(bag, null, SlotOps.empty_stack(), SlotOps.AREA_PLAYER, 13, true)
	if str(thrown["id"]) != "workbench" or bag.anchor_at(12) != -1:
		return _fail("dropping from a covered cell should drop the item")

	# The older move and drop calls respect footprints too.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "rattler_smg", "qty": 1}
	bag.slots[15] = {"id": "log", "qty": 1}
	bag.slots[22] = {"id": "workbench", "qty": 1}
	if Inventory.move(bag, 12, bag, 17, 1, false) != "occupied":
		return _fail("moving a rifle to the last column should be refused")
	if Inventory.move(bag, 12, bag, 13, 1, false) != "":
		return _fail("moving a rifle one cell over should work, it may overlap its own old cells")
	if bag.anchor_at(14) != 13 or bag.anchor_at(12) != -1:
		return _fail("the rifle should now cover 13 and 14")
	if Inventory.move(bag, 13, bag, 14, 1, false) != "occupied":
		return _fail("moving a rifle onto the log at 15 should be refused")
	if str(bag.slots[15]["id"]) != "log" or str(bag.slots[13]["id"]) != "rattler_smg":
		return _fail("a refused move changes nothing")
	bag.slots[16] = {"id": "stick", "qty": 1}
	if Inventory.drop(bag, 22, bag, 15, 1, false) != "occupied":
		return _fail("a workbench landing on a log and a stick should be refused")
	bag.slots[16] = Inventory._empty()

	# Saves from before footprints: overlaps and off-grid items are tidied, nothing is lost.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "rattler_smg", "qty": 1}
	bag.slots[13] = {"id": "workbench", "qty": 1}
	bag.slots[17] = {"id": "hornet_pdw", "qty": 1}
	bag.slots[3] = {"id": "log", "qty": 8}
	bag.repair_layout()
	var seen := {}
	for index in bag.capacity:
		var slot := bag.slots[index]
		if str(slot["id"]) == "":
			continue
		seen[str(slot["id"])] = int(slot["qty"])
		var cells := bag.cells_for(index, str(slot["id"]))
		if cells.is_empty():
			return _fail("%s was left where its footprint does not fit" % slot["id"])
		for cell in cells:
			if bag.anchor_at(cell) != index:
				return _fail("%s overlaps another item after repair" % slot["id"])
	for item_id in ["rattler_smg", "workbench", "hornet_pdw", "log"]:
		if not seen.has(item_id):
			return _fail("repair lost %s" % item_id)
	if str(bag.slots[12]["id"]) != "rattler_smg" or int(seen["log"]) != 8:
		return _fail("repair should leave a valid item where it stood")
	# A chest with no room grows a row rather than leave two items on top of each other.
	var full := Inventory.new(4)
	full.grid_columns = 2
	full.slots[0] = {"id": "armory", "qty": 1}
	full.slots[1] = {"id": "armory", "qty": 1}
	full.repair_layout()
	if full.count_item("armory") != 2 or full.capacity <= 4 or full.slots.size() != full.capacity:
		return _fail("repair must grow a chest instead of deleting or overlapping a stack")
	for index in full.capacity:
		if str(full.slots[index]["id"]) == "":
			continue
		for cell in full.cells_for(index, "armory"):
			if full.anchor_at(cell) != index:
				return _fail("a grown chest still has overlapping armories")
	# A bag with no room anywhere hands the stack back instead of overlapping it.
	bag = Inventory.new_player()
	for index in range(0, NetConfig.BAG_SLOTS):
		bag.slots[index] = {"id": "log", "qty": 1}
	bag.slots[17] = {"id": "falconer_rifle", "qty": 1}
	bag.slots[NetConfig.BAG_SLOTS] = {"id": "kodiak_rifle", "qty": 1}
	bag.repair_layout()
	if bag.overflow.size() != 1 or str(bag.overflow[0]["id"]) != "falconer_rifle" or bag.count_item("falconer_rifle") != 0:
		return _fail("a stack with no room should be handed back, overflow is %s" % [bag.overflow])
	for index in range(bag.grid_start(), bag.storage_end()):
		if str(bag.slots[index]["id"]) != "" and bag.cells_for(index, str(bag.slots[index]["id"])).size() != 1:
			return _fail("a big item was left in a full bag")
	# The hotbar takes what the grid cannot when it has a free slot.
	bag = Inventory.new_player()
	for index in range(NetConfig.HOTBAR_SLOTS, NetConfig.BAG_SLOTS):
		bag.slots[index] = {"id": "log", "qty": 1}
	bag.slots[NetConfig.BAG_SLOTS - 1] = {"id": "armory", "qty": 1}
	bag.repair_layout()
	if bag.overflow.size() != 0 or bag.count_item("armory") != 1:
		return _fail("a full grid should hand an armory to a free hotbar slot")

	# Snapshots still carry only ids and quantities, and rebuild the same layout.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "rattler_smg", "qty": 1}
	bag.slots[20] = {"id": "armory", "qty": 1}
	var mirror := Inventory.new_player()
	if not mirror.read_snapshot(bag.ids(), bag.quantities()):
		return _fail("snapshot failed")
	if mirror.anchor_at(13) != 12 or mirror.anchor_at(30) != 20:
		return _fail("a snapshot should rebuild the same footprints")
	var blocked := _all_cells_block()
	if blocked != 0:
		return blocked
	print("grid %d wide, %d storage slots" % [NetConfig.GRID_COLUMNS, NetConfig.BAG_SLOTS - NetConfig.HOTBAR_SLOTS])
	return 0


## Every cell an item covers must be taken: no other stack may start on one, and a bag
## filled by pickups never has two items claiming the same cell.
func _all_cells_block() -> int:
	var sized: Array = []
	for item_id in ItemCatalog.all_ids():
		var size := Inventory.footprint_of(item_id)
		if size.x * size.y > 1:
			sized.append(item_id)
	var others := ["log", "rattler_smg", "falconer_rifle", "goliath_amr", "titan_hmg", "armory", "workbench"]
	for item_id: String in sized:
		var bag := Inventory.new_player()
		for anchor in range(bag.grid_start(), bag.storage_end()):
			var cells := bag.cells_for(anchor, item_id)
			if cells.is_empty():
				continue
			var size := Inventory.footprint_of(item_id)
			if cells.size() != size.x * size.y:
				return _fail("%s at %d should cover %d cells, covers %d" % [item_id, anchor, size.x * size.y, cells.size()])
			bag.slots[anchor] = {"id": item_id, "qty": 1}
			for cell in cells:
				if bag.anchor_at(cell) != anchor:
					return _fail("%s at %d does not own cell %d" % [item_id, anchor, cell])
			for other: String in others:
				for start in range(bag.grid_start(), bag.storage_end()):
					var theirs := bag.cells_for(start, other)
					if theirs.is_empty():
						continue
					var overlaps := false
					for cell in theirs:
						if cells.has(cell):
							overlaps = true
					if bag.can_place(start, other) == overlaps:
						return _fail("%s at %d vs %s at %d: can_place should be %s" % [item_id, anchor, other, start, not overlaps])
			bag.slots[anchor] = Inventory._empty()
	# Fill a bag with a mix and look for any shared cell.
	var bag := Inventory.new_player()
	var queue := ["titan_hmg", "goliath_amr", "hailstorm_lmg", "falconer_rifle", "kodiak_rifle", "ridgeback_rifle", "armory", "refinery",
		"workbench", "rattler_smg", "log", "armory", "titan_hmg", "falconer_rifle", "workbench", "workbench", "kodiak_rifle"]
	for round in 4:
		for item_id: String in queue:
			bag.add_exact(item_id, 1)
	var claims := {}
	for index in range(bag.grid_start(), bag.storage_end()):
		if str(bag.slots[index]["id"]) == "" or int(bag.slots[index]["qty"]) <= 0:
			continue
		var cells := bag.cells_for(index, str(bag.slots[index]["id"]))
		if cells.is_empty():
			return _fail("%s at %d runs off the grid" % [bag.slots[index]["id"], index])
		for cell in cells:
			if claims.has(cell):
				return _fail("cell %d is claimed by both %d and %d" % [cell, claims[cell], index])
			claims[cell] = index
			if cell != index and str(bag.slots[cell]["id"]) != "":
				return _fail("cell %d under %d holds an item of its own" % [cell, index])
	if claims.size() < 20:
		return _fail("the mixed fill should use most of the grid, used %d cells" % claims.size())
	return 0


func _anchors(bag: Inventory, item_id: String) -> Array:
	var found: Array = []
	for index in bag.capacity:
		if str(bag.slots[index]["id"]) == item_id:
			found.append(index)
	return found
