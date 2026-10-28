extends Node3D
class_name BuildPreview

## Visual-only blueprint preview. It owns pooled MeshInstance3D nodes and a
## Label3D; it never creates physics bodies and never touches BuildingState.
## Transforms come from the same GridSystem functions as committed pieces.
## The preview is rebuilt only when the plan signature changes, so holding the
## cursor still costs nothing and moving it only re-poses pooled nodes.
##
## Visual language (colour is always paired with text in the label):
## - New piece: translucent ghost (green valid / red invalid) plus outline.
## - Reused piece: yellow outline only, drawn on top. No second opaque or
##   translucent surface is placed over an existing piece.
## - Replaced or removed piece: orange outline of the old piece, cyan outline
##   of the replacement.
## - Conflict: red ghost where nothing stands, red outline where something does.
## - Cyan: footprint outline, nearby grid lines, and the front / uphill arrow.

const COLOR_VALID := Color(0.30, 0.95, 0.45, 0.32)
const COLOR_INVALID := Color(1.0, 0.25, 0.20, 0.38)
const LINE_NEW := Color(0.35, 0.90, 1.0, 1.0)
const LINE_REUSE := Color(1.0, 0.86, 0.20, 1.0)
const LINE_REPLACE := Color(1.0, 0.55, 0.15, 1.0)
const LINE_INVALID := Color(1.0, 0.25, 0.20, 1.0)
const GUIDE := Color(0.35, 0.85, 1.0, 0.9)
const GUIDE_FAINT := Color(0.35, 0.85, 1.0, 0.22)
const GRID_MARGIN := 2

var grid: GridSystem
var geometry: BuildingGeometry
var shown_signature := ""
var rebuilds := 0

var _ghosts: Array[MeshInstance3D] = []
var _outlines: Array[MeshInstance3D] = []
var _ghost_used := 0
var _outline_used := 0
var _guides: MeshInstance3D
var _guide_mesh := ImmediateMesh.new()
var _label: Label3D
var _materials: Dictionary = {}


func setup(grid_system: GridSystem, building_geometry: BuildingGeometry) -> void:
	grid = grid_system
	geometry = building_geometry
	name = "BuildPreview"
	_guides = MeshInstance3D.new()
	_guides.name = "Guides"
	_guides.mesh = _guide_mesh
	_guides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guides.material_override = _line_material(Color.WHITE, 0, true)
	add_child(_guides)
	_label = Label3D.new()
	_label.name = "Status"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 30
	_label.outline_size = 9
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.render_priority = 10
	add_child(_label)
	visible = false


func show_plan(plan: ConstructionPlan, signature: String, info: String = "") -> void:
	if visible and signature == shown_signature:
		return
	shown_signature = signature
	rebuilds += 1
	_ghost_used = 0
	_outline_used = 0
	var valid := plan.is_valid()
	for entry in plan.entries:
		var kind := int(entry["kind"])
		var action := int(entry["action"])
		var xform := grid.transform_for(kind, entry["key"])
		match action:
			BuildTypes.Action.CREATE:
				_ghost(kind, xform, COLOR_VALID if valid else COLOR_INVALID)
				_outline(kind, xform, LINE_NEW if valid else LINE_INVALID, 1)
			BuildTypes.Action.REUSE:
				_outline(kind, xform, LINE_REUSE, 0)
			BuildTypes.Action.REPLACE:
				_outline(int(entry.get("existing_kind", BuildTypes.Kind.WALL)), xform, LINE_REPLACE, 0)
				_outline(kind, xform, LINE_NEW if valid else LINE_INVALID, 2)
			BuildTypes.Action.REMOVE:
				_outline(kind, xform, LINE_REPLACE if valid else LINE_INVALID, 1)
			BuildTypes.Action.CONFLICT:
				if int(entry["existing"]) == 0:
					_ghost(kind, xform, COLOR_INVALID)
				_outline(kind, xform, LINE_INVALID, 2)
	for i in range(_ghost_used, _ghosts.size()):
		_ghosts[i].visible = false
	for i in range(_outline_used, _outlines.size()):
		_outlines[i].visible = false
	_draw_guides(plan, valid)
	_write_label(plan, valid, info)
	visible = true


func hide_preview() -> void:
	visible = false
	shown_signature = ""


func pooled_nodes() -> int:
	return _ghosts.size() + _outlines.size()


func visible_pieces() -> int:
	if not visible:
		return 0
	var shown := 0
	for node in _ghosts:
		shown += 1 if node.visible else 0
	for node in _outlines:
		shown += 1 if node.visible else 0
	return shown


func status_text() -> String:
	return _label.text if _label != null else ""


## Ghost transforms currently shown, for tests that compare them with the
## canonical transforms.
func ghost_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for i in _ghost_used:
		result.append(_ghosts[i].transform)
	return result


func _ghost(kind: int, xform: Transform3D, color: Color) -> void:
	if _ghost_used >= _ghosts.size():
		var node := MeshInstance3D.new()
		node.name = "Ghost%d" % _ghosts.size()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_ghosts.append(node)
	var ghost := _ghosts[_ghost_used]
	_ghost_used += 1
	ghost.mesh = geometry.mesh_for(kind)
	ghost.material_override = _ghost_material(color)
	ghost.transform = xform
	ghost.visible = true


func _outline(kind: int, xform: Transform3D, color: Color, priority: int) -> void:
	if _outline_used >= _outlines.size():
		var node := MeshInstance3D.new()
		node.name = "Outline%d" % _outlines.size()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_outlines.append(node)
	var line := _outlines[_outline_used]
	_outline_used += 1
	line.mesh = geometry.outline_mesh(kind)
	line.material_override = _line_material(color, priority, false)
	line.transform = xform
	line.visible = true


func _draw_guides(plan: ConstructionPlan, valid: bool) -> void:
	_guide_mesh.clear_surfaces()
	var y := grid.level_y(plan.level)
	var cells := plan.footprint_cells
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x + 1), maxi(high.y, cell.y + 1))
	var request_anchor: Vector2i = plan.request.get("anchor", Vector2i.ZERO)
	if cells.is_empty():
		low = request_anchor
		high = request_anchor + Vector2i.ONE
	_guide_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(low.x - GRID_MARGIN, high.x + GRID_MARGIN + 1):
		_line(Vector2i(x, low.y - GRID_MARGIN), Vector2i(x, high.y + GRID_MARGIN), y, GUIDE_FAINT)
	for z in range(low.y - GRID_MARGIN, high.y + GRID_MARGIN + 1):
		_line(Vector2i(low.x - GRID_MARGIN, z), Vector2i(high.x + GRID_MARGIN, z), y, GUIDE_FAINT)
	var edge_colour := GUIDE if valid else LINE_INVALID
	var claimed := {}
	for cell in cells:
		claimed[cell] = true
	for cell in cells:
		for side in 4:
			var step: Vector2i = RoomPlacer.SIDE_STEPS[side]
			if claimed.has(cell + step):
				continue
			var key := GridSystem.side_edge(cell, side, plan.level)
			var ends := GridSystem.edge_vertices(key)
			_line(ends[0], ends[1], y, edge_colour)
	if not cells.is_empty():
		var centre := Vector3.ZERO
		for cell in cells:
			centre += grid.doubled_to_world(GridSystem.cell_to_doubled(cell), plan.level)
		centre /= float(cells.size())
		var forward := Vector3(plan.front.x, 0.0, plan.front.y) * grid.config.cell_size
		var side_dir := Vector3(-forward.z, 0.0, forward.x) * 0.35
		var tip := centre + forward * 0.9
		_guide_mesh.surface_set_color(edge_colour)
		_guide_mesh.surface_add_vertex(centre)
		_guide_mesh.surface_set_color(edge_colour)
		_guide_mesh.surface_add_vertex(tip)
		for wing in [side_dir, -side_dir]:
			_guide_mesh.surface_set_color(edge_colour)
			_guide_mesh.surface_add_vertex(tip)
			_guide_mesh.surface_set_color(edge_colour)
			_guide_mesh.surface_add_vertex(tip - forward * 0.35 + wing)
	_guide_mesh.surface_end()
	var label_at := grid.doubled_to_world(low + high, plan.level)
	label_at.y = y + grid.config.floor_height + 0.6
	_label.position = label_at


func _line(a: Vector2i, b: Vector2i, y: float, colour: Color) -> void:
	var pa := grid.doubled_to_world(a * 2, 0)
	var pb := grid.doubled_to_world(b * 2, 0)
	pa.y = y
	pb.y = y
	_guide_mesh.surface_set_color(colour)
	_guide_mesh.surface_add_vertex(pa)
	_guide_mesh.surface_set_color(colour)
	_guide_mesh.surface_add_vertex(pb)


func _write_label(plan: ConstructionPlan, valid: bool, info: String) -> void:
	var lines := PackedStringArray()
	var title := plan.blueprint.display_name if plan.blueprint != null else "?"
	if valid:
		lines.append("[OK] %s" % title)
	else:
		lines.append("[X] %s - %s" % [title, plan.first_reason()])
	if info != "":
		lines.append(info)
	lines.append_array(plan.summary_lines())
	_label.text = "\n".join(lines)
	_label.modulate = Color(0.75, 1.0, 0.8) if valid else Color(1.0, 0.7, 0.65)


func _ghost_material(color: Color) -> StandardMaterial3D:
	var cache_key := "ghost:%s" % color.to_html()
	if _materials.has(cache_key):
		return _materials[cache_key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[cache_key] = material
	return material


func _line_material(color: Color, priority: int, vertex_colors: bool) -> StandardMaterial3D:
	var cache_key := "line:%s:%d:%s" % [color.to_html(), priority, vertex_colors]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_colors
	material.render_priority = priority
	_materials[cache_key] = material
	return material
