extends CanvasLayer
class_name VitalsHud

## Owner-only screen furniture for staying alive: a health bar, a red edge flash
## when hurt, and the death screen with the respawn countdown. It only reads
## the player; the server decides every number it shows.
## Later vitals (stamina, hunger) get their bars here.

const _UiStyle = preload("res://scripts/ui/ui_style.gd")
const BAR_SIZE := Vector2(260.0, 22.0)
const SCREEN_MARGIN := 24
## The hotbar spans the bottom centre, so the bar sits above its row.
const BAR_LIFT := 116
const FLASH_FADE_SEC := 0.5
const FLASH_MIN := 0.2
const FLASH_MAX := 0.6
const FLASH_DEATH := 0.9

var _player: PlayerController
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _bar_text: Label
var _flash: TextureRect
var _flash_tween: Tween
var _death_screen: ColorRect
var _death_timer: Label
var _last_health := -1


func bind_player(player: PlayerController) -> void:
	_player = player
	_last_health = player.health
	player.downed.connect(_on_downed)
	player.revived.connect(_on_revived)
	_refresh()


func _ready() -> void:
	layer = 20
	_build_flash()
	_build_bar()
	_build_death_screen()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.is_down() and _player.respawn_eta > 0.0:
		_player.respawn_eta = maxf(_player.respawn_eta - delta, 0.0)
	_refresh()


func _refresh() -> void:
	if _bar == null or _player == null:
		return
	var health := _player.health
	var ratio := float(health) / float(maxi(_player.max_health, 1))
	_bar.max_value = _player.max_health
	_bar.value = health
	_bar_text.text = "%d / %d" % [health, _player.max_health]
	_bar_fill.bg_color = Color(0.82, 0.22, 0.2).lerp(Color(0.36, 0.8, 0.38), clampf(ratio * 1.25 - 0.1, 0.0, 1.0))
	if _last_health >= 0 and health < _last_health and health > 0:
		_pulse_flash(clampf(FLASH_MIN + float(_last_health - health) / 100.0, FLASH_MIN, FLASH_MAX))
	_last_health = health
	var down := _player.is_down()
	_death_screen.visible = down
	if down:
		var left := ceili(_player.respawn_eta)
		_death_timer.text = "Respawning in %d s" % left if left > 0 else "Respawning..."


func _on_downed() -> void:
	_pulse_flash(FLASH_DEATH)


func _on_revived() -> void:
	_last_health = _player.health
	_refresh()


func _pulse_flash(strength: float) -> void:
	if _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = strength
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, FLASH_FADE_SEC)


func _build_flash() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.8, 0.05, 0.03, 0.0), Color(0.8, 0.05, 0.03, 0.8)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	_flash = TextureRect.new()
	_flash.texture = texture
	_flash.stretch_mode = TextureRect.STRETCH_SCALE
	_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)


func _build_bar() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override(&"margin_left", SCREEN_MARGIN)
	margin.add_theme_constant_override(&"margin_bottom", BAR_LIFT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill = _UiStyle.box(Color(0.36, 0.8, 0.38), Color(0, 0, 0, 0), 6, 0)
	_bar.add_theme_stylebox_override(&"background", _UiStyle.box(Color(0.05, 0.055, 0.07, 0.85), Color(1, 1, 1, 0.14), 6))
	_bar.add_theme_stylebox_override(&"fill", _bar_fill)
	margin.add_child(_bar)
	_bar_text = Label.new()
	_bar_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_text.add_theme_font_size_override(&"font_size", 13)
	_bar_text.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_bar_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_bar_text)


func _build_death_screen() -> void:
	_death_screen = ColorRect.new()
	_death_screen.color = Color(0.03, 0.0, 0.0, 0.62)
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.visible = false
	add_child(_death_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)
	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 54)
	title.add_theme_color_override(&"font_color", Color(0.9, 0.22, 0.18))
	column.add_child(title)
	_death_timer = Label.new()
	_death_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_timer.add_theme_font_size_override(&"font_size", 22)
	column.add_child(_death_timer)
	var hint := Label.new()
	hint.text = "Your things are where you fell."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override(&"font_color", _UiStyle.TEXT_DIM)
	column.add_child(hint)
