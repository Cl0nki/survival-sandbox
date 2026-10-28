extends CanvasLayer
class_name BlueprintMenuUI

## Blueprint selection panel for the Build Tool. It only reads blueprint data
## and plans and calls BuildTool methods; it knows nothing about geometry.
## Icons are drawn from the blueprint data (footprint, openings, kind).

const ICON_SIZE := 40
const PANEL_WIDTH := 330

var tool: BuildTool
var _root: PanelContainer
var _buttons: Array[Button] = []
var _details: Label
var _status: Label
var _reasons: Label
var _icons: Dictionary = {}


func setup(build_tool: BuildTool) -> void:
	tool = build_tool
	layer = 25
	_root = PanelContainer.new()
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.offset_left = -PANEL_WIDTH - 12
	_root.offset_right = -12
	_root.offset_top = 12
	add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_root.add_child(column)
	var title := Label.new()
	title.text = "BUILD TOOL  -  blueprints"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	var current_category := ""
	for i in tool.blueprints.size():
		var blueprint := tool.blueprints[i]
		if blueprint.category != current_category:
			current_category = blueprint.category
			var header := Label.new()
			header.text = current_category.to_upper()
			header.add_theme_font_size_override("font_size", 11)
			header.modulate = Color(0.6, 0.85, 1.0)
			column.add_child(header)
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = icon_for(blueprint)
		button.expand_icon = false
		button.custom_minimum_size = Vector2(0, ICON_SIZE + 4)
		button.text = "  %s   %s" % [blueprint.display_name, _cost_hint(blueprint)]
		button.tooltip_text = blueprint.description
		button.pressed.connect(tool.select_blueprint.bind(i))
		column.add_child(button)
		_buttons.append(button)
	column.add_child(HSeparator.new())
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	_details.add_theme_font_size_override("font_size", 12)
	column.add_child(_details)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	column.add_child(_status)
	_reasons = Label.new()
	_reasons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reasons.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	_reasons.add_theme_font_size_override("font_size", 12)
	column.add_child(_reasons)
	var help := Label.new()
	help.text = "LMB place   RMB cancel   R / Shift+R rotate\nPgUp / PgDn level   [ ] cycle (QWERTZ: Ü +)   F3 debug"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(0.8, 0.8, 0.8)
	column.add_child(help)
	refresh()


func refresh() -> void:
	if _root == null:
		return
	visible = tool.equipped
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == tool.selected)
	var blueprint := tool.selected_blueprint()
	if blueprint == null:
		_details.text = "No blueprint selected. Click one above or press ]."
		return
	var lines := PackedStringArray()
	lines.append("%s  (%s)" % [blueprint.display_name, blueprint.category])
	lines.append(blueprint.description)
	if blueprint.resizable:
		lines.append("Size: hold LMB and drag, %d x %d up to %d x %d cells" % [blueprint.footprint.x, blueprint.footprint.y, blueprint.max_size.x, blueprint.max_size.y])
	elif blueprint.kind == BuildTypes.BlueprintKind.ROOM or blueprint.kind == BuildTypes.BlueprintKind.SLAB or blueprint.kind == BuildTypes.BlueprintKind.STAIRS:
		lines.append("Footprint %d x %d cells%s" % [blueprint.footprint.x, blueprint.footprint.y, ", rotates" if blueprint.rotatable else ""])
	lines.append("Rules: %s" % blueprint.restrictions)
	var full := _full_cost(blueprint)
	if full > 0:
		lines.append("Cost %s %d %s%s" % ["for 1x1:" if blueprint.resizable else "up to", full, tool.system.config.cost_item_id, "" if tool.system.config.require_resources else " (not charged)"])
	lines.append("Level %d   Rotation %d deg" % [tool.level, tool.rotation_steps * 90])
	_details.text = "\n".join(lines)


func show_plan(plan: ConstructionPlan) -> void:
	if _status == null:
		return
	if plan == null:
		_status.text = ""
		_reasons.text = ""
		return
	var valid := plan.is_valid()
	_status.text = "[OK] Placement valid" if valid else "[X] Placement blocked"
	_status.modulate = Color(0.55, 1.0, 0.6) if valid else Color(1.0, 0.5, 0.45)
	var lines := PackedStringArray()
	if not valid:
		for reason in plan.reasons():
			lines.append("- " + reason)
	lines.append_array(plan.summary_lines())
	_reasons.text = "\n".join(lines)


func _cost_hint(blueprint: BlueprintDefinition) -> String:
	var full := _full_cost(blueprint)
	return "" if full <= 0 else "[%d]" % full


## Cost if nothing is shared with existing pieces.
func _full_cost(blueprint: BlueprintDefinition) -> int:
	var config := tool.system.config
	match blueprint.kind:
		BuildTypes.BlueprintKind.ROOM:
			var w := blueprint.footprint.x
			var d := blueprint.footprint.y
			var slabs := w * d * (2 if blueprint.has_ceiling else 1)
			var edges := 2 * (w + d)
			var posts := (w + 1) * (d + 1)
			return slabs * config.cost_of(BuildTypes.Kind.SLAB) + edges * config.cost_of(BuildTypes.Kind.WALL) + posts * config.cost_of(BuildTypes.Kind.POST)
		BuildTypes.BlueprintKind.EDGE:
			return config.cost_of(blueprint.edge_kind) + 2 * config.cost_of(BuildTypes.Kind.POST)
		BuildTypes.BlueprintKind.SLAB:
			return blueprint.footprint.x * blueprint.footprint.y * config.cost_of(BuildTypes.Kind.SLAB)
		BuildTypes.BlueprintKind.STAIRS:
			return config.cost_of(BuildTypes.Kind.STAIRS)
		BuildTypes.BlueprintKind.SUPPORT:
			return config.cost_of(BuildTypes.Kind.POST)
	return 0


func icon_for(blueprint: BlueprintDefinition) -> Texture2D:
	if _icons.has(blueprint.id):
		return _icons[blueprint.id]
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.14, 0.17))
	var wall := Color(0.92, 0.88, 0.8)
	var floor_colour := Color(0.45, 0.4, 0.34)
	var window_colour := Color(0.45, 0.75, 1.0)
	match blueprint.kind:
		BuildTypes.BlueprintKind.ROOM:
			_draw_room(image, blueprint, wall, floor_colour, window_colour)
		BuildTypes.BlueprintKind.EDGE:
			_rect(image, 4, 17, 32, 6, wall)
			if blueprint.edge_kind == BuildTypes.Kind.DOORWAY:
				_rect(image, 13, 17, 14, 6, Color(0.12, 0.14, 0.17))
			elif blueprint.edge_kind == BuildTypes.Kind.WINDOW:
				_rect(image, 13, 18, 14, 4, window_colour)
		BuildTypes.BlueprintKind.SLAB:
			var tint := floor_colour.lightened(0.25) if blueprint.slab_level_offset > 0 else floor_colour
			var n := maxi(blueprint.footprint.x, blueprint.footprint.y)
			var cell := 30 / n
			for z in blueprint.footprint.y:
				for x in blueprint.footprint.x:
					_rect(image, 5 + x * cell, 5 + z * cell, cell - 1, cell - 1, tint)
		BuildTypes.BlueprintKind.STAIRS:
			_rect(image, 14, 4, 12, 32, floor_colour)
			for step in 6:
				_rect(image, 14, 6 + step * 5, 12, 1, wall)
			_rect(image, 19, 2, 2, 6, window_colour)
		BuildTypes.BlueprintKind.SUPPORT:
			_rect(image, 16, 16, 8, 8, wall)
		BuildTypes.BlueprintKind.DISMANTLE:
			for i in 28:
				_rect(image, 6 + i, 6 + i, 2, 2, Color(1.0, 0.35, 0.3))
				_rect(image, 33 - i, 6 + i, 2, 2, Color(1.0, 0.35, 0.3))
	var texture := ImageTexture.create_from_image(image)
	_icons[blueprint.id] = texture
	return texture


func _draw_room(image: Image, blueprint: BlueprintDefinition, wall: Color, floor_colour: Color, window_colour: Color) -> void:
	var w := blueprint.footprint.x
	var d := blueprint.footprint.y
	var cell := mini(32 / w, 32 / d)
	var ox := (ICON_SIZE - cell * w) / 2
	var oz := (ICON_SIZE - cell * d) / 2
	var fill := floor_colour.lightened(0.2) if blueprint.has_ceiling else floor_colour
	_rect(image, ox, oz, cell * w, cell * d, fill)
	_rect(image, ox, oz, cell * w, 2, wall)
	_rect(image, ox, oz + cell * d - 2, cell * w, 2, wall)
	_rect(image, ox, oz, 2, cell * d, wall)
	_rect(image, ox + cell * w - 2, oz, 2, cell * d, wall)
	for item in blueprint.openings:
		var opening := item as BlueprintOpening
		if opening == null:
			continue
		var x := ox + opening.cell.x * cell
		var z := oz + opening.cell.y * cell
		var colour := fill
		if opening.kind == BuildTypes.Kind.WINDOW:
			colour = window_colour
		elif opening.kind == BuildTypes.Kind.WALL:
			colour = wall
		match opening.side:
			BuildTypes.Side.NORTH:
				_rect(image, x + 2, z, cell - 4, 2, colour)
			BuildTypes.Side.SOUTH:
				_rect(image, x + 2, z + cell - 2, cell - 4, 2, colour)
			BuildTypes.Side.WEST:
				_rect(image, x, z + 2, 2, cell - 4, colour)
			BuildTypes.Side.EAST:
				_rect(image, x + cell - 2, z + 2 if opening.kind != BuildTypes.Kind.WALL else z, 2, cell - 4 if opening.kind != BuildTypes.Kind.WALL else cell, colour)


static func _rect(image: Image, x: int, y: int, width: int, height: int, colour: Color) -> void:
	for py in height:
		for px in width:
			var sx := x + px
			var sy := y + py
			if sx >= 0 and sy >= 0 and sx < ICON_SIZE and sy < ICON_SIZE:
				image.set_pixel(sx, sy, colour)
