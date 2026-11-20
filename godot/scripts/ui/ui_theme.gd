class_name UITheme
extends RefCounted
## One theme for every screen, built from the Kenney Adventure UI art.

const INK := Color(0.16, 0.11, 0.08)
const PAPER := Color(1.0, 0.96, 0.86)
const GOLD := Color(1.0, 0.82, 0.36)
const GLOW := Color(0.55, 0.88, 1.0)
const DANGER := Color(1.0, 0.36, 0.32)
## Secondary text on the cream panels. Cream-on-cream was unreadable.
const MUTED := Color(0.46, 0.33, 0.23)

static var _title: Font
static var _body: Font
static var _theme: Theme
static var _boxes := {}


static func title_font() -> Font:
	if _title == null:
		_title = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _title


static func body_font() -> Font:
	if _body == null:
		var variation := FontVariation.new()
		variation.base_font = load("res://assets/fonts/Fredoka.ttf")
		variation.variation_opentype = {"wght": 600}
		_body = variation
	return _body


## A 9-slice box from one of the Adventure panels.
static func box(name: String, margin := 22, content := 18) -> StyleBoxTexture:
	var key := "%s/%d/%d" % [name, margin, content]
	if _boxes.has(key):
		return _boxes[key]
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/panels/%s.png" % name)
	style.set_texture_margin_all(margin)
	style.set_content_margin_all(content)
	_boxes[key] = style
	return style


static func flat(color: Color, radius := 18, border := Color(0, 0, 0, 0), border_width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_content_margin_all(14)
	style.anti_aliasing = true
	return style


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 34

	t.set_stylebox("panel", "Panel", box("panel_brown", 28, 26))
	t.set_stylebox("panel", "PanelContainer", box("panel_brown", 28, 26))

	# Dark wood with a gold edge: Kenney's cream button art put cream text
	# on a cream face, which only its outline kept legible.
	t.set_stylebox("normal", "Button", _button(Color(0.44, 0.26, 0.15), GOLD))
	t.set_stylebox("hover", "Button", _button(Color(0.52, 0.32, 0.18), GOLD.lightened(0.2)))
	t.set_stylebox("pressed", "Button", _button(Color(0.30, 0.17, 0.10), GOLD))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _button(Color(0.40, 0.38, 0.42), Color(0.58, 0.56, 0.6)))
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.75, 0.78))
	t.set_color("font_outline_color", "Button", Color(0.18, 0.10, 0.06))
	t.set_constant("outline_size", "Button", 8)
	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 38)

	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", 32)

	t.set_stylebox("slider", "HSlider", flat(Color(0.30, 0.20, 0.14), 10))
	t.set_stylebox("grabber_area", "HSlider", flat(GOLD, 10))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(GOLD, 10))
	# The grabber art is 256 px; at native size every slider row was taller
	# than a thumb is wide and the settings ran off the screen.
	var knob := _scaled("res://assets/ui/panels/round_brown.png", 52)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _scaled("res://assets/ui/panels/checkbox_brown_checked.png", 64))
	t.set_icon("unchecked", "CheckButton", _scaled("res://assets/ui/panels/checkbox_brown_empty.png", 64))

	t.set_stylebox("panel", "TooltipPanel", box("panel_brown_dark", 24, 14))
	t.set_color("font_color", "TooltipLabel", PAPER)

	t.set_stylebox("normal", "LineEdit", flat(Color(1, 0.97, 0.88), 12, INK, 3))
	t.set_color("font_color", "LineEdit", INK)

	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.15), 8))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(0.45, 0.30, 0.20), 8))
	_theme = t
	return t


static func _scaled(path: String, size_px: int) -> Texture2D:
	var image: Image = (load(path) as Texture2D).get_image()
	image.resize(size_px, size_px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


static func _button(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := flat(fill, 20, edge, 4)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 4)
	style.set_content_margin_all(16)
	return style


## A big outlined title label.
static func title(text: String, size := 64, color := PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", title_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.05))
	label.add_theme_constant_override("outline_size", int(size * 0.22))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func text(content: String, size := 32, color := INK) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
