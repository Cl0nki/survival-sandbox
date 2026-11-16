extends PanelContainer
class_name CraftingMenu

## Shared craft / smelt menu using the same 96px slot grid as inventory.

signal craft_pressed(input_id: String, extra_id: String, amount: int)

const _Icons = preload("res://scripts/items/item_icons.gd")
const _UiStyle = preload("res://scripts/ui/ui_style.gd")

const SLOT := 96
const GRID_GAP := 4
const COLS := 9
const GRID_W := COLS * SLOT + (COLS - 1) * GRID_GAP
const LIST_COLS := 3
const LIST_ROWS := 3.5
const LIST_W := LIST_COLS * SLOT + (LIST_COLS - 1) * GRID_GAP
## 3 full slots + half a slot, with gaps between the visible rows.
const LIST_H := int(LIST_ROWS * SLOT) + 3 * GRID_GAP
const SCROLL_W := 14
const BLURB_H := LIST_H - SLOT - 88
const QUEUE_SLOTS := 6
const QUEUE_SLOT := 40
const MAX_QTY := 20

var _mode := "craft"
var _station_kind := ""
var _bag: Inventory
var _category := ""
var _selected: Dictionary = {}
var _recipes: Array = []
var _qty := 1
var _queue: Array = []
var _action_label := "Craft"

var _title: Label
var _status: Label
var _tabs: HBoxContainer
var _list: GridContainer
var _name: Label
var _blurb: Label
var _needs: GridContainer
var _qty_label: Label
var _craft: Button
var _queue_grid: GridContainer
var _progress: ProgressBar
var _output_host: Control
var _output_ghost: TextureRect

var _tab_buttons: Dictionary = {}
var _list_buttons: Array = []


func _ready() -> void:
	visible = false
	## Same outer width as the inventory panel (grid + panel padding).
	custom_minimum_size = Vector2(GRID_W + _UiStyle.PANEL_PAD_X * 2, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 12)
	add_child(root)

	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override(&"separation", 8)
	root.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text = "Station"
	_UiStyle.title(_title)
	head.add_child(_title)
	_status = Label.new()
	_status.add_theme_color_override(&"font_color", _UiStyle.ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_status)
	var queue_box := VBoxContainer.new()
	queue_box.add_theme_constant_override(&"separation", 6)
	head.add_child(queue_box)
	_queue_grid = GridContainer.new()
	_queue_grid.columns = QUEUE_SLOTS
	_queue_grid.add_theme_constant_override(&"h_separation", 2)
	_queue_grid.add_theme_constant_override(&"v_separation", 2)
	queue_box.add_child(_queue_grid)
	for _i in QUEUE_SLOTS:
		_queue_grid.add_child(_empty_slot(QUEUE_SLOT))
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.step = 0.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override(&"background", _UiStyle.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.06), 4))
	_progress.add_theme_stylebox_override(&"fill", _UiStyle.box(_UiStyle.ACCENT, Color(0, 0, 0, 0), 4, 0))
	queue_box.add_child(_progress)

	root.add_child(HSeparator.new())

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 18)
	root.add_child(_tabs)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 20)
	root.add_child(body)

	## Left: recipe icon grid (3 cols, height matches detail through Craft).
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_W + SCROLL_W, LIST_H)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	body.add_child(list_scroll)
	_list = GridContainer.new()
	_list.columns = LIST_COLS
	_list.add_theme_constant_override(&"h_separation", GRID_GAP)
	_list.add_theme_constant_override(&"v_separation", GRID_GAP)
	list_scroll.add_child(_list)

	## Right: name, description, needs + ghosted output, craft.
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size = Vector2(0, LIST_H)
	detail.add_theme_constant_override(&"separation", 10)
	body.add_child(detail)

	_name = Label.new()
	_name.add_theme_font_size_override(&"font_size", 20)
	_name.add_theme_color_override(&"font_color", Color.WHITE)
	detail.add_child(_name)

	_blurb = Label.new()
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(0, maxi(BLURB_H, 64))
	_blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blurb.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	detail.add_child(_blurb)

	var needs_label := Label.new()
	needs_label.text = "Needs"
	needs_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	detail.add_child(needs_label)

	var needs_row := HBoxContainer.new()
	needs_row.add_theme_constant_override(&"separation", GRID_GAP)
	detail.add_child(needs_row)
	_needs = GridContainer.new()
	_needs.columns = 3
	_needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_needs.add_theme_constant_override(&"h_separation", GRID_GAP)
	_needs.add_theme_constant_override(&"v_separation", GRID_GAP)
	needs_row.add_child(_needs)
	for _i in 3:
		_needs.add_child(_empty_slot(SLOT))
	var output_wrap := Control.new()
	output_wrap.custom_minimum_size = Vector2(SLOT, SLOT)
	needs_row.add_child(output_wrap)
	var output_frame := _empty_slot(SLOT)
	output_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	output_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	output_wrap.add_child(output_frame)
	_output_ghost = TextureRect.new()
	_fill_slot_icon(_output_ghost)
	_output_ghost.modulate = Color(1, 1, 1, 0.35)
	_output_ghost.visible = false
	output_wrap.add_child(_output_ghost)
	_output_host = Control.new()
	_output_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_output_host.mouse_filter = Control.MOUSE_FILTER_PASS
	output_wrap.add_child(_output_host)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 6)
	detail.add_child(actions)
	actions.add_child(_qty_btn("-", -1))
	_qty_label = Label.new()
	_qty_label.custom_minimum_size = Vector2(36, 40)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(_qty_label)
	actions.add_child(_qty_btn("+", 1))
	var actions_spacer := Control.new()
	actions_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(actions_spacer)
	_craft = Button.new()
	_craft.custom_minimum_size = Vector2(SLOT * 2 + GRID_GAP, 44)
	_craft.theme_type_variation = _UiStyle.ACCENT_BUTTON
	_craft.focus_mode = Control.FOCUS_NONE
	_craft.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_craft.pressed.connect(_on_craft)
	actions.add_child(_craft)


func output_host() -> Control:
	return _output_host


## Progress of the running job (0..1). Called every frame while the menu is open.
func set_progress(value: float) -> void:
	if _progress != null:
		_progress.value = clampf(value, 0.0, 1.0)


func show_station(
	mode: String,
	station_kind: String,
	station_name: String,
	bag: Inventory,
	status_text: String,
	queue: Array,
	action_label: String
) -> void:
	var same := visible and _station_kind == station_kind and _mode == mode
	_mode = mode
	_station_kind = station_kind
	_bag = bag
	_action_label = action_label
	_title.text = station_name if station_name != "" else action_label
	## While a job runs the progress bar replaces the "Name 12s" countdown text.
	var running := false
	for entry in queue:
		if bool((entry as Dictionary).get("active", false)):
			running = true
	_status.text = "" if running else status_text
	if not running:
		set_progress(0.0)
	_queue = queue
	_recipes = SmeltRules.recipes_for(station_kind) if mode == "smelt" else CraftRules.recipes_for(station_kind)
	if same:
		_clamp_qty()
		_paint_detail()
		_paint_queue()
		_paint_list_state()
		return
	_category = ""
	_selected = {}
	_qty = 1
	_ensure_selection()
	_rebuild_tabs()
	_rebuild_list()
	_paint_detail()
	_paint_queue()
	visible = true


func clear() -> void:
	_mode = "craft"
	_station_kind = ""
	_bag = null
	_category = ""
	_selected = {}
	_recipes = []
	_queue = []
	_qty = 1
	_tab_buttons.clear()
	_list_buttons.clear()
	visible = false


func _ensure_selection() -> void:
	var cats := _categories()
	if cats.is_empty():
		_category = ""
		_selected = {}
		return
	if _category == "" or not cats.has(_category):
		_category = str(cats[0])
	var items := _items_in(_category)
	if items.is_empty():
		_selected = {}
		return
	if not _selected.is_empty():
		for recipe in items:
			if str(recipe["output"]) == str(_selected.get("output", "")):
				_selected = recipe
				return
	_selected = items[0]


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()
	var cats := _categories()
	for i in cats.size():
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
	for recipe in _items_in(_category):
		var output_id := str(recipe["output"])
		var button := _empty_slot()
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var picture := TextureRect.new()
		_fill_slot_icon(picture)
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(output_id))
		button.add_child(picture)
		button.pressed.connect(_select_recipe.bind(recipe))
		_list.add_child(button)
		_list_buttons.append({"button": button, "recipe": recipe})
	_paint_list_state()


func _style_tabs() -> void:
	for cat in _tab_buttons.keys():
		var tab: Button = _tab_buttons[cat]
		var selected := str(cat) == _category
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 2
		style.content_margin_bottom = 6
		style.border_width_bottom = 3
		style.border_color = _UiStyle.ACCENT if selected else Color(0, 0, 0, 0)
		tab.add_theme_stylebox_override(&"normal", style)
		tab.add_theme_stylebox_override(&"hover", style)
		tab.add_theme_stylebox_override(&"pressed", style)
		tab.add_theme_stylebox_override(&"focus", style)
		tab.add_theme_font_size_override(&"font_size", 17)
		tab.add_theme_color_override(&"font_color", Color.WHITE if selected else Color(1, 1, 1, 0.55))
		tab.add_theme_color_override(&"font_hover_color", Color.WHITE)


func _paint_list_state() -> void:
	var selected_id := str(_selected.get("output", ""))
	for entry in _list_buttons:
		var button: Button = entry["button"]
		var recipe: Dictionary = entry["recipe"]
		var selected := str(recipe["output"]) == selected_id
		var can := _can_craft_once(recipe)
		button.modulate = Color(1, 1, 1, 1) if can else Color(1, 1, 1, 0.45)
		_clear_extra(button)
		if selected:
			button.add_child(_selection_border())


func _paint_detail() -> void:
	_clamp_qty()
	_qty_label.text = str(_qty)
	_craft.text = "%s x%d" % [_action_label, _qty]
	## Keep the button clickable so a failed craft still reports a reason notice.
	var can := not _selected.is_empty() and _max_amount(_selected) >= _qty
	_craft.disabled = _selected.is_empty()
	_craft.modulate = Color(1, 1, 1, 1) if can else Color(1, 1, 1, 0.55)
	if _selected.is_empty():
		_name.text = ""
		_blurb.text = "No recipes."
		_fill_need_slots([])
		_paint_output_ghost("")
		return
	var definition := ItemCatalog.get_item(str(_selected["output"]))
	_name.text = definition.display_name if definition != null else str(_selected["output"])
	_blurb.text = definition.description if definition != null and definition.description != "" else "No description."
	var needs: Array = [{"id": str(_selected["input"]), "need": int(_selected["in_n"]) * _qty}]
	if int(_selected.get("extra_n", 0)) > 0 and str(_selected.get("extra", "")) != "":
		needs.append({"id": str(_selected["extra"]), "need": int(_selected["extra_n"]) * _qty})
	var fuel := _fuel_need()
	if str(fuel["id"]) != "":
		needs.append({"id": str(fuel["id"]), "need": int(fuel["need"]) * _qty})
	_fill_need_slots(needs)
	_paint_output_ghost(str(_selected["output"]))


func _paint_output_ghost(item_id: String) -> void:
	if _output_ghost == null:
		return
	if item_id.is_empty():
		_output_ghost.texture = null
		_output_ghost.visible = false
		return
	_output_ghost.texture = _Icons.texture_for(ItemCatalog.get_item(item_id))
	_output_ghost.visible = true


func _paint_queue() -> void:
	var slots := _queue_grid.get_children()
	for i in slots.size():
		var slot := slots[i] as Button
		_clear_slot_contents(slot)
		if i >= _queue.size():
			slot.modulate = Color(1, 1, 1, 0.35)
			continue
		slot.modulate = Color(1, 1, 1, 1)
		var entry: Dictionary = _queue[i]
		var picture := TextureRect.new()
		_fill_slot_icon(picture)
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(str(entry.get("id", ""))))
		slot.add_child(picture)
		var qty := int(entry.get("qty", 1))
		if qty > 1:
			slot.add_child(_qty_overlay(str(qty), Color.WHITE, true))
		if bool(entry.get("active", false)):
			slot.add_child(_selection_border())


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
		var have := 0 if _bag == null else _bag.count_item(item_id)
		var picture := TextureRect.new()
		_fill_slot_icon(picture)
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(item_id))
		slot.add_child(picture)
		slot.add_child(_qty_overlay("%d/%d" % [have, need], Color.WHITE if have >= need else Color(0.95, 0.45, 0.35)))


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


func _qty_overlay(text: String, color: Color, small := false) -> Label:
	var count := Label.new()
	count.text = text
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -28 if small else -56
	count.offset_top = -16 if small else -22
	count.offset_right = -2 if small else -4
	count.offset_bottom = -1 if small else -2
	count.add_theme_font_size_override(&"font_size", 11 if small else 16)
	count.add_theme_color_override(&"font_color", color)
	count.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	count.add_theme_constant_override(&"outline_size", 3 if small else 5)
	count.z_index = 2
	return count

func _selection_border() -> Panel:
	return _UiStyle.selection_frame()


func _clear_slot_contents(slot: Button) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()


func _clear_extra(button: Button) -> void:
	for child in button.get_children():
		if child is Panel:
			button.remove_child(child)
			child.queue_free()


func _qty_btn(text: String, delta: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(SLOT / 2, SLOT / 2)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_nudge_qty.bind(delta))
	return btn


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


func _items_in(category: String) -> Array:
	var items: Array = []
	for recipe in _recipes:
		var definition := ItemCatalog.get_item(str(recipe["output"]))
		var raw := definition.category if definition != null else "misc"
		if CraftRules.category_label(raw) != category:
			continue
		items.append(recipe)
	return items


func _fuel_need() -> Dictionary:
	if _mode == "smelt":
		var fuel_id := "coal"
		if _bag != null and _bag.count_item("fuel") > 0 and _bag.count_item("coal") <= 0:
			fuel_id = "fuel"
		return {"id": fuel_id, "need": 1}
	var fuels := CraftRules.fuels_of(_station_kind)
	if fuels.is_empty():
		return {"id": "", "need": 0}
	var preferred := ""
	var best_qty := -1
	for fuel_id in fuels.keys():
		var id := str(fuel_id)
		if preferred == "":
			preferred = id
		if _bag == null:
			continue
		var have := _bag.count_item(id)
		if have > best_qty:
			best_qty = have
			preferred = id
	return {"id": preferred, "need": 1}


func _plan_once(recipe: Dictionary, input_have: int, extra_have: int, fuel_id: String, fuel_have: int) -> Dictionary:
	var input_id := str(recipe["input"])
	var extra_id := str(recipe.get("extra", ""))
	if _mode == "smelt":
		return SmeltRules.plan(
			_station_kind, input_id, input_have, fuel_id, fuel_have, "", 0, 1
		)
	return CraftRules.plan(
		_station_kind,
		input_id,
		input_have,
		extra_id,
		extra_have,
		fuel_id,
		fuel_have,
		"",
		0,
		1
	)


func _can_craft_once(recipe: Dictionary) -> bool:
	if _bag == null or recipe.is_empty():
		return false
	if QUEUE_SLOTS - _queue.size() <= 0:
		return false
	var fuel := _fuel_need()
	var fuel_id := str(fuel["id"])
	var planned := _plan_once(
		recipe,
		_bag.count_item(str(recipe["input"])),
		_bag.count_item(str(recipe.get("extra", ""))) if str(recipe.get("extra", "")) != "" else 0,
		fuel_id,
		0 if fuel_id == "" else _bag.count_item(fuel_id)
	)
	return bool(planned["ok"])


func _max_amount(recipe: Dictionary) -> int:
	if _bag == null or recipe.is_empty():
		return 0
	var room := QUEUE_SLOTS - _queue.size()
	if room <= 0:
		return 0
	var input_id := str(recipe["input"])
	var extra_id := str(recipe.get("extra", ""))
	var fuel := _fuel_need()
	var fuel_id := str(fuel["id"])
	var input_have := _bag.count_item(input_id)
	var extra_have := _bag.count_item(extra_id) if extra_id != "" else 0
	var fuel_have := 0 if fuel_id == "" else _bag.count_item(fuel_id)
	var limit := 0
	for _i in mini(MAX_QTY, room):
		var planned := _plan_once(recipe, input_have, extra_have, fuel_id, fuel_have)
		if not bool(planned["ok"]):
			break
		if _mode == "smelt":
			input_have -= int(planned["count"])
			fuel_have -= int(planned["fuel_count"])
		else:
			input_have -= int(planned["in_count"])
			extra_have -= int(planned["extra_count"])
			fuel_have -= int(planned["fuel_count"])
		limit += 1
	return limit


func _clamp_qty() -> void:
	var cap := _max_amount(_selected)
	_qty = 1 if cap <= 0 else clampi(_qty, 1, cap)


func _nudge_qty(delta: int) -> void:
	_qty += delta
	_clamp_qty()
	_paint_detail()


func _select_category(category: String) -> void:
	if _category == category:
		return
	_category = category
	var items := _items_in(_category)
	_selected = items[0] if not items.is_empty() else {}
	_qty = 1
	_style_tabs()
	_rebuild_list()
	_paint_detail()


func _select_recipe(recipe: Dictionary) -> void:
	if not _selected.is_empty() and str(_selected.get("output", "")) == str(recipe.get("output", "")):
		return
	_selected = recipe
	_qty = 1
	_paint_list_state()
	_paint_detail()


func _on_craft() -> void:
	if _selected.is_empty():
		return
	craft_pressed.emit(str(_selected["input"]), str(_selected.get("extra", "")), _qty)
