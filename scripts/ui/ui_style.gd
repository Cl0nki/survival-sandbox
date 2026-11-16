extends RefCounted

## Shared look for the inventory / crafting screens: dark rounded panels with
## padding and a soft drop shadow, slot-style buttons, an amber accent, and a
## dim vignette that darkens the world behind an open menu.

const ACCENT := Color(1.0, 0.78, 0.32)
const TEXT := Color(0.93, 0.94, 0.96)
const TEXT_DIM := Color(1, 1, 1, 0.55)
const PANEL_BG := Color(0.075, 0.082, 0.1, 0.96)
const PANEL_BORDER := Color(1, 1, 1, 0.09)
const SLOT_BG := Color(0.135, 0.145, 0.175, 0.95)
const PANEL_PAD_X := 22
const PANEL_PAD_Y := 18

const ACCENT_BUTTON := &"AccentButton"
const TITLE_SIZE := 22


static func box(bg: Color, border: Color, radius: int, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


static func panel_style() -> StyleBoxFlat:
	var style := box(PANEL_BG, PANEL_BORDER, 14)
	style.content_margin_left = PANEL_PAD_X
	style.content_margin_right = PANEL_PAD_X
	style.content_margin_top = PANEL_PAD_Y
	style.content_margin_bottom = PANEL_PAD_Y
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 28
	style.shadow_offset = Vector2(0, 8)
	return style


static func tooltip_style() -> StyleBoxFlat:
	var style := box(Color(0.05, 0.055, 0.07, 0.97), Color(1, 1, 1, 0.16), 8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	return style


static func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := box(bg, border, 8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox(&"panel", &"PanelContainer", panel_style())

	theme.set_color(&"font_color", &"Label", TEXT)

	theme.set_stylebox(&"normal", &"Button", _button_style(SLOT_BG, Color(1, 1, 1, 0.10)))
	theme.set_stylebox(&"hover", &"Button", _button_style(Color(0.2, 0.215, 0.26, 0.98), Color(1, 1, 1, 0.3)))
	theme.set_stylebox(&"pressed", &"Button", _button_style(Color(0.1, 0.11, 0.135, 1), Color(ACCENT, 0.7)))
	theme.set_stylebox(&"disabled", &"Button", _button_style(Color(SLOT_BG, 0.5), Color(1, 1, 1, 0.05)))
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	theme.set_color(&"font_color", &"Button", TEXT)
	theme.set_color(&"font_hover_color", &"Button", Color.WHITE)
	theme.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	theme.set_color(&"font_disabled_color", &"Button", Color(1, 1, 1, 0.35))
	theme.set_font_size(&"font_size", &"Button", 15)

	theme.set_type_variation(ACCENT_BUTTON, &"Button")
	theme.set_stylebox(&"normal", ACCENT_BUTTON, _button_style(Color(0.86, 0.63, 0.2), Color(1, 0.9, 0.6, 0.6)))
	theme.set_stylebox(&"hover", ACCENT_BUTTON, _button_style(Color(0.96, 0.73, 0.28), Color(1, 0.95, 0.75, 0.9)))
	theme.set_stylebox(&"pressed", ACCENT_BUTTON, _button_style(Color(0.7, 0.5, 0.14), Color(1, 0.9, 0.6, 0.6)))
	theme.set_stylebox(&"disabled", ACCENT_BUTTON, _button_style(Color(0.3, 0.27, 0.2, 0.6), Color(1, 1, 1, 0.05)))
	theme.set_color(&"font_color", ACCENT_BUTTON, Color(0.11, 0.08, 0.02))
	theme.set_color(&"font_hover_color", ACCENT_BUTTON, Color(0.08, 0.05, 0.0))
	theme.set_color(&"font_pressed_color", ACCENT_BUTTON, Color(0.08, 0.05, 0.0))
	theme.set_color(&"font_disabled_color", ACCENT_BUTTON, Color(1, 1, 1, 0.4))
	theme.set_font_size(&"font_size", ACCENT_BUTTON, 17)

	var track := box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 5, 0)
	track.content_margin_left = 5
	track.content_margin_right = 5
	theme.set_stylebox(&"scroll", &"VScrollBar", track)
	for state in [[&"grabber", 0.25], [&"grabber_highlight", 0.4], [&"grabber_pressed", 0.0]]:
		var grabber := box(
			Color(1, 1, 1, float(state[1])) if float(state[1]) > 0.0 else Color(ACCENT, 0.9),
			Color(0, 0, 0, 0), 5, 0
		)
		grabber.content_margin_left = 5
		grabber.content_margin_right = 5
		theme.set_stylebox(state[0], &"VScrollBar", grabber)

	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.1)
	line.thickness = 1
	theme.set_stylebox(&"separator", &"HSeparator", line)
	theme.set_constant(&"separation", &"HSeparator", 10)
	return theme


## Rounded outline for the selected / active slot.
static func selection_frame() -> Panel:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.z_index = 3
	var style := box(Color(0, 0, 0, 0), Color(ACCENT, 0.95), 8, 2)
	style.draw_center = false
	frame.add_theme_stylebox_override(&"panel", style)
	return frame


static func title(label: Label) -> void:
	label.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	label.add_theme_color_override(&"font_color", Color.WHITE)


## Full-screen vignette: lighter in the middle, darker toward the edges.
static func make_backdrop() -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.5),
		Color(0, 0, 0, 0.62),
		Color(0, 0, 0, 0.88),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	return rect
