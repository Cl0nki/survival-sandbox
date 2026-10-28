extends RefCounted
class_name Inventory

## Server-side slot list. Empty slots are id "" and quantity 0.
## Callers validate a whole move before anything is written.

var capacity := 0
var slots: Array[Dictionary] = []


func _init(slot_count: int = 0) -> void:
	resize(slot_count)


func grant_loadout() -> void:
	## The starting pistol sits in the first empty hotbar slot. It is not ammo.
	## The Build Tool takes the next empty hotbar slot.
	_grant_hotbar_item("debugweapon")
	_grant_hotbar_item("build_tool")


func _grant_hotbar_item(item_id: String) -> void:
	if count_item(item_id) > 0 or not ItemCatalog.known(item_id):
		return
	var limit := mini(NetConfig.HOTBAR_SLOTS, capacity)
	for index in limit:
		if _is_empty(slots[index]):
			slots[index] = {"id": item_id, "qty": 1}
			return


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
	for slot in slots:
		if _is_empty(slot):
			room += definition.max_stack
		elif str(slot["id"]) == item_id:
			room += maxi(definition.max_stack - int(slot["qty"]), 0)
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
		if str(slot["id"]) != item_id or _is_empty(slot):
			continue
		var put: int = mini(definition.max_stack - int(slot["qty"]), left)
		if put <= 0:
			continue
		slot["qty"] = int(slot["qty"]) + put
		slots[index] = slot
		left -= put
	for index in slots.size():
		if left <= 0:
			break
		var slot := slots[index]
		if not _is_empty(slot):
			continue
		var put: int = mini(definition.max_stack, left)
		slot["id"] = item_id
		slot["qty"] = put
		slots[index] = slot
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
	if quantity > definition.max_stack:
		return "stack_limit"
	var dst := dest.slots[dest_index]
	if dest._is_empty(dst):
		pass
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
	var incoming := src.duplicate()
	var outgoing := dst.duplicate()
	source.slots[source_index] = outgoing
	dest.slots[dest_index] = incoming
	return ""


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
