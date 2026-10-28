extends RefCounted
class_name RoomPlacer

## Builds ConstructionPlans. Planning reads BuildingState and never writes it,
## so the same code serves the client preview and the authoritative commit.
##
## Boundary rules (EdgeRegistry is the single owner of every boundary):
## - A room asks for a wall on each perimeter edge and for its overrides.
## - Existing piece of the same kind: REUSE (shared wall).
## - Room wants a wall where a doorway or window stands: REUSE (opening kept).
## - Room wants an opening where a wall stands: REPLACE the wall.
## - Room wants one opening where a different opening stands: CONFLICT.
## - Edge blueprints are explicit, so they REPLACE whatever piece is there.
## - Every new edge piece asks for posts at both ends; posts are shared.
## - Slabs are shared between the ceiling of one level and the floor of the
##   next. Stairwell cells never get a slab.
## - Rooms skip boundaries that stairs keep open; explicit edge pieces there
##   are a conflict.
## - Walls, doorways, and windows always stand on a floor on at least one
##   side: a slab, or the top of a stairwell. Rooms skip boundaries with no
##   floor; dismantling may not take away the last floor of an edge piece.

var grid: GridSystem
var geometry: BuildingGeometry
## Callable(aabb: AABB) -> String. Returns the blocker name, or "" when clear.
var obstruction_check: Callable

const STAIRS_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
## Local doubled midpoints of the stairs boundaries (stairs climb toward local -Z).
const STAIRS_TOP_EDGE := Vector2i(1, 0)
const STAIRS_CROSS_EDGES: Array[Vector2i] = [Vector2i(1, 2), Vector2i(1, 4)]
const STAIRS_BOTTOM_EDGE := Vector2i(1, 6)
const STAIRS_EXIT_CELL := Vector2i(0, -1)
const SIDE_STEPS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _init(grid_system: GridSystem, building_geometry: BuildingGeometry) -> void:
	grid = grid_system
	geometry = building_geometry


## size matters for resizable rooms and floors; zero means the default footprint.
static func make_request(blueprint_id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, target: int = 0, size := Vector2i.ZERO) -> Dictionary:
	return {"blueprint": blueprint_id, "anchor": anchor, "rotation": rotation, "level": level, "axis": axis, "target": target, "size": size}


func plan(state: BuildingState, blueprint: BlueprintDefinition, request: Dictionary) -> ConstructionPlan:
	var result := ConstructionPlan.new()
	result.blueprint = blueprint
	result.state_revision = state.revision
	var anchor: Vector2i = request.get("anchor", Vector2i.ZERO)
	var level := int(request.get("level", 0))
	var rotation := posmod(int(request.get("rotation", 0)), 4) if blueprint.rotatable else 0
	var axis := int(request.get("axis", 0))
	var requested: Variant = request.get("size", Vector2i.ZERO)
	var size := blueprint.size_for(requested if requested is Vector2i else Vector2i.ZERO)
	result.level = level
	result.rotation = rotation
	result.request = make_request(blueprint.id, anchor, rotation, level, axis, int(request.get("target", 0)), size)
	if level < 0 or level >= grid.config.max_levels:
		result.errors.append("Level %d is outside 0-%d" % [level, grid.config.max_levels - 1])
		return result
	match blueprint.kind:
		BuildTypes.BlueprintKind.ROOM:
			_plan_room(result, state, blueprint, size, anchor, rotation, level)
		BuildTypes.BlueprintKind.EDGE:
			_plan_edge(result, state, blueprint, anchor, axis, level)
		BuildTypes.BlueprintKind.SLAB:
			_plan_slabs(result, state, blueprint, size, anchor, level)
		BuildTypes.BlueprintKind.STAIRS:
			_plan_stairs(result, state, anchor, rotation, level)
		BuildTypes.BlueprintKind.SUPPORT:
			_plan_support(result, state, anchor, level)
		BuildTypes.BlueprintKind.DISMANTLE:
			_plan_dismantle(result, state, int(request.get("target", 0)))
	if result.errors.is_empty():
		_check_obstructions(result)
	_compute_cost(result)
	result.sort_entries()
	return result


# --- rooms -------------------------------------------------------------------

func _plan_room(result: ConstructionPlan, state: BuildingState, blueprint: BlueprintDefinition, size: Vector2i, anchor: Vector2i, rotation: int, level: int) -> void:
	var local_cells := BlueprintDefinition.cells_of(size)
	var world_cells: Array[Vector2i] = []
	for local in local_cells:
		world_cells.append(GridSystem.local_cell_to_world(local, size, rotation, anchor))
	result.footprint_cells = world_cells
	result.front = GridSystem.rotate_doubled(Vector2i(0, 1), rotation)
	if not _cells_in_bounds(world_cells):
		result.errors.append("Outside the build area")
		return
	if blueprint.has_ceiling and level + 1 > grid.config.max_levels:
		result.errors.append("No room for a ceiling above level %d" % level)
		return
	var identical := 0
	var others := PackedInt32Array()
	for cell in world_cells:
		var claim := GridSystem.slab_key(cell, level)
		result.room_cells.append(claim)
		var owner := state.room_at(claim)
		if owner == 0:
			continue
		if _same_room(state, owner, result.request):
			identical = owner
		elif not others.has(owner):
			others.append(owner)
	if not others.is_empty():
		result.errors.append("Overlaps room #%d" % others[0])
	elif identical != 0:
		result.reused_room = identical
	if blueprint.has_floor:
		for cell in world_cells:
			_want_slab(result, state, GridSystem.slab_key(cell, level), true)
	if blueprint.has_ceiling:
		for cell in world_cells:
			_want_slab(result, state, GridSystem.slab_key(cell, level + 1), true)
	var overrides := {}
	for item in blueprint.openings:
		var opening := item as BlueprintOpening
		if opening != null:
			overrides[GridSystem.side_doubled(opening.cell, opening.side)] = opening.kind
	var inside := Rect2i(Vector2i.ZERO, size)
	for local in local_cells:
		for side in 4:
			var local_edge := GridSystem.side_doubled(local, side)
			var desired := -2
			if overrides.has(local_edge):
				desired = int(overrides[local_edge])
			elif not inside.has_point(local + SIDE_STEPS[side]):
				desired = BuildTypes.Kind.WALL
			else:
				continue
			var key := GridSystem.doubled_to_edge(GridSystem.to_world_doubled(local_edge, size, rotation, anchor), level)
			if not _edge_gets_floor(result, state, key):
				result.add_entry(BuildTypes.Action.SKIP, desired, key, 0, "No floor beside this boundary")
				continue
			_want_edge(result, state, key, desired, false)
	if level > 0 and not _cells_supported(state, world_cells, level):
		result.errors.append("Needs support: build walls or posts below, or connect to a floor at this level")


func _same_room(state: BuildingState, room_id: int, request: Dictionary) -> bool:
	var room: Dictionary = state.rooms.get(room_id, {})
	if room.is_empty():
		return false
	var placed: Dictionary = room["request"]
	return (
		str(placed["blueprint"]) == str(request["blueprint"])
		and placed["anchor"] == request["anchor"]
		and int(placed["rotation"]) == int(request["rotation"])
		and int(placed["level"]) == int(request["level"])
		and placed.get("size", Vector2i.ZERO) == request.get("size", Vector2i.ZERO)
	)


# --- single pieces -----------------------------------------------------------

func _plan_edge(result: ConstructionPlan, state: BuildingState, blueprint: BlueprintDefinition, anchor: Vector2i, axis: int, level: int) -> void:
	if axis != BuildTypes.AXIS_X and axis != BuildTypes.AXIS_Z:
		result.errors.append("Diagonal boundaries are not supported yet")
		return
	var key := Vector4i(anchor.x, anchor.y, level, axis)
	for vertex in GridSystem.edge_vertices(key):
		if not _vertex_in_bounds(vertex):
			result.errors.append("Outside the build area")
			return
	_want_edge(result, state, key, blueprint.edge_kind, true)
	if not state.edge_has_floor(key):
		result.errors.append("Needs a floor / ceiling slab beside it")


func _plan_slabs(result: ConstructionPlan, state: BuildingState, blueprint: BlueprintDefinition, size: Vector2i, anchor: Vector2i, level: int) -> void:
	var slab_level := level + blueprint.slab_level_offset
	var cells: Array[Vector2i] = []
	for local in BlueprintDefinition.cells_of(size):
		cells.append(anchor + local)
	result.footprint_cells = cells
	if not _cells_in_bounds(cells):
		result.errors.append("Outside the build area")
		return
	if slab_level > grid.config.max_levels:
		result.errors.append("Too high")
		return
	for cell in cells:
		_want_slab(result, state, GridSystem.slab_key(cell, slab_level), false)
	if slab_level > 0 and not _cells_supported(state, cells, slab_level):
		result.errors.append("Needs support: walls or posts below, or a floor beside it")


func _plan_support(result: ConstructionPlan, state: BuildingState, vertex: Vector2i, level: int) -> void:
	if not _vertex_in_bounds(vertex):
		result.errors.append("Outside the build area")
		return
	var key := GridSystem.post_key(vertex, level)
	_want_post(result, state, key, true)
	var existing := state.get_component(state.post_at(key))
	if existing != null and not existing.pinned:
		result.entry_for(BuildTypes.Kind.POST, key)["reason"] = "Existing post becomes a support"
		result.pin_changes += 1
	if level > 0 and not _vertex_supported(state, vertex, level):
		result.errors.append("Needs support: a post below or a floor beside it")


func _plan_stairs(result: ConstructionPlan, state: BuildingState, anchor: Vector2i, rotation: int, level: int) -> void:
	var size := GridSystem.STAIRS_SIZE
	var key := Vector4i(anchor.x, anchor.y, level, rotation)
	var cells: Array[Vector2i] = []
	for local in STAIRS_CELLS:
		cells.append(GridSystem.local_cell_to_world(local, size, rotation, anchor))
	result.footprint_cells = cells
	result.front = GridSystem.rotate_doubled(Vector2i(0, -1), rotation)
	if not _cells_in_bounds(cells):
		result.errors.append("Outside the build area")
		return
	if level + 1 >= grid.config.max_levels:
		result.errors.append("No level above to climb to")
		return
	for cell in cells:
		var existing_stairs := state.stairs_at(GridSystem.slab_key(cell, level))
		if existing_stairs == 0:
			continue
		var other := state.get_component(existing_stairs)
		if other != null and other.key == key:
			result.add_entry(BuildTypes.Action.REUSE, BuildTypes.Kind.STAIRS, key, existing_stairs, "These stairs already stand here")
			return
		result.errors.append("Other stairs already use these cells")
		return
	var covered: Array[Vector3i] = []
	for cell in cells:
		var floor_key := GridSystem.slab_key(cell, level)
		covered.append(floor_key)
		var floor_id := state.slab_at(floor_key)
		if floor_id == 0:
			result.add_entry(BuildTypes.Action.CONFLICT, BuildTypes.Kind.SLAB, floor_key, 0, "Stairs need a floor slab under every cell")
		else:
			result.add_entry(BuildTypes.Action.REUSE, BuildTypes.Kind.SLAB, floor_key, floor_id, "Stairs rest on this slab")
		var upper_key := GridSystem.slab_key(cell, level + 1)
		var upper_id := state.slab_at(upper_key)
		if upper_id != 0:
			if state.stairs_at(upper_key) != 0:
				result.add_entry(BuildTypes.Action.CONFLICT, BuildTypes.Kind.SLAB, upper_key, upper_id, "Stairs above use this slab")
			else:
				result.add_entry(BuildTypes.Action.REMOVE, BuildTypes.Kind.SLAB, upper_key, upper_id, "Opened for the stairwell")
	# The bottom entry stays fully open: a doorway lintel there cuts the
	# headroom of a player who is already climbing the first step.
	var rules: Array = []
	rules.append([_stairs_edge(STAIRS_TOP_EDGE, rotation, anchor, level), 0])
	for cross in STAIRS_CROSS_EDGES:
		rules.append([_stairs_edge(cross, rotation, anchor, level), 0])
	rules.append([_stairs_edge(STAIRS_BOTTOM_EDGE, rotation, anchor, level), 0])
	rules.append([_stairs_edge(STAIRS_TOP_EDGE, rotation, anchor, level + 1), 1 << BuildTypes.Kind.DOORWAY])
	# A wall one level up across the flight would hit a climbing player's head.
	for cross in STAIRS_CROSS_EDGES:
		rules.append([_stairs_edge(cross, rotation, anchor, level + 1), 0])
	for rule in rules:
		var edge: Vector4i = rule[0]
		var piece := state.get_component(state.edges.component_at(edge))
		if piece != null and (int(rule[1]) & (1 << piece.kind)) == 0:
			result.add_entry(BuildTypes.Action.CONFLICT, piece.kind, edge, piece.id, "Stairs need this boundary open")
	var exit_cell := GridSystem.local_cell_to_world(STAIRS_EXIT_CELL, size, rotation, anchor)
	var entry := result.add_entry(BuildTypes.Action.CREATE, BuildTypes.Kind.STAIRS, key)
	entry["cells"] = covered
	entry["exit"] = GridSystem.slab_key(exit_cell, level + 1)
	entry["rules"] = rules


func _stairs_edge(local_doubled: Vector2i, rotation: int, anchor: Vector2i, level: int) -> Vector4i:
	return GridSystem.doubled_to_edge(GridSystem.to_world_doubled(local_doubled, GridSystem.STAIRS_SIZE, rotation, anchor), level)


func _plan_dismantle(result: ConstructionPlan, state: BuildingState, target: int) -> void:
	var component := state.get_component(target)
	if component == null:
		result.errors.append("Nothing to dismantle here")
		return
	var entry := result.add_entry(BuildTypes.Action.REMOVE, component.kind, component.key, component.id, "Will be removed")
	var blocked := state.removal_block_reason(component)
	if blocked != "":
		ConstructionPlan.conflict(entry, blocked)
		return
	if BuildTypes.is_edge_kind(component.kind):
		var key: Vector4i = component.key
		for vertex in GridSystem.edge_vertices(key):
			var post := state.get_component(state.post_at(GridSystem.post_key(vertex, key.z)))
			if post == null or post.pinned:
				continue
			var other_edges := 0
			for edge in GridSystem.vertex_edges(vertex, key.z):
				if edge != key and state.edges.has_piece(edge):
					other_edges += 1
			if other_edges == 0:
				result.add_entry(BuildTypes.Action.REMOVE, BuildTypes.Kind.POST, post.key, post.id, "Unused corner post")


# --- slot requests -----------------------------------------------------------

func _want_slab(result: ConstructionPlan, state: BuildingState, key: Vector3i, skip_stairwell: bool) -> void:
	if not result.entry_for(BuildTypes.Kind.SLAB, key).is_empty():
		return
	if state.stairwell_at(key) != 0:
		if skip_stairwell:
			result.add_entry(BuildTypes.Action.SKIP, BuildTypes.Kind.SLAB, key, 0, "Stairwell opening")
		else:
			result.add_entry(BuildTypes.Action.CONFLICT, BuildTypes.Kind.SLAB, key, 0, "Stairwell opening here")
		return
	var existing := state.slab_at(key)
	if existing != 0:
		result.add_entry(BuildTypes.Action.REUSE, BuildTypes.Kind.SLAB, key, existing, "Existing slab")
	else:
		result.add_entry(BuildTypes.Action.CREATE, BuildTypes.Kind.SLAB, key)


func _want_edge(result: ConstructionPlan, state: BuildingState, key: Vector4i, desired: int, explicit: bool) -> void:
	if not result.entry_for(BuildTypes.Kind.WALL, key).is_empty():
		return
	var existing_id := state.edges.component_at(key)
	var existing := state.get_component(existing_id)
	if desired == BuildTypes.EDGE_OPEN:
		if existing != null:
			result.add_entry(BuildTypes.Action.REUSE, existing.kind, key, existing_id, "Existing boundary kept")
		return
	if not state.edges.allows(key, desired):
		if explicit:
			result.add_entry(BuildTypes.Action.CONFLICT, desired, key, existing_id, "Stairs need this boundary open")
		else:
			result.add_entry(BuildTypes.Action.SKIP, desired, key, 0, "Stairs keep this boundary open")
		return
	if existing == null:
		result.add_entry(BuildTypes.Action.CREATE, desired, key)
	elif existing.kind == desired:
		result.add_entry(BuildTypes.Action.REUSE, desired, key, existing_id, "Shared boundary")
		return
	elif explicit:
		var swap := result.add_entry(BuildTypes.Action.REPLACE, desired, key, existing_id, "Replaces the %s" % BuildTypes.kind_name(existing.kind).to_lower())
		swap["existing_kind"] = existing.kind
	elif desired == BuildTypes.Kind.WALL:
		result.add_entry(BuildTypes.Action.REUSE, existing.kind, key, existing_id, "Existing opening kept")
		return
	elif existing.kind == BuildTypes.Kind.WALL:
		var swap := result.add_entry(BuildTypes.Action.REPLACE, desired, key, existing_id, "Replaces the wall")
		swap["existing_kind"] = existing.kind
	else:
		result.add_entry(BuildTypes.Action.CONFLICT, desired, key, existing_id, "Boundary already has a %s" % BuildTypes.kind_name(existing.kind).to_lower())
		return
	for vertex in GridSystem.edge_vertices(key):
		_want_post(result, state, GridSystem.post_key(vertex, key.z), false)


func _want_post(result: ConstructionPlan, state: BuildingState, key: Vector3i, pinned: bool) -> void:
	var entry := result.entry_for(BuildTypes.Kind.POST, key)
	if entry.is_empty():
		var existing := state.post_at(key)
		if existing != 0:
			entry = result.add_entry(BuildTypes.Action.REUSE, BuildTypes.Kind.POST, key, existing, "Shared corner post")
		else:
			entry = result.add_entry(BuildTypes.Action.CREATE, BuildTypes.Kind.POST, key)
	if pinned:
		entry["pinned"] = true


# --- validation --------------------------------------------------------------

func _cells_in_bounds(cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not grid.in_bounds(cell):
			return false
	return true


func _vertex_in_bounds(vertex: Vector2i) -> bool:
	var low := grid.config.build_min_cell
	var high := grid.config.build_max_cell + Vector2i.ONE
	return vertex.x >= low.x and vertex.y >= low.y and vertex.x <= high.x and vertex.y <= high.y


## Upper-level pieces must touch something already built: a slab on the same
## level in or beside the footprint, or a wall or post on the level below.
func _cells_supported(state: BuildingState, cells: Array[Vector2i], level: int) -> bool:
	for cell in cells:
		if state.slab_at(GridSystem.slab_key(cell, level)) != 0:
			return true
		for step in SIDE_STEPS:
			if state.slab_at(GridSystem.slab_key(cell + step, level)) != 0:
				return true
		for edge in GridSystem.cell_edges(cell, level - 1):
			if state.edges.has_piece(edge):
				return true
		for vertex in GridSystem.cell_vertices(cell):
			if state.post_at(GridSystem.post_key(vertex, level - 1)) != 0:
				return true
	return false


## A room boundary has a floor when this plan builds or keeps a slab beside it,
## or a slab or stairwell top already is there.
func _edge_gets_floor(result: ConstructionPlan, state: BuildingState, key: Vector4i) -> bool:
	for cell in GridSystem.edge_cells(key):
		var slab := GridSystem.slab_key(cell, key.z)
		if state.stairwell_at(slab) != 0:
			return true
		var entry := result.entry_for(BuildTypes.Kind.SLAB, slab)
		if not entry.is_empty():
			var action := int(entry["action"])
			if action == BuildTypes.Action.CREATE or action == BuildTypes.Action.REUSE:
				return true
		elif state.slab_at(slab) != 0:
			return true
	return false


func _vertex_supported(state: BuildingState, vertex: Vector2i, level: int) -> bool:
	if state.post_at(GridSystem.post_key(vertex, level - 1)) != 0:
		return true
	if state.vertex_has_edges(vertex, level - 1):
		return true
	for cell in GridSystem.vertex_cells(vertex):
		if state.slab_at(GridSystem.slab_key(cell, level)) != 0:
			return true
	return false


func _check_obstructions(result: ConstructionPlan) -> void:
	if not obstruction_check.is_valid() or geometry == null:
		return
	var boxes: Array = []
	var union := AABB()
	for entry in result.entries:
		var action := int(entry["action"])
		if action != BuildTypes.Action.CREATE and action != BuildTypes.Action.REPLACE:
			continue
		var kind := int(entry["kind"])
		var box := geometry.world_aabb(kind, grid.transform_for(kind, entry["key"]))
		union = box if boxes.is_empty() else union.merge(box)
		boxes.append([entry, box])
	if boxes.is_empty() or str(obstruction_check.call(union)) == "":
		return
	for pair in boxes:
		var blocker := str(obstruction_check.call(pair[1]))
		if blocker != "":
			ConstructionPlan.conflict(pair[0], "Blocked by %s" % blocker)


func _compute_cost(result: ConstructionPlan) -> void:
	var total := 0
	for entry in result.entries:
		var action := int(entry["action"])
		if action == BuildTypes.Action.CREATE or action == BuildTypes.Action.REPLACE:
			total += grid.config.cost_of(int(entry["kind"]))
	if total > 0:
		result.cost = {grid.config.cost_item_id: total}
