extends CanvasLayer
## On-screen UI: score/timer, end-of-round panel, and touch controls.
## Left half of the screen: a floating joystick that appears where you touch.
## Right half: tap to jump.

signal restart_pressed

const JOY_RADIUS := 90.0

var _status: Label
var _toast: Label
var _toast_time := 0.0
var _end_panel: PanelContainer
var _end_label: Label
var _touch_view: TouchView

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vector := Vector2.ZERO
var _jump_requested := false


func _ready() -> void:
	_touch_view = TouchView.new()
	_touch_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_touch_view)

	_status = _make_label(34)
	_status.position = Vector2(24, 16)
	add_child(_status)

	_toast = _make_label(40)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position.y = 90
	_toast.visible = false
	add_child(_toast)

	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.18, 0.85)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	_end_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	_end_label = _make_label(40)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_label)
	var button := Button.new()
	button.text = "Play again"
	button.custom_minimum_size = Vector2(260, 80)
	button.add_theme_font_size_override("font_size", 34)
	button.pressed.connect(func(): restart_pressed.emit())
	box.add_child(button)
	_end_panel.add_child(box)
	add_child(_end_panel)


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 8)
	return label


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0


func _input(event: InputEvent) -> void:
	if _end_panel.visible:
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and _joy_index == -1:
				_joy_index = event.index
				_joy_center = event.position
				_joy_vector = Vector2.ZERO
			elif event.position.x >= half:
				_jump_requested = true
		elif event.index == _joy_index:
			_joy_index = -1
			_joy_vector = Vector2.ZERO
		_touch_view.update_joystick(_joy_index != -1, _joy_center, _joy_vector * JOY_RADIUS)
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_joy_vector = (event.position - _joy_center).limit_length(JOY_RADIUS) / JOY_RADIUS
		_touch_view.update_joystick(true, _joy_center, _joy_vector * JOY_RADIUS)


# --- API used by main.gd ------------------------------------------------------

func joystick_vector() -> Vector2:
	return _joy_vector


func consume_jump() -> bool:
	var j := _jump_requested
	_jump_requested = false
	return j


func set_status(score: int, total: int, time_left: float) -> void:
	_status.text = "Orbs %d / %d     Time %d" % [score, total, ceili(time_left)]


func flash(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_time = 1.5


func show_end(text: String) -> void:
	_joy_index = -1
	_joy_vector = Vector2.ZERO
	_touch_view.update_joystick(false, Vector2.ZERO, Vector2.ZERO)
	_end_label.text = text
	_end_panel.visible = true
	# Re-center after the label has its final size.
	await get_tree().process_frame
	_end_panel.position = (get_viewport().get_visible_rect().size - _end_panel.size) * 0.5


## Draws the joystick (when held) and a jump button hint.
class TouchView extends Control:
	var _active := false
	var _center := Vector2.ZERO
	var _knob := Vector2.ZERO

	func update_joystick(active: bool, center: Vector2, knob: Vector2) -> void:
		_active = active
		_center = center
		_knob = knob
		queue_redraw()

	func _draw() -> void:
		var vp := get_viewport_rect().size
		if _active:
			draw_circle(_center, 90.0, Color(1, 1, 1, 0.18))
			draw_arc(_center, 90.0, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
			draw_circle(_center + _knob, 40.0, Color(1, 1, 1, 0.55))
		else:
			var hint := Vector2(170, vp.y - 170)
			draw_arc(hint, 90.0, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
			draw_circle(hint, 40.0, Color(1, 1, 1, 0.2))
		var jump := Vector2(vp.x - 150, vp.y - 150)
		draw_circle(jump, 70.0, Color(1, 1, 1, 0.2))
		draw_arc(jump, 70.0, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_string(ThemeDB.fallback_font, jump + Vector2(-38, 12), "JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.8))
