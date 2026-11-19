extends RefCounted
class_name Inventory

## Server-side slot list. Empty slots are id "" and quantity 0.
## Callers validate a whole move before anything is written.

const STARTING_SCRAP := 0

var capacity := 0
var slots: Array[Dictionary] = []
## Station that owns these slots. Null accepts every item.
var host: Object = null
## True for a player's own bag. Its slots from NetConfig.BAG_SLOTS on are the
## weapon slots (primary, sidearm, melee). Each takes only its kind of weapon,
## and picking up or crafting never fills one by itself.
var player_layout := false
## Footprint grid. When above zero, the slots from grid_start() to storage_end() are laid
## out this many to a row, and an item covers the cells of its ItemDefinition
## grid_w by grid_h, counted right and down from the slot that holds it.
## Zero keeps every slot a single cell. Hotbar, weapon and station slots always are.
var grid_columns := 0
## Stacks repair_layout() found no room for. The caller drops them in the world.
var overflow: Array = []
## No footprint is larger than this, which bounds the search for a covering item.
const MAX_FOOTPRINT := 4


func _init(slot_count: int = 0) -> void:
	resize(slot_count)


static func new_player() -> Inventory:
	var bag := Inventory.new(NetConfig.INVENTORY_SLOTS)
	bag.player_layout = true
	bag.grid_columns = NetConfig.GRID_COLUMNS
	return bag


## Width and height in cells of one stack of the item.
static func footprint_of(item_id: String) -> Vector2i:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return Vector2i.ONE
	return Vector2i(clampi(definition.grid_w, 1, MAX_FOOTPRINT), clampi(definition.grid_h, 1, MAX_FOOTPRINT))


## First slot of the footprint grid. The player's hotbar comes before it.
func grid_start() -> int:
	return NetConfig.HOTBAR_SLOTS if player_layout else 0


func in_grid(index: int) -> bool:
	return grid_columns > 0 and index >= grid_start() and index < storage_end()


## The slots a stack would cover if its top-left were at `anchor`. A slot outside the
## grid covers only itself. Empty when the footprint runs off the grid.
func cells_for(anchor: int, item_id: String) -> PackedInt32Array:
	var cells := PackedInt32Array()
	if not in_grid(anchor):
		cells.append(anchor)
		return cells
	var size := footprint_of(item_id)
	var relative := anchor - grid_start()
	var column := relative % grid_columns
	var row := relative / grid_columns
	if column + size.x > grid_columns:
		return cells
	for dy in size.y:
		for dx in size.x:
			var cell := grid_start() + (row + dy) * grid_columns + column + dx
			if cell >= storage_end():
				return PackedInt32Array()
			cells.append(cell)
	return cells


## The slot holding the item that covers `cell`, or -1 when the cell is free.
## Slots listed in `ignore` count as empty.
func anchor_at(cell: int, ignore: Array = []) -> int:
	if cell < 0 or cell >= capacity:
		return -1
	if not in_grid(cell):
		if _is_empty(slots[cell]) or ignore.has(cell):
			return -1
		return cell
	var relative := cell - grid_start()
	var column := relative % grid_columns
	var row := relative / grid_columns
	for dy in MAX_FOOTPRINT:
		if row - dy < 0:
			break
		for dx in MAX_FOOTPRINT:
			if column - dx < 0:
				break
			var anchor := grid_start() + (row - dy) * grid_columns + (column - dx)
			if ignore.has(anchor) or _is_empty(slots[anchor]):
				continue
			var size := footprint_of(str(slots[anchor]["id"]))
			if dx < size.x and dy < size.y:
				return anchor
	return -1


## What a stack of the item would land on with its top-left at `anchor`.
## "fits" is false when it runs off the grid. "anchors" lists each item it overlaps.
func footprint_hits(anchor: int, item_id: String, ignore: Array = []) -> Dictionary:
	var hits: Array = []
	if anchor < 0 or anchor >= capacity:
		return {"fits": false, "anchors": hits}
	var cells := cells_for(anchor, item_id)
	if cells.is_empty():
		return {"fits": false, "anchors": hits}
	for cell in cells:
		var holder := anchor_at(cell, ignore)
		if holder >= 0 and not hits.has(holder):
			hits.append(holder)
	return {"fits": true, "anchors": hits}


## True when a new stack can start at `anchor` without touching another item.
func can_place(anchor: int, item_id: String, ignore: Array = []) -> bool:
	var hits := footprint_hits(anchor, item_id, ignore)
	return bool(hits["fits"]) and (hits["anchors"] as Array).is_empty()


## Slots covered by an item, one flag per slot.
func _occupancy() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(capacity)
	for index in capacity:
		if _is_empty(slots[index]):
			continue
		var cells := cells_for(index, str(slots[index]["id"]))
		if cells.is_empty():
			mask[index] = 1
		for cell in cells:
			mask[cell] = 1
	return mask


## The first slot a new stack could start in, given an _occupancy() mask. Weapon slots
## are never picked, and a weapon never goes to the hotbar. A hotbar slot holds anything
## in one cell, but only by hand: a pickup of something bigger than one cell
## looks for room in the grid so the limit means something. -1 when there is no room.
func _free_anchor(item_id: String, mask: PackedByteArray) -> int:
	var size := footprint_of(item_id)
	var keep_out_of_hotbar := player_layout and size.x * size.y > 1
	for index in capacity:
		if mask[index] != 0 or not weapon_slot_for(index).is_empty() or not _built_in_allows(index, item_id):
			continue
		if keep_out_of_hotbar and index < NetConfig.HOTBAR_SLOTS:
			continue
		var cells := cells_for(index, item_id)
		if cells.is_empty():
			continue
		var free := true
		for cell in cells:
			if mask[cell] != 0:
				free = false
				break
		if free:
			return index
	return -1


## "primary", "sidearm" or "melee" for a weapon slot, "" for any other slot.
func weapon_slot_for(index: int) -> String:
	if not player_layout or index < NetConfig.BAG_SLOTS or index >= capacity:
		return ""
	var which := index - NetConfig.BAG_SLOTS
	if which >= WeaponSpec.SLOTS.size():
		return ""
	return WeaponSpec.SLOTS[which]


## Index of the named weapon slot, or -1 when this bag has none.
func weapon_slot_index(slot_name: String) -> int:
	if not player_layout:
		return -1
	var which := WeaponSpec.SLOTS.find(slot_name)
	if which < 0 or NetConfig.BAG_SLOTS + which >= capacity:
		return -1
	return NetConfig.BAG_SLOTS + which


## One past the last hotbar or storage slot. Equal to capacity unless the bag has weapon slots.
func storage_end() -> int:
	if player_layout:
		return mini(NetConfig.BAG_SLOTS, capacity)
	return capacity


## The Q cycle. Given the slot in hand, the next filled weapon slot after it, or
## -1 when there is none and the player should go back to the hotbar. From a
## hotbar slot the cycle starts at the primary.
func next_weapon_slot(current: int) -> int:
	if not player_layout:
		return -1
	var start := 0
	if current >= NetConfig.BAG_SLOTS:
		start = current - NetConfig.BAG_SLOTS + 1
	for which in range(start, WeaponSpec.SLOTS.size()):
		var index := NetConfig.BAG_SLOTS + which
		if index < capacity and not _is_empty(slots[index]):
			return index
	return -1


func grant_loadout(map_id: String = "") -> void:
	## Survival: empty bag — starter tools and the hut workbench are in the world.
	## Debug map keeps free toolkit weapons.
	var map := map_id
	if map.is_empty():
		map = _session_map()
	if map == NetConfig.MAP_SURVIVAL:
		return
	_grant_hotbar_item("debugweapon")
	_grant_hotbar_item("build_tool")
	_grant_hotbar_item("blast_gun")
	_grant_hotbar_item("repair_tool")
	_grant_hotbar_item("upgrade_tool")


static func _session_map() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return NetConfig.DEFAULT_MAP
	var session := tree.root.get_node_or_null("/root/NetSession")
	if session == null:
		return NetConfig.DEFAULT_MAP
	var mapped := NetConfig.normalize_map(str(session.get("map_id")))
	if mapped.is_empty():
		return NetConfig.DEFAULT_MAP
	return mapped


func ensure_item(item_id: String) -> void:
	_grant_hotbar_item(item_id)


func _grant_hotbar_item(item_id: String) -> void:
	if count_item(item_id) > 0 or not ItemCatalog.known(item_id):
		return
	# A weapon is only usable from its own slot, so that is where a granted one goes.
	var weapon_index := weapon_slot_index(WeaponSpec.slot_of(item_id))
	if weapon_index >= 0:
		if _is_empty(slots[weapon_index]):
			slots[weapon_index] = {"id": item_id, "qty": 1}
		return
	var limit := mini(NetConfig.HOTBAR_SLOTS, capacity)
	for index in limit:
		if _is_empty(slots[index]):
			slots[index] = {"id": item_id, "qty": 1}
			return


## The rules every bag has, apart from its host station. A weapon slot takes only its own
## kind of weapon, and a weapon is only usable from a weapon slot, so the hotbar refuses it.
func _built_in_allows(index: int, item_id: String) -> bool:
	if not player_layout:
		return true
	var weapon_slot := weapon_slot_for(index)
	if not weapon_slot.is_empty():
		return WeaponSpec.slot_of(item_id) == weapon_slot
	if index >= 0 and index < NetConfig.HOTBAR_SLOTS and WeaponSpec.is_weapon(item_id):
		return false
	return true


## True when a weapon in `index` can be fired. Anything else is usable from any slot.
func usable_in_hand(index: int, item_id: String) -> bool:
	if not player_layout or not WeaponSpec.is_weapon(item_id):
		return true
	return not weapon_slot_for(index).is_empty()


func accepts_insert(index: int, item_id: String) -> bool:
	if not _built_in_allows(index, item_id):
		return false
	if host == null or not is_instance_valid(host):
		return true
	if not host.has_method(&"accepts_insert"):
		return true
	return bool(host.call(&"accepts_insert", index, item_id))


func resize(slot_count: int) -> void:
	capacity = maxi(slot_count, 0)
	slots.clear()
	for _index in capacity:
		slots.append(_empty())


func count_item(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if str(slot["id"]) == item_id:
			total += int(slot["qty"])
	return total


func space_for(item_id: String) -> int:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or not definition.can_pickup or definition.max_stack <= 0:
		return 0
	var room := 0
	for index in slots.size():
		var slot := slots[index]
		if _is_empty(slot) or str(slot["id"]) != item_id or not weapon_slot_for(index).is_empty():
			continue
		room += maxi(definition.max_stack - int(slot["qty"]), 0)
	# New stacks need a free footprint, so count how many could start.
	var mask := _occupancy()
	while true:
		var anchor := _free_anchor(item_id, mask)
		if anchor < 0:
			break
		room += definition.max_stack
		for cell in cells_for(anchor, item_id):
			mask[cell] = 1
	return room


func add_exact(item_id: String, quantity: int) -> bool:
	if quantity <= 0 or space_for(item_id) < quantity:
		return false
	var definition := ItemCatalog.get_item(item_id)
	var left := quantity
	for index in slots.size():
		if left <= 0:
			break
		var slot := slots[index]
		if str(slot["id"]) != item_id or _is_empty(slot) or not weapon_slot_for(index).is_empty():
			continue
		var put: int = mini(definition.max_stack - int(slot["qty"]), left)
		if put <= 0:
			continue
		slot["qty"] = int(slot["qty"]) + put
		slots[index] = slot
		left -= put
	var mask := _occupancy()
	while left > 0:
		var anchor := _free_anchor(item_id, mask)
		if anchor < 0:
			break
		var put: int = mini(definition.max_stack, left)
		slots[anchor] = {"id": item_id, "qty": put}
		for cell in cells_for(anchor, item_id):
			mask[cell] = 1
		left -= put
	return left == 0


func take_item(item_id: String, quantity: int) -> bool:
	if quantity < 0 or count_item(item_id) < quantity:
		return false
	if quantity == 0:
		return true
	var left := quantity
	for index in slots.size():
		if left <= 0:
			break
		var slot := slots[index]
		if str(slot["id"]) != item_id:
			continue
		var used: int = mini(int(slot["qty"]), left)
		slot["qty"] = int(slot["qty"]) - used
		if int(slot["qty"]) <= 0:
			slot = _empty()
		slots[index] = slot
		left -= used
	return left == 0


func remove_from_slot(index: int, quantity: int) -> bool:
	if index < 0 or index >= capacity or quantity <= 0:
		return false
	var slot := slots[index]
	if _is_empty(slot) or int(slot["qty"]) < quantity:
		return false
	slot["qty"] = int(slot["qty"]) - quantity
	if int(slot["qty"]) <= 0:
		slot = _empty()
	slots[index] = slot
	return true


static func move(
	source: Inventory,
	source_index: int,
	dest: Inventory,
	dest_index: int,
	quantity: int,
	into_container: bool
) -> String:
	if source == null or dest == null:
		return "missing"
	if source_index < 0 or source_index >= source.capacity:
		return "bad_source"
	if dest_index < 0 or dest_index >= dest.capacity:
		return "bad_dest"
	if quantity <= 0 or quantity > 100000:
		return "bad_qty"
	if source == dest and source_index == dest_index:
		return "same_slot"
	var src := source.slots[source_index]
	if source._is_empty(src) or int(src["qty"]) < quantity:
		return "short"
	var item_id := str(src["id"])
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return "unknown_item"
	if into_container and not definition.can_store:
		return "not_storable"
	if not dest.accepts_insert(dest_index, item_id):
		return "wrong_slot"
	if quantity > definition.max_stack:
		return "stack_limit"
	var dst := dest.slots[dest_index]
	if dest._is_empty(dst):
		# Moving a whole stack inside one bag frees the cells it stood on.
		var freed: Array = []
		if source == dest and quantity == int(src["qty"]):
			freed.append(source_index)
		if not dest.can_place(dest_index, item_id, freed):
			return "occupied"
	elif str(dst["id"]) != item_id:
		return "occupied"
	elif int(dst["qty"]) + quantity > definition.max_stack:
		return "stack_limit"
	src["qty"] = int(src["qty"]) - quantity
	if int(src["qty"]) <= 0:
		source.slots[source_index] = source._empty()
	else:
		source.slots[source_index] = src
	if dest._is_empty(dst):
		dest.slots[dest_index] = {"id": item_id, "qty": quantity}
	else:
		dst["qty"] = int(dst["qty"]) + quantity
		dest.slots[dest_index] = dst
	return ""


static func drop(
	source: Inventory,
	source_index: int,
	dest: Inventory,
	dest_index: int,
	quantity: int,
	into_container: bool
) -> String:
	## Drag result. A matching stack takes as much as fits. A full stack
	## dropped on a different item swaps the two slots.
	if source == null or dest == null:
		return "missing"
	if source_index < 0 or source_index >= source.capacity:
		return "bad_source"
	if dest_index < 0 or dest_index >= dest.capacity:
		return "bad_dest"
	if quantity <= 0 or quantity > 100000:
		return "bad_qty"
	if source == dest and source_index == dest_index:
		return "same_slot"
	var src := source.slots[source_index]
	if _is_empty(src) or int(src["qty"]) < quantity:
		return "short"
	var item_id := str(src["id"])
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return "unknown_item"
	if into_container and not definition.can_store:
		return "not_storable"
	var dst := dest.slots[dest_index]
	if _is_empty(dst) or str(dst["id"]) == item_id:
		var room := definition.max_stack
		if not _is_empty(dst):
			room = definition.max_stack - int(dst["qty"])
		var amount := mini(quantity, room)
		if amount <= 0:
			return "stack_limit"
		return move(source, source_index, dest, dest_index, amount, into_container)
	if quantity < int(src["qty"]):
		return "occupied"
	if ItemCatalog.get_item(str(dst["id"])) == null:
		return "unknown_item"
	if not dest.accepts_insert(dest_index, item_id):
		return "wrong_slot"
	if not source.accepts_insert(source_index, str(dst["id"])):
		return "wrong_slot"
	# Each stack must fit where the other one stood, and two of them swapped inside
	# one bag must not land on each other.
	var dst_id := str(dst["id"])
	var freed_dest: Array = [dest_index]
	var freed_source: Array = [source_index]
	if source == dest:
		freed_dest.append(source_index)
		freed_source.append(dest_index)
	if not dest.can_place(dest_index, item_id, freed_dest) or not source.can_place(source_index, dst_id, freed_source):
		return "occupied"
	if source == dest:
		var incoming_cells := dest.cells_for(dest_index, item_id)
		for cell in source.cells_for(source_index, dst_id):
			if incoming_cells.has(cell):
				return "occupied"
	var incoming := src.duplicate()
	var outgoing := dst.duplicate()
	source.slots[source_index] = outgoing
	dest.slots[dest_index] = incoming
	return ""


## Tidies a bag loaded from a save made before footprints and the weapon rules: a weapon
## in the hotbar moves to its slot (or storage), and an item whose footprint now runs
## off the grid or lands on another is moved to free room. The hotbar takes what the grid
## cannot, and a chest grows by rows. What still has no room is left in `overflow` for the
## caller to put on the ground. A stack is never left overlapping another, and never deleted.
func repair_layout() -> void:
	overflow.clear()
	var claimed := PackedByteArray()
	claimed.resize(capacity)
	# Lift every misplaced stack out first, so none is placed over another.
	var lifted: Array = []
	for index in capacity:
		var slot := slots[index]
		if _is_empty(slot):
			continue
		var item_id := str(slot["id"])
		var cells := cells_for(index, item_id)
		var valid := _built_in_allows(index, item_id) and not cells.is_empty()
		for cell in cells:
			if claimed[cell] != 0:
				valid = false
		if valid:
			for cell in cells:
				claimed[cell] = 1
		else:
			lifted.append({"index": index, "slot": slot})
			slots[index] = _empty()
	for entry in lifted:
		var slot: Dictionary = entry["slot"]
		var item_id := str(slot["id"])
		var target := weapon_slot_index(WeaponSpec.slot_of(item_id))
		if target < 0 or claimed[target] != 0:
			target = _free_anchor(item_id, claimed)
		if target < 0:
			target = _free_hotbar_slot(item_id, claimed)
		var grown := 0
		while target < 0 and not player_layout and grid_columns > 0 and grown < 8:
			capacity += grid_columns
			for _row_slot in grid_columns:
				slots.append(_empty())
			claimed.resize(capacity)
			target = _free_anchor(item_id, claimed)
			grown += 1
		if target < 0:
			overflow.append(slot)
			continue
		slots[target] = slot
		for cell in cells_for(target, item_id):
			claimed[cell] = 1


## An empty hotbar slot, which holds one stack of anything it accepts. -1 when none.
func _free_hotbar_slot(item_id: String, claimed: PackedByteArray) -> int:
	if not player_layout:
		return -1
	for index in mini(NetConfig.HOTBAR_SLOTS, capacity):
		if claimed[index] == 0 and _is_empty(slots[index]) and _built_in_allows(index, item_id):
			return index
	return -1


func ids() -> PackedStringArray:
	var packed := PackedStringArray()
	for slot in slots:
		packed.append(str(slot["id"]))
	return packed


func quantities() -> PackedInt32Array:
	var packed := PackedInt32Array()
	for slot in slots:
		packed.append(int(slot["qty"]))
	return packed


func read_snapshot(item_ids: PackedStringArray, item_qtys: PackedInt32Array) -> bool:
	if item_ids.size() != capacity or item_qtys.size() != capacity:
		return false
	for index in capacity:
		var item_id := str(item_ids[index])
		var qty := int(item_qtys[index])
		if item_id.is_empty() or qty <= 0:
			slots[index] = _empty()
		else:
			slots[index] = {"id": item_id, "qty": qty}
	return true


static func _empty() -> Dictionary:
	return {"id": "", "qty": 0}


static func _is_empty(slot: Dictionary) -> bool:
	return str(slot.get("id", "")) == "" or int(slot.get("qty", 0)) <= 0
