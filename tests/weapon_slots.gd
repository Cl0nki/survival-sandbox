extends SceneTree

## Headless check of the primary, sidearm and melee slots and the Q cycle order.
## godot --headless --path <project> --script res://tests/weapon_slots.gd

const PRIMARY := NetConfig.BAG_SLOTS
const SIDEARM := NetConfig.BAG_SLOTS + 1
const MELEE := NetConfig.BAG_SLOTS + 2


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("WEAPON_SLOTS_OK")
	quit(code)


func _fail(message: String) -> int:
	print("FAIL %s" % message)
	return 1


func _run() -> int:
	if NetConfig.INVENTORY_SLOTS != NetConfig.BAG_SLOTS + NetConfig.WEAPON_SLOT_COUNT:
		return _fail("inventory size should be the bag plus the weapon slots")
	if NetConfig.WEAPON_SLOT_COUNT != WeaponSpec.SLOTS.size():
		return _fail("weapon slot count should match WeaponSpec.SLOTS")
	for pistol in ["pistol", "courier_pistol", "marshal_pistol", "debugweapon"]:
		if WeaponSpec.slot_of(pistol) != WeaponSpec.SLOT_SIDEARM:
			return _fail("%s should be a sidearm" % pistol)
	for long_gun in ["falconer_rifle", "titan_hmg", "breacher_shotgun"]:
		if WeaponSpec.slot_of(long_gun) != WeaponSpec.SLOT_PRIMARY:
			return _fail("%s should be a primary" % long_gun)
	if WeaponSpec.slot_of("sword") != WeaponSpec.SLOT_MELEE:
		return _fail("sword should be melee")
	if not WeaponSpec.slot_of("log").is_empty() or not WeaponSpec.slot_of("nothing_here").is_empty():
		return _fail("a non-weapon has no weapon slot")

	var bag := Inventory.new_player()
	if bag.capacity != NetConfig.INVENTORY_SLOTS:
		return _fail("player bag should have %d slots" % NetConfig.INVENTORY_SLOTS)
	if bag.weapon_slot_for(PRIMARY) != "primary" or bag.weapon_slot_for(SIDEARM) != "sidearm" or bag.weapon_slot_for(MELEE) != "melee":
		return _fail("weapon slots should follow the bag in order")
	if not bag.weapon_slot_for(0).is_empty() or not bag.weapon_slot_for(NetConfig.BAG_SLOTS - 1).is_empty():
		return _fail("hotbar and storage are not weapon slots")
	if bag.storage_end() != NetConfig.BAG_SLOTS:
		return _fail("storage should end where the weapon slots start")
	var plain := Inventory.new(NetConfig.INVENTORY_SLOTS)
	if not plain.weapon_slot_for(PRIMARY).is_empty() or plain.storage_end() != plain.capacity:
		return _fail("a bag that is not the player's has no weapon slots")
	if plain.accepts_insert(PRIMARY, "log") != true:
		return _fail("a crate of the same size must not restrict slots")

	if bag.accepts_insert(PRIMARY, "falconer_rifle") != true:
		return _fail("a rifle fits the primary slot")
	if bag.accepts_insert(SIDEARM, "falconer_rifle"):
		return _fail("a rifle must not fit the sidearm slot")
	if bag.accepts_insert(PRIMARY, "courier_pistol"):
		return _fail("a pistol must not fit the primary slot")
	if bag.accepts_insert(MELEE, "marshal_pistol") or not bag.accepts_insert(MELEE, "sword"):
		return _fail("only a blade fits the melee slot")
	if bag.accepts_insert(PRIMARY, "log") or bag.accepts_insert(SIDEARM, "ammo_9mm"):
		return _fail("only weapons fit a weapon slot")
	if not bag.accepts_insert(12, "courier_pistol") or not bag.accepts_insert(12, "falconer_rifle"):
		return _fail("weapons still fit the storage grid")
	if bag.accepts_insert(0, "courier_pistol") or bag.accepts_insert(8, "falconer_rifle") or bag.accepts_insert(3, "sword"):
		return _fail("a weapon must not go in the hotbar")
	if not bag.accepts_insert(0, "log") or not bag.accepts_insert(0, "workbench"):
		return _fail("anything else fits the hotbar")

	# Pickups and crafting output never fill a weapon slot on their own.
	# A rifle covers three cells, never goes in the hotbar, and never in a weapon slot by itself:
	# three fit in each of the three storage rows of nine.
	if bag.space_for("falconer_rifle") != 9:
		return _fail("space for a rifle should be 9, was %d" % bag.space_for("falconer_rifle"))
	for _n in 9:
		if not bag.add_exact("falconer_rifle", 1):
			return _fail("rifle should fit in the bag")
	if bag.add_exact("falconer_rifle", 1):
		return _fail("a full bag must not spill a rifle into the primary slot")
	for index in [PRIMARY, SIDEARM, MELEE]:
		if str(bag.slots[index]["id"]) != "":
			return _fail("weapon slot %d was filled by a pickup" % index)

	# Clicking with a held weapon.
	bag = Inventory.new_player()
	var cursor := {"id": "falconer_rifle", "qty": 1}
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, SIDEARM, false, false) != "wrong_slot":
		return _fail("a rifle on the sidearm slot should be refused")
	if int(cursor["qty"]) != 1:
		return _fail("a refused click keeps the cursor")
	if SlotOps.click(bag, null, cursor, SlotOps.AREA_PLAYER, PRIMARY, false, false) != "":
		return _fail("a rifle on the primary slot should be accepted")
	if str(bag.slots[PRIMARY]["id"]) != "falconer_rifle" or int(cursor["qty"]) != 0:
		return _fail("the rifle should sit in the primary slot")
	var other := {"id": "courier_pistol", "qty": 1}
	if SlotOps.click(bag, null, other, SlotOps.AREA_PLAYER, PRIMARY, false, false) != "wrong_slot":
		return _fail("a pistol must not swap into the primary slot")
	if str(bag.slots[PRIMARY]["id"]) != "falconer_rifle":
		return _fail("a refused swap leaves the slot alone")

	# Shift-click equips a weapon, then puts it back.
	bag = Inventory.new_player()
	bag.slots[12] = {"id": "falconer_rifle", "qty": 1}
	bag.slots[15] = {"id": "courier_pistol", "qty": 1}
	bag.slots[16] = {"id": "sword", "qty": 1}
	bag.slots[17] = {"id": "log", "qty": 5}
	for index in [12, 15, 16]:
		if SlotOps.quick_move(bag, null, SlotOps.AREA_PLAYER, index) != "":
			return _fail("shift-click on slot %d failed" % index)
	if str(bag.slots[PRIMARY]["id"]) != "falconer_rifle" or str(bag.slots[SIDEARM]["id"]) != "courier_pistol" or str(bag.slots[MELEE]["id"]) != "sword":
		return _fail("shift-click should equip each weapon into its slot")
	if SlotOps.quick_move(bag, null, SlotOps.AREA_PLAYER, 17) != "" or str(bag.slots[17]["id"]) != "":
		return _fail("a non-weapon should still shift-click from storage")
	if str(bag.slots[0]["id"]) != "log":
		return _fail("shift-click should move a log into the hotbar, was %s" % str(bag.slots[0]["id"]))
	if SlotOps.quick_move(bag, null, SlotOps.AREA_PLAYER, PRIMARY) != "":
		return _fail("shift-click on the primary slot failed")
	if str(bag.slots[PRIMARY]["id"]) != "" or bag.count_item("falconer_rifle") != 1:
		return _fail("shift-click on a weapon slot should unequip it")
	var back := -1
	for index in bag.storage_end():
		if str(bag.slots[index]["id"]) == "falconer_rifle":
			back = index
	if back < SlotOps.HOTBAR:
		return _fail("an unequipped weapon should land in storage first, was slot %d" % back)
	# A second rifle with the primary slot taken stays where it is: the hotbar refuses weapons.
	bag.slots[PRIMARY] = {"id": "falconer_rifle", "qty": 1}
	bag.slots[20] = {"id": "titan_hmg", "qty": 1}
	if SlotOps.quick_move(bag, null, SlotOps.AREA_PLAYER, 20) == "":
		return _fail("a rifle must not shift-click into the hotbar")
	if str(bag.slots[PRIMARY]["id"]) != "falconer_rifle" or str(bag.slots[20]["id"]) != "titan_hmg":
		return _fail("a taken primary slot must stay put")

	# Chest to bag.
	var crate := Inventory.new(27)
	crate.slots[3] = {"id": "marshal_pistol", "qty": 1}
	crate.slots[4] = {"id": "log", "qty": 2}
	bag = Inventory.new_player()
	if SlotOps.quick_move(bag, crate, SlotOps.AREA_CONTAINER, 3) != "" or str(bag.slots[SIDEARM]["id"]) != "marshal_pistol":
		return _fail("a pistol shift-clicked out of a chest should be equipped")
	if SlotOps.quick_move(bag, crate, SlotOps.AREA_CONTAINER, 4) != "":
		return _fail("a log shift-clicked out of a chest failed")
	for index in [PRIMARY, SIDEARM, MELEE]:
		if str(bag.slots[index]["id"]) == "log":
			return _fail("a log must not land in a weapon slot")
	if SlotOps.quick_move(bag, crate, SlotOps.AREA_PLAYER, SIDEARM) != "" or str(crate.slots[0]["id"]) != "marshal_pistol":
		return _fail("a weapon slot can be shift-clicked into an open chest")

	# The Q cycle: primary, sidearm, melee, then back to the hotbar.
	bag = Inventory.new_player()
	if bag.next_weapon_slot(0) != -1:
		return _fail("with nothing equipped the cycle has nowhere to go")
	bag.slots[PRIMARY] = {"id": "falconer_rifle", "qty": 1}
	bag.slots[SIDEARM] = {"id": "courier_pistol", "qty": 1}
	bag.slots[MELEE] = {"id": "sword", "qty": 1}
	if bag.next_weapon_slot(3) != PRIMARY:
		return _fail("first press from the hotbar should draw the primary")
	if bag.next_weapon_slot(PRIMARY) != SIDEARM:
		return _fail("second press should draw the sidearm")
	if bag.next_weapon_slot(SIDEARM) != MELEE:
		return _fail("third press should draw the melee weapon")
	if bag.next_weapon_slot(MELEE) != -1:
		return _fail("fourth press should holster")
	bag.slots[SIDEARM] = Inventory._empty()
	if bag.next_weapon_slot(PRIMARY) != MELEE:
		return _fail("an empty sidearm slot should be skipped")
	bag.slots[PRIMARY] = Inventory._empty()
	if bag.next_weapon_slot(2) != MELEE:
		return _fail("with only a melee weapon the first press should draw it")
	bag.slots[MELEE] = Inventory._empty()
	if bag.next_weapon_slot(PRIMARY) != -1:
		return _fail("an emptied last slot should holster")

	# Which slots the hand can take.
	for index in range(NetConfig.HOTBAR_SLOTS):
		if not NetConfig.is_selectable_slot(index):
			return _fail("hotbar slot %d should be selectable" % index)
	for index in [NetConfig.HOTBAR_SLOTS, NetConfig.BAG_SLOTS - 1, NetConfig.INVENTORY_SLOTS, -1]:
		if NetConfig.is_selectable_slot(index):
			return _fail("slot %d should not be selectable" % index)
	for index in [PRIMARY, SIDEARM, MELEE]:
		if not NetConfig.is_selectable_slot(index):
			return _fail("weapon slot %d should be selectable" % index)

	# Snapshots carry the weapon slots.
	bag = Inventory.new_player()
	bag.slots[SIDEARM] = {"id": "marshal_pistol", "qty": 1}
	var mirror := Inventory.new_player()
	if not mirror.read_snapshot(bag.ids(), bag.quantities()) or str(mirror.slots[SIDEARM]["id"]) != "marshal_pistol":
		return _fail("a snapshot should carry the weapon slots")

	# A save from before the weapon slots has only the bag.
	var old_save: Array = []
	for index in NetConfig.BAG_SLOTS:
		old_save.append({"id": "", "qty": 0})
	old_save[2] = {"id": "courier_pistol", "qty": 1}
	old_save[20] = {"id": "log", "qty": 7}
	var loaded := Inventory.new_player()
	if not WorldStore.apply_inventory(loaded, {"slots": old_save}):
		return _fail("a 36-slot save should still load")
	if loaded.capacity != NetConfig.INVENTORY_SLOTS or not loaded.player_layout:
		return _fail("a loaded save should keep the weapon slots")
	if int(loaded.slots[20]["qty"]) != 7:
		return _fail("an old save should keep its items in place")
	# The pistol was in the hotbar, where a weapon can no longer be, so it moves to its slot.
	if str(loaded.slots[2]["id"]) != "" or str(loaded.slots[SIDEARM]["id"]) != "courier_pistol":
		return _fail("an old save's hotbar pistol should move to the sidearm slot")
	if str(loaded.slots[PRIMARY]["id"]) != "" or str(loaded.slots[MELEE]["id"]) != "":
		return _fail("an old save leaves the other weapon slots empty")
	print("weapon slots: %d, bag: %d" % [NetConfig.WEAPON_SLOT_COUNT, NetConfig.BAG_SLOTS])
	return 0
