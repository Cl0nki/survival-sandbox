extends CanvasLayer
class_name InventoryUI

const _Icons = preload("res://scripts/items/item_icons.gd")
const _CraftingMenu = preload("res://scripts/ui/crafting_menu.gd")
const SLOT_SIZE := 96
const NAME_DELAY_MSEC := 1000

## Minecraft-style inventory. Clicks are requests. The picture updates only
## after the server confirms the slots and the cursor stack.

var _player: PlayerController
var _screen: Control
var _hud: Control
var _box_panel: PanelContainer
var _box_title: Label
var _box_hint: Label
var _box_grid: GridContainer
var _craft_menu: PanelContainer
var _storage_grid: GridContainer
var _hotbar_grid: GridContainer
var _hud_grid: GridContainer
var _notice: Label
var _hud_notice: Label
var _name_tip: PanelContainer
var _name_label: Label
var _hover_started_msec := 0
var _cursor_icon: TextureRect
var _cursor_qty: Label
var _buttons: Array[Button] = []
var _areas: Array[int] = []
var _indices: Array[int] = []
var _hover_area := -1
var _hover_index := -1
var _last_click_msec := 0
var _last_click_area := -1
var _last_click_index := -1
var _painting := false
var _paint_right := false
var _paint_areas := PackedInt32Array()
var _paint_indices := PackedInt32Array()


func bind_player(player: PlayerController) -> void:
	_player = player
	if not player.inventory_changed.is_connected(_refresh):
		player.inventory_changed.connect(_refresh)
	if not player.container_changed.is_connected(_on_container):
		player.container_changed.connect(_on_container)
	if not player.item_notice.is_connected(_show_notice):
		player.item_notice.connect(_show_notice)
	_refresh()


func is_open() -> bool:
	return _screen != null and _screen.visible


func close() -> void:
	if is_open():
		_close_screen()


func _ready() -> void:
	layer = 30
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_screen = VBoxContainer.new()
	_screen.visible = false
	_screen.add_theme_constant_override(&"separation", 8)
	center.add_child(_screen)
	_craft_menu = _CraftingMenu.new()
	_craft_menu.craft_pressed.connect(_on_station_craft)
	_screen.add_child(_craft_menu)
	_box_panel = PanelContainer.new()
	_box_panel.visible = false
	_screen.add_child(_box_panel)
	var box_column := VBoxContainer.new()
	_box_panel.add_child(box_column)
	_box_title = Label.new()
	_box_title.text = "Crate"
	box_column.add_child(_box_title)
	_box_hint = Label.new()
	_box_hint.visible = false
	box_column.add_child(_box_hint)
	_box_grid = GridContainer.new()
	_box_grid.columns = 9
	_box_grid.add_theme_constant_override(&"h_separation", 4)
	_box_grid.add_theme_constant_override(&"v_separation", 4)
	box_column.add_child(_box_grid)
	var bag_panel := PanelContainer.new()
	_screen.add_child(bag_panel)
	var column := VBoxContainer.new()
	bag_panel.add_child(column)
	var title := Label.new()
	title.text = "Inventory"
	column.add_child(title)
	_notice = Label.new()
	_notice.visible = false
	column.add_child(_notice)
	_storage_grid = GridContainer.new()
	_storage_grid.columns = 9
	_storage_grid.add_theme_constant_override(&"h_separation", 4)
	_storage_grid.add_theme_constant_override(&"v_separation", 4)
	column.add_child(_storage_grid)
	_hotbar_grid = GridContainer.new()
	_hotbar_grid.columns = 9
	_hotbar_grid.add_theme_constant_override(&"h_separation", 4)
	_hotbar_grid.add_theme_constant_override(&"v_separation", 4)
	column.add_child(_hotbar_grid)
	_hud = CenterContainer.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -160
	_hud.offset_bottom = -16
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	var hud_box := VBoxContainer.new()
	_hud.add_child(hud_box)
	_hud_notice = Label.new()
	_hud_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_box.add_child(_hud_notice)
	_hud_grid = GridContainer.new()
	_hud_grid.columns = 9
	_hud_grid.add_theme_constant_override(&"h_separation", 4)
	_hud_grid.add_theme_constant_override(&"v_separation", 4)
	hud_box.add_child(_hud_grid)
	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	_cursor_icon.z_index = 30
	add_child(_cursor_icon)
	_cursor_qty = _count_label()
	_cursor_qty.visible = false
	_cursor_qty.z_index = 31
	add_child(_cursor_qty)
	_name_tip = PanelContainer.new()
	_name_tip.visible = false
	_name_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tip.z_index = 40
	add_child(_name_tip)
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tip.add_child(_name_label)


func _process(_delta: float) -> void:
	if _player == null or _cursor_icon == null:
		return
	var held := _player.cursor_qty > 0 and _player.cursor_item_id != ""
	_cursor_icon.visible = held
	_cursor_qty.visible = held and _player.cursor_qty > 1
	if held:
		var mouse := get_viewport().get_mouse_position()
		_cursor_icon.global_position = mouse + Vector2(12, 12)
		_cursor_icon.texture = _Icons.texture_for(ItemCatalog.get_item(_player.cursor_item_id))
		if _cursor_qty.visible:
			_cursor_qty.text = str(_player.cursor_qty)
			_cursor_qty.size = Vector2(48, 22)
			_cursor_qty.global_position = _cursor_icon.global_position + Vector2(SLOT_SIZE - 48, SLOT_SIZE - 22)
	_update_name_tip()


func _input(event: InputEvent) -> void:
	if _player == null:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _screen != null and _screen.visible:
			_close_screen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"inventory"):
		if _screen.visible:
			_close_screen()
		else:
			if _player != null and _player.has_method("close_tech_tree"):
				_player.call("close_tech_tree")
			_screen.visible = true
			_hud.visible = false
			_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"drop_item"):
		var whole := event is InputEventKey and (event as InputEventKey).ctrl_pressed
		_throw(whole)
		get_viewport().set_input_as_handled()
		return
	for hotbar_slot in NetConfig.HOTBAR_SLOTS:
		if not event.is_action_pressed(StringName("hotbar_%d" % (hotbar_slot + 1))):
			continue
		if _screen.visible and _hover_index >= 0:
			_player.request_hotbar_swap(_hover_area, _hover_index, hotbar_slot)
		else:
			_player.select_hotbar(hotbar_slot)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _painting:
		_add_paint_slot(_slot_at((event as InputEventMouseMotion).global_position))
	elif event is InputEventMouseButton and _painting:
		var button := event as InputEventMouseButton
		if not button.pressed and button.button_index == (MOUSE_BUTTON_RIGHT if _paint_right else MOUSE_BUTTON_LEFT):
			_finish_paint()


func _close_screen() -> void:
	_cancel_paint()
	_screen.visible = false
	_hud.visible = true
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_release_focus()
	if _player != null:
		_player.call("close_container_view")


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not _screen.visible or _painting:
		return
	if _player.cursor_qty <= 0:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_player.request_slot_throw(-1, -1, true)


func _on_container() -> void:
	if _player != null and _player.container_view != null:
		if _player.has_method("close_tech_tree"):
			_player.call("close_tech_tree")
		_screen.visible = true
		_hud.visible = false
	_refresh()


func _show_notice(text: String) -> void:
	if _notice != null:
		_notice.text = text
		_notice.visible = text != ""
	if _hud_notice != null:
		_hud_notice.text = text


func _refresh() -> void:
	if _player == null or _player.inventory == null or _storage_grid == null:
		return
	var bag := _player.inventory
	## Closed inventory: only rebuild the always-on HUD hotbar. Full slot rebuilds
	## on every hotbar/item change were hitching input.
	if _screen == null or not _screen.visible:
		_clear_grid(_hud_grid)
		for index in mini(NetConfig.HOTBAR_SLOTS, bag.capacity):
			_add_slot(_hud_grid, SlotOps.AREA_PLAYER, index, true, false)
		if _craft_menu != null and _craft_menu.visible:
			_craft_menu.clear()
		return
	_buttons.clear()
	_areas.clear()
	_indices.clear()
	_clear_grid(_storage_grid)
	_clear_grid(_hotbar_grid)
	_clear_grid(_hud_grid)
	_clear_grid(_box_grid)
	for index in mini(NetConfig.HOTBAR_SLOTS, bag.capacity):
		_add_slot(_hotbar_grid, SlotOps.AREA_PLAYER, index, true, true)
		_add_slot(_hud_grid, SlotOps.AREA_PLAYER, index, true, false)
	for index in range(NetConfig.HOTBAR_SLOTS, bag.capacity):
		_add_slot(_storage_grid, SlotOps.AREA_PLAYER, index, false, true)
	var crate: Inventory = _player.container_view
	var station := _open_loot()
	var station_ui := station is Crafter or station is Smelter
	_box_panel.visible = crate != null and not station_ui
	_paint_box_header()
	if station_ui:
		_show_station_menu(station as LootContainer, bag)
	else:
		_craft_menu.clear()
		if crate != null:
			for index in crate.capacity:
				_add_slot(_box_grid, SlotOps.AREA_CONTAINER, index, false, true)


func _show_station_menu(station: LootContainer, bag: Inventory) -> void:
	var status := ""
	if station.has_method(&"slot_hint"):
		status = str(station.call(&"slot_hint"))
	var queue: Array = []
	if station.has_method(&"queue_snapshot"):
		queue = station.call(&"queue_snapshot") as Array
	var out_index := 0
	var mode := "craft"
	var kind := ""
	var action := "Craft"
	if station is Crafter:
		var crafter := station as Crafter
		kind = crafter.station_kind
		out_index = crafter.output_index()
		if status == CraftRules.hint(kind):
			status = ""
		mode = "craft"
		action = "Craft"
	elif station is Smelter:
		var smelter := station as Smelter
		kind = smelter.station_kind
		out_index = smelter.output_index()
		if status == SmeltRules.hint(kind):
			status = ""
		mode = "smelt"
		action = "Smelt"
	_craft_menu.show_station(mode, kind, station.prompt, bag, status, queue, action)
	var host: Control = _craft_menu.output_host()
	_clear_host(host)
	_add_slot(host, SlotOps.AREA_CONTAINER, out_index, false, true)
	_style_craft_output_slot(host, station.inventory, out_index)


func _paint_box_header() -> void:
	if _box_title == null:
		return
	var station := _open_loot()
	if station == null or station is Crafter or station is Smelter:
		_box_title.text = "Crate"
		_box_hint.text = ""
		_box_hint.visible = false
		return
	_box_title.text = station.prompt if station.prompt != "" else "Crate"
	var hint := ""
	if station.has_method(&"slot_hint"):
		hint = str(station.call(&"slot_hint"))
	_box_hint.text = hint
	_box_hint.visible = hint != ""


func _on_station_craft(input_id: String, extra_id: String, amount: int) -> void:
	if _player == null:
		return
	_player.request_craft(input_id, extra_id, amount)


func _clear_host(host: Control) -> void:
	if host == null:
		return
	for child in host.get_children():
		host.remove_child(child)
		child.free()


func _style_craft_output_slot(host: Control, station_bag: Inventory, out_index: int) -> void:
	if host == null or host.get_child_count() <= 0 or station_bag == null:
		return
	if out_index < 0 or out_index >= station_bag.slots.size():
		return
	var button := host.get_child(0) as Button
	if button == null:
		return
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.text = ""
	var slot: Dictionary = station_bag.slots[out_index]
	var empty := str(slot["id"]).is_empty() or int(slot["qty"]) <= 0
	if not empty:
		return
	## Let the craft-menu ghost show through while the slot stays clickable.
	var clear := StyleBoxEmpty.new()
	button.add_theme_stylebox_override(&"normal", clear)
	button.add_theme_stylebox_override(&"hover", clear)
	button.add_theme_stylebox_override(&"pressed", clear)
	button.add_theme_stylebox_override(&"focus", clear)
	button.add_theme_stylebox_override(&"disabled", clear)


func _slot_caption(area: int, index: int) -> String:
	if area != SlotOps.AREA_CONTAINER:
		return ""
	var station := _open_loot()
	if station == null or station is Crafter or station is Smelter:
		return ""
	if index < 0 or index >= station.slot_labels.size():
		return ""
	return station.slot_labels[index]


func _open_loot() -> LootContainer:
	if _player == null or _player.container_view_id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group(&"loot_container"):
		var crate := node as LootContainer
		if crate != null and crate.container_id == _player.container_view_id:
			return crate
	return null


func _add_slot(grid: Control, area: int, index: int, hotbar: bool, interactive: bool, size: int = SLOT_SIZE) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size)
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	var bag := _player.container_view if area == SlotOps.AREA_CONTAINER else _player.inventory
	var slot: Dictionary = bag.slots[index]
	var item_id := str(slot["id"])
	var qty := int(slot["qty"])
	if item_id.is_empty() or qty <= 0:
		button.text = _slot_caption(area, index)
	else:
		var picture := TextureRect.new()
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		picture.texture = _Icons.texture_for(ItemCatalog.get_item(item_id))
		button.add_child(picture)
		if qty > 1:
			var count := _count_label()
			count.text = str(qty)
			count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			count.offset_left = -48
			count.offset_top = -22
			count.offset_right = -4
			count.offset_bottom = -2
			button.add_child(count)
	if hotbar and index == _player.hotbar_index and area == SlotOps.AREA_PLAYER:
		button.add_child(_active_border())
	elif _hover_area == area and _hover_index == index:
		button.modulate = Color(1.0, 1.0, 0.75, 1)
	button.gui_input.connect(_on_slot_input.bind(area, index))
	button.mouse_entered.connect(_set_hover.bind(area, index))
	button.mouse_exited.connect(_clear_hover.bind(area, index))
	if not interactive:
		button.pressed.connect(_select_hotbar.bind(index))
		grid.add_child(button)
		return
	grid.add_child(button)
	_buttons.append(button)
	_areas.append(area)
	_indices.append(index)


func _active_border() -> Panel:
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


func _count_label() -> Label:
	var count := Label.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override(&"font_size", 16)
	count.add_theme_color_override(&"font_color", Color.WHITE)
	count.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	count.add_theme_constant_override(&"outline_size", 5)
	count.z_index = 2
	return count


func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.free()


func _on_slot_input(event: InputEvent, area: int, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	var right := button.button_index == MOUSE_BUTTON_RIGHT
	var now := Time.get_ticks_msec()
	var repeat_click := area == _last_click_area and index == _last_click_index and now - _last_click_msec < 280
	_last_click_msec = now
	_last_click_area = area
	_last_click_index = index
	if button.shift_pressed and not right:
		_player.request_slot_click(area, index, false, true, false)
	elif repeat_click and not right and _player.cursor_qty <= 0:
		_player.request_slot_click(area, index, false, false, true)
	elif _player.cursor_qty > 0:
		_painting = true
		_paint_right = right
		_paint_areas = PackedInt32Array()
		_paint_indices = PackedInt32Array()
		_add_paint_slot({"area": area, "index": index})
	else:
		_player.request_slot_click(area, index, right, false, false)
	get_viewport().set_input_as_handled()


func _select_hotbar(index: int) -> void:
	if _screen.visible:
		return
	_player.select_hotbar(index)


func _throw(whole: bool) -> void:
	if _player.cursor_qty > 0:
		_player.request_slot_throw(-1, -1, whole)
		return
	if _screen.visible and _hover_index >= 0:
		_player.request_slot_throw(_hover_area, _hover_index, whole)
		return
	_player.request_slot_throw(SlotOps.AREA_PLAYER, _player.hotbar_index, whole)


func _add_paint_slot(hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var area := int(hit["area"])
	var index := int(hit["index"])
	for i in _paint_areas.size():
		if int(_paint_areas[i]) == area and int(_paint_indices[i]) == index:
			return
	_paint_areas.append(area)
	_paint_indices.append(index)


func _finish_paint() -> void:
	var areas := _paint_areas
	var indices := _paint_indices
	var right := _paint_right
	_cancel_paint()
	if areas.is_empty():
		return
	if areas.size() == 1:
		_player.request_slot_click(int(areas[0]), int(indices[0]), right, false, false)
		return
	_player.request_slot_spread(areas, indices, right)


func _cancel_paint() -> void:
	_painting = false
	_paint_areas = PackedInt32Array()
	_paint_indices = PackedInt32Array()


func _slot_at(at: Vector2) -> Dictionary:
	for i in _buttons.size():
		if _buttons[i].get_global_rect().has_point(at):
			return {"area": _areas[i], "index": _indices[i]}
	return {}


func _set_hover(area: int, index: int) -> void:
	if _hover_area != area or _hover_index != index:
		_hover_started_msec = Time.get_ticks_msec()
	_hover_area = area
	_hover_index = index


func _clear_hover(area: int, index: int) -> void:
	if _hover_area == area and _hover_index == index:
		_hover_area = -1
		_hover_index = -1
		if _name_tip != null:
			_name_tip.visible = false


func _update_name_tip() -> void:
	if _name_tip == null or _player == null or _hover_index < 0:
		if _name_tip != null:
			_name_tip.visible = false
		return
	if Time.get_ticks_msec() - _hover_started_msec < NAME_DELAY_MSEC:
		_name_tip.visible = false
		return
	var item_name := _hovered_item_name()
	if item_name == "":
		_name_tip.visible = false
		return
	_name_label.text = item_name
	_name_tip.visible = true
	_name_tip.global_position = get_viewport().get_mouse_position() + Vector2(18, 22)


func _hovered_item_name() -> String:
	var bag := _player.container_view if _hover_area == SlotOps.AREA_CONTAINER else _player.inventory
	if bag == null or _hover_index < 0 or _hover_index >= bag.capacity:
		return ""
	var slot: Dictionary = bag.slots[_hover_index]
	var item_id := str(slot["id"])
	if item_id.is_empty() or int(slot["qty"]) <= 0:
		return ""
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return item_id
	return definition.display_name
