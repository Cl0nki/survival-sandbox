extends Node
class_name BuildTool

## Player-facing Build Tool. The flow is:
##   aim point -> snapped request -> read-only plan -> preview
##   confirm -> request (not the plan) -> BuildingAuthority
## Snapping is computed from the aim on the build level's plane with
## hysteresis, so the anchor only changes once the cursor is clearly inside
## the next slot. A plan is rebuilt only when the request or the state
## revision changes. Equipping is driven by the player's hotbar item.
## Resizable rooms and floors are dragged: press on one corner cell, release
## on the opposite one. A wall drag stays on the edge where it started and
## runs straight along that line. A click without moving builds one piece.

signal status_changed(text: String)

var system: BuildingSystem
var player: PlayerController
var blueprints: Array[BlueprintDefinition] = []
var selected := 0
var rotation_steps := 0
var level := 0
var equipped := false
var current_plan: ConstructionPlan
var current_request: Dictionary = {}
var last_result: Dictionary = {}
var plans_built := 0
var preview: BuildPreview
var menu: BlueprintMenuUI

var _anchor: Variant = null
var _anchor_mode := ""
var _aim: Variant = null
var _signature := ""
var _drag_start: Variant = null


func setup(building_system: BuildingSystem, owner_player: PlayerController = null) -> void:
	name = "BuildTool"
	system = building_system
	player = owner_player
	blueprints = BlueprintCatalog.all()
	preview = BuildPreview.new()
	system.preview_root.add_child(preview)
	preview.setup(system.grid, system.geometry)
	system.state.changed.connect(_on_state_changed)
	system.debug_view.tool = self
	if player != null:
		menu = BlueprintMenuUI.new()
		add_child(menu)
		menu.setup(self)


func _exit_tree() -> void:
	if system != null and is_instance_valid(system):
		system.cut_override = -2
		if preview != null and is_instance_valid(preview):
			preview.queue_free()


func _process(_delta: float) -> void:
	if player == null:
		return
	set_equipped(player.holds_build_tool())
	if equipped:
		update_aim(_mouse_aim())


func set_equipped(on: bool) -> void:
	if on == equipped:
		return
	equipped = on
	_anchor = null
	_drag_start = null
	if on:
		if player != null:
			level = clampi(system.grid.level_for_height(player.global_position.y), 0, system.config.max_levels - 1)
	else:
		_clear_preview()
		system.cut_override = -2
	if menu != null:
		menu.refresh()


func selected_blueprint() -> BlueprintDefinition:
	if selected < 0 or selected >= blueprints.size():
		return null
	return blueprints[selected]


func select_blueprint(index: int) -> void:
	selected = clampi(index, -1, blueprints.size() - 1)
	_anchor = null
	_drag_start = null
	_signature = ""
	if menu != null:
		menu.refresh()
	update_aim(_aim)


func select_by_id(blueprint_id: String) -> void:
	for i in blueprints.size():
		if blueprints[i].id == blueprint_id:
			select_blueprint(i)
			return


func cycle(delta: int) -> void:
	if blueprints.is_empty():
		return
	select_blueprint(posmod(maxi(selected, 0) + delta, blueprints.size()))


func rotate_blueprint(delta: int) -> void:
	rotation_steps = posmod(rotation_steps + delta, 4)
	_anchor = null
	if menu != null:
		menu.refresh()
	update_aim(_aim)


func change_level(delta: int) -> void:
	level = clampi(level + delta, 0, system.config.max_levels - 1)
	_anchor = null
	_drag_start = null
	if menu != null:
		menu.refresh()
	update_aim(_aim)


## Drops the current blueprint. Nothing was written, so nothing is undone.
func cancel() -> void:
	selected = -1
	_drag_start = null
	_clear_preview()
	_notify("Placement cancelled")
	if menu != null:
		menu.refresh()


func update_aim(point: Variant) -> void:
	_aim = point
	var blueprint := selected_blueprint()
	if not equipped or blueprint == null or not (point is Vector3):
		_clear_preview()
		return
	var request := _request_for(blueprint, point)
	var signature := "%s|%d" % [str(request), system.state.revision]
	if signature != _signature:
		_signature = signature
		current_request = request
		current_plan = system.authority.make_plan(request)
		plans_built += 1
		if menu != null:
			menu.show_plan(current_plan)
	preview.show_plan(current_plan, signature, _info_line())
	system.cut_override = level


func confirm() -> Dictionary:
	if not equipped or current_plan == null or current_request.is_empty():
		return {}
	var requester := player.network_id if player != null else 0
	var result := system.authority.request_place(current_request, requester)
	last_result = result
	var blueprint := selected_blueprint()
	var label := blueprint.display_name if blueprint != null else "piece"
	if bool(result["ok"]) and bool(result["changed"]):
		var plan: ConstructionPlan = result["plan"]
		var summary := plan.summary_lines()
		_notify("Built %s. %s" % [label, summary[0] if not summary.is_empty() else ""])
	elif bool(result["ok"]):
		_notify("%s: already built here" % label)
	else:
		_notify("Cannot build %s: %s" % [label, str(result["reason"])])
	return result


func is_dragging() -> bool:
	return _drag_start is Vector2i or _drag_start is Vector3i


## Starts sizing a resizable blueprint at the hovered cell. Returns false when
## the selected blueprint is not resizable or nothing is aimed at.
func begin_drag() -> bool:
	var blueprint := selected_blueprint()
	if not equipped or blueprint == null or not blueprint.resizable or current_request.is_empty():
		return false
	var anchor: Vector2i = current_request["anchor"]
	if blueprint.kind == BuildTypes.BlueprintKind.EDGE:
		_drag_start = Vector3i(anchor.x, anchor.y, int(current_request.get("axis", 0)))
	else:
		_drag_start = anchor
	_signature = ""
	update_aim(_aim)
	return true


## Builds the dragged rectangle and goes back to hovering.
func end_drag() -> Dictionary:
	var result := confirm()
	cancel_drag()
	return result


func cancel_drag() -> void:
	_drag_start = null
	_anchor = null
	_signature = ""
	update_aim(_aim)


func _unhandled_input(event: InputEvent) -> void:
	if not equipped:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if not button.pressed:
				if is_dragging():
					end_drag()
					get_viewport().set_input_as_handled()
				return
			if player == null or player.container_view == null:
				if not begin_drag():
					confirm()
			get_viewport().set_input_as_handled()
			return
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			if is_dragging():
				cancel_drag()
				_notify("Sizing cancelled")
			else:
				cancel()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"build_rotate"):
		var reverse := event is InputEventKey and (event as InputEventKey).shift_pressed
		rotate_blueprint(-1 if reverse else 1)
	elif event.is_action_pressed(&"build_level_up"):
		change_level(1)
	elif event.is_action_pressed(&"build_level_down"):
		change_level(-1)
	elif event.is_action_pressed(&"build_next"):
		cycle(1)
	elif event.is_action_pressed(&"build_prev"):
		cycle(-1)
	else:
		return
	get_viewport().set_input_as_handled()


# --- snapping ------------------------------------------------------------------

func _request_for(blueprint: BlueprintDefinition, point: Vector3) -> Dictionary:
	var g := system.grid.world_to_grid(point)
	var steps := rotation_steps if blueprint.rotatable else 0
	match blueprint.kind:
		BuildTypes.BlueprintKind.EDGE:
			if blueprint.resizable:
				return _edge_drag_request(blueprint, g)
			var edge := _snap_edge(g, "edge")
			return RoomPlacer.make_request(blueprint.id, Vector2i(edge.x, edge.y), 0, level, edge.z)
		BuildTypes.BlueprintKind.SUPPORT:
			return RoomPlacer.make_request(blueprint.id, _snap_vertex(g), 0, level)
		BuildTypes.BlueprintKind.DISMANTLE:
			var target := _pick_target(g)
			return RoomPlacer.make_request(blueprint.id, Vector2i(floori(g.x), floori(g.y)), 0, level, 0, target)
		_:
			if blueprint.resizable:
				var hovered := _snap_cells(g, Vector2i.ONE)
				if level > 0:
					hovered = _pull_to_floor_below(g, hovered)
				return _drag_request(blueprint, hovered)
			var size := GridSystem.rotated_size(blueprint.footprint, steps)
			return RoomPlacer.make_request(blueprint.id, _snap_cells(g, size), steps, level)


## A straight run along the edge where the drag started. Moving sideways does
## not turn the corner. Without a drag it is the single hovered edge.
func _edge_drag_request(blueprint: BlueprintDefinition, g: Vector2) -> Dictionary:
	if not (_drag_start is Vector3i):
		var edge := _snap_edge(g, "edge")
		return RoomPlacer.make_request(blueprint.id, Vector2i(edge.x, edge.y), 0, level, edge.z, 0, Vector2i.ONE)
	var start: Vector3i = _drag_start
	var along := g.x if start.z == BuildTypes.AXIS_X else g.y
	var origin := start.x if start.z == BuildTypes.AXIS_X else start.y
	var end_index := _run_index(along, start.z)
	var reach := blueprint.max_size.x - 1
	end_index = clampi(end_index, origin - reach, origin + reach)
	var low := mini(origin, end_index)
	var anchor := Vector2i(low, start.y) if start.z == BuildTypes.AXIS_X else Vector2i(start.x, low)
	return RoomPlacer.make_request(blueprint.id, anchor, 0, level, start.z, 0, Vector2i(absi(end_index - origin) + 1, 1))


## Edge index along a wall run. Holds the current segment until the cursor is
## clearly past its far end, matching the cell-snap hysteresis.
func _run_index(along: float, axis: int) -> int:
	var mode := "run:%d" % axis
	var h := system.config.snap_hysteresis
	if mode == _anchor_mode and _anchor is int:
		var current: int = _anchor
		if along >= float(current) - h and along <= float(current) + 1.0 + h:
			return current
	var candidate := floori(along)
	_anchor_mode = mode
	_anchor = candidate
	return candidate


## The rectangle between the drag start and the hovered cell, clamped to the
## blueprint's max_size. Without a drag it is the single hovered cell.
func _drag_request(blueprint: BlueprintDefinition, cell: Vector2i) -> Dictionary:
	if not (_drag_start is Vector2i):
		return RoomPlacer.make_request(blueprint.id, cell, 0, level, 0, 0, blueprint.footprint)
	var start: Vector2i = _drag_start
	var reach := blueprint.max_size - Vector2i.ONE
	var end := cell.clamp(start - reach, start + reach)
	var low := Vector2i(mini(start.x, end.x), mini(start.y, end.y))
	return RoomPlacer.make_request(blueprint.id, low, 0, level, 0, 0, (end - start).abs() + Vector2i.ONE)


## Aiming at the outside face of a wall lands just past the floor. Pull that
## cell back onto the floor below so tracing the storey does not count as wider.
func _pull_to_floor_below(g: Vector2, cell: Vector2i) -> Vector2i:
	if _floor_below(cell):
		return cell
	var margin := system.config.snap_hysteresis + system.config.wall_thickness
	var best := cell
	var best_dist := margin
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var other := cell + Vector2i(dx, dz)
			if not _floor_below(other):
				continue
			var dist := _distance_to_cell(g, other)
			if dist < best_dist or (is_equal_approx(dist, best_dist) and other.x + other.y < best.x + best.y):
				best = other
				best_dist = dist
	return best


func _floor_below(cell: Vector2i) -> bool:
	var below := GridSystem.slab_key(cell, level - 1)
	return system.state.slab_at(below) != 0 or system.state.stairwell_at(below) != 0


func _distance_to_cell(g: Vector2, cell: Vector2i) -> float:
	var dx := 0.0
	if g.x < float(cell.x):
		dx = float(cell.x) - g.x
	elif g.x > float(cell.x) + 1.0:
		dx = g.x - (float(cell.x) + 1.0)
	var dz := 0.0
	if g.y < float(cell.y):
		dz = float(cell.y) - g.y
	elif g.y > float(cell.y) + 1.0:
		dz = g.y - (float(cell.y) + 1.0)
	return Vector2(dx, dz).length()


func _snap_cells(g: Vector2, size: Vector2i) -> Vector2i:
	var mode := "cells:%s" % str(size)
	var fx := g.x - float(size.x) * 0.5
	var fz := g.y - float(size.y) * 0.5
	var limit := 0.5 + system.config.snap_hysteresis
	if mode == _anchor_mode and _anchor is Vector2i:
		var current: Vector2i = _anchor
		if absf(fx - current.x) <= limit and absf(fz - current.y) <= limit:
			return current
	var candidate := Vector2i(roundi(fx), roundi(fz))
	_anchor_mode = mode
	_anchor = candidate
	return candidate


func _snap_vertex(g: Vector2) -> Vector2i:
	var limit := 0.5 + system.config.snap_hysteresis
	if _anchor_mode == "vertex" and _anchor is Vector2i:
		var current: Vector2i = _anchor
		if absf(g.x - current.x) <= limit and absf(g.y - current.y) <= limit:
			return current
	var candidate := Vector2i(roundi(g.x), roundi(g.y))
	_anchor_mode = "vertex"
	_anchor = candidate
	return candidate


## Returns Vector3i(x, z, axis) of the nearest boundary.
func _snap_edge(g: Vector2, mode: String) -> Vector3i:
	var round_z := roundi(g.y)
	var round_x := roundi(g.x)
	var dist_z := absf(g.y - round_z)
	var dist_x := absf(g.x - round_x)
	var candidate := Vector3i(floori(g.x), round_z, BuildTypes.AXIS_X)
	var best := dist_z
	if dist_x < dist_z:
		candidate = Vector3i(round_x, floori(g.y), BuildTypes.AXIS_Z)
		best = dist_x
	var h := system.config.snap_hysteresis
	if _anchor_mode == mode and _anchor is Vector3i:
		var current: Vector3i = _anchor
		var along := g.x - current.x if current.z == BuildTypes.AXIS_X else g.y - current.y
		var dist := absf(g.y - current.y) if current.z == BuildTypes.AXIS_X else absf(g.x - current.x)
		if along >= -h and along <= 1.0 + h and dist <= best + h:
			return current
	_anchor_mode = mode
	_anchor = candidate
	return candidate


## Dismantle target: the boundary under the cursor if it carries a piece and
## the cursor is close to it, else stairs, else the floor slab of the cell.
func _pick_target(g: Vector2) -> int:
	var state := system.state
	var edge := _snap_edge(g, "dismantle")
	var key := Vector4i(edge.x, edge.y, level, edge.z)
	var dist := absf(g.y - edge.y) if edge.z == BuildTypes.AXIS_X else absf(g.x - edge.x)
	var edge_piece := state.edges.component_at(key)
	if edge_piece != 0 and dist <= 0.3:
		return edge_piece
	var cell := GridSystem.slab_key(Vector2i(floori(g.x), floori(g.y)), level)
	if state.stairs_at(cell) != 0:
		return state.stairs_at(cell)
	if state.slab_at(cell) != 0:
		return state.slab_at(cell)
	return edge_piece


func _mouse_aim() -> Variant:
	var camera := player.current_camera()
	if camera == null:
		return null
	var mouse := player.get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, system.grid.level_y(level))
	return plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


func _info_line() -> String:
	var request := current_request
	var anchor: Vector2i = request.get("anchor", Vector2i.ZERO)
	var text := "Level %d   Rotation %d deg   Grid (%d, %d)" % [level, rotation_steps * 90, anchor.x, anchor.y]
	var blueprint := selected_blueprint()
	if blueprint != null and blueprint.kind == BuildTypes.BlueprintKind.EDGE:
		var axis_name := "X" if int(request.get("axis", 0)) == 0 else "Z"
		if blueprint.resizable:
			var run: Vector2i = request.get("size", Vector2i.ONE)
			text = "Level %d   %s run of %d   Edge (%d, %d)   %s" % [level, axis_name, run.x, anchor.x, anchor.y, "release to build" if is_dragging() else "hold LMB and drag along the edge"]
		else:
			text = "Level %d   Edge %s (%d, %d)" % [level, axis_name, anchor.x, anchor.y]
	elif blueprint != null and blueprint.resizable:
		var size: Vector2i = request.get("size", blueprint.footprint)
		text = "Level %d   Size %d x %d   Grid (%d, %d)   %s" % [level, size.x, size.y, anchor.x, anchor.y, "release to build" if is_dragging() else "hold LMB and drag to size"]
	return text


func _clear_preview() -> void:
	if preview != null:
		preview.hide_preview()
	current_plan = null
	current_request = {}
	_signature = ""
	if menu != null:
		menu.show_plan(null)


func _on_state_changed(_change: Dictionary) -> void:
	_signature = ""
	if equipped and _aim is Vector3:
		update_aim(_aim)


func _notify(text: String) -> void:
	status_changed.emit(text)
	if player != null:
		player.show_item_notice(text)
