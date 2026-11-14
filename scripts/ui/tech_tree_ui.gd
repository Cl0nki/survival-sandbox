extends CanvasLayer
class_name TechTreeUI

## Encyclopedia of every craft / smelt recipe and the path to reach each item.
## Toggle with H.

const _Icons = preload("res://scripts/items/item_icons.gd")

const SLOT := 72
const GRID_GAP := 4
const LIST_COLS := 5
const PANEL_W := 920
const LIST_H := 420
const PATH_ROW := 36

var _player: PlayerController
var _screen: Control
var _category := ""
var _selected: Dictionary = {}
var _recipes: Array = []
var _alt_index := 0

var _tabs: HBoxContainer
var _list: GridContainer
var _name: Label
var _station: Label
var _blurb: Label
var _needs: GridContainer
var _alt_row: HBoxContainer
var _path: VBoxContainer
var _tab_buttons: Dictionary = {}
var _list_buttons: Array = []


func bind_player(player: PlayerController) -> void:
	_player = player


func is_open() -> bool:
	return _screen != null and _screen.visible


func close() -> void:
	if not is_open():
		return
	_screen.visible = false
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()


func _ready() -> void:
	layer = 29
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_screen = PanelContainer.new()
	_screen.visible = false
	_screen.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(_screen)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	_screen.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	root.add_child(head)
	var title := Label.new()
	title.text = "Tech Tree"
	title.add_theme_font_size_override(&"font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := Label.new()
	hint.text = "H / Esc"
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	head.add_child(hint)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 8)
	root.add_child(_tabs)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	root.add_child(body)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_COLS * SLOT + (LIST_COLS - 1) * GRID_GAP + 14, LIST_H)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	body.add_child(list_scroll)
	_list = GridContainer.new()
	_list.columns = LIST_COLS
	_list.add_theme_constant_override(&"h_separation", GRID_GAP)
	_list.add_theme_constant_override(&"v_separation", GRID_GAP)
	list_scroll.add_child(_list)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, LIST_H)
	detail.add_theme_constant_override(&"separation", 6)
	body.add_child(detail)

	_name = Label.new()
	_name.add_theme_font_size_override(&"font_size", 18)
	detail.add_child(_name)

	_station = Label.new()
	_station.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.75))
	detail.add_child(_station)

	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(0, 48)
	_blurb.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.65))
	detail.add_child(_blurb)

	_alt_row = HBoxContainer.new()
	_alt_row.add_theme_constant_override(&"separation", 6)
	_alt_row.visible = false
	detail.add_child(_alt_row)

	var needs_label := Label.new()
	needs_label.text = "Recipe"
	needs_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	detail.add_child(needs_label)

	_needs = GridContainer.new()
	_needs.columns = 3
	_needs.add_theme_constant_override(&"h_separation", GRID_GAP)
	_needs.add_theme_constant_override(&"v_separation", GRID_GAP)
	detail.add_child(_needs)
	for _i in 3:
		_needs.add_child(_empty_slot(SLOT))

	var path_label := Label.new()
	path_label.text = "How to reach"
	path_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	detail.add_child(path_label)

	var path_scroll := ScrollContainer.new()
	path_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	path_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	path_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	detail.add_child(path_scroll)
	_path = VBoxContainer.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.add_theme_constant_override(&"separation", 2)
	path_scroll.add_child(_path)

	_recipes = TechTree.all_recipes()


func _input(event: InputEvent) -> void:
	if _player == null:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if is_open():
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"tech_tree"):
		if is_open():
			close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	if _player != null and _player.has_method("close_inventory"):
		_player.call("close_inventory")
	_ensure_selection()
	_rebuild_tabs()
	_rebuild_list()
	_paint_detail()
	_screen.visible = true


func _ensure_selection() -> void:
	var cats := _categories()
	if cats.is_empty():
		_category = ""
		_selected = {}
		_alt_index = 0
		return
	if _category == "" or not cats.has(_category):
		_category = str(cats[0])
	var items := _outputs_in(_category)
	if items.is_empty():
		_selected = {}
		_alt_index = 0
		return
	if not _selected.is_empty():
		var keep := str(_selected.get("output", ""))
		for output_id in items:
			if str(output_id) == keep:
				_selected = _pick_recipe(keep)
				return
	_selected = _pick_recipe(str(items[0]))
	_alt_index = 0


func _pick_recipe(output_id: String) -> Dictionary:
	var options := TechTree.recipes_for_output(output_id)
	if options.is_empty():
		return {}
	_alt_index = clampi(_alt_index, 0, options.size() - 1)
	return options[_alt_index]


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var cats := _categories()
	for i in cats.size():
		if i > 0:
			var sep := Label.new()
			sep.text = "||"
			sep.modulate = Color(1, 1, 1, 0.35)
			_tabs.add_child(sep)
		var cat := str(cats[i])
		var tab := Button.new()
		tab.text = cat
		tab.flat = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_select_category.bind(cat))
		_tabs.add_child(tab)
		_tab_buttons[cat] = tab
	_style_tabs()


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_list_buttons.clear()
	for output_id in _outputs_in(_category):
		var button := _empty_slot(SLOT)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var picture := TextureRect.new()
		_fill_slot_icon(picture)
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(str(output_id)))
		button.add_child(picture)
		button.pressed.connect(_select_output.bind(str(output_id)))
		_list.add_child(button)
		_list_buttons.append({"button": button, "output": str(output_id)})
	_paint_list_state()


func _style_tabs() -> void:
	for cat in _tab_buttons.keys():
		var tab: Button = _tab_buttons[cat]
		var selected := str(cat) == _category
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 2
		style.content_margin_bottom = 4
		style.border_width_bottom = 2
		style.border_color = Color.WHITE if selected else Color(0, 0, 0, 0)
		tab.add_theme_stylebox_override(&"normal", style)
		tab.add_theme_stylebox_override(&"hover", style)
		tab.add_theme_stylebox_override(&"pressed", style)
		tab.add_theme_stylebox_override(&"focus", style)
		tab.add_theme_color_override(&"font_color", Color.WHITE if selected else Color(1, 1, 1, 0.55))
		tab.add_theme_color_override(&"font_hover_color", Color.WHITE)


func _paint_list_state() -> void:
	var selected_id := str(_selected.get("output", ""))
	for entry in _list_buttons:
		var button: Button = entry["button"]
		_clear_extra(button)
		if str(entry["output"]) == selected_id:
			button.add_child(_selection_border())


func _paint_detail() -> void:
	if _selected.is_empty():
		_name.text = ""
		_station.text = ""
		_blurb.text = "No recipes."
		_alt_row.visible = false
		_fill_need_slots([])
		_clear_path()
		return
	var output_id := str(_selected["output"])
	var definition := ItemCatalog.get_item(output_id)
	_name.text = definition.display_name if definition != null else output_id
	var station := TechTree.station_for(_selected)
	var station_name := str(station.get("name", TechTree.family_label(str(_selected.get("family", "")))))
	_station.text = "Made at %s  ·  %s tier %d" % [
		station_name,
		TechTree.family_label(str(_selected.get("family", ""))),
		int(_selected.get("tier", 1)),
	]
	_blurb.text = definition.description if definition != null and definition.description != "" else "No description."
	_paint_alts(output_id)
	var needs: Array = [{"id": str(_selected["input"]), "need": int(_selected["in_n"])}]
	if int(_selected.get("extra_n", 0)) > 0 and str(_selected.get("extra", "")) != "":
		needs.append({"id": str(_selected["extra"]), "need": int(_selected["extra_n"])})
	needs.append({"id": output_id, "need": int(_selected.get("out_n", 1)), "result": true})
	_fill_need_slots(needs)
	_paint_path()


func _paint_alts(output_id: String) -> void:
	for child in _alt_row.get_children():
		_alt_row.remove_child(child)
		child.queue_free()
	var options := TechTree.recipes_for_output(output_id)
	if options.size() <= 1:
		_alt_row.visible = false
		return
	_alt_row.visible = true
	var label := Label.new()
	label.text = "Routes"
	label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	_alt_row.add_child(label)
	for i in options.size():
		var option: Dictionary = options[i]
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		var station := TechTree.station_for(option)
		btn.text = str(station.get("name", "Route %d" % (i + 1)))
		btn.disabled = i == _alt_index
		btn.pressed.connect(_select_alt.bind(i))
		_alt_row.add_child(btn)


func _paint_path() -> void:
	_clear_path()
	var rows := TechTree.path_for(_selected)
	## Skip the root row — the header already covers the selected item.
	for i in rows.size():
		if i == 0:
			continue
		var row: Dictionary = rows[i]
		_path.add_child(_path_row(row))


func _path_row(row: Dictionary) -> Control:
	var wrap := HBoxContainer.new()
	wrap.custom_minimum_size = Vector2(0, PATH_ROW)
	wrap.add_theme_constant_override(&"separation", 6)
	var indent := int(row.get("depth", 1))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(maxi(indent - 1, 0) * 18, PATH_ROW)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(spacer)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(PATH_ROW - 4, PATH_ROW - 4)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _Icons.texture_for(ItemCatalog.get_item(str(row.get("id", ""))))
	wrap.add_child(icon)

	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var definition := ItemCatalog.get_item(str(row.get("id", "")))
	var label := definition.display_name if definition != null else str(row.get("id", ""))
	var qty := int(row.get("qty", 1))
	if bool(row.get("gather", false)):
		text.text = "%s x%d  ·  gather / loot" % [label, qty]
		text.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	else:
		var station: Dictionary = row.get("station", {})
		text.text = "%s x%d  ·  %s" % [label, qty, str(station.get("name", "craft"))]
	wrap.add_child(text)
	return wrap


func _fill_need_slots(needs: Array) -> void:
	var slots := _needs.get_children()
	for i in slots.size():
		var slot := slots[i] as Button
		_clear_slot_contents(slot)
		if i >= needs.size():
			slot.modulate = Color(1, 1, 1, 0.35)
			continue
		slot.modulate = Color(1, 1, 1, 1)
		var item_id := str(needs[i]["id"])
		var need := int(needs[i]["need"])
		var picture := TextureRect.new()
		_fill_slot_icon(picture)
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(item_id))
		if bool(needs[i].get("result", false)):
			picture.modulate = Color(1, 1, 1, 0.4)
		slot.add_child(picture)
		slot.add_child(_qty_overlay("x%d" % need))


func _categories() -> PackedStringArray:
	var seen: Dictionary = {}
	for recipe in _recipes:
		var definition := ItemCatalog.get_item(str(recipe["output"]))
		var raw := definition.category if definition != null else "misc"
		seen[CraftRules.category_label(raw)] = true
	var labels: Array = seen.keys()
	labels.sort_custom(func(a, b): return CraftRules.category_sort_key(str(a)) < CraftRules.category_sort_key(str(b)))
	var packed := PackedStringArray()
	for label in labels:
		packed.append(str(label))
	return packed


func _outputs_in(category: String) -> PackedStringArray:
	var seen: Dictionary = {}
	var order: Array = []
	for recipe in _recipes:
		var output_id := str(recipe["output"])
		if seen.has(output_id):
			continue
		var definition := ItemCatalog.get_item(output_id)
		var raw := definition.category if definition != null else "misc"
		if CraftRules.category_label(raw) != category:
			continue
		seen[output_id] = true
		order.append(output_id)
	order.sort_custom(func(a, b):
		var da := ItemCatalog.get_item(str(a))
		var db := ItemCatalog.get_item(str(b))
		var na := da.display_name if da != null else str(a)
		var nb := db.display_name if db != null else str(b)
		return na.naturalnocasecmp_to(nb) < 0
	)
	var packed := PackedStringArray()
	for output_id in order:
		packed.append(str(output_id))
	return packed


func _select_category(category: String) -> void:
	if _category == category:
		return
	_category = category
	_alt_index = 0
	var items := _outputs_in(_category)
	_selected = _pick_recipe(str(items[0])) if not items.is_empty() else {}
	_style_tabs()
	_rebuild_list()
	_paint_detail()


func _select_output(output_id: String) -> void:
	if str(_selected.get("output", "")) == output_id:
		return
	_alt_index = 0
	_selected = _pick_recipe(output_id)
	_paint_list_state()
	_paint_detail()


func _select_alt(index: int) -> void:
	_alt_index = index
	_selected = _pick_recipe(str(_selected.get("output", "")))
	_paint_detail()


func _clear_path() -> void:
	for child in _path.get_children():
		_path.remove_child(child)
		child.queue_free()


func _empty_slot(size: int = SLOT) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	return button


func _fill_slot_icon(picture: TextureRect) -> void:
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _qty_overlay(text: String) -> Label:
	var count := Label.new()
	count.text = text
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -48
	count.offset_top = -20
	count.offset_right = -4
	count.offset_bottom = -2
	count.add_theme_font_size_override(&"font_size", 14)
	count.add_theme_color_override(&"font_color", Color.WHITE)
	count.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	count.add_theme_constant_override(&"outline_size", 4)
	count.z_index = 2
	return count


func _selection_border() -> Panel:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.z_index = 3
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1, 1, 1, 0.95)
	style.set_border_width_all(2)
	frame.add_theme_stylebox_override(&"panel", style)
	return frame


func _clear_slot_contents(slot: Button) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()


func _clear_extra(button: Button) -> void:
	for child in button.get_children():
		if child is Panel:
			button.remove_child(child)
			child.queue_free()
