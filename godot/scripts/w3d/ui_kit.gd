class_name UiKit
extends RefCounted
## Shared look for the front-end screens: dark violet glass panels with a
## gold edge, Cinzel labels, and buttons with real states — idle, hover/focus
## (brighter edge and glow), pressed (a quick squash, a click), disabled
## (dimmed, ignores input). Everything is built in code and sized for a
## 1920x1080 canvas that stretches to the phone.

const GOLD := Color(0.9, 0.8, 0.58)
const PALE := Color(0.92, 0.92, 0.95)
const DIM := Color(0.66, 0.66, 0.74)
const VIOLET := Color(0.66, 0.56, 0.9)
const ERROR := Color(1.0, 0.55, 0.55)

static var _fonts := {}


static func font(which: String) -> Font:
	if not _fonts.has(which):
		match which:
			"title":
				# Plain Cinzel, lightly spaced: quiet, not decorative.
				var tf := FontVariation.new()
				tf.base_font = load("res://assets/fonts/Cinzel.ttf")
				tf.variation_opentype = {"wght": 500}
				tf.spacing_glyph = 3
				_fonts[which] = tf
			"italic":
				_fonts[which] = load("res://assets/fonts/Cormorant-Italic.ttf")
			_:
				var f := FontVariation.new()
				f.base_font = load("res://assets/fonts/Cinzel.ttf")
				f.variation_opentype = {"wght": 600 if which == "bold" else 450}
				_fonts[which] = f
	return _fonts[which]


static func label(text: String, size := 28, col := PALE, which := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(which))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static var _tex := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://assets/ui/front/%s.png" % name)
	return _tex[name]


## Dark smoked glass, a hairline pale-gold edge, an ornament in each corner.
static func panel_style(alpha := 1.0, _radius := 22, _border := 0.75) -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.035, 0.04, 0.07, 0.78 * alpha)
	s.border_color = Color(0.86, 0.78, 0.6, 0.38 * alpha)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 24
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_content_margin(side, 48.0)
	return s


static func panel(size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	p.custom_minimum_size = size
	p.draw.connect(_corners.bind(p))
	return p


## The four corner ornaments (one painted corner, mirrored).
static func _corners(c: Control) -> void:
	var t := tex("corner")
	var k := 64.0
	var w := c.size.x
	var h := c.size.y
	var tint := Color(1, 1, 1, 0.85)
	c.draw_texture_rect(t, Rect2(Vector2(-6, -6), Vector2(k, k)), false, tint)
	c.draw_texture_rect(t, Rect2(Vector2(w + 6, -6), Vector2(-k, k)), false, tint)
	c.draw_texture_rect(t, Rect2(Vector2(-6, h + 6), Vector2(k, -k)), false, tint)
	c.draw_texture_rect(t, Rect2(Vector2(w + 6, h + 6), Vector2(-k, -k)), false, tint)


## The gold divider with its star, as a centred strip.
static func divider(width := 560.0) -> TextureRect:
	var d := TextureRect.new()
	d.texture = tex("divider")
	d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	d.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	d.custom_minimum_size = Vector2(width, 40)
	d.modulate = Color(1, 1, 1, 0.55)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## The Ethereal Tales logo (painted), scaled to `width`.
static func logo(width := 900.0) -> TextureRect:
	var l := TextureRect.new()
	l.texture = tex("logo")
	l.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	l.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	l.custom_minimum_size = Vector2(width, width * 174.0 / 1143.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _plate(fill: Color, edge: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(3)
	s.content_margin_left = 40
	s.content_margin_right = 40
	return s


## A quiet button with every state: idle (smoked glass, faint edge), hover/
## focus (brighter edge, a little light, a gold diamond marker at the left),
## pressed (a quick squash and a click), disabled (dim, inert).
## `kind`: "primary" (warm gold hairline and text), "normal", "quiet" (text).
static func button(text: String, action: Callable, kind := "normal", width := 420.0, height := 72.0) -> Button:
	var b := Button.new()
	b.text = text.to_upper() if kind != "quiet" else text
	b.custom_minimum_size = Vector2(width, height)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font("bold"))
	b.add_theme_font_size_override("font_size", 24 if kind != "quiet" else 22)
	b.add_theme_constant_override("h_separation", 6)
	var gold := Color(0.9, 0.8, 0.58)
	if kind == "quiet":
		var none := StyleBoxEmpty.new()
		for state in ["normal", "pressed", "disabled", "hover", "focus"]:
			b.add_theme_stylebox_override(state, none)
		b.add_theme_color_override("font_color", Color(0.8, 0.8, 0.86))
		b.add_theme_color_override("font_hover_color", gold)
		b.add_theme_color_override("font_focus_color", gold)
	else:
		var edge := Color(gold, 0.75) if kind == "primary" else Color(1, 1, 1, 0.18)
		var fill := Color(0.12, 0.1, 0.06, 0.62) if kind == "primary" else Color(0.03, 0.035, 0.06, 0.55)
		b.add_theme_stylebox_override("normal", _plate(fill, edge))
		b.add_theme_stylebox_override("hover", _plate(fill.lightened(0.08), Color(gold, 0.95)))
		b.add_theme_stylebox_override("focus", _plate(fill.lightened(0.08), Color(gold, 0.95)))
		b.add_theme_stylebox_override("pressed", _plate(fill.darkened(0.3), Color(gold, 1.0), 2))
		b.add_theme_stylebox_override("disabled", _plate(Color(fill, 0.3), Color(1, 1, 1, 0.07)))
		b.add_theme_color_override("font_color", gold if kind == "primary" else Color(0.9, 0.9, 0.94))
		b.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.88))
		b.add_theme_color_override("font_focus_color", Color(1, 0.96, 0.88))
		b.draw.connect(func():
			if b.has_focus() or b.is_hovered():
				var c := Vector2(22, b.size.y * 0.5)
				b.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), gold))
		b.focus_entered.connect(b.queue_redraw)
		b.focus_exited.connect(b.queue_redraw)
	b.add_theme_color_override("font_pressed_color", gold)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.4))
	b.pivot_offset = Vector2(width, height) * 0.5
	b.button_down.connect(func():
		var t := b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE * 0.97, 0.05))
	b.button_up.connect(func():
		var t := b.create_tween()
		t.tween_property(b, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(func():
		Sfx.play("click", -8.0, 0.03)
		Input.vibrate_handheld(12)
		action.call())
	return b


static func field(placeholder: String, secret := false, width := 640.0) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(width, 68)
	e.add_theme_font_override("font", font("body"))
	e.add_theme_font_size_override("font_size", 28)
	e.add_theme_color_override("font_color", PALE)
	e.add_theme_color_override("font_placeholder_color", Color(DIM, 0.6))
	for state in ["normal", "focus", "read_only"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.02, 0.02, 0.04, 0.6)
		s.border_color = Color(GOLD, 0.85 if state == "focus" else 0.3)
		s.set_border_width_all(2)
		s.set_corner_radius_all(3)
		s.content_margin_left = 22
		s.content_margin_right = 22
		e.add_theme_stylebox_override(state, s)
	return e


## Fade a control in from slightly below.
static func appear(c: CanvasItem, delay := 0.0) -> void:
	c.modulate.a = 0.0
	var t := c.create_tween()
	t.tween_interval(delay)
	t.tween_property(c, "modulate:a", 1.0, 0.35)
