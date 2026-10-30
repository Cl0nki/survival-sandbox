extends SceneTree

## Headless regression suite for Phase 3 (support and collapse).
## godot --headless --path <project> --script res://tests/building_phase3.gd

var _stage: Node3D
var _failures := PackedStringArray()
var _checks := 0
var _section := ""


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("BUILDING_PHASE3 timed out in section ", _section)
		quit(2), CONNECT_ONE_SHOT)
	await _body()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("BUILDING_PHASE3_OK")
		quit(0)
	else:
		quit(1)


func _body() -> void:
	_test_one_missing_wall_stays()
	_test_last_support_drops_the_floor()
	_test_overload()
	_test_separate_building_is_left_alone()
	_test_chain_from_the_ground_floor()
	_test_stairs_follow_their_floor()
	_test_repair_and_dismantle()
	await _test_rebuild_during_the_delay()
	_test_upper_floor_cannot_be_wider()
	_test_stairs_do_not_make_the_next_floor_wider()
	_test_full_tower_is_at_bearing()
	await _test_collapse_falls_from_the_top()
	_test_debug_weight()
	if _stage != null:
		_stage.free()


func _begin(section: String, config: BuildingConfig = null) -> BuildingSystem:
	_section = section
	print("-- ", section)
	if _stage != null:
		_stage.free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	root.add_child(_stage)
	var system := BuildingSystem.new()
	if config == null:
		config = _instant()
	system.config = config
	_stage.add_child(system)
	return system


func _instant() -> BuildingConfig:
	var config := BuildingConfig.new()
	config.collapse_delay_sec = 0.0
	config.collapse_span_sec = 0.0
	return config


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [_section, message])
	return condition


func _place(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> Dictionary:
	return system.authority.request_place(RoomPlacer.make_request(id, anchor, rotation, level, axis, 0, size))


func _built(system: BuildingSystem, id: String, anchor: Vector2i, rotation: int = 0, level: int = 0, axis: int = 0, size := Vector2i.ZERO) -> void:
	var result := _place(system, id, anchor, rotation, level, axis, size)
	_check(bool(result["ok"]) and bool(result["changed"]), "%s at %s L%d was not built: %s" % [id, anchor, level, result.get("reason", "")])


func _audit(system: BuildingSystem, label: String) -> void:
	var report := GeometryAudit.run(system)
	_check(bool(report["ok"]), "%s\n%s" % [label, GeometryAudit.describe(report, 12)])


func _walls(system: BuildingSystem, level: int) -> Array[BuildComponent]:
	var found: Array[BuildComponent] = []
	for component: BuildComponent in system.state.components.values():
		if component.kind == BuildTypes.Kind.WALL and component.level == level:
			found.append(component)
	found.sort_custom(func(a: BuildComponent, b: BuildComponent) -> bool: return a.id < b.id)
	return found


func _slabs(system: BuildingSystem, level: int) -> int:
	var count := 0
	for component: BuildComponent in system.state.components.values():
		if component.kind == BuildTypes.Kind.SLAB and component.level == level:
			count += 1
	return count


func _kill(system: BuildingSystem, component: BuildComponent) -> void:
	system.authority.apply_bullet(component.id, 10000, Vector3.ZERO, "kill-%d" % component.id)


func _test_one_missing_wall_stays() -> void:
	var system := _begin("one missing wall leaves the floor standing")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(1, 1))
	var lower := _walls(system, 0)
	_check(lower.size() == 4 and _slabs(system, 1) == 1, "stacked room was not built")
	_kill(system, lower[0])
	_check(_slabs(system, 1) == 1 and _slabs(system, 2) == 1, "one wall brought the upper floors down")
	_check(_walls(system, 1).size() == 4, "the upper room lost a wall")
	_audit(system, "after one wall was destroyed")


func _test_last_support_drops_the_floor() -> void:
	var system := _begin("the last supporting wall drops the floor")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var walls := _walls(system, 0)
	for index in walls.size() - 1:
		_kill(system, walls[index])
	_check(_slabs(system, 1) == 1 and _walls(system, 0).size() == 1, "the ceiling fell before the last wall was gone")
	_kill(system, _walls(system, 0)[0])
	_check(_slabs(system, 1) == 0 and _walls(system, 0).is_empty(), "the ceiling stayed up with no wall under it")
	_check(_slabs(system, 0) == 1, "the ground floor fell with the ceiling")
	_audit(system, "after the last wall collapsed the ceiling")


func _test_overload() -> void:
	var config := _instant()
	config.wall_bearing = 2.0
	var system := _begin("too many tiles on too few walls", config)
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(3, 2))
	_check(_slabs(system, 1) == 6, "3x2 room has %d ceiling tiles" % _slabs(system, 1))
	var walls := _walls(system, 0)
	while walls.size() > 2:
		_kill(system, walls[0])
		walls = _walls(system, 0)
	_check(walls.size() == 2 and _slabs(system, 1) == 6, "two walls could not carry 6 tiles")
	_kill(system, walls[0])
	_check(_walls(system, 0).is_empty() and _slabs(system, 1) == 0, "the overloaded wall did not bring the ceiling down")
	_check(_slabs(system, 0) == 6, "overload removed the ground floor")
	_audit(system, "after an overloaded wall buckled")


func _test_separate_building_is_left_alone() -> void:
	var system := _begin("a separate building is not recalculated")
	_built(system, "room", Vector2i(8, 8), 0, 0, 0, Vector2i(1, 1))
	var far_ceiling := system.state.slab_at(GridSystem.slab_key(Vector2i(8, 8), 1))
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var before := system.state.component_count()
	var near: BuildComponent = null
	for wall in _walls(system, 0):
		var key: Vector4i = wall.key
		if key.x < 4 and key.y < 4:
			near = wall
			break
	_check(near != null, "the near room has no wall")
	if near == null:
		return
	_kill(system, near)
	_check(system.authority.last_region_count > 0 and system.authority.last_region_count < before, "region walked %d of %d pieces" % [system.authority.last_region_count, before])
	_check(system.state.slab_at(GridSystem.slab_key(Vector2i(8, 8), 1)) == far_ceiling, "the far ceiling was touched")
	_audit(system, "after a local wall was destroyed")


func _test_chain_from_the_ground_floor() -> void:
	var system := _begin("destroying the ground floor brings the storeys down")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(1, 1))
	var ground := system.state.get_component(system.state.slab_at(GridSystem.slab_key(Vector2i(0, 0), 0)))
	_check(ground != null, "no ground slab")
	if ground == null:
		return
	_kill(system, ground)
	_check(system.state.component_count() == 0 and system.world.node_count() == 0, "the stack left %d pieces and %d nodes" % [system.state.component_count(), system.world.node_count()])
	_audit(system, "after the stack collapsed")


func _test_stairs_follow_their_floor() -> void:
	var system := _begin("stairs fall when a step loses its floor")
	for cell in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]:
		_built(system, "floor_1x1", cell)
	_built(system, "stairs_straight", Vector2i(0, 0))
	var stairs_id := 0
	for component: BuildComponent in system.state.components.values():
		if component.kind == BuildTypes.Kind.STAIRS:
			stairs_id = component.id
	_check(stairs_id != 0, "stairs were not built")
	var step := system.state.get_component(system.state.slab_at(GridSystem.slab_key(Vector2i(0, 1), 0)))
	if step == null:
		_check(false, "middle step has no slab")
		return
	_kill(system, step)
	_check(system.state.get_component(stairs_id) == null, "stairs stayed after their floor was destroyed")
	_check(_slabs(system, 0) == 2, "the other stair floors fell too")
	_audit(system, "after stairs collapsed")


func _test_repair_and_dismantle() -> void:
	var system := _begin("repair keeps a building, dismantle does not collapse it")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var wall := _walls(system, 0)[0]
	var floor_id := system.state.slab_at(GridSystem.slab_key(Vector2i(0, 0), 0))
	var hurt := system.authority.apply_bullet(wall.id, 40, Vector3.ZERO, "chip")
	_check(bool(hurt["changed"]) and not bool(hurt["destroyed"]) and _slabs(system, 1) == 1, "a chip collapsed the ceiling")
	var repaired := system.authority.repair(wall.id)
	_check(bool(repaired["ok"]) and wall.health == wall.max_health, "repair failed: %s" % repaired.get("reason", ""))
	var blocked := system.authority.request_remove(floor_id)
	_check(not bool(blocked["ok"]) and _slabs(system, 0) == 1, "the floor under the walls was dismantled: %s" % blocked.get("reason", ""))
	var removed := system.authority.request_remove(wall.id)
	_check(bool(removed["ok"]) and _slabs(system, 1) == 1, "dismantling a wall collapsed the ceiling")
	_check(system.authority._collapse_waves == 0, "dismantle started a collapse")


func _test_rebuild_during_the_delay() -> void:
	var config := BuildingConfig.new()
	config.collapse_delay_sec = 0.2
	config.wall_bearing = 2.0
	var system := _begin("rebuilding a wall during the delay saves the floor", config)
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(3, 2))
	var walls := _walls(system, 0)
	var replaced: Vector4i = walls[0].key
	while walls.size() > 2:
		_kill(system, walls[0])
		walls = _walls(system, 0)
	_kill(system, walls[0])
	_check(_slabs(system, 1) == 6 and not system.authority._pending_collapse.is_empty(), "the ceiling fell before the delay, or nothing was waiting")
	var placed := _place(system, "wall", Vector2i(replaced.x, replaced.y), 0, replaced.z, replaced.w)
	_check(bool(placed["ok"]) and bool(placed["changed"]), "could not put the wall back: %s" % placed.get("reason", ""))
	_check(system.authority._pending_collapse.is_empty(), "the rebuilt wall did not cancel the collapse")
	await create_timer(0.35).timeout
	_check(_slabs(system, 1) == 6, "the ceiling fell after the wall was rebuilt")
	_audit(system, "after a collapse was cancelled")


func _test_upper_floor_cannot_be_wider() -> void:
	var system := _begin("an upper floor cannot stick out past the floor below")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(2, 2))
	var inside := _place(system, "room", Vector2i(1, 1), 0, 1, 0, Vector2i(1, 1))
	_check(bool(inside["ok"]) and bool(inside["changed"]), "a smaller upper room was refused: %s" % inside.get("reason", ""))
	var stuck_out := _place(system, "room", Vector2i(2, 0), 0, 1, 0, Vector2i(1, 1))
	_check(not bool(stuck_out["ok"]) and str(stuck_out["reason"]) == "Wider than the level below", "overhang: %s" % stuck_out.get("reason", ""))
	var heavy := _instant()
	heavy.wall_bearing = 0.3
	system = _begin("overload waits until a wall is destroyed", heavy)
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(1, 1))
	_check(_slabs(system, 2) == 1, "the heavy upper floor was refused at placement")
	_kill(system, _walls(system, 0)[0])
	_check(_slabs(system, 2) == 0 and _slabs(system, 1) == 0, "destroying a wall did not bring the overloaded floors down")
	_check(_slabs(system, 0) == 1, "overload removed the ground floor")
	_audit(system, "after an overloaded building was brought down")


func _test_stairs_do_not_make_the_next_floor_wider() -> void:
	var system := _begin("a stair opening still counts as the floor below")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(8, 8))
	_built(system, "stairs_straight", Vector2i(2, 2), 0, 0)
	_built(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(8, 8))
	_built(system, "stairs_straight", Vector2i(5, 2), 0, 1)
	var third := _place(system, "room", Vector2i(0, 0), 0, 2, 0, Vector2i(8, 8))
	_check(bool(third["ok"]) and bool(third["changed"]), "third storey over the stairs: %s" % third.get("reason", ""))
	_built(system, "stairs_straight", Vector2i(2, 2), 0, 2)
	var fourth := _place(system, "room", Vector2i(0, 0), 0, 3, 0, Vector2i(8, 8))
	_check(bool(fourth["ok"]) and bool(fourth["changed"]), "fourth storey over the stairs: %s" % fourth.get("reason", ""))
	var stuck := _place(system, "room", Vector2i(8, 0), 0, 2, 0, Vector2i(1, 1))
	_check(not bool(stuck["ok"]) and str(stuck["reason"]) == "Wider than the level below", "a cell past the floor was accepted: %s" % stuck.get("reason", ""))
	_audit(system, "four storeys with a flight on each")


func _test_full_tower_is_at_bearing() -> void:
	var system := _begin("a 4 storey 8x8 sits at 4/4 until a wall is destroyed")
	for level in 4:
		_built(system, "room", Vector2i(0, 0), 0, level, 0, Vector2i(8, 8))
	var ids: Array[int] = []
	for component: BuildComponent in system.state.components.values():
		ids.append(component.id)
	var carried := StructuralSolver.loads(system.state, ids, system.config)
	var worst := 0.0
	for component: BuildComponent in system.state.components.values():
		if component.kind != BuildTypes.Kind.WALL:
			continue
		worst = maxf(worst, float(carried.get(component.id, 0.0)))
	_check(is_equal_approx(worst, system.config.wall_bearing), "heaviest wall is %.3f, expected 4/4" % worst)
	var again := _place(system, "room", Vector2i(0, 0), 0, 1, 0, Vector2i(8, 8))
	_check(bool(again["ok"]) and str(again.get("reason", "")) != "Wider than the level below", "the same 8x8 was wider: %s" % again.get("reason", ""))
	var stuck := _place(system, "room", Vector2i(8, 0), 0, 1, 0, Vector2i(1, 1))
	_check(not bool(stuck["ok"]) and str(stuck["reason"]) == "Wider than the level below", "a cell past the floor was accepted: %s" % stuck.get("reason", ""))
	var tool := BuildTool.new()
	_stage.add_child(tool)
	tool.setup(system)
	tool.set_equipped(true)
	tool.select_by_id("room")
	tool.level = 1
	tool.update_aim(Vector3(-0.08, 3.0, -0.08))
	_check(tool.begin_drag(), "could not start a drag on the outer corner")
	tool.update_aim(Vector3(8.08, 3.0, 8.08))
	_check(tool.current_request.get("anchor") == Vector2i(0, 0) and tool.current_request.get("size") == Vector2i(8, 8), "tracing the outside face is %s at %s" % [tool.current_request.get("size"), tool.current_request.get("anchor")])
	_check(tool.current_plan != null and tool.current_plan.is_valid(), "tracing the storey: %s" % (tool.current_plan.first_reason() if tool.current_plan != null else "no plan"))
	tool.cancel_drag()
	tool.update_aim(Vector3(8.6, 3.0, 4.5))
	_check(tool.current_plan != null and str(tool.current_plan.first_reason()) == "Wider than the level below", "a cell clearly outside was accepted: %s" % (tool.current_plan.first_reason() if tool.current_plan != null else ""))
	_kill(system, _walls(system, 0)[0])
	_check(_slabs(system, 4) == 0 and _slabs(system, 1) == 0, "destroying one wall left the tower standing")
	_check(_slabs(system, 0) == 64, "the ground floor fell with the tower")
	_audit(system, "after the full tower lost one wall")


func _test_collapse_falls_from_the_top() -> void:
	var config := BuildingConfig.new()
	config.collapse_delay_sec = 0.0
	config.collapse_span_sec = 0.4
	var system := _begin("each storey waits 0.4s before the one under it drops", config)
	for level in 3:
		_built(system, "room", Vector2i(0, 0), 0, level, 0, Vector2i(1, 1))
	var ground := system.state.get_component(system.state.slab_at(GridSystem.slab_key(Vector2i(0, 0), 0)))
	_check(ground != null and _slabs(system, 3) == 1 and _walls(system, 2).size() == 4, "three storeys were not built")
	if ground == null:
		return
	_kill(system, ground)
	_check(_slabs(system, 3) == 0 and _walls(system, 2).is_empty(), "the roof was still standing after the collapse started")
	_check(_slabs(system, 2) == 1 and _walls(system, 1).size() == 4, "the middle storey fell with the roof")
	_check(_slabs(system, 1) == 1 and _walls(system, 0).size() == 4, "the bottom storey fell before the roof")
	await create_timer(0.25).timeout
	_check(_slabs(system, 2) == 1 and _walls(system, 1).size() == 4, "the middle storey fell before 0.4s")
	await create_timer(0.25).timeout
	_check(_slabs(system, 2) == 0 and _walls(system, 1).is_empty(), "the middle storey was still up after 0.4s")
	_check(_slabs(system, 1) == 1 and _walls(system, 0).size() == 4, "the bottom storey fell with the middle")
	await create_timer(0.5).timeout
	_check(system.state.component_count() == 0, "the tower left %d pieces" % system.state.component_count())
	await create_timer(0.9).timeout
	_check(system.world._falls.is_empty(), "rubble was still falling")
	_audit(system, "after the tower pancaked")


func _test_debug_weight() -> void:
	var system := _begin("debug screen shows floor load")
	_built(system, "room", Vector2i(0, 0), 0, 0, 0, Vector2i(1, 1))
	var overlay := (load("res://scenes/ui/debug_overlay.tscn") as PackedScene).instantiate()
	_stage.add_child(overlay)
	overlay._process(0.0)
	var text := str(overlay.get_node("Panel/Label").text)
	_check(text.contains("Weight") and text.contains("upper tiles") and text.contains("Wall L0"), "weight lines missing:\n%s" % text)
	_check(not text.contains("WASD") and not text.contains("Hotbar") and not text.contains("Build Tool:"), "key help is still on the debug screen")
