extends Node3D
class_name BuildingDebugView

## F3 debug view: grid coordinates and edge ids around the focus point,
## component bounds (white), real collision shapes read from the scene
## (magenta), and audit warnings (red). The geometry audit reruns only when
## the building changes, not every frame. Drawing never adds physics bodies.

const RADIUS := 3
const BOUNDS_COLOUR := Color(1, 1, 1, 0.55)
const SHAPE_COLOUR := Color(1.0, 0.2, 0.9, 0.9)
const ISSUE_COLOUR := Color(1.0, 0.15, 0.1, 1.0)

var system: BuildingSystem
var tool: BuildTool
var enabled := false
var last_report: Dictionary = {}

var _lines := ImmediateMesh.new()
var _line_node: MeshInstance3D
var _labels: Array[Label3D] = []
var _labels_used := 0
var _hud: CanvasLayer
var _hud_label: Label
var _audit_dirty := true
var _focus_key := ""
var _points := PackedVector3Array()
var _colours := PackedColorArray()


func bind(building_system: BuildingSystem) -> void:
	system = building_system
	system.state.changed.connect(_on_changed)
	_line_node = MeshInstance3D.new()
	_line_node.name = "Lines"
	_line_node.mesh = _lines
	_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	_line_node.material_override = material
	add_child(_line_node)
	_hud = CanvasLayer.new()
	_hud.layer = 26
	_hud_label = Label.new()
	_hud_label.anchor_left = 0.5
	_hud_label.anchor_right = 0.5
	_hud_label.offset_left = -260
	_hud_label.offset_top = 8
	_hud_label.add_theme_font_size_override("font_size", 13)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_hud_label)
	add_child(_hud)
	set_enabled(false)


func _on_changed(_change: Dictionary) -> void:
	_audit_dirty = true
	_focus_key = ""


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	_hud.visible = on
	_focus_key = ""
	_audit_dirty = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"build_debug"):
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not enabled:
		return
	refresh()


## Rebuilds the overlay when the building or the focus cell changed.
func refresh() -> void:
	var focus := _focus()
	var level := tool.level if tool != null and tool.equipped else system.grid.level_for_height(focus.y)
	var cell := system.grid.world_to_cell(focus)
	var key := "%s|%d" % [str(cell), level]
	if _audit_dirty:
		last_report = GeometryAudit.run(system)
		_audit_dirty = false
		_focus_key = ""
	if key == _focus_key:
		return
	_focus_key = key
	_labels_used = 0
	_points = PackedVector3Array()
	_colours = PackedColorArray()
	for child in system.world.get_children():
		var node := child as Node3D
		if node == null or not node.has_meta(&"component_id"):
			continue
		var component := system.state.get_component(int(node.get_meta(&"component_id")))
		if component == null:
			continue
		_box(system.geometry.world_aabb(component.kind, node.transform), BOUNDS_COLOUR)
		for box in GeometryAudit._shape_boxes(node):
			_box((box as AABB).grow(0.004), SHAPE_COLOUR)
	for issue: Dictionary in last_report.get("issues", []):
		var at: Vector3 = issue["position"]
		_cross(at, ISSUE_COLOUR)
		_label(at + Vector3.UP * 0.3, "%s: %s" % [issue["type"], issue["message"]], ISSUE_COLOUR)
	_lines.clear_surfaces()
	if not _points.is_empty():
		_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in _points.size():
			_lines.surface_set_color(_colours[i])
			_lines.surface_add_vertex(_points[i])
		_lines.surface_end()
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var c := cell + Vector2i(dx, dz)
			var centre := system.grid.doubled_to_world(GridSystem.cell_to_doubled(c), level)
			_label(centre + Vector3.UP * 0.15, "(%d,%d)" % [c.x, c.y], Color(0.6, 0.9, 1.0))
			for side in [BuildTypes.Side.NORTH, BuildTypes.Side.WEST]:
				var edge := GridSystem.side_edge(c, side, level)
				var piece := system.state.edges.component_at(edge)
				if piece == 0:
					continue
				var at := system.grid.edge_transform(edge).origin + Vector3.UP * 1.6
				_label(at, "%s %d,%d L%d #%d" % ["X" if edge.w == BuildTypes.AXIS_X else "Z", edge.x, edge.y, edge.z, piece], Color(1.0, 0.95, 0.6))
	for i in range(_labels_used, _labels.size()):
		_labels[i].visible = false
	var issues: Array = last_report.get("issues", [])
	_hud_label.text = "BUILD DEBUG (F3)  pieces %d  nodes %d  shapes %d  triangles %d  boundaries %d  links %d\nAudit: %s" % [
		int(last_report.get("components", 0)), int(last_report.get("nodes", 0)), int(last_report.get("shapes", 0)),
		int(last_report.get("triangles", 0)), system.state.edges.size(), system.state.graph.link_count(),
		"OK - no duplicates, overlaps, coplanar faces, or gaps" if issues.is_empty() else "%d issue(s), see red markers" % issues.size(),
	]
	_hud_label.modulate = Color(0.7, 1.0, 0.75) if issues.is_empty() else Color(1.0, 0.6, 0.55)


func _focus() -> Vector3:
	if tool != null and tool.equipped and tool._aim is Vector3:
		return tool._aim
	var player := system._local_player()
	if player != null:
		return player.global_position
	return Vector3.ZERO


func _box(box: AABB, colour: Color) -> void:
	var lines := PackedVector3Array()
	BuildingGeometry._box_lines(lines, box)
	for point in lines:
		_points.append(point)
		_colours.append(colour)


func _cross(at: Vector3, colour: Color) -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_points.append(at - axis * 0.25)
		_colours.append(colour)
		_points.append(at + axis * 0.25)
		_colours.append(colour)


func _label(at: Vector3, text: String, colour: Color) -> void:
	if _labels_used >= _labels.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0008
		label.font_size = 22
		label.outline_size = 6
		label.render_priority = 5
		add_child(label)
		_labels.append(label)
	var target := _labels[_labels_used]
	_labels_used += 1
	target.position = at
	target.text = text
	target.modulate = colour
	target.visible = true
