extends Node
class_name DeployTool

## Hotbar deployables. Selecting one shows its footprint ghost. Left click
## places it when the aim point and the piece are within 5 m. R rotates a
## cell piece. A chest ghost is the 2x1 with the box in the middle. A door
## or window bars ghost sits in the opening under the cursor.

const VALID := Color(0.30, 0.95, 0.45, 0.35)
const INVALID := Color(1.0, 0.25, 0.20, 0.38)
const LINE_OK := Color(0.35, 0.90, 1.0, 1.0)
const LINE_BAD := Color(1.0, 0.25, 0.20, 1.0)

var deployables: DeployableSystem
var building: BuildingSystem
var player: PlayerController
var rotation_steps := 0
var equipped := false

var _ghost: MeshInstance3D
var _lip: MeshInstance3D
var _lines: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _label: Label3D
var _valid_mat: StandardMaterial3D
var _invalid_mat: StandardMaterial3D
var _anchor: Variant = null
var _anchor_mode := ""
var _signature := ""
var _shown := false
var _drawing := false


func setup(system: DeployableSystem, grid_host: BuildingSystem, owner_player: PlayerController = null) -> void:
	name = "DeployTool"
	deployables = system
	building = grid_host
	player = owner_player
	var preview := Node3D.new()
	preview.name = "DeployPreview"
	system.add_child(preview)
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.add_child(_ghost)
	_lip = MeshInstance3D.new()
	_lip.name = "Front"
	_lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(_lip)
	_lines = MeshInstance3D.new()
	_lines.name = "Footprint"
	_lines.mesh = _line_mesh
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.material_override = _line_material()
	preview.add_child(_lines)
	_label = Label3D.new()
	_label.name = "Status"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 28
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate = Color.WHITE
	preview.add_child(_label)
	_valid_mat = _ghost_material(VALID)
	_invalid_mat = _ghost_material(INVALID)
	_hide()


func _process(_delta: float) -> void:
	if player == null or deployables == null:
		return
	var kind := player.held_item_id()
	var on := DeployableCatalog.known(kind)
	if on != equipped:
		equipped = on
		_anchor = null
		_signature = ""
		if not on:
			_hide()
	if not equipped:
		return
	var aim_info := player.cursor_aim()
	preview_at(kind, aim_info["point"], player.global_position, rotation_steps, aim_info.get("normal", Vector3.UP))


func ghost_shown() -> bool:
	return _shown and _ghost != null and _ghost.visible


func preview_at(kind: String, aim: Vector3, from: Vector3, rotation: int, normal: Vector3 = Vector3.UP) -> Dictionary:
	rotation_steps = posmod(rotation, 4)
	var plan := _plan(kind, aim, from, normal)
	var signature := "%s|%d|%d|%s|%s|%s" % [kind, rotation_steps, int(plan.get("level", 0)), str(plan.get("anchor", Vector2i.ZERO)), str(plan.get("edge", Vector4i.ZERO)), str(plan.get("ok", false)) + str(plan.get("reason", ""))]
	if signature != _signature:
		_signature = signature
		_show(plan)
	return plan


func place_from(bag: Inventory, slot: int, kind: String, aim: Vector3, from: Vector3, rotation: int) -> Dictionary:
	var plan := preview_at(kind, aim, from, rotation)
	if not bool(plan.get("ok", false)):
		return {"ok": false, "reason": str(plan.get("reason", "")), "id": 0}
	if bag == null or slot < 0 or slot >= bag.capacity:
		return {"ok": false, "reason": "Not in hand", "id": 0}
	var held: Dictionary = bag.slots[slot]
	if str(held.get("id", "")) != kind or int(held.get("qty", 0)) < 1:
		return {"ok": false, "reason": "Not in hand", "id": 0}
	var placed: Dictionary
	if DeployableCatalog.on_cells(kind):
		placed = deployables.try_place(kind, plan["anchor"], int(plan["steps"]), int(plan["level"]))
	else:
		placed = deployables.try_place_edge(kind, plan["edge"])
	if bool(placed.get("ok", false)):
		bag.remove_from_slot(slot, 1)
		_signature = ""
	return placed


func _unhandled_input(event: InputEvent) -> void:
	if not equipped or player == null:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			if player.container_view == null:
				_click()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_rotate"):
		var reverse := event is InputEventKey and (event as InputEventKey).shift_pressed
		rotation_steps = posmod(rotation_steps + (-1 if reverse else 1), 4)
		_anchor = null
		_signature = ""
		get_viewport().set_input_as_handled()


func _click() -> void:
	var kind := player.held_item_id()
	if not DeployableCatalog.known(kind):
		return
	var aim_info := player.cursor_aim()
	var aim: Vector3 = aim_info["point"]
	var plan := preview_at(kind, aim, player.global_position, rotation_steps, aim_info.get("normal", Vector3.UP))
	if not deployables.local_authority():
		if not bool(plan.get("ok", false)):
			player.show_item_notice("Cannot place %s: %s" % [DeployableCatalog.display_name(kind), str(plan.get("reason", ""))])
			return
		var edge: Vector4i = plan.get("edge", Vector4i(0, 0, int(plan.get("level", 0)), -1))
		var anchor: Vector2i = plan.get("anchor", Vector2i.ZERO)
		deployables.request_place(kind, anchor, int(plan.get("steps", 0)), int(plan.get("level", 0)), edge)
		player.show_item_notice("Placing %s..." % DeployableCatalog.display_name(kind))
		return
	var placed := place_from(player.inventory, player.hotbar_index, kind, aim, player.global_position, rotation_steps)
	var label := DeployableCatalog.display_name(kind)
	if bool(placed.get("ok", false)):
		player.show_item_notice("Placed %s" % label)
		player.inventory_changed.emit()
	else:
		player.show_item_notice("Cannot place %s: %s" % [label, str(placed.get("reason", ""))])


func _plan(kind: String, aim: Vector3, from: Vector3, normal: Vector3) -> Dictionary:
	var level := _level_for(aim, normal)
	var plan: Dictionary
	if DeployableCatalog.on_cells(kind):
		var size := GridSystem.rotated_size(DeployableCatalog.footprint(kind), rotation_steps)
		var anchor := _snap_anchor(aim, size)
		plan = deployables.plan_cells(kind, anchor, rotation_steps, level)
	else:
		var edge := _slot_edge(kind, aim, level)
		plan = deployables.plan_edge(kind, edge)
		plan["anchor"] = Vector2i(edge.x, edge.y)
	_apply_range(plan, aim, from)
	_reject_body(plan, from)
	return plan


func _apply_range(plan: Dictionary, aim: Vector3, from: Vector3) -> void:
	var center: Vector3 = plan.get("center", aim)
	var edge: Variant = plan.get("edge", null)
	var count_center := not (edge is Vector4i and (edge as Vector4i).w < 0)
	var reached := DeployableSystem.in_place_range(from, aim)
	if count_center:
		reached = reached and DeployableSystem.in_place_range(from, center)
	if reached:
		return
	plan["ok"] = false
	plan["reason"] = "Too far"


func _reject_body(plan: Dictionary, feet: Vector3) -> void:
	if not bool(plan.get("ok", false)):
		return
	if not DeployableCatalog.on_cells(str(plan.get("kind", ""))):
		return
	var height := 1.8
	if player != null:
		height = player.body_height()
	if deployables.blocks_player(plan.get("volume", AABB()), feet, height):
		plan["ok"] = false
		plan["reason"] = "Blocked by you"


func _level_for(point: Vector3, normal: Vector3) -> int:
	var y := point.y
	if normal.dot(Vector3.UP) <= 0.6 and player != null:
		y = player.global_position.y
	return clampi(building.grid.level_for_height(y), 0, building.config.max_levels - 1)


func _snap_anchor(point: Vector3, size: Vector2i) -> Vector2i:
	var g := building.grid.world_to_grid(point)
	var fx := g.x - float(size.x) * 0.5
	var fz := g.y - float(size.y) * 0.5
	var limit := 0.5 + building.config.snap_hysteresis
	var mode := "cells:%s" % str(size)
	if mode == _anchor_mode and _anchor is Vector2i:
		var current: Vector2i = _anchor
		if absf(fx - current.x) <= limit and absf(fz - current.y) <= limit:
			return current
	var candidate := Vector2i(roundi(fx), roundi(fz))
	_anchor_mode = mode
	_anchor = candidate
	return candidate


func _slot_edge(kind: String, point: Vector3, level: int) -> Vector4i:
	var need := DeployableCatalog.slot_kind(kind)
	var cell := building.grid.world_to_cell(point)
	var best_match := Vector4i(0, 0, level, -1)
	var best_match_dist := 1.6
	var best_any := Vector4i(0, 0, level, -1)
	var best_any_dist := 0.4
	var seen := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var here := cell + Vector2i(dx, dz)
			for side in 4:
				var edge := GridSystem.side_edge(here, side, level)
				if seen.has(edge):
					continue
				seen[edge] = true
				var mid := building.grid.edge_transform(edge).origin
				var dist := Vector2(mid.x - point.x, mid.z - point.z).length()
				var host := building.state.get_component(building.state.edges.component_at(edge))
				if host != null and not host.destroyed and host.kind == need and dist < best_match_dist:
					best_match = edge
					best_match_dist = dist
				elif dist < best_any_dist:
					best_any = edge
					best_any_dist = dist
	if best_match.w >= 0:
		return best_match
	return best_any


func _show(plan: Dictionary) -> void:
	var ok := bool(plan.get("ok", false))
	var kind := str(plan.get("kind", ""))
	_line_mesh.clear_surfaces()
	_drawing = false
	var line_color := LINE_OK if ok else LINE_BAD
	if DeployableCatalog.on_cells(kind) and plan.get("body", Vector3.ZERO) != Vector3.ZERO:
		var body: Vector3 = plan["body"]
		var center: Vector3 = plan["center"]
		var basis := GridSystem.rotation_basis(int(plan.get("steps", 0)))
		_ghost.basis = basis
		_ghost.position = center + Vector3(0.0, body.y * 0.5, 0.0)
		var box := BoxMesh.new()
		box.size = body
		_ghost.mesh = box
		_ghost.material_override = _valid_mat if ok else _invalid_mat
		_ghost.visible = true
		_draw_aabb(Transform3D(basis, _ghost.position), AABB(body * -0.5, body), line_color)
		_draw_cells(plan.get("cells", []), float(plan.get("support_y", center.y)) + 0.04, line_color)
		if kind == "chest":
			var lip := BoxMesh.new()
			lip.size = Vector3(body.x * 0.72, body.y * 0.22, 0.04)
			_lip.mesh = lip
			_lip.position = Vector3(0.0, body.y * 0.42 - body.y * 0.5, body.z * 0.5)
			var lip_mat := StandardMaterial3D.new()
			lip_mat.albedo_color = Color(0.28, 0.18, 0.1, 0.9)
			lip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			lip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_lip.set_surface_override_material(0, lip_mat)
			_lip.visible = true
		else:
			_lip.visible = false
		_label.position = _ghost.position + Vector3(0.0, body.y * 0.5 + 0.35, 0.0)
	elif plan.has("local") and (plan["local"] as AABB).size.length_squared() > 0.0 and int((plan.get("edge", Vector4i.ZERO) as Vector4i).w) >= 0:
		var local: AABB = plan["local"]
		var xform: Transform3D = plan["xform"]
		_ghost.basis = xform.basis
		_ghost.position = xform * local.get_center()
		var box := BoxMesh.new()
		box.size = local.size
		_ghost.mesh = box
		_ghost.material_override = _valid_mat if ok else _invalid_mat
		_ghost.visible = true
		_lip.visible = false
		_draw_aabb(xform, local, line_color)
		_label.position = _ghost.position + Vector3(0.0, local.size.y * 0.5 + 0.25, 0.0)
	else:
		_ghost.visible = false
		_lip.visible = false
		_label.position = plan.get("center", Vector3.ZERO) + Vector3(0.0, 0.4, 0.0)
	if _drawing:
		_line_mesh.surface_end()
	var footprint: Vector2i = DeployableCatalog.footprint(kind)
	var title := DeployableCatalog.display_name(kind)
	if footprint != Vector2i.ZERO:
		title = "%s  %dx%d" % [title, footprint.x, footprint.y]
	var reason := str(plan.get("reason", ""))
	_label.text = title if reason == "" else "%s\n%s" % [title, reason]
	_label.modulate = Color(0.75, 1.0, 0.8) if ok else Color(1.0, 0.55, 0.45)
	_label.visible = true
	_lines.visible = _line_mesh.get_surface_count() > 0
	_shown = true


func _draw_cells(cells: Array, y: float, color: Color) -> void:
	var origin := building.grid.config.grid_origin
	var span := building.grid.config.cell_size
	for cell in cells:
		var here := cell as Vector2i
		var x0 := origin.x + float(here.x) * span
		var z0 := origin.z + float(here.y) * span
		var x1 := x0 + span
		var z1 := z0 + span
		_segment(Vector3(x0, y, z0), Vector3(x1, y, z0), color)
		_segment(Vector3(x1, y, z0), Vector3(x1, y, z1), color)
		_segment(Vector3(x1, y, z1), Vector3(x0, y, z1), color)
		_segment(Vector3(x0, y, z1), Vector3(x0, y, z0), color)


func _draw_aabb(xform: Transform3D, local: AABB, color: Color) -> void:
	var corners: Array[Vector3] = []
	var end := local.position + local.size
	for y in [local.position.y, end.y]:
		for z in [local.position.z, end.z]:
			for x in [local.position.x, end.x]:
				corners.append(xform * Vector3(x, y, z))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_segment(corners[pair[0]], corners[pair[1]], color)


func _segment(a: Vector3, b: Vector3, color: Color) -> void:
	if not _drawing:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_drawing = true
	_line_mesh.surface_set_color(color)
	_line_mesh.surface_add_vertex(a)
	_line_mesh.surface_set_color(color)
	_line_mesh.surface_add_vertex(b)


func _hide() -> void:
	_shown = false
	_signature = ""
	if _ghost != null:
		_ghost.visible = false
	if _lip != null:
		_lip.visible = false
	if _label != null:
		_label.visible = false
	if _lines != null:
		_lines.visible = false
	if _line_mesh != null:
		_line_mesh.clear_surfaces()


func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
