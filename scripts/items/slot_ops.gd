extends RefCounted
class_name SlotOps

## Minecraft-style slot rules shared by the server and local play.
## The cursor dictionary is mutated in place. Item ids always come from
## these inventories, never from the client.

const AREA_PLAYER := 0
const AREA_CONTAINER := 1
const HOTBAR := 9


static func empty_stack() -> Dictionary:
	return {"id": "", "qty": 0}


static func click(
	player_bag: Inventory,
	crate_bag: Inventory,
	cursor: Dictionary,
	area: int,
	index: int,
	right: bool,
	shift: bool
) -> String:
	if shift:
		return quick_move(player_bag, crate_bag, area, index)
	var bag := _bag(player_bag, crate_bag, area)
	if bag == null:
		return "closed" if area == AREA_CONTAINER else "missing"
	if index < 0 or index >= bag.capacity:
		return "bad_source"
	var slot: Dictionary = bag.slots[index]
	if _empty(cursor):
		if _empty(slot):
			return ""
		if ItemCatalog.get_item(str(slot["id"])) == null:
			return "unknown_item"
		var take := int(slot["qty"])
		if right:
			take = (take + 1) / 2
		var pulled := _pull(bag, index, take)
		cursor["id"] = pulled["id"]
		cursor["qty"] = pulled["qty"]
		return ""
	if ItemCatalog.get_item(str(cursor["id"])) == null:
		return "unknown_item"
	if _empty(slot):
		return _place(bag, index, cursor, 1 if right else int(cursor["qty"]))
	if str(slot["id"]) == str(cursor["id"]):
		return _place(bag, index, cursor, 1 if right else int(cursor["qty"]))
	if ItemCatalog.get_item(str(slot["id"])) == null:
		return "unknown_item"
	var held_id := str(cursor["id"])
	var held_qty := int(cursor["qty"])
	cursor["id"] = str(slot["id"])
	cursor["qty"] = int(slot["qty"])
	bag.slots[index] = {"id": held_id, "qty": held_qty}
	return ""


static func quick_move(player_bag: Inventory, crate_bag: Inventory, area: int, index: int) -> String:
	var from := _bag(player_bag, crate_bag, area)
	if from == null:
		return "closed" if area == AREA_CONTAINER else "missing"
	if index < 0 or index >= from.capacity:
		return "bad_source"
	if _empty(from.slots[index]):
		return "short"
	if area == AREA_CONTAINER:
		return _pour(from, index, player_bag, _storage_then_hotbar(player_bag), false)
	if crate_bag != null:
		return _pour(from, index, crate_bag, _all_slots(crate_bag), true)
	if index < HOTBAR:
		return _pour(player_bag, index, player_bag, _range_slots(HOTBAR, player_bag.capacity), false)
	return _pour(player_bag, index, player_bag, _range_slots(0, HOTBAR), false)


static func collect_same(player_bag: Inventory, crate_bag: Inventory, cursor: Dictionary, area: int, index: int) -> String:
	if _empty(cursor):
		var picked := click(player_bag, crate_bag, cursor, area, index, false, false)
		if picked != "":
			return picked
	if _empty(cursor):
		return ""
	var definition := ItemCatalog.get_item(str(cursor["id"]))
	if definition == null:
		return "unknown_item"
	var bags: Array[Inventory] = [player_bag]
	if crate_bag != null:
		bags.append(crate_bag)
	for bag in bags:
		for slot_index in bag.capacity:
			if int(cursor["qty"]) >= definition.max_stack:
				return ""
			var slot: Dictionary = bag.slots[slot_index]
			if str(slot["id"]) != str(cursor["id"]) or int(slot["qty"]) <= 0:
				continue
			var room: int = definition.max_stack - int(cursor["qty"])
			var pulled := _pull(bag, slot_index, mini(int(slot["qty"]), room))
			cursor["qty"] = int(cursor["qty"]) + int(pulled["qty"])
	return ""


static func spread(
	player_bag: Inventory,
	crate_bag: Inventory,
	cursor: Dictionary,
	areas: PackedInt32Array,
	indices: PackedInt32Array,
	right: bool
) -> String:
	if _empty(cursor):
		return "short"
	var definition := ItemCatalog.get_item(str(cursor["id"]))
	if definition == null:
		return "unknown_item"
	var chosen: Array[Vector2i] = []
	for i in mini(areas.size(), indices.size()):
		var area := int(areas[i])
		var index := int(indices[i])
		var bag := _bag(player_bag, crate_bag, area)
		if bag == null or index < 0 or index >= bag.capacity:
			continue
		var slot: Dictionary = bag.slots[index]
		if not _empty(slot) and str(slot["id"]) != str(cursor["id"]):
			continue
		if not _empty(slot) and int(slot["qty"]) >= definition.max_stack:
			continue
		var key := Vector2i(area, index)
		if chosen.has(key):
			continue
		chosen.append(key)
	if chosen.is_empty():
		return "occupied"
	if right:
		for key in chosen:
			if int(cursor["qty"]) <= 0:
				break
			var bag := _bag(player_bag, crate_bag, key.x)
			_place(bag, key.y, cursor, 1)
		return ""
	var count := chosen.size()
	var base := int(cursor["qty"]) / count
	var extra := int(cursor["qty"]) % count
	for i in count:
		var give := base + (1 if i < extra else 0)
		if give <= 0:
			break
		var key: Vector2i = chosen[i]
		var bag := _bag(player_bag, crate_bag, key.x)
		_place(bag, key.y, cursor, give)
	return ""


static func swap_hotbar(player_bag: Inventory, crate_bag: Inventory, area: int, index: int, hotbar_index: int) -> String:
	if player_bag == null or hotbar_index < 0 or hotbar_index >= HOTBAR:
		return "bad_dest"
	var bag := _bag(player_bag, crate_bag, area)
	if bag == null:
		return "closed" if area == AREA_CONTAINER else "missing"
	if index < 0 or index >= bag.capacity:
		return "bad_source"
	if bag == player_bag and index == hotbar_index:
		return ""
	var from: Dictionary = bag.slots[index]
	var hot: Dictionary = player_bag.slots[hotbar_index]
	if not _empty(from) and ItemCatalog.get_item(str(from["id"])) == null:
		return "unknown_item"
	if not _empty(hot) and ItemCatalog.get_item(str(hot["id"])) == null:
		return "unknown_item"
	bag.slots[index] = hot.duplicate()
	player_bag.slots[hotbar_index] = from.duplicate()
	return ""


static func throw_stack(
	player_bag: Inventory,
	crate_bag: Inventory,
	cursor: Dictionary,
	area: int,
	index: int,
	whole: bool
) -> Dictionary:
	if not _empty(cursor):
		var definition := ItemCatalog.get_item(str(cursor["id"]))
		if definition == null:
			return empty_stack()
		var amount := int(cursor["qty"]) if whole else 1
		amount = mini(amount, int(cursor["qty"]))
		var thrown := {"id": str(cursor["id"]), "qty": amount}
		cursor["qty"] = int(cursor["qty"]) - amount
		if int(cursor["qty"]) <= 0:
			cursor["id"] = ""
			cursor["qty"] = 0
		return thrown
	var bag := _bag(player_bag, crate_bag, area)
	if bag == null or index < 0 or index >= bag.capacity or _empty(bag.slots[index]):
		return empty_stack()
	if ItemCatalog.get_item(str(bag.slots[index]["id"])) == null:
		return empty_stack()
	var amount := int(bag.slots[index]["qty"]) if whole else 1
	return _pull(bag, index, amount)


static func _pour(from: Inventory, index: int, into: Inventory, order: Array, require_store: bool) -> String:
	if into == null:
		return "missing"
	var slot: Dictionary = from.slots[index]
	if _empty(slot):
		return "short"
	var item_id := str(slot["id"])
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return "unknown_item"
	if require_store and not definition.can_store:
		return "not_storable"
	var left := int(slot["qty"])
	var moved := 0
	for dest_index in order:
		if left <= 0:
			break
		if into == from and int(dest_index) == index:
			continue
		var placed := _push_into(into, int(dest_index), item_id, left)
		left -= placed
		moved += placed
	if moved <= 0:
		return "full"
	_pull(from, index, moved)
	return ""


static func _place(bag: Inventory, index: int, cursor: Dictionary, amount: int) -> String:
	var placed := _push_into(bag, index, str(cursor["id"]), mini(amount, int(cursor["qty"])))
	if placed <= 0:
		return "stack_limit"
	cursor["qty"] = int(cursor["qty"]) - placed
	if int(cursor["qty"]) <= 0:
		cursor["id"] = ""
		cursor["qty"] = 0
	return ""


static func _push_into(bag: Inventory, index: int, item_id: String, amount: int) -> int:
	if amount <= 0 or index < 0 or index >= bag.capacity:
		return 0
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return 0
	var slot: Dictionary = bag.slots[index]
	if _empty(slot):
		var put := mini(amount, definition.max_stack)
		bag.slots[index] = {"id": item_id, "qty": put}
		return put
	if str(slot["id"]) != item_id:
		return 0
	var room: int = definition.max_stack - int(slot["qty"])
	var put := mini(amount, room)
	if put <= 0:
		return 0
	slot["qty"] = int(slot["qty"]) + put
	bag.slots[index] = slot
	return put


static func _pull(bag: Inventory, index: int, amount: int) -> Dictionary:
	var slot: Dictionary = bag.slots[index]
	var qty := mini(amount, int(slot["qty"]))
	if qty <= 0 or _empty(slot):
		return empty_stack()
	var item_id := str(slot["id"])
	slot["qty"] = int(slot["qty"]) - qty
	if int(slot["qty"]) <= 0:
		bag.slots[index] = empty_stack()
	else:
		bag.slots[index] = slot
	return {"id": item_id, "qty": qty}


static func _bag(player_bag: Inventory, crate_bag: Inventory, area: int) -> Inventory:
	if area == AREA_CONTAINER:
		return crate_bag
	if area == AREA_PLAYER:
		return player_bag
	return null


static func _empty(slot: Dictionary) -> bool:
	return str(slot.get("id", "")) == "" or int(slot.get("qty", 0)) <= 0


static func _all_slots(bag: Inventory) -> Array:
	return _range_slots(0, bag.capacity)


static func _storage_then_hotbar(bag: Inventory) -> Array:
	var order := _range_slots(HOTBAR, bag.capacity)
	order.append_array(_range_slots(0, mini(HOTBAR, bag.capacity)))
	return order


static func _range_slots(start: int, end: int) -> Array:
	var order: Array = []
	for index in range(start, end):
		order.append(index)
	return order
