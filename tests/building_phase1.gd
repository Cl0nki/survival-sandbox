extends SceneTree

## Headless regression suite for Phase 1 building (grid, rooms, blueprints,
## Build Tool, preview, seamless construction).
## godot --headless --path <project> --script res://tests/building_phase1.gd
## Every section builds a fresh BuildingSystem on a flat ground body and runs
## GeometryAudit (slots, nodes, exact transforms, collision overlaps, coplanar
## faces, winding, joints, graph, preview bodies) where geometry changed.

var _stage: Node3D
var _failures := PackedStringArray()
var _checks := 0
var _section := ""


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("BUILDING_PHASE1 timed out in section ", _section)
		quit(2), CONNECT_ONE_SHOT)
	await _body()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("BUILDING_PHASE1_OK")
		quit(0)
	else:
		quit(1)


func _body() -> void:
	_test_catalog_and_config()
	_test_grid_math()
	_test_single_room()
	_test_adjacent_rooms()
	_test_four_room_corner()
	_test_large_rectangles()
	_test_repeated_placement()
	_test_rotations()
	_test_snapping()
	_test_drag_rooms()
	_test_doors_and_windows()
	_test_floors_and_ceilings()
	_test_stacked_levels()
	await _test_stairs()
	_test_walls_need_floor()
	_test_preview_isolation()
	_test_rapid_preview()
	await _test_rejections()
	_test_resources()
	_test_dismantle()
	await _test_physics_stability()
	_test_showcase()
	_test_audit_detects_faults()
	await _test_arena_integration()
	if _stage != null:
		_stage.free()
		_stage = null


# --- helpers -----------------------------------------------------------------

func _begin(section: String, config: BuildingConfig = null) -> BuildingSystem:
	_section = section
	print("-- ", section)
	if _stage != null:
		_stage.free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	root.add_child(_stage)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = PhysicsLayers.WORLD
	ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	_stage.add_child(ground)
	var system := BuildingSystem.new()
	if config != null:
		system.config = config
	_stage.add_child(system)
	return system


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_section, message])
	return condition


func _place(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> Dictionary:
	return system.authority.request_place(RoomPlacer.make_request(id, anchor, rotation, level, axis, 0, size))


func _plan(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> ConstructionPlan:
	return system.authority.make_plan(RoomPlacer.make_request(id, anchor, rotation, level, axis, 0, size))


func _built(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> Dictionary:
	var result := _place(system, id, anchor, rotation, level, axis, size)
	_check(bool(result["ok"]) and bool(result["changed"]), "%s %s at %s rot %d level %d was not built: %s" % [id, size, anchor, rotation, level, result["reason"]])
	return result


func _audit(system: BuildingSystem, label: String) -> void:
	var report := GeometryAudit.run(system)
	_check(bool(report["ok"]), "%s\n%s" % [label, GeometryAudit.describe(report, 12)])
	_check(int(report["nodes"]) == system.state.component_count(), "%s: %d nodes for %d pieces" % [label, int(report["nodes"]), system.state.component_count()])


func _counts(system: BuildingSystem) -> String:
	var state := system.state
	return "slabs=%d walls=%d doorways=%d windows=%d posts=%d stairs=%d" % [
		state.count_kind(BuildTypes.Kind.SLAB), state.count_kind(BuildTypes.Kind.WALL),
		state.count_kind(BuildTypes.Kind.DOORWAY), state.count_kind(BuildTypes.Kind.WINDOW),
		state.count_kind(BuildTypes.Kind.POST), state.count_kind(BuildTypes.Kind.STAIRS),
	]


func _expect_counts(system: BuildingSystem, expected: String, label: String) -> void:
	var actual := _counts(system)
	_check(actual == expected, "%s: expected %s, got %s" % [label, expected, actual])


func _edge_piece(system: BuildingSystem, key: Vector4i) -> BuildComponent:
	return system.state.get_component(system.state.edges.component_at(key))


func _tool(system: BuildingSystem) -> BuildTool:
	var tool := BuildTool.new()
	_stage.add_child(tool)
	tool.setup(system)
	tool.set_equipped(true)
	return tool


func _bodies_under(node: Node) -> int:
	return node.find_children("*", "CollisionObject3D", true, false).size()


# --- 0. data and math ----------------------------------------------------------

func _test_catalog_and_config() -> void:
	_section = "catalog"
	print("-- ", _section)
	_check(BuildingSystem.DEFAULT_CONFIG.validate().is_empty(), "default config invalid: %s" % ", ".join(BuildingSystem.DEFAULT_CONFIG.validate()))
	var problems := BlueprintCatalog.load_problems()
	_check(problems.is_empty(), "catalog problems: %s" % ", ".join(problems))
	_check(BlueprintCatalog.all().size() == BlueprintCatalog.FILES.size(), "catalog loaded %d of %d" % [BlueprintCatalog.all().size(), BlueprintCatalog.FILES.size()])
	_check(ItemCatalog.get_item("build_tool") != null, "build_tool item missing")


func _test_grid_math() -> void:
	_section = "grid math"
	print("-- ", _section)
	for steps in 4:
		var basis := GridSystem.rotation_basis(steps)
		for column in 3:
			for row in 3:
				var value := basis[column][row]
				_check(value == 0.0 or value == 1.0 or value == -1.0, "basis %d has inexact entry %f" % [steps, value])
		_check(basis.determinant() == 1.0, "basis %d is not a pure rotation" % steps)
	_check(GridSystem.rotate_doubled(Vector2i(3, -5), 4) == Vector2i(3, -5), "four turns are not identity")
	var size := Vector2i(3, 2)
	for steps in 4:
		var anchor := Vector2i(-4, 7)
		var seen := {}
		var low := Vector2i(1 << 20, 1 << 20)
		var high := Vector2i(-(1 << 20), -(1 << 20))
		for x in size.x:
			for z in size.y:
				var cell := GridSystem.local_cell_to_world(Vector2i(x, z), size, steps, anchor)
				seen[cell] = true
				low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
				high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
		_check(seen.size() == 6, "rotation %d footprint has %d cells" % [steps, seen.size()])
		_check(low == anchor, "rotation %d footprint min %s != anchor" % [steps, low])
		_check(high - low + Vector2i.ONE == GridSystem.rotated_size(size, steps), "rotation %d extent %s" % [steps, high - low + Vector2i.ONE])
	var grid := GridSystem.new(BuildingSystem.DEFAULT_CONFIG)
	_check(grid.world_to_cell(Vector3(-0.01, 0.0, -0.99)) == Vector2i(-1, -1), "negative world_to_cell")
	_check(grid.world_to_cell(Vector3(0.0, 0.0, 0.0)) == Vector2i(0, 0), "origin world_to_cell")
	for key: Vector4i in [Vector4i(2, -3, 0, BuildTypes.AXIS_Z), Vector4i(-4, 5, 1, BuildTypes.AXIS_X)]:
		_check(GridSystem.doubled_to_edge(GridSystem.edge_to_doubled(key), key.z) == key, "edge round trip %s" % key)
	var wall := grid.edge_transform(Vector4i(2, -3, 1, BuildTypes.AXIS_Z))
	_check(wall.origin == Vector3(2.0, 3.0, -2.5), "AXIS_Z wall origin %s" % wall.origin)
	_check(grid.post_transform(Vector3i(-1, 0, 4)).origin == Vector3(-1.0, 0.0, 4.0), "post origin")


# --- 1-4. rooms ------------------------------------------------------------------

func _test_single_room() -> void:
	var system := _begin("1 single room")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_expect_counts(system, "slabs=2 walls=4 doorways=0 windows=0 posts=4 stairs=0", "single room")
	_check(system.world.node_count() == 10, "single room spawned %d nodes" % system.world.node_count())
	_check(system.state.slab_at(GridSystem.slab_key(Vector2i(0, 0), 1)) != 0, "room has no ceiling")
	_check(system.state.edges.rejected_claims == 0, "edge registry refused a claim")
	_audit(system, "single room")


func _test_adjacent_rooms() -> void:
	var system := _begin("2 adjacent rooms share a wall")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var plan := _plan(system, "room", Vector2i(1, 0), 0, 0, 0, Vector2i(1, 1))
	_check(plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.WALL) == 1, "second room reuses %d walls" % plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.WALL))
	_check(plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.POST) == 2, "second room reuses %d posts" % plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.POST))
	_check(plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.WALL) == 3, "second room creates %d walls" % plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.WALL))
	_check(plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.POST) == 2, "second room creates %d posts" % plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.POST))
	_built(system, "room", Vector2i(1, 0), 0, 0, 0, Vector2i(1, 1))
	_expect_counts(system, "slabs=4 walls=7 doorways=0 windows=0 posts=6 stairs=0", "two rooms")
	var shared := _edge_piece(system, Vector4i(1, 0, 0, BuildTypes.AXIS_Z))
	_check(shared != null and shared.rooms.size() == 2, "shared wall is not referenced by both rooms")
	_check(system.state.edges.rejected_claims == 0, "edge registry refused a claim")
	_audit(system, "two rooms")


func _test_four_room_corner() -> void:
	var system := _begin("3 four rooms meet at a corner")
	for anchor: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_built(system, "room", anchor, 0, 0, 0, Vector2i(1, 1))
	_expect_counts(system, "slabs=8 walls=12 doorways=0 windows=0 posts=9 stairs=0", "four rooms")
	var centre := system.state.post_at(GridSystem.post_key(Vector2i(1, 1), 0))
	var attached := 0
	for edge in GridSystem.vertex_edges(Vector2i(1, 1), 0):
		var piece := system.state.edges.component_at(edge)
		var links := system.state.graph.neighbours(centre)
		if piece != 0 and links.get(piece, -1) == ConstructionGraph.Link.ATTACHED:
			attached += 1
	_check(attached == 4, "centre post attached to %d walls" % attached)
	_audit(system, "four rooms")


func _test_large_rectangles() -> void:
	var system := _begin("4 multiple rooms form larger rectangles")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(3, 3))
	_built(system, "room", Vector2i(3, 0), 0, 0, 0, Vector2i(3, 3))
	_expect_counts(system, "slabs=36 walls=21 doorways=0 windows=0 posts=20 stairs=0", "6x3 from two rooms")
	for x in 3:
		for z in 3:
			_built(system, "room", Vector2i(x, 5 + z), 0, 0, 0, Vector2i(1, 1))
	_expect_counts(system, "slabs=54 walls=45 doorways=0 windows=0 posts=36 stairs=0", "plus 3x3 of single rooms")
	_built(system, "room", Vector2i(6, 0), 0, 0, 0, Vector2i(2, 2))
	_built(system, "room", Vector2i(8, 0), 0, 0, 0, Vector2i(1, 1))
	_expect_counts(system, "slabs=64 walls=54 doorways=0 windows=0 posts=43 stairs=0", "plus 2x2 and 1x1 against the 3x3")
	_check(system.state.edges.rejected_claims == 0, "edge registry refused a claim")
	_audit(system, "large rectangles")


# --- 5-6. idempotency, rotation, snapping ---------------------------------------

func _test_repeated_placement() -> void:
	var system := _begin("5 repeated placement is idempotent")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	var checksum := system.state.checksum()
	var revision := system.state.revision
	var spawned := system.world.spawned_total
	for _i in 3:
		var again := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
		_check(bool(again["ok"]) and not bool(again["changed"]), "repeat placement changed state: %s" % again["reason"])
	_check(system.state.checksum() == checksum, "checksum changed on repeat placement")
	_check(system.state.revision == revision, "revision changed on repeat placement")
	_check(system.world.spawned_total == spawned, "repeat placement spawned nodes")
	var overlap := _place(system, "room", Vector2i(1, 1), 0, 0, 0, Vector2i(1, 1))
	_check(not bool(overlap["ok"]) and str(overlap["reason"]).begins_with("Overlaps room"), "overlapping room not rejected: %s" % overlap["reason"])
	var north := _edge_piece(system, Vector4i(1, 0, 0, BuildTypes.AXIS_X))
	var removed := system.authority.request_remove(north.id)
	_check(bool(removed["ok"]), "could not remove a wall: %s" % removed["reason"])
	var repair := _plan(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	_check(repair.count(BuildTypes.Action.CREATE) == 1 and repair.count(BuildTypes.Action.CREATE, BuildTypes.Kind.WALL) == 1, "repair plan creates %d pieces" % repair.count(BuildTypes.Action.CREATE))
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	_expect_counts(system, "slabs=8 walls=8 doorways=0 windows=0 posts=8 stairs=0", "after repair")
	_audit(system, "repeated placement")


func _test_rotations() -> void:
	var system := _begin("6 rotation in 90 degree steps")
	var points := system.geometry.stairs_points()
	for steps in 4:
		var floor_anchor := Vector2i(-12 + steps * 4, 0)
		for cell in BlueprintDefinition.cells_of(Vector2i(3, 3)):
			_built(system, "floor_1x1", floor_anchor + cell)
		var anchor := floor_anchor + (Vector2i(1, 0) if steps % 2 == 0 else Vector2i(0, 1))
		var plan := _plan(system, "stairs_straight", anchor, steps)
		_check(plan.is_valid(), "stairs rotation %d invalid: %s" % [steps, plan.first_reason()])
		var size := GridSystem.rotated_size(GridSystem.STAIRS_SIZE, steps)
		var low := Vector2i(1 << 20, 1 << 20)
		var high := -low
		for cell in plan.footprint_cells:
			low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
			high = Vector2i(maxi(high.x, cell.x + 1), maxi(high.y, cell.y + 1))
		_check(low == anchor and high - low == size, "stairs rotation %d footprint %s..%s" % [steps, low, high])
		var xform := system.grid.stairs_transform(Vector4i(anchor.x, anchor.y, 0, steps))
		var top := xform * points[4]
		var front := Vector2(plan.front)
		var reach := Vector2(top.x, top.z).dot(front)
		var far := maxf(Vector2(low).dot(front), Vector2(high).dot(front))
		_check(is_equal_approx(reach, far), "stairs rotation %d does not climb toward its front %s" % [steps, plan.front])
		_built(system, "stairs_straight", anchor, steps)
	_check(system.state.count_kind(BuildTypes.Kind.STAIRS) == 4, "four rotated stairs")
	_audit(system, "rotations")


func _test_snapping() -> void:
	var system := _begin("6b snapping and hysteresis")
	var tool := _tool(system)
	tool.select_by_id("room")
	tool.update_aim(Vector3(0.5, 0.0, 0.5))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0), "centre aim anchor %s" % tool.current_request.get("anchor"))
	tool.update_aim(Vector3(1.1, 0.0, 0.5))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0), "hysteresis did not hold the anchor")
	tool.update_aim(Vector3(1.2, 0.0, 0.5))
	_check(tool.current_request.get("anchor") == Vector2i(1, 0), "anchor did not move past the hysteresis band")
	tool.update_aim(Vector3(0.9, 0.0, 0.5))
	_check(tool.current_request.get("anchor") == Vector2i(1, 0), "anchor flipped back inside the band")
	var plans := tool.plans_built
	var changes := 0
	var last: Variant = tool.current_request.get("anchor")
	for i in 200:
		tool.update_aim(Vector3(1.0 + (0.03 if i % 2 == 0 else -0.03), 0.0, 0.5 + (0.02 if i % 3 == 0 else -0.02)))
		if tool.current_request.get("anchor") != last:
			changes += 1
			last = tool.current_request.get("anchor")
	_check(changes == 0, "anchor flickered %d times at a boundary" % changes)
	_check(tool.plans_built == plans, "plans rebuilt %d times without a request change" % (tool.plans_built - plans))
	var same := tool.preview.rebuilds
	tool.update_aim(Vector3(0.9, 0.0, 0.5))
	_check(tool.preview.rebuilds == same, "preview rebuilt without a signature change")
	tool.select_by_id("wall")
	tool.update_aim(Vector3(0.5, 0.0, 0.05))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0) and int(tool.current_request.get("axis")) == BuildTypes.AXIS_X, "edge snap %s" % str(tool.current_request))
	tool.update_aim(Vector3(0.5, 0.0, 0.52))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0), "edge hysteresis did not hold")
	tool.update_aim(Vector3(0.5, 0.0, 0.62))
	_check(tool.current_request.get("anchor") == Vector2i(0, 1), "edge did not move to the next boundary")
	tool.update_aim(Vector3(0.05, 0.0, 1.5))
	_check(int(tool.current_request.get("axis")) == BuildTypes.AXIS_Z and tool.current_request.get("anchor") == Vector2i(0, 1), "vertical edge snap %s" % str(tool.current_request))


func _test_drag_rooms() -> void:
	var system := _begin("6c rooms sized by dragging")
	var tool := _tool(system)
	tool.select_by_id("wall")
	tool.update_aim(Vector3(0.5, 0.0, 0.05))
	_check(not tool.begin_drag(), "a wall started a size drag")
	tool.select_by_id("room")
	tool.update_aim(Vector3(0.5, 0.0, 0.5))
	_check(tool.current_request.get("size") == Vector2i(1, 1), "hover is not 1x1: %s" % str(tool.current_request))
	_check(tool.begin_drag() and tool.is_dragging(), "drag did not start")
	_check(tool.current_request.get("size") == Vector2i(1, 1), "drag start is not 1x1")
	tool.update_aim(Vector3(3.5, 0.0, 2.5))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0) and tool.current_request.get("size") == Vector2i(4, 3), "drag to (3, 2): %s" % str(tool.current_request))
	tool.update_aim(Vector3(-1.5, 0.0, -0.5))
	_check(tool.current_request.get("anchor") == Vector2i(-2, -1) and tool.current_request.get("size") == Vector2i(3, 2), "drag back past the start: %s" % str(tool.current_request))
	tool.update_aim(Vector3(20.5, 0.0, 0.5))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0) and tool.current_request.get("size") == Vector2i(8, 1), "drag is not clamped to 8 cells: %s" % str(tool.current_request))
	var checksum := system.state.checksum()
	tool.cancel_drag()
	_check(not tool.is_dragging() and system.state.checksum() == checksum, "cancelled drag changed something")
	_check(tool.current_request.get("size") == Vector2i(1, 1), "hover after cancel is not 1x1")
	tool.update_aim(Vector3(0.5, 0.0, 0.5))
	tool.begin_drag()
	tool.update_aim(Vector3(3.5, 0.0, 2.5))
	var built := tool.end_drag()
	_check(bool(built.get("ok", false)) and bool(built.get("changed", false)), "dragged 4x3 room not built: %s" % built.get("reason", "no plan"))
	_check(not tool.is_dragging(), "drag still active after building")
	_expect_counts(system, "slabs=24 walls=14 doorways=0 windows=0 posts=14 stairs=0", "dragged 4x3 room")
	tool.update_aim(Vector3(4.5, 0.0, 0.5))
	tool.begin_drag()
	_check(bool(tool.end_drag().get("changed", false)), "click without moving did not build a 1x1 room")
	_expect_counts(system, "slabs=26 walls=17 doorways=0 windows=0 posts=16 stairs=0", "1x1 room beside the 4x3 room")
	var again := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(4, 3))
	_check(bool(again["ok"]) and not bool(again["changed"]), "same dragged room again changed the state")
	var smaller := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	_check(not bool(smaller["ok"]), "smaller room inside the 4x3 room accepted")
	var huge := _plan(system, "room", Vector2i(-10, -10), 0, 0, 0, Vector2i(50, 50))
	_check(huge.request.get("size") == Vector2i(8, 8), "oversized request not clamped: %s" % huge.request.get("size"))
	var empty := _plan(system, "room", Vector2i(-10, -10), 0, 0, 0, Vector2i(0, -3))
	_check(empty.request.get("size") == Vector2i(1, 1), "invalid size not reset to 1x1: %s" % empty.request.get("size"))
	_audit(system, "dragged rooms")


# --- 7. doors and windows ---------------------------------------------------------

func _test_doors_and_windows() -> void:
	var system := _begin("7 doors and windows replace walls")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var plan := _plan(system, "room", Vector2i(0, -2), 0, 0, 0, Vector2i(2, 2))
	_check(plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.WALL) == 1, "neighbour room does not reuse the shared wall")
	_check(plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.DOORWAY) + plan.count(BuildTypes.Action.CREATE, BuildTypes.Kind.WINDOW) == 0, "room blueprint brought its own openings")
	_built(system, "room", Vector2i(0, -2), 0, 0, 0, Vector2i(2, 2))
	var shared_key := Vector4i(0, 0, 0, BuildTypes.AXIS_X)
	var swap := _plan(system, "doorway", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	_check(swap.count(BuildTypes.Action.REPLACE, BuildTypes.Kind.DOORWAY) == 1 and swap.count(BuildTypes.Action.CREATE) == 0, "doorway does not replace the shared wall in place")
	_built(system, "doorway", Vector2i(0, 0), 0, 0, BuildTypes.AXIS_X)
	var shared := _edge_piece(system, shared_key)
	_check(shared != null and shared.kind == BuildTypes.Kind.DOORWAY, "shared boundary is not a doorway")
	_check(shared != null and shared.rooms.size() == 2, "doorway lost a room reference")
	_expect_counts(system, "slabs=10 walls=10 doorways=1 windows=0 posts=10 stairs=0", "door between rooms")
	var keep := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_check(bool(keep["ok"]) and not bool(keep["changed"]), "re-placing a room put a wall back over a doorway")
	var north_key := Vector4i(0, -2, 0, BuildTypes.AXIS_X)
	var old_wall := _edge_piece(system, north_key)
	_built(system, "window", Vector2i(0, -2), 0, 0, BuildTypes.AXIS_X)
	var window := _edge_piece(system, north_key)
	_check(window != null and window.kind == BuildTypes.Kind.WINDOW, "window did not replace the wall")
	_check(system.world.node_for(old_wall.id) == null, "replaced wall node still exists")
	_built(system, "doorway", Vector2i(0, -2), 0, 0, BuildTypes.AXIS_X)
	_check(_edge_piece(system, north_key).kind == BuildTypes.Kind.DOORWAY, "doorway did not replace the window")
	_built(system, "wall", Vector2i(0, -2), 0, 0, BuildTypes.AXIS_X)
	_check(_edge_piece(system, north_key).kind == BuildTypes.Kind.WALL, "wall did not replace the doorway")
	_expect_counts(system, "slabs=10 walls=10 doorways=1 windows=0 posts=10 stairs=0", "after swaps")
	_built(system, "window", Vector2i(0, 1), 0, 0, BuildTypes.AXIS_X)
	var before := system.state.checksum()
	var keeps := _place(system, "room", Vector2i(0, 1), 0, 0, 0, Vector2i(1, 1))
	_check(bool(keeps["ok"]) and _edge_piece(system, Vector4i(0, 1, 0, BuildTypes.AXIS_X)).kind == BuildTypes.Kind.WINDOW, "neighbour room put a wall over a window")
	_check(system.state.checksum() != before, "neighbour room was not built")
	_audit(system, "doors and windows")


# --- 8-9. floors, ceilings, levels ---------------------------------------------

func _test_floors_and_ceilings() -> void:
	var system := _begin("8 floor and ceiling alignment")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(3, 3))
	_check(system.state.count_kind(BuildTypes.Kind.SLAB) == 18, "3x3 room has %d slabs" % system.state.count_kind(BuildTypes.Kind.SLAB))
	var upper := _plan(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(3, 3))
	_check(upper.count(BuildTypes.Action.REUSE, BuildTypes.Kind.SLAB) == 9, "upper room reuses %d slabs" % upper.count(BuildTypes.Action.REUSE, BuildTypes.Kind.SLAB))
	_check(upper.count(BuildTypes.Action.CREATE, BuildTypes.Kind.SLAB) == 9, "upper room creates %d slabs" % upper.count(BuildTypes.Action.CREATE, BuildTypes.Kind.SLAB))
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(3, 3))
	_check(system.state.count_kind(BuildTypes.Kind.SLAB) == 27, "two levels have %d slabs" % system.state.count_kind(BuildTypes.Kind.SLAB))
	var perimeter := _edge_piece(system, Vector4i(1, 0, 1, BuildTypes.AXIS_X))
	var full := BuildingGeometry.full_mask(perimeter.kind)
	var mask := system.world.mask_of(perimeter.id)
	_check(mask != full and mask != 0, "perimeter wall bottom mask %d should keep only the outside half" % mask)
	_built(system, "room", Vector2i(6, 0), 0, 0, 0, Vector2i(2, 2))
	var reuse := _plan(system, "room", Vector2i(6, 0), 0, 1, 0, Vector2i(2, 2))
	_check(reuse.count(BuildTypes.Action.REUSE, BuildTypes.Kind.SLAB) == 4 and reuse.count(BuildTypes.Action.CREATE, BuildTypes.Kind.SLAB) == 4, "room above a room does not stand on its ceiling")
	_built(system, "floor_1x1", Vector2i(8, 0), 0, 1)
	_check(system.state.slab_at(GridSystem.slab_key(Vector2i(8, 0), 1)) != 0, "ceiling tile beside a ceiling was not built")
	_built(system, "room", Vector2i(6, 0), 0, 1, 0, Vector2i(2, 2))
	_audit(system, "floors and ceilings")


func _test_stacked_levels() -> void:
	var system := _begin("9 stacked floors")
	for level in 3:
		_built(system, "room", Vector2i(0, 0), 0, level, 0, Vector2i(2, 2))
	_expect_counts(system, "slabs=16 walls=24 doorways=0 windows=0 posts=24 stairs=0", "three levels")
	var low := system.state.post_at(GridSystem.post_key(Vector2i(0, 0), 0))
	var mid := system.state.post_at(GridSystem.post_key(Vector2i(0, 0), 1))
	_check(system.state.graph.neighbours(mid).get(low, -1) == ConstructionGraph.Link.RESTS_ON, "upper post does not rest on the lower post")
	_check(system.state.graph.neighbours(low).get(mid, -1) == ConstructionGraph.Link.SUPPORTS, "graph link is not mirrored")
	var floating := _place(system, "room", Vector2i(10, 10), 0, 1, 0, Vector2i(1, 1))
	_check(not bool(floating["ok"]) and str(floating["reason"]).begins_with("Needs support"), "floating room accepted: %s" % floating["reason"])
	_built(system, "room", Vector2i(2, 0), 0, 1, 0, Vector2i(1, 1))
	_audit(system, "stacked floors")


func _test_stairs() -> void:
	var system := _begin("9b stairs between levels")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(3, 3))
	_built(system, "room", Vector2i(3, 0), 0, 0, 0, Vector2i(3, 3))
	var no_floor := _place(system, "stairs_straight", Vector2i(10, 10), 1)
	_check(not bool(no_floor["ok"]), "stairs without floor slabs accepted")
	var through_wall := _place(system, "stairs_straight", Vector2i(1, 1), 1)
	_check(not bool(through_wall["ok"]), "stairs through the partition wall accepted")
	var partition := system.authority.request_remove(system.state.edges.component_at(Vector4i(3, 1, 0, BuildTypes.AXIS_Z)))
	_check(bool(partition["ok"]), "could not open the partition: %s" % partition["reason"])
	var plan := _plan(system, "stairs_straight", Vector2i(1, 1), 1)
	_check(plan.count(BuildTypes.Action.REMOVE, BuildTypes.Kind.SLAB) == 3, "stairs open %d ceiling slabs" % plan.count(BuildTypes.Action.REMOVE, BuildTypes.Kind.SLAB))
	_built(system, "stairs_straight", Vector2i(1, 1), 1)
	for x in range(1, 4):
		_check(system.state.stairwell_at(GridSystem.slab_key(Vector2i(x, 1), 1)) != 0, "cell %d,1 is not a stairwell" % x)
	var upper := _plan(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(3, 3))
	_check(upper.count(BuildTypes.Action.SKIP, BuildTypes.Kind.SLAB) == 2, "upper room skips %d stairwell cells" % upper.count(BuildTypes.Action.SKIP, BuildTypes.Kind.SLAB))
	_check(upper.count(BuildTypes.Action.SKIP, BuildTypes.Kind.WALL) == 1, "upper room does not leave the wall over the stairs open")
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(3, 3))
	_built(system, "room", Vector2i(3, 0), 0, 1, 0, Vector2i(3, 3))
	_check(not system.state.edges.has_piece(Vector4i(3, 1, 1, BuildTypes.AXIS_Z)), "wall built over the stairs")
	_check(system.state.count_kind(BuildTypes.Kind.SLAB) == 51, "slab count with stairwell %d" % system.state.count_kind(BuildTypes.Kind.SLAB))
	var head_wall := _place(system, "wall", Vector2i(2, 1), 0, 1, BuildTypes.AXIS_Z)
	_check(not bool(head_wall["ok"]), "wall above the flight accepted (no headroom)")
	var top_wall := _place(system, "wall", Vector2i(4, 1), 0, 0, BuildTypes.AXIS_Z)
	_check(not bool(top_wall["ok"]), "wall across the top of the stairs accepted")
	var entry_door := _place(system, "doorway", Vector2i(1, 1), 0, 0, BuildTypes.AXIS_Z)
	_check(not bool(entry_door["ok"]), "doorway at the stairs entry accepted (no headroom for a climbing player)")
	var exit_door := _place(system, "doorway", Vector2i(4, 1), 0, 1, BuildTypes.AXIS_Z)
	_check(bool(exit_door["ok"]), "doorway at the stairs exit rejected: %s" % exit_door["reason"])
	var into_wall := _place(system, "stairs_straight", Vector2i(2, 0), 1, 1)
	_check(not bool(into_wall["ok"]), "stairs running into a wall accepted")
	var under := system.authority.request_remove(system.state.slab_at(GridSystem.slab_key(Vector2i(2, 1), 0)))
	_check(not bool(under["ok"]), "removed the slab under the stairs")
	_audit(system, "stairs")
	for _i in 3:
		await physics_frame
	var space := _stage.get_world_3d().direct_space_state
	var slab_top := system.config.slab_thickness
	var rise := system.config.floor_height
	for step in 3:
		var x := 1.5 + float(step)
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, rise - 0.05, 1.5), Vector3(x, -1.0, 1.5), PhysicsLayers.BUILDING)
		var hit := space.intersect_ray(query)
		var expected := slab_top + rise * (x - 1.0) / 3.0
		_check(not hit.is_empty() and absf((hit["position"] as Vector3).y - expected) < 0.01, "stairs surface at x=%.1f is %s, expected %.3f" % [x, hit.get("position"), expected])
	var walker := _walker(Vector3(0.6, 0.5, 1.5))
	for _i in 30:
		await physics_frame
		_step_walker(walker, Vector3.ZERO)
	for _i in 180:
		await physics_frame
		_step_walker(walker, Vector3(2.5, 0.0, 0.0))
	_check(walker.global_position.y > rise - 0.1 and walker.global_position.x > 4.0, "walker did not climb the stairs: %s" % walker.global_position)


func _test_walls_need_floor() -> void:
	var system := _begin("9c walls on top of stairs")
	for z in 3:
		_built(system, "floor_1x1", Vector2i(0, z))
	_built(system, "floor_1x1", Vector2i(1, 1))
	_built(system, "wall", Vector2i(1, 1), 0, 0, BuildTypes.AXIS_Z)
	_built(system, "floor_1x1", Vector2i(0, 1), 0, 1)
	_built(system, "wall", Vector2i(0, 1), 0, 1, BuildTypes.AXIS_Z)
	_built(system, "stairs_straight", Vector2i(0, 0))
	var kept := Vector4i(0, 1, 1, BuildTypes.AXIS_Z)
	_check(system.state.edges.component_at(kept) != 0 and system.state.edge_has_floor(kept), "wall beside the stairwell top lost its floor")
	_built(system, "wall", Vector2i(1, 0), 0, 1, BuildTypes.AXIS_Z)
	_built(system, "window", Vector2i(1, 2), 0, 1, BuildTypes.AXIS_Z)
	_built(system, "wall", Vector2i(0, 3), 0, 1, BuildTypes.AXIS_X)
	_check(not bool(_place(system, "wall", Vector2i(0, 0), 0, 1, BuildTypes.AXIS_X)["ok"]), "wall across the stairs exit accepted")
	_built(system, "doorway", Vector2i(0, 0), 0, 1, BuildTypes.AXIS_X)
	_check(not bool(_place(system, "wall", Vector2i(0, 1), 0, 1, BuildTypes.AXIS_X)["ok"]), "wall over the flight accepted")
	var removal := system.authority.request_remove(system.state.stairs_at(GridSystem.slab_key(Vector2i(0, 0), 0)))
	_check(not bool(removal["ok"]) and str(removal["reason"]).begins_with("Walls stand on top"), "stairs removed under the walls on top: %s" % removal["reason"])
	_audit(system, "walls on top of stairs")
	var rooms := _begin("9d room over a stairwell keeps its walls")
	for z in 3:
		_built(rooms, "floor_1x1", Vector2i(0, z))
	_built(rooms, "floor_1x1", Vector2i(1, 1))
	_built(rooms, "wall", Vector2i(1, 1), 0, 0, BuildTypes.AXIS_Z)
	_built(rooms, "stairs_straight", Vector2i(0, 0))
	var upper := _plan(rooms, "room", Vector2i(-1, 0), 0, 1, 0, Vector2i(2, 3))
	var floorless := 0
	var stair_skips := 0
	for entry in upper.entries:
		if int(entry["action"]) != BuildTypes.Action.SKIP:
			continue
		var reason := str(entry.get("reason", ""))
		if reason == "No floor beside this boundary":
			floorless += 1
		elif reason == "Stairs keep this boundary open":
			stair_skips += 1
	_check(upper.is_valid(), "room over the stairwell rejected: %s" % upper.first_reason())
	_check(floorless == 0, "room over the stairwell left %d boundaries without walls" % floorless)
	_check(stair_skips == 1, "room skipped %d stair boundaries, expected only the exit" % stair_skips)
	_built(rooms, "room", Vector2i(-1, 0), 0, 1, 0, Vector2i(2, 3))
	_check(rooms.state.edges.component_at(Vector4i(1, 1, 1, BuildTypes.AXIS_Z)) != 0, "no wall beside the stairwell top")
	_check(rooms.state.edges.component_at(Vector4i(0, 3, 1, BuildTypes.AXIS_X)) != 0, "no wall above the stairs entry")
	_audit(rooms, "room over a stairwell")


# --- 11-14. preview, rejections ----------------------------------------------------

func _test_preview_isolation() -> void:
	var system := _begin("11 preview beside existing geometry")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var tool := _tool(system)
	var checksum := system.state.checksum()
	var revision := system.state.revision
	var nodes := system.world.node_count()
	tool.select_by_id("room")
	tool.update_aim(Vector3(1.5, 0.0, 0.5))
	var plan := tool.current_plan
	_check(plan != null and plan.count(BuildTypes.Action.REUSE, BuildTypes.Kind.WALL) == 1, "preview plan does not reuse the shared wall")
	var creates: Array[Transform3D] = []
	for entry in plan.entries:
		if int(entry["action"]) == BuildTypes.Action.CREATE:
			creates.append(system.grid.transform_for(int(entry["kind"]), entry["key"]))
	var ghosts := tool.preview.ghost_transforms()
	_check(ghosts.size() == creates.size(), "%d ghosts for %d new pieces" % [ghosts.size(), creates.size()])
	for xform in ghosts:
		_check(creates.has(xform), "ghost transform %s is not canonical" % xform)
	for component: BuildComponent in system.state.components.values():
		var existing := system.grid.component_transform(component)
		for i in ghosts.size():
			_check(not (ghosts[i] == existing and _ghost_kind(plan, i) == component.kind), "ghost drawn over existing %s" % component.describe())
	_check(_bodies_under(system.preview_root) == 0, "preview has physics bodies")
	_check(system.state.checksum() == checksum and system.state.revision == revision, "preview changed the state")
	_check(system.world.node_count() == nodes, "preview spawned committed nodes")
	_check(tool.preview.status_text().begins_with("[OK]"), "status text: %s" % tool.preview.status_text())
	tool.select_by_id("room")
	tool.update_aim(Vector3(1.5, 0.0, 1.5))
	tool.begin_drag()
	tool.update_aim(Vector3(0.5, 0.0, 0.5))
	_check(tool.current_request.get("size") == Vector2i(2, 2), "drag over the room is not 2x2: %s" % str(tool.current_request))
	_check(tool.preview.status_text().begins_with("[X]"), "overlapping preview has no [X] text: %s" % tool.preview.status_text())
	_audit(system, "preview isolation")


func _ghost_kind(plan: ConstructionPlan, index: int) -> int:
	var seen := 0
	for entry in plan.entries:
		if int(entry["action"]) == BuildTypes.Action.CREATE:
			if seen == index:
				return int(entry["kind"])
			seen += 1
	return -1


func _test_rapid_preview() -> void:
	var system := _begin("12 rapid preview movement and rotation")
	_built(system, "room", Vector2i(-2, -2), 0, 0, 0, Vector2i(3, 3))
	_built(system, "room", Vector2i(1, -2), 0, 0, 0, Vector2i(2, 2))
	var tool := _tool(system)
	var checksum := system.state.checksum()
	var spawned := system.world.spawned_total
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var max_entries := 0
	for i in 1200:
		if i % 5 == 0:
			tool.rotate_blueprint(1)
		if i % 40 == 0:
			tool.cycle(1)
		if i % 97 == 0:
			tool.change_level(1 if rng.randf() < 0.5 else -1)
		tool.update_aim(Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0)))
		if tool.current_plan != null:
			max_entries = maxi(max_entries, tool.current_plan.entries.size())
	_check(system.state.checksum() == checksum, "preview movement changed the state")
	_check(system.world.spawned_total == spawned, "preview movement spawned committed nodes")
	_check(_bodies_under(system.preview_root) == 0, "preview has physics bodies")
	_check(tool.preview.pooled_nodes() <= max_entries * 3, "preview pool grew to %d for at most %d entries" % [tool.preview.pooled_nodes(), max_entries])
	_check(system.preview_root.get_child_count() == 1, "preview root has %d children" % system.preview_root.get_child_count())
	var pooled := tool.preview.pooled_nodes()
	for i in 600:
		if i % 5 == 0:
			tool.rotate_blueprint(1)
		if i % 40 == 0:
			tool.cycle(1)
		tool.update_aim(Vector3(rng.randf_range(-7.0, 7.0), 0.0, rng.randf_range(-7.0, 7.0)))
	_check(tool.preview.pooled_nodes() <= maxi(pooled, max_entries * 3), "preview pool keeps growing")
	print("   pool=%d max_entries=%d plans=%d rebuilds=%d" % [tool.preview.pooled_nodes(), max_entries, tool.plans_built, tool.preview.rebuilds])


func _test_rejections() -> void:
	var system := _begin("13 rejected and cancelled placement")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	var checksum := system.state.checksum()
	var outside := _place(system, "room", Vector2i(40, 40), 0, 0, 0, Vector2i(1, 1))
	_check(not bool(outside["ok"]) and str(outside["reason"]) == "Outside the build area", "out of bounds: %s" % outside["reason"])
	var too_high := _place(system, "room", Vector2i(0, 0), 0, 9, 0, Vector2i(1, 1))
	_check(not bool(too_high["ok"]), "level 9 accepted")
	var ceiling := _place(system, "floor_1x1", Vector2i(12, 12), 0, 1)
	_check(not bool(ceiling["ok"]), "unsupported ceiling accepted")
	var crate := StaticBody3D.new()
	crate.name = "Crate"
	crate.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	crate.add_child(shape)
	_stage.add_child(crate)
	crate.global_position = Vector3(5.5, 0.3, 5.5)
	for _i in 2:
		await physics_frame
	var blocked := _place(system, "room", Vector2i(5, 5), 0, 0, 0, Vector2i(1, 1))
	_check(not bool(blocked["ok"]) and str(blocked["reason"]).contains("Crate"), "crate did not block: %s" % blocked["reason"])
	var beside := _place(system, "room", Vector2i(7, 5), 0, 0, 0, Vector2i(1, 1))
	_check(bool(beside["ok"]), "room beside the crate rejected: %s" % beside["reason"])
	checksum = system.state.checksum()
	var stale := system.authority.make_plan(RoomPlacer.make_request("room", Vector2i(-5, -5)))
	_built(system, "room", Vector2i(-8, -8), 0, 0, 0, Vector2i(1, 1))
	var after := system.state.checksum()
	print("   (expected error follows: stale plan refused)")
	var refused := system.state.commit(stale)
	_check(not bool(refused["ok"]), "stale plan committed")
	_check(system.state.checksum() == after, "stale plan changed state")
	var tool := _tool(system)
	tool.select_by_id("room")
	tool.update_aim(Vector3(10.5, 0.0, 10.5))
	_check(tool.preview.visible_pieces() > 0, "preview not shown before cancel")
	tool.cancel()
	_check(tool.preview.visible_pieces() == 0 and not tool.preview.visible, "cancel left the preview visible")
	_check(tool.confirm().is_empty(), "confirm after cancel did something")
	_check(system.state.checksum() == after, "cancel changed state")
	_audit(system, "rejections")


func _test_resources() -> void:
	var config := (BuildingSystem.DEFAULT_CONFIG as BuildingConfig).duplicate() as BuildingConfig
	config.require_resources = true
	var system := _begin("13b resource costs", config)
	var wallet := {"scrap_metal": 3}
	system.authority.wallet_count = func(id: String) -> int: return int(wallet.get(id, 0))
	system.authority.wallet_spend = func(id: String, qty: int) -> bool:
		wallet[id] = int(wallet.get(id, 0)) - qty
		return true
	var plan := _plan(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var cost := int(plan.cost.get(config.cost_item_id, 0))
	_check(cost > 3, "room cost %d is not above the test wallet" % cost)
	var poor := _place(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_check(not bool(poor["ok"]) and str(poor["reason"]).begins_with("Needs"), "placement without resources: %s" % poor["reason"])
	_check(system.state.component_count() == 0, "pieces built without resources")
	wallet["scrap_metal"] = 500
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_check(int(wallet["scrap_metal"]) == 500 - cost, "wallet charged %d instead of %d" % [500 - int(wallet["scrap_metal"]), cost])
	var neighbour := _plan(system, "room", Vector2i(1, 0), 0, 0, 0, Vector2i(1, 1))
	_check(int(neighbour.cost.get(config.cost_item_id, 0)) < cost, "reused pieces were charged again")


func _test_dismantle() -> void:
	var system := _begin("10a dismantle and rebuild")
	_built(system, "room", Vector2i(5, 0), 0, 0, 0, Vector2i(1, 1))
	for edge in GridSystem.cell_edges(Vector2i(5, 0), 0):
		var removed := system.authority.request_remove(system.state.edges.component_at(edge))
		_check(bool(removed["ok"]), "wall removal failed: %s" % removed["reason"])
	_expect_counts(system, "slabs=2 walls=0 doorways=0 windows=0 posts=0 stairs=0", "walls removed")
	_built(system, "room", Vector2i(5, 0), 0, 0, 0, Vector2i(1, 1))
	_built(system, "room", Vector2i(8, 0), 0, 0, 0, Vector2i(1, 1))
	var only_floor := system.authority.request_remove(system.state.slab_at(GridSystem.slab_key(Vector2i(8, 0), 0)))
	_check(not bool(only_floor["ok"]) and str(only_floor["reason"]).begins_with("Walls stand only"), "floor under free-standing walls removed: %s" % only_floor["reason"])
	_built(system, "floor_1x1", Vector2i(8, 1))
	var wall := _edge_piece(system, Vector4i(8, 1, 0, BuildTypes.AXIS_X))
	var before := system.world.mask_of(wall.id)
	var slab := system.authority.request_remove(system.state.slab_at(GridSystem.slab_key(Vector2i(8, 1), 0)))
	_check(bool(slab["ok"]), "slab beside a wall with another floor not removable: %s" % slab["reason"])
	_check(system.world.mask_of(wall.id) != before, "wall bottom did not change after slab removal")
	_check(BlueprintCatalog.get_blueprint("support_post") == null, "support posts are still placeable on their own")
	_check(not _place(system, "wall", Vector2i(12, 0), 0, 0, BuildTypes.AXIS_X)["ok"], "wall without a floor accepted")
	_check(not _place(system, "doorway", Vector2i(12, 0), 0, 0, BuildTypes.AXIS_X)["ok"], "doorway without a floor accepted")
	_check(not _place(system, "window", Vector2i(12, 0), 0, 0, BuildTypes.AXIS_X)["ok"], "window without a floor accepted")
	_built(system, "floor_1x1", Vector2i(12, 0))
	_built(system, "wall", Vector2i(12, 0), 0, 0, BuildTypes.AXIS_X)
	_built(system, "window", Vector2i(12, 1), 0, 0, BuildTypes.AXIS_X)
	_check(system.state.post_at(GridSystem.post_key(Vector2i(12, 0), 0)) != 0, "wall did not get its corner posts")
	system.authority.request_remove(system.state.edges.component_at(Vector4i(12, 0, 0, BuildTypes.AXIS_X)))
	_check(system.state.post_at(GridSystem.post_key(Vector2i(12, 0), 0)) == 0, "orphan corner post kept")
	_check(system.state.post_at(GridSystem.post_key(Vector2i(12, 1), 0)) != 0, "post still used by the window removed")
	_audit(system, "dismantle")


# --- physics -----------------------------------------------------------------------

func _walker(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Walker"
	body.collision_layer = PhysicsLayers.PLAYER
	body.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.BUILDING
	body.floor_snap_length = 0.45
	body.floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	_stage.add_child(body)
	body.global_position = at
	return body


func _step_walker(body: CharacterBody3D, horizontal: Vector3) -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var vertical := -18.0 * dt if body.is_on_floor() else body.velocity.y - 18.0 * dt
	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()


func _test_physics_stability() -> void:
	var system := _begin("14 collision stability")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	var snapshot := {}
	for component: BuildComponent in system.state.components.values():
		snapshot[component.id] = system.world.node_for(component.id).global_transform
	var walker := _walker(Vector3(1.0, 0.4, 1.0))
	for _i in 60:
		await physics_frame
		_step_walker(walker, Vector3.ZERO)
	var rest := walker.global_position
	var drift := 0.0
	for _i in 120:
		await physics_frame
		_step_walker(walker, Vector3.ZERO)
		drift = maxf(drift, walker.global_position.distance_to(rest))
	_check(walker.is_on_floor(), "walker is not on the floor slab")
	_check(drift < 0.0001, "standing walker drifted %.6f" % drift)
	_check(absf(rest.y - system.config.slab_thickness) < 0.02, "walker rests at y=%.4f, slab top %.4f" % [rest.y, system.config.slab_thickness])
	var xs: Array[float] = []
	for i in 180:
		await physics_frame
		_step_walker(walker, Vector3(3.0, 0.0, 0.0))
		if i >= 120:
			xs.append(walker.global_position.x)
	var spread: float = xs.max() - xs.min()
	var inner := 2.0 - system.config.wall_thickness * 0.5 - 0.3
	_check(spread < 0.001, "walker pressed into a wall jitters by %.5f" % spread)
	_check(walker.global_position.x <= inner + 0.01, "walker went into the wall: x=%.4f limit %.4f" % [walker.global_position.x, inner])
	_built(system, "room", Vector2i(2, 0), 0, 0, 0, Vector2i(2, 2))
	_built(system, "room", Vector2i(0, 2), 0, 0, 0, Vector2i(2, 2))
	for _i in 10:
		await physics_frame
	for id: int in snapshot.keys():
		var node := system.world.node_for(id)
		_check(node != null and node.global_transform == snapshot[id], "piece %d moved after neighbours were built" % id)
	var space := _stage.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(1.0, 1.2, 0.6), Vector3(5.0, 1.2, 0.6), PhysicsLayers.HITS_MASK)
	var hit := space.intersect_ray(ray)
	_check(not hit.is_empty() and (hit["collider"] as Node).get_parent().has_meta(&"component_id"), "hitscan ray does not stop at the building wall")
	walker.free()
	_audit(system, "physics stability")


# --- showcase and arena --------------------------------------------------------------

func _test_showcase() -> void:
	var system := _begin("showcase layout")
	var failures := BuildingScenarios.build_all(system.authority)
	_check(failures.is_empty(), "showcase steps failed:\n  %s" % "\n  ".join(failures))
	print("   ", _counts(system))
	_audit(system, "showcase")


## Plants known faults and expects the audit to report each one, so a clean
## audit elsewhere means something.
func _test_audit_detects_faults() -> void:
	var system := _begin("audit self-check")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var wall := _edge_piece(system, Vector4i(0, 0, 0, BuildTypes.AXIS_X))
	var node := system.world.node_for(wall.id)
	var canonical := node.transform
	node.position.x += 0.001
	_check(_issue_types(system).has("transform"), "audit missed a 1 mm transform drift")
	node.transform = canonical
	var copy := node.duplicate() as Node3D
	system.world.add_child(copy)
	_check(_issue_types(system).has("duplicate"), "audit missed a duplicate wall node")
	copy.free()
	var mesh_node := node.get_node("Mesh") as MeshInstance3D
	var masked := mesh_node.mesh
	mesh_node.mesh = system.geometry.mesh_for(wall.kind, BuildingGeometry.full_mask(wall.kind))
	var types := _issue_types(system)
	_check(types.has("mesh"), "audit missed the wrong bottom-mask mesh")
	_check(types.has("zfight"), "audit missed a wall bottom coplanar with the slab bottom")
	mesh_node.mesh = masked
	var stray := StaticBody3D.new()
	system.preview_root.add_child(stray)
	_check(_issue_types(system).has("preview"), "audit missed a body in the preview")
	stray.free()
	_audit(system, "audit restored")


func _issue_types(system: BuildingSystem) -> Dictionary:
	var types := {}
	for issue: Dictionary in GeometryAudit.run(system)["issues"]:
		types[str(issue["type"])] = true
	return types


func _test_arena_integration() -> void:
	_section = "arena integration"
	print("-- ", _section)
	if _stage != null:
		_stage.free()
		_stage = null
	var arena := (load("res://scenes/world/test_arena.tscn") as PackedScene).instantiate()
	arena.set("force_mode", NetConfig.MODE_LOCAL)
	root.add_child(arena)
	for _i in 20:
		await physics_frame
	var system := get_first_node_in_group(&"building_system") as BuildingSystem
	var player := arena.get_node_or_null("Player") as PlayerController
	if not _check(system != null and player != null, "arena has no building system or player"):
		arena.free()
		return
	var slot := -1
	for i in player.inventory.capacity:
		if str(player.inventory.slots[i]["id"]) == "build_tool":
			slot = i
	_check(slot >= 0, "build tool not in the loadout")
	var tool := player.get_node_or_null("BuildTool") as BuildTool
	_check(tool != null and tool.menu != null, "player has no Build Tool")
	if tool == null or slot < 0:
		arena.free()
		return
	_check(not tool.equipped, "tool equipped without being selected")
	player.select_hotbar(slot)
	await process_frame
	await process_frame
	_check(player.holds_build_tool() and tool.equipped, "selecting the hotbar slot did not equip the tool")
	_check(tool.menu.visible, "blueprint menu hidden while equipped")
	tool.select_by_id("room")
	var built := false
	for candidate: Vector3 in [Vector3(-12.0, 0.0, 12.0), Vector3(12.0, 0.0, 12.0), Vector3(-12.0, 0.0, -12.0), Vector3(12.0, 0.0, -12.0), Vector3(4.0, 0.0, 12.0)]:
		tool.update_aim(candidate)
		var result := tool.confirm()
		if bool(result.get("ok", false)) and bool(result.get("changed", false)):
			built = true
			print("   built a room in the arena at ", candidate)
			break
		print("   arena spot ", candidate, " rejected: ", result.get("reason", "no plan"))
	_check(built, "could not build a room anywhere in the arena")
	player.select_hotbar(0)
	await process_frame
	await process_frame
	_check(not tool.equipped and not tool.preview.visible, "switching items did not unequip the tool")
	_audit(system, "arena")
	arena.free()
