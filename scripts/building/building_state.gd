extends RefCounted
class_name BuildingState

## Logical building state. No nodes, meshes, or physics live here.
## Slot dictionaries guarantee one piece per canonical slot:
##   slabs        Vector3i(x, level, z) -> id
##   posts        Vector3i(vx, level, vz) -> id
##   edges        EdgeRegistry, Vector4i(x, z, level, axis) -> id
##   stairs_cells Vector3i(x, level, z) -> stairs id
##   stairwells   Vector3i(x, level + 1, z) -> stairs id (no slab may exist here)
##   stair_exits  Vector3i(x, level + 1, z) -> stairs id (landing cell)
##   room_claims  Vector3i(x, level, z) -> room id
## Every commit emits `changed` once with the ids added and removed and the
## slab cells whose presence changed, so presentation updates only what moved.
## Damage, repair, and rebuild emit `integrity_changed` for that one id and
## do not add or remove nodes.

signal changed(change: Dictionary)
signal integrity_changed(component_id: int)

var components: Dictionary = {}
var slabs: Dictionary = {}
var posts: Dictionary = {}
var edges := EdgeRegistry.new()
var stairs_cells: Dictionary = {}
var stairwells: Dictionary = {}
var stair_exits: Dictionary = {}
var room_claims: Dictionary = {}
var rooms: Dictionary = {}
var graph := ConstructionGraph.new()
var revision := 0
var _next_component := 1
var _next_room := 1


func get_component(component_id: int) -> BuildComponent:
	return components.get(component_id) as BuildComponent


func slab_at(key: Vector3i) -> int:
	return int(slabs.get(key, 0))


func post_at(key: Vector3i) -> int:
	return int(posts.get(key, 0))


func stairs_at(key: Vector3i) -> int:
	return int(stairs_cells.get(key, 0))


func stairwell_at(key: Vector3i) -> int:
	return int(stairwells.get(key, 0))


func room_at(key: Vector3i) -> int:
	return int(room_claims.get(key, 0))


func component_count() -> int:
	return components.size()


## Independent copy for a placement probe or a collapse forecast.
## Committing the copy does not touch this state.
func fork() -> BuildingState:
	var copy := BuildingState.new()
	copy.revision = revision
	copy._next_component = _next_component
	copy._next_room = _next_room
	for id in components.keys():
		copy.components[id] = _copy_component(components[id])
	copy.slabs = slabs.duplicate()
	copy.posts = posts.duplicate()
	copy.stairs_cells = stairs_cells.duplicate()
	copy.stairwells = stairwells.duplicate()
	copy.stair_exits = stair_exits.duplicate()
	copy.room_claims = room_claims.duplicate()
	for room_id in rooms.keys():
		var src: Dictionary = rooms[room_id]
		copy.rooms[room_id] = {
			"id": src["id"],
			"blueprint": src["blueprint"],
			"request": (src["request"] as Dictionary).duplicate(true),
			"cells": (src["cells"] as Array).duplicate(),
		}
	copy.edges = edges.fork()
	for id in copy.components.keys():
		copy.graph.add_component(copy, copy.components[id])
	return copy


func _copy_component(src: BuildComponent) -> BuildComponent:
	var dst := BuildComponent.new()
	dst.id = src.id
	dst.kind = src.kind
	dst.key = src.key
	dst.level = src.level
	dst.rotation = src.rotation
	dst.cells = src.cells.duplicate()
	dst.rooms = src.rooms.duplicate()
	dst.pinned = src.pinned
	dst.material = src.material
	dst.max_health = src.max_health
	dst.health = src.health
	dst.destroyed = src.destroyed
	return dst


func count_kind(kind: int) -> int:
	var total := 0
	for component: BuildComponent in components.values():
		if component.kind == kind:
			total += 1
	return total


func vertex_has_edges(vertex: Vector2i, level: int) -> bool:
	for edge in GridSystem.vertex_edges(vertex, level):
		if edges.has_piece(edge):
			return true
	return false


## Applies a validated plan. The caller (BuildingAuthority) re-plans against
## the current revision, so nothing here can fail half way.
func commit(plan: ConstructionPlan) -> Dictionary:
	var change := _new_change()
	if plan.state_revision != revision or not plan.is_valid():
		push_error("BuildingState.commit refused a stale or invalid plan")
		change["ok"] = false
		return change
	var room_id := plan.reused_room
	if room_id == 0 and not plan.room_cells.is_empty():
		room_id = _next_room
		_next_room += 1
		rooms[room_id] = {
			"id": room_id,
			"blueprint": plan.blueprint.id,
			"request": plan.request.duplicate(),
			"cells": plan.room_cells.duplicate(),
		}
		for cell in plan.room_cells:
			room_claims[cell] = room_id
	var inherited: Dictionary = {}
	for entry in plan.entries:
		var action := int(entry["action"])
		if action == BuildTypes.Action.REMOVE or action == BuildTypes.Action.REPLACE:
			var old := get_component(int(entry["existing"]))
			if old != null:
				inherited[str(entry["key"])] = old.rooms.duplicate()
			_remove_internal(int(entry["existing"]), change)
	for entry in plan.entries:
		var action := int(entry["action"])
		if action == BuildTypes.Action.CREATE or action == BuildTypes.Action.REPLACE:
			var created := _create(entry, change)
			for kept in inherited.get(str(entry["key"]), PackedInt32Array()):
				created.add_room(int(kept))
			_reference(created, room_id)
		elif action == BuildTypes.Action.REUSE:
			var existing := get_component(int(entry["existing"]))
			if existing == null:
				continue
			_reference(existing, room_id)
			if bool(entry.get("pinned", false)):
				existing.pinned = true
	_finish(change)
	return change


## Removes one piece. Corner posts that no longer carry a wall go with it
## unless they were placed as supports.
func remove_piece(component_id: int) -> Dictionary:
	var change := _new_change()
	var component := get_component(component_id)
	if component == null:
		change["ok"] = false
		change["reason"] = "Nothing to remove"
		return change
	var reason := removal_block_reason(component)
	if reason != "":
		change["ok"] = false
		change["reason"] = reason
		return change
	_remove_internal(component_id, change)
	if BuildTypes.is_edge_kind(component.kind):
		var key: Vector4i = component.key
		for vertex in GridSystem.edge_vertices(key):
			var post_id := post_at(GridSystem.post_key(vertex, key.z))
			var post := get_component(post_id)
			if post != null and not post.pinned and not vertex_has_edges(vertex, key.z):
				_remove_internal(post_id, change)
	_finish(change)
	return change


## True when an edge piece on this boundary stands on a floor: one of the two
## cells beside it has a slab on the edge's level, or is the top of a stairwell
## (the stairs below carry walls around their opening). Cells listed in
## ignoring count as already gone.
func edge_has_floor(key: Vector4i, ignoring: Array = []) -> bool:
	for cell in GridSystem.edge_cells(key):
		var slab := GridSystem.slab_key(cell, key.z)
		if (slab_at(slab) != 0 or stairwell_at(slab) != 0) and not ignoring.has(slab):
			return true
	return false


## Edge pieces that would lose their last floor if these cells went away.
func edges_left_floating(removed: Array) -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for slab: Vector3i in removed:
		for edge in GridSystem.cell_edges(Vector2i(slab.x, slab.z), slab.y):
			if edges.has_piece(edge) and not result.has(edge) and not edge_has_floor(edge, removed):
				result.append(edge)
	return result


func removal_block_reason(component: BuildComponent) -> String:
	if component.kind == BuildTypes.Kind.SLAB and stairs_at(component.key) != 0:
		return "Remove the stairs on this slab first"
	if component.kind == BuildTypes.Kind.SLAB and not edges_left_floating([component.key]).is_empty():
		return "Walls stand only on this floor; remove them first"
	if component.kind == BuildTypes.Kind.STAIRS:
		var openings: Array = []
		for cell: Vector3i in component.cells:
			openings.append(Vector3i(cell.x, cell.y + 1, cell.z))
		if not edges_left_floating(openings).is_empty():
			return "Walls stand on top of these stairs; remove them first"
	if component.kind == BuildTypes.Kind.POST:
		var key: Vector3i = component.key
		if vertex_has_edges(Vector2i(key.x, key.z), key.y):
			return "Walls still end on this post"
	return ""


## Subtracts health. At zero the piece is deleted, not left as an empty slot.
## A wall placed on its own is the only thing removed. A piece that belongs to
## a room takes that room with it once the room has no floor, wall, opening, or
## stairs left. `removed` lists the pieces that left, for debris.
func apply_damage(component_id: int, amount: int) -> Dictionary:
	var component := get_component(component_id)
	if component == null:
		return {"ok": false, "changed": false, "destroyed": false, "health": 0, "reason": "Missing piece", "removed": []}
	if amount <= 0 or component.destroyed:
		return {"ok": true, "changed": false, "destroyed": false, "health": component.health, "reason": "No effect", "removed": []}
	component.health = maxi(component.health - amount, 0)
	if component.health > 0:
		integrity_changed.emit(component_id)
		return {"ok": true, "changed": true, "destroyed": false, "health": component.health, "reason": "", "removed": [], "seeds": []}
	var killed := _destroy_killed(component_id)
	return {
		"ok": true,
		"changed": true,
		"destroyed": true,
		"health": 0,
		"reason": "",
		"removed": killed["removed"],
		"seeds": killed["seeds"],
	}


## Restores a damaged piece that is still standing. Destroyed pieces must be rebuilt.
func repair_component(component_id: int) -> Dictionary:
	var component := get_component(component_id)
	if component == null:
		return {"ok": false, "changed": false, "reason": "Nothing to repair"}
	if component.destroyed:
		return {"ok": false, "changed": false, "reason": "Destroyed; rebuild it"}
	if component.health >= component.max_health:
		return {"ok": false, "changed": false, "reason": "Not damaged"}
	component.health = component.max_health
	integrity_changed.emit(component_id)
	return {"ok": true, "changed": true, "reason": ""}


## Deletes the piece that just reached zero health, unused posts at its ends,
## and any room that no longer has a floor, wall, opening, or stairs.
## `seeds` are the pieces that were touching it, for the collapse check.
func _destroy_killed(component_id: int) -> Dictionary:
	var change := _new_change()
	var removed: Array = []
	var seeds: Array[int] = []
	var component := get_component(component_id)
	if component == null:
		return {"removed": removed, "seeds": seeds}
	var kind := component.kind
	var key: Variant = component.key
	_remember_seeds(component.id, seeds)
	_force_remove(component, change, removed)
	if BuildTypes.is_edge_kind(kind):
		_release_unused_posts(key, change, removed, seeds)
	_erase_empty_rooms(change, removed, seeds)
	_finish(change)
	return {"removed": removed, "seeds": seeds}


## Drops these pieces because nothing holds them up any more. Dismantle does
## not call this. `seeds` are what the next collapse stage should look at.
## `falling` tells the presentation to pancake the meshes instead of deleting
## them on the spot. `step_sec` is how long a mesh takes to drop one storey.
func collapse_pieces(ids: Array, falling: bool = false, step_sec: float = 0.14) -> Dictionary:
	var change := _new_change()
	var removed: Array = []
	var seeds: Array[int] = []
	var ordered: Array[int] = []
	for id in ids:
		ordered.append(int(id))
	ordered.sort()
	for component_id in ordered:
		var component := get_component(component_id)
		if component == null:
			continue
		_remember_seeds(component.id, seeds)
		var kind := component.kind
		var key: Variant = component.key
		_force_remove(component, change, removed)
		if BuildTypes.is_edge_kind(kind):
			_release_unused_posts(key, change, removed, seeds)
	_erase_empty_rooms(change, removed, seeds)
	if not removed.is_empty():
		change["falling"] = falling
		change["step_sec"] = step_sec
		_finish(change)
	return {"removed": removed, "seeds": seeds}


func _remember_seeds(component_id: int, seeds: Array[int]) -> void:
	for other in graph.neighbours(component_id).keys():
		var next := int(other)
		if next > 0 and not seeds.has(next):
			seeds.append(next)


func _force_remove(component: BuildComponent, change: Dictionary, removed: Array) -> void:
	if get_component(component.id) == null:
		return
	removed.append({"id": component.id, "kind": component.kind, "key": component.key})
	_remove_internal(component.id, change)


func _release_unused_posts(key: Variant, change: Dictionary, removed: Array, seeds: Array[int]) -> void:
	if key is not Vector4i:
		return
	var edge: Vector4i = key
	for vertex in GridSystem.edge_vertices(edge):
		var post := get_component(post_at(GridSystem.post_key(vertex, edge.z)))
		if post != null and not post.pinned and not vertex_has_edges(vertex, edge.z):
			_remember_seeds(post.id, seeds)
			_force_remove(post, change, removed)


## A room leaves when none of its floors, walls, openings, or stairs remain.
## Posts that belonged only to it go too. A wall shared with another room stays.
func _erase_empty_rooms(change: Dictionary, removed: Array, seeds: Array[int]) -> void:
	var empty: Array[int] = []
	for room_id in rooms.keys():
		if not _room_has_structure(int(room_id)):
			empty.append(int(room_id))
	for room_id in empty:
		var leftovers: Array[BuildComponent] = []
		for component: BuildComponent in components.values():
			if component.rooms.has(room_id):
				leftovers.append(component)
		for component in leftovers:
			if component.rooms.size() <= 1:
				_remember_seeds(component.id, seeds)
				_force_remove(component, change, removed)
			else:
				_forget_room(component, room_id)
		var cells: Array = []
		for cell in room_claims.keys():
			if int(room_claims[cell]) == room_id:
				cells.append(cell)
		for cell in cells:
			room_claims.erase(cell)
		rooms.erase(room_id)


func _room_has_structure(room_id: int) -> bool:
	for component: BuildComponent in components.values():
		if component.rooms.has(room_id) and component.kind != BuildTypes.Kind.POST:
			return true
	return false


func _forget_room(component: BuildComponent, room_id: int) -> void:
	var kept := PackedInt32Array()
	for existing in component.rooms:
		if int(existing) != room_id:
			kept.append(int(existing))
	component.rooms = kept
	if BuildTypes.is_edge_kind(component.kind):
		edges.drop_room_ref(component.key, room_id)


## Restores a destroyed piece in its existing slot. Refuses a piece that is
## still standing, and never allocates a new id.
func rebuild_component(component_id: int) -> Dictionary:
	var component := get_component(component_id)
	if component == null:
		return {"ok": false, "changed": false, "reason": "Nothing to rebuild"}
	if not component.destroyed:
		return {"ok": false, "changed": false, "reason": "Not destroyed"}
	if _slot_owner(component) != component.id:
		return {"ok": false, "changed": false, "reason": "Slot no longer belongs to this piece"}
	component.destroyed = false
	component.health = component.max_health
	integrity_changed.emit(component_id)
	return {"ok": true, "changed": true, "reason": ""}


func _slot_owner(component: BuildComponent) -> int:
	match component.kind:
		BuildTypes.Kind.SLAB:
			return slab_at(component.key)
		BuildTypes.Kind.POST:
			return post_at(component.key)
		BuildTypes.Kind.STAIRS:
			return stairs_at(component.cells[0]) if not component.cells.is_empty() else 0
		_:
			return edges.component_at(component.key)


## Order-independent fingerprint of the logical state, used by tests to prove
## that previews and rejected requests changed nothing.
func checksum() -> int:
	var lines := PackedStringArray()
	for component: BuildComponent in components.values():
		lines.append("c%d|%d|%s|%s|%s|%s|%d|%s" % [component.id, component.kind, str(component.key), component.pinned, str(component.rooms), str(component.cells), component.health, component.destroyed])
	for cell in room_claims.keys():
		lines.append("r%s=%d" % [str(cell), int(room_claims[cell])])
	for cell in stairwells.keys():
		lines.append("w%s=%d" % [str(cell), int(stairwells[cell])])
	lines.append("e%d" % edges.size())
	lines.sort()
	return "\n".join(lines).hash()


func _create(entry: Dictionary, change: Dictionary) -> BuildComponent:
	var component := BuildComponent.new()
	component.id = _next_component
	_next_component += 1
	component.kind = int(entry["kind"])
	component.key = entry["key"]
	component.pinned = bool(entry.get("pinned", false))
	var profile := DamageCatalog.for_kind(component.kind)
	component.material = profile.id
	component.max_health = profile.max_health
	component.health = profile.max_health
	component.destroyed = false
	match component.kind:
		BuildTypes.Kind.SLAB:
			var key: Vector3i = component.key
			component.level = key.y
			slabs[key] = component.id
		BuildTypes.Kind.POST:
			var key: Vector3i = component.key
			component.level = key.y
			posts[key] = component.id
		BuildTypes.Kind.STAIRS:
			var key: Vector4i = component.key
			component.level = key.z
			component.rotation = key.w
			for cell in entry["cells"]:
				var covered: Vector3i = cell
				component.cells.append(covered)
				stairs_cells[covered] = component.id
				stairwells[Vector3i(covered.x, covered.y + 1, covered.z)] = component.id
			stair_exits[entry["exit"]] = component.id
			for rule in entry["rules"]:
				edges.set_rule(rule[0], component.id, int(rule[1]))
		_:
			var key: Vector4i = component.key
			component.level = key.z
			edges.claim(key, component.id)
	components[component.id] = component
	graph.add_component(self, component)
	(change["added"] as Array).append(component.id)
	if component.kind == BuildTypes.Kind.SLAB:
		(change["slab_cells"] as Array).append(component.key)
	return component


func _remove_internal(component_id: int, change: Dictionary) -> void:
	var component := get_component(component_id)
	if component == null:
		return
	graph.remove_component(component_id)
	match component.kind:
		BuildTypes.Kind.SLAB:
			slabs.erase(component.key)
			(change["slab_cells"] as Array).append(component.key)
		BuildTypes.Kind.POST:
			posts.erase(component.key)
		BuildTypes.Kind.STAIRS:
			for cell in component.cells:
				stairs_cells.erase(cell)
				stairwells.erase(Vector3i(cell.x, cell.y + 1, cell.z))
			for exit_key in stair_exits.keys():
				if int(stair_exits[exit_key]) == component_id:
					stair_exits.erase(exit_key)
			edges.clear_rules_for(component_id)
		_:
			edges.release(component.key, component_id)
	components.erase(component_id)
	(change["removed"] as Array).append(component_id)


func _reference(component: BuildComponent, room_id: int) -> void:
	if room_id <= 0:
		return
	component.add_room(room_id)
	if BuildTypes.is_edge_kind(component.kind):
		edges.add_room_ref(component.key, room_id)


func _new_change() -> Dictionary:
	return {"ok": true, "added": [], "removed": [], "slab_cells": [], "revision": revision}


func _finish(change: Dictionary) -> void:
	revision += 1
	change["revision"] = revision
	changed.emit(change)
