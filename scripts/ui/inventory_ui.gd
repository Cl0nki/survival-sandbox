extends CanvasLayer
class_name InventoryUI

const _Icons = preload("res://scripts/items/item_icons.gd")
const SLOT_SIZE := 72
const NAME_DELAY_MSEC := 1000

## Minecraft-style inventory. Clicks are requests. The picture updates only
## after the server confirms the slots and the cursor stack.

var _player: PlayerController
var _screen: Control
var _hud: Control
var _box_panel: PanelContainer
var _box_grid: GridContainer
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


func _ready() -> void:
	layer = 30
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_screen = VBoxContainer.new()
	_screen.visible = false
	center.add_child(_screen)
	_box_panel = PanelContainer.new()
	_box_panel.visible = false
	_screen.add_child(_box_panel)
	var box_column := VBoxContainer.new()
	_box_panel.add_child(box_column)
	var box_title := Label.new()
	box_title.text = "Crate"
	box_column.add_child(box_title)
	_box_grid = GridContainer.new()
	_box_grid.columns = 9
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
	column.add_child(_storage_grid)
	_hotbar_grid = GridContainer.new()
	_hotbar_grid.columns = 9
	column.add_child(_hotbar_grid)
	_hud = CenterContainer.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -128
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
	hud_box.add_child(_hud_grid)
	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(48, 48)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	_cursor_icon.z_index = 30
	add_child(_cursor_icon)
	_cursor_qty = Label.new()
	_cursor_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_cursor_qty.visible = held
	if held:
		var mouse := get_viewport().get_mouse_position()
		_cursor_icon.global_position = mouse + Vector2(12, 12)
		_cursor_qty.global_position = mouse + Vector2(36, 36)
		_cursor_icon.texture = _Icons.texture_for(ItemCatalog.get_item(_player.cursor_item_id))
		_cursor_qty.text = str(_player.cursor_qty)
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
			_screen.visible = true
			_hud.visible = false
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
	_buttons.clear()
	_areas.clear()
	_indices.clear()
	_clear_grid(_storage_grid)
	_clear_grid(_hotbar_grid)
	_clear_grid(_hud_grid)
	_clear_grid(_box_grid)
	var bag := _player.inventory
	for index in mini(NetConfig.HOTBAR_SLOTS, bag.capacity):
		_add_slot(_hotbar_grid, SlotOps.AREA_PLAYER, index, true, true)
		_add_slot(_hud_grid, SlotOps.AREA_PLAYER, index, true, false)
	for index in range(NetConfig.HOTBAR_SLOTS, bag.capacity):
		_add_slot(_storage_grid, SlotOps.AREA_PLAYER, index, false, true)
	var crate: Inventory = _player.container_view
	_box_panel.visible = crate != null
	if crate != null:
		for index in crate.capacity:
			_add_slot(_box_grid, SlotOps.AREA_CONTAINER, index, false, true)


func _add_slot(grid: GridContainer, area: int, index: int, hotbar: bool, interactive: bool) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.expand_icon = true
	var bag := _player.container_view if area == SlotOps.AREA_CONTAINER else _player.inventory
	var slot: Dictionary = bag.slots[index]
	var item_id := str(slot["id"])
	var qty := int(slot["qty"])
	if item_id.is_empty() or qty <= 0:
		button.text = ""
		button.icon = null
	else:
		button.text = str(qty)
		button.icon = _Icons.texture_for(ItemCatalog.get_item(item_id))
	if hotbar and index == _player.hotbar_index and area == SlotOps.AREA_PLAYER:
		button.modulate = Color(1.0, 0.9, 0.45, 1)
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
