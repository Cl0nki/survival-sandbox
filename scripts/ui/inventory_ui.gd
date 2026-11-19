extends CanvasLayer
class_name InventoryUI

const _Icons = preload("res://scripts/items/item_icons.gd")
const _CraftingMenu = preload("res://scripts/ui/crafting_menu.gd")
const _UiStyle = preload("res://scripts/ui/ui_style.gd")
const SLOT_SIZE := 96
const SLOT_GAP := 4
## Free space kept around a weapon's drawing inside its slot.
const WEAPON_PAD := 6.0
## Height a weapon's trigger is drawn at, so every gun has the same trigger and the icons
## keep their true size to each other. Set so the longest rifle just fills the tall primary
## slot. A gun that would not fit its slot at this size is shrunk to fit instead.
const WEAPON_TRIGGER := 5.6
## Width every sidearm is drawn at, so all pistols are the same size.
const SIDEARM_WIDTH := 60.0
const NAME_DELAY_MSEC := 1000
## Open screen and HUD hotbar shrink to fit small windows (never grow past 1:1).
const SCREEN_MARGIN := 20.0
const MIN_UI_SCALE := 0.35

## Minecraft-style inventory. Clicks are requests. The picture updates only
## after the server confirms the slots and the cursor stack.

var _player: PlayerController
var _screen: Control
var _backdrop: TextureRect
var _theme: Theme
var _hud: Control
var _hud_box: VBoxContainer
var _ui_scale := 1.0
var _box_panel: PanelContainer
var _box_title: Label
var _box_hint: Label
## The crate and the storage rows are laid out by hand so an item can span cells.
var _box_grid: Control
var _craft_menu: PanelContainer
var _progress_station: LootContainer
var _storage_grid: Control
var _hotbar_grid: GridContainer
var _hud_grid: GridContainer
## Primary and sidearm, beside the storage rows.
var _weapon_grid: GridContainer
## Melee, beside the hotbar.
var _melee_grid: GridContainer
var _hud_weapon_grid: GridContainer
var _notice: Label
var _hud_notice: Label
var _name_tip: PanelContainer
var _name_label: Label
var _hover_started_msec := 0
## The dragged stack: a box the size of the cells it would take, with the picture in it.
var _cursor_box: Control
var _cursor_icon: TextureRect
var _cursor_shown_id := ""
## Tint squares over the cells the held stack would cover.
var _drop_marks: Array[ColorRect] = []
var _cursor_box_size := Vector2(SLOT_SIZE, SLOT_SIZE)
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
	_theme = _UiStyle.build_theme()
	## Dim vignette behind the open menu (sits under everything else).
	_backdrop = _UiStyle.make_backdrop()
	add_child(_backdrop)
	## Plain Control, not a CenterContainer: containers reset their children's
	## scale, so `_update_scale` places and scales `_screen` by hand.
	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_screen = VBoxContainer.new()
	_screen.visible = false
	_screen.theme = _theme
	_screen.add_theme_constant_override(&"separation", 16)
	center.add_child(_screen)
	_screen.visibility_changed.connect(_on_screen_visibility)
	_craft_menu = _CraftingMenu.new()
	_craft_menu.craft_pressed.connect(_on_station_craft)
	_screen.add_child(_craft_menu)
	_box_panel = PanelContainer.new()
	_box_panel.visible = false
	_screen.add_child(_box_panel)
	var box_column := VBoxContainer.new()
	box_column.add_theme_constant_override(&"separation", 8)
	_box_panel.add_child(box_column)
	_box_title = Label.new()
	_box_title.text = "Crate"
	_UiStyle.title(_box_title)
	box_column.add_child(_box_title)
	_box_hint = Label.new()
	_box_hint.visible = false
	_box_hint.add_theme_color_override(&"font_color", _UiStyle.TEXT_DIM)
	box_column.add_child(_box_hint)
	box_column.add_child(HSeparator.new())
	_box_grid = Control.new()
	box_column.add_child(_box_grid)
	var bag_panel := PanelContainer.new()
	_screen.add_child(bag_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	bag_panel.add_child(column)
	var title := Label.new()
	title.text = "Inventory"
	_UiStyle.title(title)
	column.add_child(title)
	_notice = Label.new()
	_notice.visible = false
	_notice.add_theme_color_override(&"font_color", _UiStyle.ACCENT)
	column.add_child(_notice)
	column.add_child(HSeparator.new())
	_storage_grid = Control.new()
	## The weapon slots are the right-hand column of the same panel. The primary is two
	## rows tall beside the top two storage rows and the sidearm sits beside the third.
	## The melee slot sits at the end of the hotbar row.
	var storage_row := HBoxContainer.new()
	storage_row.add_theme_constant_override(&"separation", SLOT_GAP)
	column.add_child(storage_row)
	storage_row.add_child(_storage_grid)
	_weapon_grid = _weapon_column()
	storage_row.add_child(_weapon_grid)
	column.add_child(HSeparator.new())
	_hotbar_grid = GridContainer.new()
	_hotbar_grid.columns = 9
	_hotbar_grid.add_theme_constant_override(&"h_separation", 4)
	_hotbar_grid.add_theme_constant_override(&"v_separation", 4)
	var hotbar_row := HBoxContainer.new()
	hotbar_row.add_theme_constant_override(&"separation", SLOT_GAP)
	column.add_child(hotbar_row)
	hotbar_row.add_child(_hotbar_grid)
	_melee_grid = _weapon_column()
	hotbar_row.add_child(_melee_grid)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hud.offset_top = -160
	_hud.offset_bottom = -16
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = _theme
	add_child(_hud)
	_hud_box = VBoxContainer.new()
	_hud.add_child(_hud_box)
	_hud_notice = Label.new()
	_hud_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_box.add_child(_hud_notice)
	_hud_grid = GridContainer.new()
	_hud_grid.columns = 9
	_hud_grid.add_theme_constant_override(&"h_separation", 4)
	_hud_grid.add_theme_constant_override(&"v_separation", 4)
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override(&"separation", 28)
	_hud_box.add_child(hud_row)
	hud_row.add_child(_hud_grid)
	_hud_weapon_grid = GridContainer.new()
	_hud_weapon_grid.columns = NetConfig.WEAPON_SLOT_COUNT
	_hud_weapon_grid.add_theme_constant_override(&"h_separation", 4)
	_hud_weapon_grid.add_theme_constant_override(&"v_separation", 4)
	hud_row.add_child(_hud_weapon_grid)
	_cursor_box = Control.new()
	_cursor_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_box.visible = false
	_cursor_box.z_index = 30
	add_child(_cursor_box)
	_cursor_icon = TextureRect.new()
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_box.add_child(_cursor_icon)
	_cursor_qty = _count_label()
	_cursor_qty.visible = false
	_cursor_qty.z_index = 31
	add_child(_cursor_qty)
	_name_tip = PanelContainer.new()
	_name_tip.visible = false
	_name_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tip.z_index = 40
	_name_tip.theme = _theme
	_name_tip.add_theme_stylebox_override(&"panel", _UiStyle.tooltip_style())
	add_child(_name_tip)
	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_tip.add_child(_name_label)
	## Re-fit whenever the window or the content size changes.
	get_viewport().size_changed.connect(_update_scale)
	_screen.minimum_size_changed.connect(_update_scale)
	_screen.resized.connect(_update_scale)
	_hud_box.minimum_size_changed.connect(_update_scale)
	_hud.resized.connect(_update_scale)
	_update_scale.call_deferred()


## Shrinks the open screen (and the hotbar) so they fit the window with a margin,
## and keeps them centered. Scaling the control keeps the layout intact, so
## clicks still hit the right slots.
func _update_scale() -> void:
	if _screen == null or _hud_box == null or not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var avail := view - Vector2(SCREEN_MARGIN, SCREEN_MARGIN) * 2.0
	_screen.reset_size()
	var need := _screen.size
	_ui_scale = _fit(need, avail)
	_screen.scale = Vector2(_ui_scale, _ui_scale)
	_screen.pivot_offset = need * 0.5
	_screen.position = ((view - need) * 0.5).floor()
	_hud_box.reset_size()
	var hud_need := _hud_box.size
	var hud_scale := _fit(hud_need, Vector2(avail.x, INF))
	_hud_box.scale = Vector2(hud_scale, hud_scale)
	_hud_box.pivot_offset = Vector2(hud_need.x * 0.5, hud_need.y)
	_hud_box.position = Vector2(floorf((_hud.size.x - hud_need.x) * 0.5), _hud.size.y - hud_need.y)


static func _fit(need: Vector2, avail: Vector2) -> float:
	if need.x <= 1.0 or need.y <= 1.0:
		return 1.0
	return clampf(minf(avail.x / need.x, avail.y / need.y), MIN_UI_SCALE, 1.0)


## Sizes the dragged stack like it is in the storage grid: one box over every cell the
## item covers, picture drawn the same way, so you can see how many slots it will take.
func _layout_cursor(item_id: String) -> void:
	_cursor_shown_id = item_id
	var definition := ItemCatalog.get_item(item_id)
	var span := Inventory.footprint_of(item_id)
	_cursor_box_size = Vector2(SLOT_SIZE * span.x + SLOT_GAP * (span.x - 1), SLOT_SIZE * span.y + SLOT_GAP * (span.y - 1))
	_cursor_icon.rotation = 0.0
	_cursor_icon.pivot_offset = Vector2.ZERO
	_cursor_icon.texture = _Icons.texture_for(definition)
	if _cursor_icon.texture != null and not WeaponSpec.slot_of(item_id).is_empty():
		_fit_weapon_picture(_cursor_icon, definition, _cursor_box_size, false)
		return
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if span == Vector2i.ONE else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.position = Vector2.ZERO
	_cursor_icon.size = _cursor_box_size


## Where the held stack would land if dropped now, while it is held over a footprint grid.
## The stack is drawn centred on the pointer, so its top-left cell is the one under the
## top-left of the picture. Empty when the pointer is not over such a grid. Otherwise
## "area" and "index" name the top-left cell, "column" and "row" place it in the host, and
## "host" and "bag" are what it sits in.
func _cursor_anchor() -> Dictionary:
	if _player == null or _player.cursor_qty <= 0 or _player.cursor_item_id.is_empty():
		return {}
	var in_container := _hover_area == SlotOps.AREA_CONTAINER
	var bag := _player.container_view if in_container else _player.inventory
	var host := _box_grid if in_container else _storage_grid
	if not _screen.visible or _hover_index < 0 or bag == null or host == null or not host.is_visible_in_tree() \
			or _hover_index >= bag.capacity or not bag.in_grid(_hover_index):
		return {}
	var columns := NetConfig.GRID_COLUMNS
	var first := bag.grid_start()
	var rows := maxi(1, ceili(float(bag.storage_end() - first) / columns))
	var stride := float(SLOT_SIZE + SLOT_GAP)
	var s := _ui_scale
	var mouse := get_viewport().get_mouse_position()
	var corner := mouse - _cursor_box_size * s * 0.5 + Vector2(SLOT_SIZE, SLOT_SIZE) * s * 0.5
	var local := host.get_global_transform().affine_inverse() * corner
	var column := clampi(floori(local.x / stride), 0, columns - 1)
	var row := clampi(floori(local.y / stride), 0, rows - 1)
	var index := first + row * columns + column
	if index >= bag.storage_end():
		return {}
	return {"area": _hover_area, "index": index, "column": column, "row": row, "host": host, "bag": bag}


## Tints the cells the held stack would cover when dropped: green when free, yellow when it
## lands on one item, red when it cannot go there. Clears the tint when nothing is held
## over a grid.
func _update_drop_marks(s: float) -> void:
	var held_id := _player.cursor_item_id
	var anchor := _cursor_anchor()
	if anchor.is_empty():
		_hide_drop_marks(0)
		return
	var bag: Inventory = anchor["bag"]
	var host: Control = anchor["host"]
	var column: int = anchor["column"]
	var row: int = anchor["row"]
	var columns := NetConfig.GRID_COLUMNS
	var rows := maxi(1, ceili(float(bag.storage_end() - bag.grid_start()) / columns))
	var stride := float(SLOT_SIZE + SLOT_GAP)
	var hits := bag.footprint_hits(int(anchor["index"]), held_id)
	var tint := Color(0.95, 0.3, 0.25, 0.45)
	if bool(hits["fits"]):
		var holders: Array = hits["anchors"]
		if holders.is_empty():
			tint = Color(0.3, 0.85, 0.4, 0.4)
		elif holders.size() == 1:
			tint = Color(0.95, 0.85, 0.3, 0.4)
	var size := Inventory.footprint_of(held_id)
	var host_xf := host.get_global_transform()
	var used := 0
	for dy in size.y:
		for dx in size.x:
			if column + dx >= columns or row + dy >= rows:
				continue
			var mark := _drop_mark(used)
			mark.color = tint
			mark.scale = Vector2(s, s)
			mark.size = Vector2(SLOT_SIZE, SLOT_SIZE)
			mark.global_position = host_xf * Vector2((column + dx) * stride, (row + dy) * stride)
			mark.visible = true
			used += 1
	_hide_drop_marks(used)


func _drop_mark(index: int) -> ColorRect:
	while _drop_marks.size() <= index:
		var mark := ColorRect.new()
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.z_index = 29
		mark.visible = false
		add_child(mark)
		_drop_marks.append(mark)
	return _drop_marks[index]


func _hide_drop_marks(from: int) -> void:
	for i in range(from, _drop_marks.size()):
		_drop_marks[i].visible = false


func _on_screen_visibility() -> void:
	if _backdrop == null or _screen == null:
		return
	_backdrop.visible = _screen.visible
	if not _screen.visible or not is_inside_tree():
		return
	## Quick fade-in for the dim and the panels.
	_backdrop.modulate.a = 0.0
	_screen.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, 0.18)
	tween.tween_property(_screen, "modulate:a", 1.0, 0.12)


func _process(_delta: float) -> void:
	if _player == null or _cursor_box == null:
		return
	var held := _player.cursor_qty > 0 and _player.cursor_item_id != ""
	_cursor_box.visible = held
	_cursor_qty.visible = held and _player.cursor_qty > 1
	if held:
		var mouse := get_viewport().get_mouse_position()
		## The dragged stack matches the (possibly shrunk) slot size.
		var s := _ui_scale if _screen.visible else 1.0
		if _cursor_shown_id != _player.cursor_item_id:
			_layout_cursor(_player.cursor_item_id)
		_cursor_box.scale = Vector2(s, s)
		_cursor_box.size = _cursor_box_size
		## The dragged stack stays centred on the mouse cursor.
		_cursor_box.global_position = mouse - _cursor_box_size * s * 0.5
		_update_drop_marks(s)
		if _cursor_qty.visible:
			_cursor_qty.text = str(_player.cursor_qty)
			_cursor_qty.size = Vector2(48, 22)
			_cursor_qty.scale = Vector2(s, s)
			_cursor_qty.global_position = _cursor_box.global_position + (_cursor_box_size - Vector2(48, 22)) * s
	else:
		_cursor_shown_id = ""
		_hide_drop_marks(0)
	_update_name_tip()
	if _screen.visible and _progress_station != null and is_instance_valid(_progress_station):
		_craft_menu.set_progress(float(_progress_station.call(&"progress")))


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
	if event.is_action_pressed(&"cycle_weapon"):
		if not _screen.visible:
			_player.cycle_weapon()
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
		_clear_grid(_hud_weapon_grid)
		for index in mini(NetConfig.HOTBAR_SLOTS, bag.capacity):
			_add_slot(_hud_grid, SlotOps.AREA_PLAYER, index, true, false)
		_add_weapon_slots(_hud_weapon_grid, false)
		if _craft_menu != null and _craft_menu.visible:
			_craft_menu.clear()
		return
	_buttons.clear()
	_areas.clear()
	_indices.clear()
	_clear_grid(_storage_grid)
	_clear_grid(_hotbar_grid)
	_clear_grid(_hud_grid)
	_clear_grid(_hud_weapon_grid)
	_clear_grid(_weapon_grid)
	_clear_grid(_melee_grid)
	_clear_grid(_box_grid)
	for index in mini(NetConfig.HOTBAR_SLOTS, bag.capacity):
		_add_slot(_hotbar_grid, SlotOps.AREA_PLAYER, index, true, true)
		_add_slot(_hud_grid, SlotOps.AREA_PLAYER, index, true, false)
	_fill_cells(_storage_grid, SlotOps.AREA_PLAYER, bag, NetConfig.HOTBAR_SLOTS, bag.storage_end())
	_weapon_grid.visible = bag.weapon_slot_index(WeaponSpec.SLOT_PRIMARY) >= 0
	_melee_grid.visible = _weapon_grid.visible
	_add_weapon_slot(_weapon_grid, WeaponSpec.SLOT_PRIMARY, true, 2)
	_add_weapon_slot(_weapon_grid, WeaponSpec.SLOT_SIDEARM, true)
	_add_weapon_slot(_melee_grid, WeaponSpec.SLOT_MELEE, true)
	_add_weapon_slots(_hud_weapon_grid, false)
	var crate: Inventory = _player.container_view
	var station := _open_loot()
	var station_ui := station is Crafter or station is Smelter
	_box_panel.visible = crate != null and not station_ui
	_paint_box_header()
	if station_ui:
		_show_station_menu(station as LootContainer, bag)
	else:
		_progress_station = null
		_craft_menu.clear()
		if crate != null:
			_fill_cells(_box_grid, SlotOps.AREA_CONTAINER, crate, 0, crate.capacity)


## A one-column grid for stacking weapon slots.
func _weapon_column() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override(&"h_separation", SLOT_GAP)
	grid.add_theme_constant_override(&"v_separation", SLOT_GAP)
	return grid


## The primary, sidearm and melee slots in a row, each captioned while empty.
func _add_weapon_slots(grid: GridContainer, interactive: bool) -> void:
	for slot_name in WeaponSpec.SLOTS:
		_add_weapon_slot(grid, slot_name, interactive)


## One weapon slot. `rows` above 1 makes it a tall slot.
func _add_weapon_slot(grid: GridContainer, slot_name: String, interactive: bool, rows: int = 1) -> void:
	var index := _player.inventory.weapon_slot_index(slot_name)
	if index >= 0:
		## A tall slot stands its weapon upright, muzzle pointing up.
		_add_slot(grid, SlotOps.AREA_PLAYER, index, true, interactive, SLOT_SIZE, Vector2i(1, rows), rows > 1)


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
	_progress_station = station if station.has_method(&"progress") else null
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
	if area == SlotOps.AREA_PLAYER:
		if _player == null or _player.inventory == null:
			return ""
		return _player.inventory.weapon_slot_for(index).capitalize()
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


## Lays the slots first..last-1 of a bag out `GRID_COLUMNS` to a row in a hand-placed host.
## When the bag has a footprint grid, an item gets one button over every cell it covers
## and the covered cells get none. Anything else is one cell per slot.
func _fill_cells(host: Control, area: int, bag: Inventory, first: int, last: int) -> void:
	var columns := NetConfig.GRID_COLUMNS
	var stride := SLOT_SIZE + SLOT_GAP
	var rows := maxi(1, ceili(float(last - first) / columns))
	host.custom_minimum_size = Vector2(columns * stride - SLOT_GAP, rows * stride - SLOT_GAP)
	for index in range(first, last):
		var cell := index - first
		var column := cell % columns
		var row := cell / columns
		var span := Vector2i.ONE
		var item_id := str(bag.slots[index]["id"])
		if bag.grid_columns > 0:
			var holder := bag.anchor_at(index)
			if holder >= 0 and holder != index:
				continue
			if holder == index and int(bag.slots[index]["qty"]) > 0:
				var size := Inventory.footprint_of(item_id)
				span = Vector2i(mini(size.x, columns - column), mini(size.y, rows - row))
		var button := _add_slot(host, area, index, false, true, SLOT_SIZE, span)
		button.position = Vector2(column * stride, row * stride)
		button.size = button.custom_minimum_size


## `span` makes a slot that covers that many cells of the grid, gaps included. `rotated`
## lays the picture on its side across a tall slot.
func _add_slot(grid: Control, area: int, index: int, hotbar: bool, interactive: bool, size: int = SLOT_SIZE, span: Vector2i = Vector2i.ONE, rotated := false) -> Button:
	var button := Button.new()
	var box := Vector2(size * span.x + SLOT_GAP * (span.x - 1), size * span.y + SLOT_GAP * (span.y - 1))
	button.custom_minimum_size = box
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
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var definition := ItemCatalog.get_item(item_id)
		picture.texture = _Icons.texture_for(definition)
		if not WeaponSpec.slot_of(item_id).is_empty() and picture.texture != null:
			_fit_weapon_picture(picture, definition, box, rotated)
		else:
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if span == Vector2i.ONE else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.set_anchors_preset(Control.PRESET_FULL_RECT)
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
		return button
	grid.add_child(button)
	_buttons.append(button)
	_areas.append(area)
	_indices.append(index)
	return button


## Sizes a weapon's picture so the drawn part sits inside the slot with WEAPON_PAD of free
## space on every side, however long or tall the slot is. Guns with a measured trigger are
## drawn at the same trigger size (WEAPON_TRIGGER) and only shrunk when they would not fit.
## Sidearms are the exception and share one width (SIDEARM_WIDTH).
## `rotated` stands the weapon up,
## muzzle to the top, for a tall slot.
func _fit_weapon_picture(picture: TextureRect, definition: ItemDefinition, box: Vector2, rotated: bool) -> void:
	var used := _Icons.content_rect(definition)
	var texture_size := picture.texture.get_size()
	# The picture is laid out unrotated, in a frame turned on its side when rotated.
	var frame := Vector2(box.y, box.x) if rotated else box
	var room := frame - Vector2(WEAPON_PAD, WEAPON_PAD) * 2.0
	var scale := minf(room.x / used.size.x, room.y / used.size.y)
	var trigger := _Icons.trigger_fraction(definition.id)
	if WeaponSpec.slot_of(definition.id) == WeaponSpec.SLOT_SIDEARM:
		# Pistols all get the same drawn width, whatever their trigger measures.
		scale = minf(scale, SIDEARM_WIDTH / used.size.x)
	elif trigger > 0.0:
		scale = minf(scale, WEAPON_TRIGGER / (trigger * texture_size.x))
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size = texture_size * scale
	var middle := (used.position + used.size * 0.5) * scale
	if rotated:
		picture.pivot_offset = picture.size * 0.5
		picture.rotation_degrees = -90.0
		picture.position = box * 0.5 - picture.size * 0.5 - (middle - picture.size * 0.5).rotated(-PI * 0.5)
	else:
		picture.position = box * 0.5 - middle


func _active_border() -> Panel:
	return _UiStyle.selection_frame()


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


func _clear_grid(grid: Control) -> void:
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
	_player.select_slot(index)


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
	## A stack bigger than one cell lands where its top-left is, not under the pointer.
	if _player.cursor_qty > 0 and Inventory.footprint_of(_player.cursor_item_id) != Vector2i.ONE:
		var anchor := _cursor_anchor()
		if not anchor.is_empty():
			hit = anchor
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
		## get_global_rect ignores scale, so measure through the full transform.
		var button := _buttons[i]
		if (button.get_global_transform() * Rect2(Vector2.ZERO, button.size)).has_point(at):
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
