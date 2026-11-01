extends RefCounted
class_name WorldStore

## File snapshot of one arena. The dedicated server is the only writer.
## A reconnect token is a cookie, not an account.

const VERSION := 1
const TOKEN_MIN := 8
const TOKEN_MAX := 64
const YARD := 17.2


static func valid_token(token: String) -> bool:
	if token.length() < TOKEN_MIN or token.length() > TOKEN_MAX:
		return false
	for index in token.length():
		var code := token.unicode_at(index)
		var letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var digit := code >= 48 and code <= 57
		if not letter and not digit and code != 45 and code != 95:
			return false
	return true


static func new_token() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


static func capture(
	building: BuildingSystem,
	pickups: Dictionary,
	containers: Dictionary,
	dummies: Dictionary,
	profiles: Dictionary,
	drop_seq: int
) -> Dictionary:
	var loot: Array = []
	var pickup_ids: Array = pickups.keys()
	pickup_ids.sort()
	for pickup_id in pickup_ids:
		var pickup := pickups[pickup_id] as WorldPickup
		if pickup == null or not is_instance_valid(pickup):
			continue
		loot.append({
			"id": pickup.pickup_id,
			"item": pickup.item_id,
			"qty": pickup.quantity,
			"x": pickup.global_position.x,
			"y": pickup.global_position.y,
			"z": pickup.global_position.z,
		})
	var crates := {}
	var crate_ids: Array = containers.keys()
	crate_ids.sort()
	for crate_id in crate_ids:
		var crate := containers[crate_id] as LootContainer
		if crate == null or crate.inventory == null:
			continue
		crates[str(crate_id)] = _slots(crate.inventory)
	var packet := {}
	if building != null and building.state != null:
		packet = _json_ready(building.state.export_packet())
	return {
		"version": VERSION,
		"buildings": packet,
		"loot": loot,
		"containers": crates,
		"dummies": dummies.duplicate(),
		"players": _json_ready(profiles),
		"drop_seq": drop_seq,
	}


static func write(path: String, snapshot: Dictionary) -> bool:
	if path.is_empty() or snapshot.is_empty():
		return false
	var text := JSON.stringify(snapshot, "\t")
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	var abs_path := _absolute(path)
	var abs_tmp := _absolute(tmp)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
	var err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		DirAccess.remove_absolute(abs_tmp)
		return false
	return true


static func read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(_absolute(path)):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text().strip_edges()
	file.close()
	if not text.begins_with("{") or text.find("\"version\"") < 0:
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {}
	var snapshot: Dictionary = parsed
	if int(snapshot.get("version", 0)) != VERSION:
		return {}
	return snapshot


static func apply_buildings(state: BuildingState, snapshot: Dictionary) -> void:
	if state == null:
		return
	var packet: Dictionary = snapshot.get("buildings", {})
	if packet.is_empty():
		return
	state.apply_remote(packet)


static func apply_inventory(bag: Inventory, row: Dictionary) -> bool:
	if bag == null or row.is_empty():
		return false
	var ids := PackedStringArray()
	var qtys := PackedInt32Array()
	var slots: Array = row.get("slots", [])
	if slots.is_empty():
		for item_id in row.get("ids", []):
			ids.append(str(item_id))
		for qty in row.get("qtys", []):
			qtys.append(int(qty))
	else:
		for slot in slots:
			if slot is Dictionary:
				ids.append(str(slot.get("id", "")))
				qtys.append(int(slot.get("qty", 0)))
	if ids.size() != bag.capacity:
		bag.resize(ids.size() if ids.size() > 0 else bag.capacity)
	if ids.size() != bag.capacity:
		return false
	return bag.read_snapshot(ids, qtys)


static func profile_from(bag: Inventory, player: PlayerController) -> Dictionary:
	var pos := Vector3(0.0, 0.15, 8.0)
	var yaw := 0.0
	var health := 100
	if player != null and is_instance_valid(player):
		var pose := player.global_position if player.is_inside_tree() else player.position
		if NetConfig.finite_vector(pose):
			pos = pose
			yaw = player.get_facing_yaw()
			health = player.health
	return {
		"slots": _slots(bag) if bag != null else [],
		"x": pos.x,
		"y": pos.y,
		"z": pos.z,
		"yaw": yaw,
		"health": health,
	}


static func restore_pose(row: Dictionary) -> Vector3:
	if row.is_empty() or not row.has("x") or not row.has("z"):
		return Vector3(INF, INF, INF)
	var pos := Vector3(float(row.get("x", 0.0)), float(row.get("y", 0.15)), float(row.get("z", 8.0)))
	if not NetConfig.finite_vector(pos):
		return Vector3(INF, INF, INF)
	if absf(pos.x) > YARD or absf(pos.z) > YARD or pos.y < -0.5 or pos.y > 14.0:
		return Vector3(INF, INF, INF)
	return pos


static func _slots(bag: Inventory) -> Array:
	var rows: Array = []
	if bag == null:
		return rows
	for slot in bag.slots:
		rows.append({"id": str(slot.get("id", "")), "qty": int(slot.get("qty", 0))})
	return rows


static func _json_ready(value: Variant) -> Variant:
	if value is PackedInt32Array:
		var rows: Array = []
		for number in value:
			rows.append(int(number))
		return rows
	if value is Array:
		var rows: Array = []
		for item in value:
			rows.append(_json_ready(item))
		return rows
	if value is Dictionary:
		var copy := {}
		for key in value.keys():
			copy[str(key)] = _json_ready(value[key])
		return copy
	return value


static func _absolute(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
