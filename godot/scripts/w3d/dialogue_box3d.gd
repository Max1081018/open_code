class_name DialogueBox3D
extends Control
## Conversation at the bottom of the screen, anime-RPG style: a soft dark
## gradient rising from the bottom edge, the speaker's name in gold between
## two thin rules with their title beneath, the line typed out, and a small
## bobbing diamond when it can be advanced. F, Space, Enter, a click or a
## tap shows the rest of a line, then the next. The rest of the HUD hides.

signal finished

const CHARS_PER_SECOND := 48.0
const GOLD := Color(0.96, 0.84, 0.56)

var lines: Array = []
var index := 0
var showing := false
var _shown := 0.0
var _on_done: Callable
var _name: Label
var _title: Label
var _text: Label
var _next: Control
var _rules: Control
var _fade: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# The gradient.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0.02, 0.03, 0.1, 0.0), Color(0.03, 0.04, 0.12, 0.62), Color(0.03, 0.04, 0.12, 0.86)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 128
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_top = -360
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var cinzel := FontVariation.new()
	cinzel.base_font = load("res://assets/fonts/Cinzel.ttf")
	cinzel.variation_opentype = {"wght": 700}
	_name = _make_label(cinzel, 38, GOLD)
	_name.offset_top = -268
	_title = _make_label(load("res://assets/fonts/Cinzel.ttf"), 22, Color(0.82, 0.8, 0.9))
	_title.offset_top = -222
	_text = _make_label(load("res://assets/fonts/Fredoka.ttf"), 31, Color(0.98, 0.97, 1.0))
	_text.offset_top = -182
	_text.offset_left = -640
	_text.offset_right = 640
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.custom_minimum_size = Vector2(1280, 110)
	# Thin gold rules either side of the name.
	_rules = Control.new()
	_rules.anchor_left = 0.5
	_rules.anchor_right = 0.5
	_rules.anchor_top = 1.0
	_rules.anchor_bottom = 1.0
	_rules.offset_top = -244
	_rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules.draw.connect(_draw_rules)
	add_child(_rules)
	_next = Control.new()
	_next.anchor_left = 0.5
	_next.anchor_right = 0.5
	_next.anchor_top = 1.0
	_next.anchor_bottom = 1.0
	_next.offset_top = -52
	_next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_next.draw.connect(_draw_next)
	add_child(_next)


func _make_label(font: Font, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.08, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -700
	l.offset_right = 700
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _draw_rules() -> void:
	var half := _name.get_theme_font("font").get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x * 0.5
	for s in [-1.0, 1.0]:
		var a := Vector2(s * (half + 24.0), 0)
		var b := Vector2(s * (half + 260.0), 0)
		_rules.draw_line(a, b, Color(GOLD, 0.75), 2.0, true)
		_rules.draw_colored_polygon(PackedVector2Array([a + Vector2(s * -2, 0), a + Vector2(s * 6, -6),
			a + Vector2(s * 14, 0), a + Vector2(s * 6, 6)]), GOLD)


func _draw_next() -> void:
	if _shown < float(_current().length()):
		return
	var y := sin(Time.get_ticks_msec() / 160.0) * 4.0
	var m := Vector2(0, y)
	_next.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -9), m + Vector2(9, 0), m + Vector2(0, 9), m + Vector2(-9, 0)]), GOLD)


func _current() -> String:
	return String(lines[index]) if index < lines.size() else ""


## Show `say` (lines) from `speaker`; `done` runs after the last one.
func open(_speaker_id: String, speaker: Dictionary, say: Array, done: Callable) -> void:
	lines = say
	index = 0
	_on_done = done
	_name.text = String(speaker.get("name", ""))
	_title.text = String(speaker.get("title", ""))
	showing = true
	visible = true
	modulate.a = 0.0
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.25)
	_start_line()


func _start_line() -> void:
	_shown = 0.0
	_text.text = _current()
	_text.visible_characters = 0
	_rules.queue_redraw()


## Show the rest of the line, or move to the next.
func advance() -> void:
	if not showing:
		return
	if _shown < float(_current().length()):
		_shown = float(_current().length())
		_text.visible_characters = -1
		return
	index += 1
	if index < lines.size():
		Sfx.play("click", -8.0)
		_start_line()
		return
	showing = false
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.2)
	_fade.tween_callback(func(): visible = false)
	finished.emit()
	if _on_done.is_valid():
		_on_done.call()


func _process(delta: float) -> void:
	if not showing:
		return
	var total := float(_current().length())
	if _shown < total:
		_shown = minf(total, _shown + delta * CHARS_PER_SECOND)
		_text.visible_characters = int(_shown)
	_next.queue_redraw()


func _input(event: InputEvent) -> void:
	if not showing:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		go = event.physical_keycode in [KEY_F, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	elif event is InputEventScreenTouch and event.pressed:
		go = true
	if go:
		get_viewport().set_input_as_handled()
		advance()
