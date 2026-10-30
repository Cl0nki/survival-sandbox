extends Node
class_name BuildingRelay

## Server-side batch of building changes, split by chunk, and the client
## apply path. A peer receives a chunk when they stand near it, and only the
## pieces that actually changed. Previews never pass through here.

const CHUNK := 8
const INTEREST := 2
const REACH := 15.0
const BUILD_RATE := 8

var system
var authoritative := false
var accepted := 0
var rejected := 0
var packets_sent := 0
## peer id -> packets that would be sent. Tests read these when no client is connected.
var delivered: Dictionary = {}

var _out_seq := 0
var _seq: Dictionary = {}
var _rates: Dictionary = {}
var _known: Dictionary = {}
var _subscribed: Dictionary = {}
var _chunks: Dictionary = {}
var _chunk_of_id: Dictionary = {}
var _pending: Array = []
var _health: Array = []
var _impacts: Array = []
var _peer_upserts: Dictionary = {}
var _peer_quiet: Dictionary = {}


func setup(building_system) -> void:
	system = building_system
	authoritative = system.authoritative
	if not authoritative:
		return
	system.state.changed.connect(_on_changed)
	system.state.integrity_changed.connect(_on_integrity)
	system.authority.presentation.connect(_on_presentation)
	for component_id in system.state.components.keys():
		_track(int(component_id))


func _process(_delta: float) -> void:
	if authoritative:
		flush()


static func chunk_of_cell(cell: Vector2i) -> String:
	return "%d,%d" % [floori(float(cell.x) / float(CHUNK)), floori(float(cell.y) / float(CHUNK))]


static func chunk_of(component: BuildComponent) -> String:
	if component.kind == BuildTypes.Kind.SLAB or component.kind == BuildTypes.Kind.POST:
		var key: Vector3i = component.key
		return chunk_of_cell(Vector2i(key.x, key.z))
	var key: Vector4i = component.key
	return chunk_of_cell(Vector2i(key.x, key.y))


static func interest_at(cell: Vector2i) -> Dictionary:
	var centre_x := floori(float(cell.x) / float(CHUNK))
	var centre_z := floori(float(cell.y) / float(CHUNK))
	var keys := {}
	for dz in range(-INTEREST, INTEREST + 1):
		for dx in range(-INTEREST, INTEREST + 1):
			keys["%d,%d" % [centre_x + dx, centre_z + dz]] = true
	return keys


func request_place(request: Dictionary) -> void:
	if authoritative:
		return
	_out_seq += 1
	var anchor: Vector2i = request.get("anchor", Vector2i.ZERO)
	var size: Vector2i = request.get("size", Vector2i.ZERO)
	submit_place.rpc_id(
		1,
		_out_seq,
		str(request.get("blueprint", "")),
		anchor.x,
		anchor.y,
		int(request.get("rotation", 0)),
		int(request.get("level", 0)),
		int(request.get("axis", 0)),
		int(request.get("target", 0)),
		size.x,
		size.y
	)


func request_repair(component_id: int) -> void:
	if authoritative:
		return
	_out_seq += 1
	submit_repair.rpc_id(1, _out_seq, component_id)


func request_blast(origin: Vector3) -> void:
	if authoritative:
		return
	_out_seq += 1
	submit_blast.rpc_id(1, _out_seq, origin)


@rpc("any_peer", "reliable")
func submit_place(
	seq: int,
	blueprint: String,
	anchor_x: int,
	anchor_y: int,
	rotation: int,
	level: int,
	axis: int,
	target: int,
	size_x: int,
	size_y: int
) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	handle_place(multiplayer.get_remote_sender_id(), seq, {
		"blueprint": blueprint,
		"anchor": Vector2i(anchor_x, anchor_y),
		"rotation": rotation,
		"level": level,
		"axis": axis,
		"target": target,
		"size": Vector2i(size_x, size_y),
	})


@rpc("any_peer", "reliable")
func submit_repair(seq: int, component_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	handle_repair(multiplayer.get_remote_sender_id(), seq, component_id)


@rpc("any_peer", "reliable")
func submit_blast(seq: int, origin: Vector3) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	handle_blast(multiplayer.get_remote_sender_id(), seq, origin)


@rpc("authority", "reliable")
func receive_delta(packet: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	present(system, packet)


@rpc("authority", "reliable")
func build_notice(seq: int, ok: bool, reason: String) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	var player: Node = system._local_player()
	if player != null and player.has_method("show_item_notice"):
		var text := reason
		if text == "" and ok:
			text = "Built."
		elif text == "" and not ok:
			text = "Cannot build."
		player.show_item_notice(text)


func handle_place(sender: int, seq: int, request: Dictionary) -> Dictionary:
	var denied := _gate(sender, seq, "build_tool", _anchor_point(request))
	if not denied.is_empty():
		return denied
	_bind_wallet(sender)
	var result: Dictionary = system.authority.request_place(request, sender)
	_clear_wallet()
	if bool(result.get("ok", false)):
		accepted += 1
		_notify(sender, seq, true, "Built." if bool(result.get("changed", false)) else "Already built.")
	else:
		rejected += 1
		_notify(sender, seq, false, str(result.get("reason", "Cannot build.")))
	flush()
	return result


func handle_repair(sender: int, seq: int, component_id: int) -> Dictionary:
	var component: BuildComponent = system.state.get_component(component_id)
	var player := _players().get(sender) as Node3D
	var point := player.global_position if component == null and player != null else Vector3.ZERO
	if component != null:
		point = system.grid.component_transform(component).origin
	var denied := _gate(sender, seq, "repair_tool", point)
	if not denied.is_empty():
		return denied
	if component == null:
		rejected += 1
		_notify(sender, seq, false, "Nothing to repair")
		return {"ok": false, "reason": "Nothing to repair"}
	var result: Dictionary = system.authority.repair(component_id)
	if bool(result.get("ok", false)):
		accepted += 1
		_notify(sender, seq, true, "Repaired.")
	else:
		rejected += 1
		_notify(sender, seq, false, str(result.get("reason", "Cannot repair.")))
	flush()
	return result


func handle_blast(sender: int, seq: int, origin: Vector3) -> Dictionary:
	if not NetConfig.finite_vector(origin):
		rejected += 1
		_notify(sender, seq, false, "Invalid blast.")
		return {"ok": false, "reason": "Invalid blast."}
	var denied := _gate(sender, seq, "blast_gun", origin)
	if not denied.is_empty():
		return denied
	var result: Dictionary = system.authority.apply_explosion(
		origin,
		system.config.blast_radius,
		system.config.blast_damage,
		"b%d-%d" % [sender, seq]
	)
	accepted += 1
	var hits: Array = result.get("hits", [])
	_notify(sender, seq, true, "Blast hit %d." % hits.size() if not hits.is_empty() else "Blast hit nothing.")
	flush()
	return result


func clear_rate(peer_id: int) -> void:
	_rates.erase(peer_id)


func forget_peer(peer_id: int) -> void:
	_seq.erase(peer_id)
	_rates.erase(peer_id)
	_known.erase(peer_id)
	_subscribed.erase(peer_id)
	_peer_upserts.erase(peer_id)
	_peer_quiet.erase(peer_id)
	delivered.erase(peer_id)


func sync_peer(peer_id: int) -> void:
	_subscribed.erase(peer_id)
	_known.erase(peer_id)
	_refresh_interest()
	flush()


func take_delivered(peer_id: int) -> Array:
	var list: Array = delivered.get(peer_id, [])
	delivered[peer_id] = []
	return list


func flush() -> void:
	if not authoritative or system == null:
		return
	_refresh_interest()
	if _pending.is_empty() and _health.is_empty() and _impacts.is_empty() and _peer_upserts.is_empty() and _peer_quiet.is_empty():
		return
	var merged := _merge_pending()
	_pending.clear()
	var health := _health.duplicate()
	_health.clear()
	var impacts := _impacts.duplicate()
	_impacts.clear()
	for peer_id in _player_ids():
		var packet := _packet_for(int(peer_id), merged, health, impacts)
		_peer_upserts.erase(peer_id)
		_peer_quiet.erase(peer_id)
		if _packet_empty(packet):
			continue
		_send(int(peer_id), packet)


static func present(building, packet: Dictionary) -> void:
	if building == null or building.state == null:
		return
	building.state.apply_remote(packet)
	if building.impacts != null:
		for mark in packet.get("impacts", []):
			if mark is Array and (mark as Array).size() >= 6:
				var values: Array = mark
				building.impacts.add_hole(
					Vector3(float(values[0]), float(values[1]), float(values[2])),
					Vector3(float(values[3]), float(values[4]), float(values[5]))
				)
	if building.debris == null:
		return
	for chip in packet.get("debris", []):
		if chip is Array and (chip as Array).size() >= 5:
			var values: Array = chip
			var origin := Vector3(float(values[0]), float(values[1]), float(values[2]))
			if int(values[4]) == 1:
				building.debris.spawn_collapse(origin, int(values[3]))
			else:
				var count := int(values[5]) if values.size() >= 6 else 1
				building.debris.spawn(origin, count, int(values[3]))


func _on_changed(change: Dictionary) -> void:
	if not bool(change.get("ok", true)):
		return
	var upsert_ids: Array[int] = []
	var seen := {}
	for component_id in change.get("added", []):
		var id := int(component_id)
		seen[id] = true
		upsert_ids.append(id)
		_track(id)
	for component_id in change.get("retouched", []):
		var id := int(component_id)
		if seen.has(id) or system.state.get_component(id) == null:
			continue
		upsert_ids.append(id)
	var removed: Array[int] = []
	for component_id in change.get("removed", []):
		var id := int(component_id)
		removed.append(id)
		_untrack(id)
	var falling: Array[int] = []
	if bool(change.get("falling", false)):
		falling = removed.duplicate()
	_pending.append({
		"upserts": upsert_ids,
		"removed": removed,
		"falling": falling,
		"gone": change.get("gone", []),
		"rooms_added": change.get("rooms_added", []),
		"rooms_removed": change.get("rooms_removed", []),
		"step_sec": float(change.get("step_sec", 0.14)),
	})


func _on_integrity(component_id: int) -> void:
	var component: BuildComponent = system.state.get_component(component_id)
	if component == null:
		return
	_health.append([component_id, component.health])


func _on_presentation(event_name: String, data: Dictionary) -> void:
	if event_name != "impact":
		return
	var point: Vector3 = data.get("point", Vector3.ZERO)
	var normal: Vector3 = data.get("normal", Vector3.UP)
	_impacts.append([point.x, point.y, point.z, normal.x, normal.y, normal.z, int(data.get("id", 0))])


func _merge_pending() -> Dictionary:
	var upserts: Array[int] = []
	var upsert_set := {}
	var removed := {}
	var falling := {}
	var gone: Array = []
	var rooms_added := {}
	var rooms_removed := {}
	var step_sec := 0.14
	for entry in _pending:
		for component_id in entry["removed"]:
			var id := int(component_id)
			upsert_set.erase(id)
			removed[id] = true
			if (entry["falling"] as Array).has(id):
				falling[id] = true
			else:
				falling.erase(id)
		for component_id in entry["upserts"]:
			var id := int(component_id)
			if system.state.get_component(id) == null:
				continue
			removed.erase(id)
			falling.erase(id)
			upsert_set[id] = true
		for snap in entry["gone"]:
			gone.append(snap)
		for room_id in entry["rooms_added"]:
			rooms_removed.erase(int(room_id))
			rooms_added[int(room_id)] = true
		for room_id in entry["rooms_removed"]:
			rooms_added.erase(int(room_id))
			rooms_removed[int(room_id)] = true
		if not (entry["falling"] as Array).is_empty():
			step_sec = float(entry["step_sec"])
	for component_id in upsert_set.keys():
		upserts.append(int(component_id))
	var removed_ids: Array[int] = []
	for component_id in removed.keys():
		removed_ids.append(int(component_id))
	var falling_ids: Array[int] = []
	for component_id in falling.keys():
		falling_ids.append(int(component_id))
	return {
		"upserts": upserts,
		"removed": removed_ids,
		"falling": falling_ids,
		"gone": gone,
		"rooms_added": rooms_added.keys(),
		"rooms_removed": rooms_removed.keys(),
		"step_sec": step_sec,
	}


func _packet_for(peer_id: int, merged: Dictionary, health: Array, impacts: Array) -> Dictionary:
	var subscribed: Dictionary = _subscribed.get(peer_id, {})
	var known: Dictionary = _known.get(peer_id, {})
	var upserts: Array = []
	var rooms_needed := {}
	var included := {}
	for component_id in merged["upserts"]:
		_offer_upsert(int(component_id), subscribed, known, upserts, rooms_needed, included)
	for component_id in _peer_upserts.get(peer_id, []):
		_offer_upsert(int(component_id), subscribed, known, upserts, rooms_needed, included)
	var removed: Array[int] = []
	var falling: Array[int] = []
	var falling_set := {}
	for component_id in merged["falling"]:
		falling_set[int(component_id)] = true
	for component_id in merged["removed"]:
		var id := int(component_id)
		if not known.has(id):
			continue
		removed.append(id)
		if falling_set.has(id):
			falling.append(id)
		known.erase(id)
	var quiet: Array[int] = []
	for component_id in _peer_quiet.get(peer_id, []):
		var id := int(component_id)
		if not known.has(id):
			continue
		quiet.append(id)
		known.erase(id)
	var rooms: Array = []
	for room_id in merged["rooms_added"]:
		if _room_in_interest(int(room_id), subscribed):
			rooms_needed[int(room_id)] = true
	for room_id in rooms_needed.keys():
		var encoded: Dictionary = BuildingCodec.room(system.state, int(room_id))
		if not encoded.is_empty():
			rooms.append(encoded)
	var rooms_removed: Array[int] = []
	for room_id in merged["rooms_removed"]:
		rooms_removed.append(int(room_id))
	var health_rows: Array = []
	for pair in health:
		var id := int(pair[0])
		if known.has(id) or included.has(id):
			health_rows.append([id, int(pair[1])])
	var impact_rows: Array = []
	for mark in impacts:
		var id := int(mark[6]) if mark is Array and (mark as Array).size() >= 7 else 0
		var chunk := str(_chunk_of_id.get(id, ""))
		if chunk != "" and subscribed.has(chunk):
			impact_rows.append([mark[0], mark[1], mark[2], mark[3], mark[4], mark[5]])
	var debris: Array = []
	var removed_set := {}
	for component_id in removed:
		removed_set[int(component_id)] = true
	for snap in merged["gone"]:
		var id := int(snap.get("id", 0))
		if not removed_set.has(id):
			continue
		var origin: Vector3 = system.geometry.world_aabb(
			int(snap["kind"]),
			system.grid.transform_for(int(snap["kind"]), snap["key"])
		).get_center()
		var count := DamageCatalog.for_kind(int(snap["kind"])).debris_count
		debris.append([origin.x, origin.y, origin.z, id, 1 if falling_set.has(id) else 0, count])
	_known[peer_id] = known
	return {
		"revision": system.state.revision,
		"next_component": system.state._next_component,
		"next_room": system.state._next_room,
		"upserts": upserts,
		"removed": removed,
		"quiet_removed": quiet,
		"falling": falling,
		"step_sec": float(merged["step_sec"]),
		"rooms": rooms,
		"rooms_removed": rooms_removed,
		"health": health_rows,
		"impacts": impact_rows,
		"debris": debris,
	}


func _room_in_interest(room_id: int, subscribed: Dictionary) -> bool:
	var src: Dictionary = system.state.rooms.get(room_id, {})
	for cell in src.get("cells", []):
		var key: Vector3i = cell
		if subscribed.has(chunk_of_cell(Vector2i(key.x, key.z))):
			return true
	return false


func _offer_upsert(
	component_id: int,
	subscribed: Dictionary,
	known: Dictionary,
	upserts: Array,
	rooms_needed: Dictionary,
	included: Dictionary
) -> void:
	if included.has(component_id):
		return
	var component: BuildComponent = system.state.get_component(component_id)
	if component == null:
		return
	var chunk := chunk_of(component)
	if not subscribed.has(chunk):
		return
	var record: Dictionary = BuildingCodec.piece(system.state, component)
	record["chunk"] = chunk
	upserts.append(record)
	included[component_id] = true
	known[component_id] = chunk
	for room_id in component.rooms:
		rooms_needed[int(room_id)] = true


func _refresh_interest() -> void:
	var live := {}
	for peer_id in _player_ids():
		live[int(peer_id)] = true
		var player := _players().get(peer_id) as Node3D
		if player == null or not is_instance_valid(player):
			continue
		var want := interest_at(system.grid.world_to_cell(player.global_position))
		var have: Dictionary = _subscribed.get(peer_id, {})
		for chunk in want.keys():
			if have.has(chunk):
				continue
			var row: Dictionary = _chunks.get(chunk, {})
			for component_id in row.keys():
				_peer_list(_peer_upserts, int(peer_id)).append(int(component_id))
		var known: Dictionary = _known.get(peer_id, {})
		for chunk in have.keys():
			if want.has(chunk):
				continue
			for component_id in known.keys():
				if str(known[component_id]) == str(chunk):
					_peer_list(_peer_quiet, int(peer_id)).append(int(component_id))
		_subscribed[peer_id] = want
	for peer_id in _subscribed.keys():
		if not live.has(int(peer_id)):
			forget_peer(int(peer_id))


func _peer_list(store: Dictionary, peer_id: int) -> Array:
	if not store.has(peer_id):
		store[peer_id] = []
	return store[peer_id]


func _packet_empty(packet: Dictionary) -> bool:
	return (
		(packet["upserts"] as Array).is_empty()
		and (packet["removed"] as Array).is_empty()
		and (packet["quiet_removed"] as Array).is_empty()
		and (packet["rooms"] as Array).is_empty()
		and (packet["rooms_removed"] as Array).is_empty()
		and (packet["health"] as Array).is_empty()
		and (packet["impacts"] as Array).is_empty()
		and (packet["debris"] as Array).is_empty()
	)


func _send(peer_id: int, packet: Dictionary) -> void:
	if not delivered.has(peer_id):
		delivered[peer_id] = []
	(delivered[peer_id] as Array).append(packet)
	packets_sent += 1
	var peer := multiplayer.multiplayer_peer
	if peer != null and multiplayer.get_peers().has(peer_id):
		receive_delta.rpc_id(peer_id, packet)


func _notify(peer_id: int, seq: int, ok: bool, reason: String) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and multiplayer.get_peers().has(peer_id):
		build_notice.rpc_id(peer_id, seq, ok, reason)


func _gate(sender: int, seq: int, item_id: String, point: Vector3) -> Dictionary:
	if not authoritative:
		return _deny(sender, "Not the authority")
	if sender <= 1 or not _players().has(sender):
		return _deny(sender, "No player")
	if not _accept_seq(sender, seq):
		return _deny(sender, "Repeated request")
	if not _rate_ok(sender):
		return _deny(sender, "Too many requests")
	if not _holds(sender, item_id):
		return _deny(sender, "Wrong tool")
	var player := _players()[sender] as Node3D
	if player == null or not NetConfig.finite_vector(point):
		return _deny(sender, "Invalid request")
	if player.global_position.distance_to(point) > REACH:
		return _deny(sender, "Too far")
	return {}


func _deny(sender: int, reason: String) -> Dictionary:
	rejected += 1
	_notify(sender, 0, false, reason)
	return {"ok": false, "changed": false, "reason": reason}


func _accept_seq(sender: int, seq: int) -> bool:
	if seq <= 0 or seq > 1_000_000_000:
		return false
	var last := int(_seq.get(sender, 0))
	if seq <= last:
		return false
	_seq[sender] = seq
	return true


func _rate_ok(sender: int) -> bool:
	var now := Time.get_ticks_msec()
	var kept: Array[int] = []
	for stamp in _rates.get(sender, []):
		if now - int(stamp) < 1000:
			kept.append(int(stamp))
	if kept.size() >= BUILD_RATE:
		_rates[sender] = kept
		return false
	kept.append(now)
	_rates[sender] = kept
	return true


func _holds(sender: int, item_id: String) -> bool:
	var bag := _inventory(sender)
	var player := _players().get(sender) as PlayerController
	if bag == null or player == null:
		return false
	var index := player.hotbar_index
	if index < 0 or index >= bag.capacity:
		return false
	var slot: Dictionary = bag.slots[index]
	return str(slot.get("id", "")) == item_id and int(slot.get("qty", 0)) > 0


func _bind_wallet(sender: int) -> void:
	var bag := _inventory(sender)
	if bag == null or not system.config.require_resources:
		_clear_wallet()
		return
	system.authority.wallet_count = func(item_id: String) -> int: return bag.count_item(item_id)
	system.authority.wallet_spend = func(item_id: String, quantity: int) -> bool: return bag.take_item(item_id, quantity)


func _clear_wallet() -> void:
	system.authority.wallet_count = Callable()
	system.authority.wallet_spend = Callable()


func _anchor_point(request: Dictionary) -> Vector3:
	var anchor: Vector2i = request.get("anchor", Vector2i.ZERO)
	var level := int(request.get("level", 0))
	return Vector3(
		system.config.grid_origin.x + (float(anchor.x) + 0.5) * system.config.cell_size,
		system.grid.level_y(level) + 1.0,
		system.config.grid_origin.z + (float(anchor.y) + 0.5) * system.config.cell_size
	)


func _track(component_id: int) -> void:
	_untrack(component_id)
	var component: BuildComponent = system.state.get_component(component_id)
	if component == null:
		return
	var chunk := chunk_of(component)
	_chunk_of_id[component_id] = chunk
	if not _chunks.has(chunk):
		_chunks[chunk] = {}
	(_chunks[chunk] as Dictionary)[component_id] = true


func _untrack(component_id: int) -> void:
	if not _chunk_of_id.has(component_id):
		return
	var chunk := str(_chunk_of_id[component_id])
	_chunk_of_id.erase(component_id)
	if not _chunks.has(chunk):
		return
	var row: Dictionary = _chunks[chunk]
	row.erase(component_id)
	if row.is_empty():
		_chunks.erase(chunk)


func _players() -> Dictionary:
	var arena: Node = system.get_parent()
	if arena == null:
		return {}
	var net: Node = arena.get_node_or_null("GameNet")
	if net != null and net.has_method("authority_players"):
		return net.call("authority_players")
	return {}


func _player_ids() -> Array:
	var ids: Array = []
	for peer_id in _players().keys():
		ids.append(int(peer_id))
	return ids


func _inventory(sender: int) -> Inventory:
	var arena: Node = system.get_parent()
	if arena == null:
		return null
	var net: Node = arena.get_node_or_null("GameNet")
	if net != null and net.has_method("debug_inventory"):
		return net.call("debug_inventory", sender) as Inventory
	return null
