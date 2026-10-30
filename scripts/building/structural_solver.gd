extends RefCounted
class_name StructuralSolver

## Support model, kept small on purpose.
##
## Foundations are level-0 slabs. The ground holds them, so they never fall
## from missing support and they never buckle.
##
## Every higher slab weighs BuildingConfig.slab_weight, plus whatever the walls
## standing on it have brought down from above. A connected floor shares that weight equally
## across the walls and doorways it still rests on. Windows and posts do not
## carry floor load; posts only join walls.
##
## A wall or doorway buckles when its share is greater than
## BuildingConfig.wall_bearing. A higher slab with no wall or doorway under
## its whole connected floor is unsupported. An edge piece with no floor
## beside it, stairs missing a slab under any step, and a post with nothing
## left to stand on, fall the same way.
##
## Only the pieces reachable from the seeds are visited. A separate building
## is left alone. `failing` is one stage. `cascade` runs every stage and
## returns every piece that will fall. The caller drops that set from the
## roof downward.

static func region(state: BuildingState, seeds: Array) -> Array[int]:
	var seen := {}
	var queue: Array[int] = []
	for id in seeds:
		var start := int(id)
		if start <= 0 or seen.has(start) or state.get_component(start) == null:
			continue
		seen[start] = true
		queue.append(start)
	var index := 0
	while index < queue.size():
		var current: int = queue[index]
		index += 1
		for other in state.graph.neighbours(current).keys():
			var next := int(other)
			if next <= 0 or seen.has(next) or state.get_component(next) == null:
				continue
			seen[next] = true
			queue.append(next)
	queue.sort()
	return queue


## Floor load on each id in `region_ids`. Walls and doorways carry a share.
## Upper slabs also store the load brought down onto them. Foundations stay at 0.
static func loads(state: BuildingState, region_ids: Array, config: BuildingConfig = null) -> Dictionary:
	var tile_weight := 0.5 if config == null else config.slab_weight
	return _loads(state, region_ids, tile_weight)


## Ids that fall in this stage, sorted so the order never depends on hash order.
static func failing(state: BuildingState, region_ids: Array, config: BuildingConfig) -> Array[int]:
	var loads := _loads(state, region_ids, config.slab_weight)
	var bad: Array[int] = []
	for id in region_ids:
		var component := state.get_component(int(id))
		if component == null:
			continue
		if _unsupported(state, component) or _overloaded(component, float(loads.get(int(id), 0.0)), config):
			bad.append(int(id))
	bad.sort()
	return bad


static func _loads(state: BuildingState, region_ids: Array, tile_weight: float) -> Dictionary:
	var load := {}
	var slabs_by_level := {}
	var max_level := 0
	for id in region_ids:
		load[int(id)] = 0.0
		var component := state.get_component(int(id))
		if component == null or component.kind != BuildTypes.Kind.SLAB or component.level <= 0:
			continue
		if not slabs_by_level.has(component.level):
			slabs_by_level[component.level] = []
		(slabs_by_level[component.level] as Array).append(int(id))
		max_level = maxi(max_level, component.level)
	for level in range(max_level, 0, -1):
		if not slabs_by_level.has(level):
			continue
		var remaining: Array[int] = []
		for id in slabs_by_level[level]:
			remaining.append(int(id))
		remaining.sort()
		while not remaining.is_empty():
			var group := _take_group(state, remaining)
			_charge_group(state, group, load, tile_weight)
	return load


static func _take_group(state: BuildingState, remaining: Array[int]) -> Array[int]:
	var start: int = remaining[0]
	var group: Array[int] = []
	var queue: Array[int] = [start]
	var seen := {start: true}
	var index := 0
	while index < queue.size():
		var current: int = queue[index]
		index += 1
		group.append(current)
		for other in _adjacent_slabs(state, current):
			if seen.has(other) or not remaining.has(other):
				continue
			seen[other] = true
			queue.append(other)
	for id in group:
		remaining.erase(id)
	group.sort()
	return group


static func _charge_group(state: BuildingState, group: Array[int], load: Dictionary, tile_weight: float) -> void:
	var bearers: Array[int] = []
	var weight := 0.0
	for id in group:
		weight += tile_weight + float(load.get(id, 0.0))
		for bearer_id in _bearers(state, id):
			if not bearers.has(bearer_id):
				bearers.append(bearer_id)
	if bearers.is_empty():
		return
	bearers.sort()
	var share := weight / float(bearers.size())
	for bearer_id in bearers:
		load[bearer_id] = float(load.get(bearer_id, 0.0)) + share
		_transfer_down(state, bearer_id, share, load)


static func _transfer_down(state: BuildingState, bearer_id: int, amount: float, load: Dictionary) -> void:
	var bearer := state.get_component(bearer_id)
	if bearer == null:
		return
	var floors: Array[int] = []
	var links: Dictionary = state.graph.neighbours(bearer_id)
	for other in links.keys():
		if int(links[other]) != ConstructionGraph.Link.FLOOR_JOIN:
			continue
		var slab := state.get_component(int(other))
		if slab != null and slab.kind == BuildTypes.Kind.SLAB and slab.level == bearer.level:
			floors.append(int(other))
	if floors.is_empty():
		return
	floors.sort()
	var share := amount / float(floors.size())
	for floor_id in floors:
		load[floor_id] = float(load.get(floor_id, 0.0)) + share


static func _unsupported(state: BuildingState, component: BuildComponent) -> bool:
	match component.kind:
		BuildTypes.Kind.SLAB:
			return component.level > 0 and not _slab_supported(state, component.id)
		BuildTypes.Kind.POST:
			return _post_unsupported(state, component)
		BuildTypes.Kind.STAIRS:
			return _stairs_unsupported(state, component)
		_:
			if BuildTypes.is_edge_kind(component.kind):
				return not state.edge_has_floor(component.key)
			return false


## Every piece a collapse starting at `seeds` would remove, in wave order.
## The state passed in is not changed.
static func cascade(state: BuildingState, seeds: Array, config: BuildingConfig) -> Array[int]:
	var copy := state.fork()
	var pending: Array = []
	for id in seeds:
		var start := int(id)
		if start > 0 and not pending.has(start):
			pending.append(start)
	var doomed: Array[int] = []
	var seen := {}
	var waves := 0
	while waves < config.collapse_max_waves and not pending.is_empty():
		waves += 1
		var failing := failing(copy, region(copy, pending), config)
		if failing.is_empty():
			break
		var collapsed := copy.collapse_pieces(failing)
		for snap in collapsed.get("removed", []):
			var id := int(snap["id"])
			if seen.has(id):
				continue
			seen[id] = true
			doomed.append(id)
		pending = collapsed.get("seeds", [])
	return doomed


## Storey used to order a pancake. The roof slab falls with the walls under it.
static func storey_of(component: BuildComponent) -> int:
	if component.kind == BuildTypes.Kind.SLAB and component.level > 0:
		return component.level - 1
	return component.level


static func _overloaded(component: BuildComponent, amount: float, config: BuildingConfig) -> bool:
	if component.kind != BuildTypes.Kind.WALL and component.kind != BuildTypes.Kind.DOORWAY:
		return false
	return amount > config.wall_bearing + 0.001


static func _slab_supported(state: BuildingState, slab_id: int) -> bool:
	var seen := {slab_id: true}
	var queue: Array[int] = [slab_id]
	var index := 0
	while index < queue.size():
		var current: int = queue[index]
		index += 1
		if not _bearers(state, current).is_empty():
			return true
		var component := state.get_component(current)
		if component != null and component.level <= 0:
			return true
		for other in _adjacent_slabs(state, current):
			if seen.has(other):
				continue
			seen[other] = true
			queue.append(other)
	return false


static func _bearers(state: BuildingState, slab_id: int) -> Array[int]:
	var found: Array[int] = []
	var links: Dictionary = state.graph.neighbours(slab_id)
	for other in links.keys():
		if int(links[other]) != ConstructionGraph.Link.RESTS_ON:
			continue
		var component := state.get_component(int(other))
		if component != null and _carries_floors(component.kind):
			found.append(int(other))
	return found


static func _carries_floors(kind: int) -> bool:
	return kind == BuildTypes.Kind.WALL or kind == BuildTypes.Kind.DOORWAY


static func _adjacent_slabs(state: BuildingState, slab_id: int) -> Array[int]:
	var found: Array[int] = []
	var links: Dictionary = state.graph.neighbours(slab_id)
	for other in links.keys():
		if int(links[other]) != ConstructionGraph.Link.ADJACENT:
			continue
		var component := state.get_component(int(other))
		if component != null and component.kind == BuildTypes.Kind.SLAB:
			found.append(int(other))
	return found


static func _post_unsupported(state: BuildingState, component: BuildComponent) -> bool:
	var key: Vector3i = component.key
	var vertex := Vector2i(key.x, key.z)
	if state.vertex_has_edges(vertex, key.y):
		return false
	if state.post_at(GridSystem.post_key(vertex, key.y - 1)) != 0:
		return false
	for cell in GridSystem.vertex_cells(vertex):
		if state.slab_at(GridSystem.slab_key(cell, key.y)) != 0:
			return false
	return true


static func _stairs_unsupported(state: BuildingState, component: BuildComponent) -> bool:
	if component.cells.is_empty():
		return true
	for cell in component.cells:
		if state.slab_at(cell) == 0:
			return true
	return false
