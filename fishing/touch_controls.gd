extends CanvasLayer
## Mobile controls for walking around: a floating joystick on the left half, a
## look-drag on the right half, and a context interact button.
##
## Multi-touch aware — each finger is tracked by its own index, so you can walk
## and turn the camera at the same time.

signal interact_pressed

const JOY_RADIUS := 110.0
const LOOK_SENS := 0.0052

var move := Vector2.ZERO       # -1..1, screen space
var look := Vector2.ZERO       # consumed each frame by the camera
var prompt := ""               # interact button label; empty hides it

var _view: Painter
var _joy_index := -1
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _btn_center := Vector2.ZERO
const BTN_RADIUS := 86.0


func _ready() -> void:
	layer = 5
	_view = Painter.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_recalc()
	get_viewport().size_changed.connect(_recalc)


func _recalc() -> void:
	var s := get_viewport().get_visible_rect().size
	_btn_center = Vector2(s.x - 150, s.y - 330)


func _process(_d: float) -> void:
	_view.queue_redraw()


func consume_look() -> Vector2:
	var l := look
	look = Vector2.ZERO
	return l


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var half := vp.x * 0.5

	if event is InputEventScreenTouch:
		if event.pressed:
			# Interact button first — it sits on the right side.
			if prompt != "" and event.position.distance_to(_btn_center) <= BTN_RADIUS:
				interact_pressed.emit()
				return
			if event.position.x < half and _joy_index == -1:
				_joy_index = event.index
				_joy_origin = event.position
				_joy_knob = Vector2.ZERO
				move = Vector2.ZERO
			elif event.position.x >= half and _look_index == -1:
				_look_index = event.index
				_look_last = event.position
		else:
			if event.index == _joy_index:
				_joy_index = -1
				_joy_knob = Vector2.ZERO
				move = Vector2.ZERO
			elif event.index == _look_index:
				_look_index = -1

	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_joy_knob = (event.position - _joy_origin).limit_length(JOY_RADIUS)
			move = _joy_knob / JOY_RADIUS
		elif event.index == _look_index:
			look += (event.position - _look_last) * LOOK_SENS
			_look_last = event.position


## Draws the joystick and the interact button.
class Painter extends Control:
	var ui

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font

		# Joystick: shown where you grabbed, or as a hint when idle.
		var active: bool = ui._joy_index != -1
		var centre: Vector2 = ui._joy_origin if active else Vector2(190, vp.y - 190)
		draw_circle(centre, ui.JOY_RADIUS, Color(1, 1, 1, 0.14 if active else 0.08))
		draw_arc(centre, ui.JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45 if active else 0.25), 3.0)
		draw_circle(centre + ui._joy_knob, 46.0, Color(1, 1, 1, 0.5 if active else 0.22))

		# Interact button.
		if ui.prompt != "":
			draw_circle(ui._btn_center, ui.BTN_RADIUS, Color(0.12, 0.5, 0.68, 0.75))
			draw_arc(ui._btn_center, ui.BTN_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.8), 4.0)
			var w := font.get_string_size(ui.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
			var p: Vector2 = ui._btn_center + Vector2(-w * 0.5, 10)
			draw_string_outline(font, p, ui.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color(0, 0, 0, 0.7))
			draw_string(font, p, ui.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
