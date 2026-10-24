class_name UIKit
extends RefCounted
## Utilidades de interfaz: paleta, estilos y constructores de controles (todo por código).

const BG := Color(0.06, 0.07, 0.11, 0.94)
const PANEL := Color(0.11, 0.13, 0.19, 0.97)
const PANEL_LIGHT := Color(0.17, 0.2, 0.28, 1.0)
const ACCENT := Color(1.0, 0.76, 0.2)
const ACCENT_DARK := Color(0.75, 0.52, 0.08)
const TEXT := Color(0.94, 0.95, 0.98)
const TEXT_DIM := Color(0.68, 0.72, 0.8)
const GOOD := Color(0.4, 0.92, 0.55)
const BAD := Color(1.0, 0.35, 0.35)

static var _theme: Theme


static func style(bg: Color, border := Color(0, 0, 0, 0), radius := 14, border_w := 0, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.set_default_font_size(24)
	t.set_stylebox("normal", "Button", style(PANEL_LIGHT, Color(1, 1, 1, 0.12), 12, 2, 16))
	t.set_stylebox("hover", "Button", style(PANEL_LIGHT.lightened(0.12), ACCENT, 12, 2, 16))
	t.set_stylebox("pressed", "Button", style(ACCENT_DARK, ACCENT, 12, 2, 16))
	t.set_stylebox("disabled", "Button", style(PANEL.darkened(0.2), Color(1, 1, 1, 0.05), 12, 2, 16))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), ACCENT, 12, 2, 16))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", style(PANEL, Color(1, 1, 1, 0.1), 16, 2, 16))
	t.set_stylebox("slider", "HSlider", style(Color(0.2, 0.22, 0.3), Color(0, 0, 0, 0), 6, 0, 0))
	t.set_stylebox("grabber_area", "HSlider", style(ACCENT, Color(0, 0, 0, 0), 6, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", style(ACCENT.lightened(0.2), Color(0, 0, 0, 0), 6, 0, 0))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	var knob := _knob_texture()
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_constant("center_grabber", "HSlider", 1)
	t.set_stylebox("normal", "LineEdit", style(Color(0.05, 0.06, 0.09), Color(1, 1, 1, 0.2), 8, 2, 12))
	t.set_stylebox("normal", "CheckButton", style(Color(0, 0, 0, 0)))
	return t


static func _knob_texture() -> Texture2D:
	var img := Image.create(44, 44, false, Image.FORMAT_RGBA8)
	for y in 44:
		for x in 44:
			var d := Vector2(x - 21.5, y - 21.5).length()
			if d < 19.0:
				img.set_pixel(x, y, Color(1.0, 0.92, 0.7) if d < 15.0 else ACCENT)
	return ImageTexture.create_from_image(img)


static func button(text: String, min_size := Vector2(280, 66), font_size := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_ALL if PadInput.pad_mode else Control.FOCUS_NONE
	return b


static func accent_button(text: String, min_size := Vector2(280, 70), font_size := 28) -> Button:
	var b := button(text, min_size, font_size)
	b.add_theme_stylebox_override("normal", style(ACCENT_DARK, ACCENT, 12, 2, 16))
	b.add_theme_stylebox_override("hover", style(ACCENT_DARK.lightened(0.15), Color(1, 1, 1), 12, 2, 16))
	b.add_theme_stylebox_override("pressed", style(ACCENT, Color(1, 1, 1), 12, 2, 16))
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	return b


static func label(text: String, size := 24, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4 if size >= 28 else 0)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.horizontal_alignment = align
	return l


static func title(text: String, size := 56) -> Label:
	var l := label(text, size, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 10)
	return l


static func panel(min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func dim_background(alpha := 0.7) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_to_group("pad_dim")         # marca un panel modal: la navegación con mando se limita al más reciente
	return c


static func center_box(parent: Control, min_size := Vector2(700, 0)) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var p := panel(min_size)
	cc.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	return v


static func hsep(parent: Control) -> void:
	var s := HSeparator.new()
	parent.add_child(s)


static func fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


## Coloca un control con anclas puntuales (ax, ay) y desplazamientos relativos a ese punto.
static func place(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h
