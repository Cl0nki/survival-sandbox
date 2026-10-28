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

signal changed(change: Dictionary)

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


## Order-independent fingerprint of the logical state, used by tests to prove
## that previews and rejected requests changed nothing.
func checksum() -> int:
	var lines := PackedStringArray()
	for component: BuildComponent in components.values():
		lines.append("c%d|%d|%s|%s|%s|%s" % [component.id, component.kind, str(component.key), component.pinned, str(component.rooms), str(component.cells)])
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
