class_name DialogueBox
extends Control
## Spoken dialogue: a portrait, the speaker's name and role, and the line
## as a subtitle revealed in step with the voice as it plays. Tapping the
## box skips to the end of a line, or on to the next. It never blocks
## movement: on a phone you keep walking while someone talks.

signal finished

var _queue: Array = []
var _player: AudioStreamPlayer
var _portrait: TextureRect
var _name: Label
var _role: Label
var _text: RichTextLabel
var _hint: Label
var _line_time := 0.0
var _line_length := 1.0
var _hold := 0.0
var _current := ""


func _ready() -> void:
	# Top centre, between the vitals and the menu buttons: the play area
	# and the touch controls below stay clear.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -520
	offset_right = 520
	offset_top = 18
	offset_bottom = 228
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.07, 0.06, 0.10, 0.92), 26, Color(0.85, 0.66, 0.30, 0.9), 4))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(170, 170)
	frame.add_theme_stylebox_override("panel", UITheme.flat(Color(0.18, 0.14, 0.20), 20, Color(0.5, 0.4, 0.3), 3))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_portrait)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	var names := HBoxContainer.new()
	names.add_theme_constant_override("separation", 16)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(names)
	_name = UITheme.title("", 42, UITheme.GOLD)
	names.add_child(_name)
	_role = Label.new()
	_role.add_theme_font_size_override("font_size", 26)
	_role.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	_role.size_flags_vertical = Control.SIZE_SHRINK_END
	names.add_child(_role)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 30)
	_text.add_theme_color_override("default_color", UITheme.PAPER)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_text)
	_hint = Label.new()
	_hint.text = "tap ›"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	column.add_child(_hint)

	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)


func is_talking() -> bool:
	return visible


## Say these lines, one after another.
func say(lines: Array) -> void:
	for id in lines:
		if not Story.line(id).is_empty():
			_queue.append(id)
	if not visible and not _queue.is_empty():
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		_player.stop()
		_current = ""
		Sfx.duck_music(false)
		finished.emit()
		return
	_current = _queue.pop_front()
	var line := Story.line(_current)
	var who := Story.speaker(line.speaker)
	_portrait.texture = Story.portrait(line.speaker)
	_name.text = who.get("name", line.speaker)
	_role.text = who.get("title", "")
	_text.text = line.text
	_text.visible_ratio = 0.0
	var audio := Story.audio(_current)
	_player.stream = audio
	# Without a recording, read at a comfortable pace.
	_line_length = audio.get_length() if audio else maxf(2.0, line.text.length() / 16.0)
	_line_time = 0.0
	_hold = 0.0
	if audio:
		_player.play()
	Sfx.duck_music(true)
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_line_time += delta
	# The subtitle runs slightly ahead of the voice, so the eye leads the ear.
	_text.visible_ratio = clampf(_line_time / (_line_length * 0.85), 0.0, 1.0)
	if _line_time >= _line_length:
		_hold += delta
		_hint.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
		# Linger a moment after the voice ends, then go on by itself.
		if _hold > 1.6:
			_next()
	else:
		_hint.modulate.a = 0.35


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not tapped:
		return
	accept_event()
	if _text.visible_ratio < 1.0:
		# First tap: show the whole line.
		_line_time = _line_length
		_text.visible_ratio = 1.0
	else:
		_next()


## Skip everything (cutscene skip, opening a menu).
func stop() -> void:
	_queue.clear()
	_next()
