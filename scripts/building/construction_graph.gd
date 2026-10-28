extends RefCounted
class_name ConstructionGraph

## Undirected links between committed pieces, derived from canonical slots.
## Phase 1 uses it for connectivity and support checks; the structural solver
## of a later phase walks the same links. Links are stored from both ends with
## mirrored meaning (RESTS_ON on one side is SUPPORTS on the other).

enum Link { ATTACHED, FLOOR_JOIN, RESTS_ON, SUPPORTS, ADJACENT }

var _links: Dictionary = {}


static func mirror(link: int) -> int:
	if link == Link.RESTS_ON:
		return Link.SUPPORTS
	if link == Link.SUPPORTS:
		return Link.RESTS_ON
	return link


func add_component(state: BuildingState, component: BuildComponent) -> void:
	_links[component.id] = {}
	for pair in neighbours_from_slots(state, component):
		var other: int = pair[0]
		if other == component.id or not state.components.has(other):
			continue
		var link: int = pair[1]
		(_links[component.id] as Dictionary)[other] = link
		if not _links.has(other):
			_links[other] = {}
		(_links[other] as Dictionary)[component.id] = mirror(link)


func remove_component(component_id: int) -> void:
	var mine: Dictionary = _links.get(component_id, {})
	for other in mine.keys():
		if _links.has(other):
			(_links[other] as Dictionary).erase(component_id)
	_links.erase(component_id)


func neighbours(component_id: int) -> Dictionary:
	return _links.get(component_id, {})


func link_count() -> int:
	var total := 0
	for value in _links.values():
		total += (value as Dictionary).size()
	return total / 2


## Returns [other_id, link] pairs from the component's point of view.
static func neighbours_from_slots(state: BuildingState, component: BuildComponent) -> Array:
	var found: Array = []
	match component.kind:
		BuildTypes.Kind.SLAB:
			var key: Vector3i = component.key
			var cell := Vector2i(key.x, key.z)
			var level := key.y
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_add(found, state.slab_at(GridSystem.slab_key(cell + offset, level)), Link.ADJACENT)
			for edge in GridSystem.cell_edges(cell, level):
				_add(found, state.edges.component_at(edge), Link.FLOOR_JOIN)
			for edge in GridSystem.cell_edges(cell, level - 1):
				_add(found, state.edges.component_at(edge), Link.RESTS_ON)
			for vertex in GridSystem.cell_vertices(cell):
				_add(found, state.post_at(GridSystem.post_key(vertex, level)), Link.FLOOR_JOIN)
				_add(found, state.post_at(GridSystem.post_key(vertex, level - 1)), Link.RESTS_ON)
			_add(found, state.stairs_at(key), Link.SUPPORTS)
			_add(found, int(state.stair_exits.get(key, 0)), Link.FLOOR_JOIN)
		BuildTypes.Kind.POST:
			var key: Vector3i = component.key
			var vertex := Vector2i(key.x, key.z)
			for edge in GridSystem.vertex_edges(vertex, key.y):
				_add(found, state.edges.component_at(edge), Link.ATTACHED)
			for cell in GridSystem.vertex_cells(vertex):
				_add(found, state.slab_at(GridSystem.slab_key(cell, key.y)), Link.FLOOR_JOIN)
				_add(found, state.slab_at(GridSystem.slab_key(cell, key.y + 1)), Link.SUPPORTS)
			_add(found, state.post_at(GridSystem.post_key(vertex, key.y - 1)), Link.RESTS_ON)
			_add(found, state.post_at(GridSystem.post_key(vertex, key.y + 1)), Link.SUPPORTS)
		BuildTypes.Kind.STAIRS:
			for cell in component.cells:
				_add(found, state.slab_at(cell), Link.RESTS_ON)
			for exit_key in state.stair_exits.keys():
				if int(state.stair_exits[exit_key]) == component.id:
					_add(found, state.slab_at(exit_key), Link.FLOOR_JOIN)
		_:
			var key: Vector4i = component.key
			for vertex in GridSystem.edge_vertices(key):
				_add(found, state.post_at(GridSystem.post_key(vertex, key.z)), Link.ATTACHED)
			for cell in GridSystem.edge_cells(key):
				_add(found, state.slab_at(GridSystem.slab_key(cell, key.z)), Link.FLOOR_JOIN)
				_add(found, state.slab_at(GridSystem.slab_key(cell, key.z + 1)), Link.SUPPORTS)
			_add(found, state.edges.component_at(Vector4i(key.x, key.y, key.z - 1, key.w)), Link.RESTS_ON)
			_add(found, state.edges.component_at(Vector4i(key.x, key.y, key.z + 1, key.w)), Link.SUPPORTS)
	return found


static func _add(found: Array, other: int, link: int) -> void:
	if other != 0:
		found.append([other, link])
