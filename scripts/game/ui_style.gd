class_name UiStyle
extends RefCounted
## Shared look for the in-game menus (pause, settings, death / ending screens).

const ACCENT := Color(0.75, 0.16, 0.12)
const TEXT := Color(0.9, 0.88, 0.84)


static func button(text: String, width := 240.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _box(Color(0.05, 0.05, 0.06, 0.85), Color(0.3, 0.3, 0.32, 0.8)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.04, 0.04, 0.95), ACCENT))
	b.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.05, 0.04, 0.95), ACCENT))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), ACCENT))
	b.add_theme_stylebox_override("disabled", _box(Color(0.05, 0.05, 0.06, 0.5), Color(0.2, 0.2, 0.2, 0.5)))
	return b


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
