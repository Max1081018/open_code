extends CanvasLayer
## Mobile controls for walking around.
##
## Left half: a floating joystick that appears under your thumb.
## Right half: drag to look.
## Bottom right: a context action pill (FISH / BUY 170 / EQUIP ...).
## Centre: a crosshair, with a compact info pill for whatever it's on.
##
## Multi-touch: the joystick, the look drag and the button each track their own
## finger, so you can walk, aim and act at the same time.

signal interact_pressed

const JOY_RADIUS := 105.0
const JOY_KNOB := 44.0
const LOOK_SENS := 0.0048
const BTN_SIZE := Vector2(300, 96)

var move := Vector2.ZERO       # -1..1, screen space
var look := Vector2.ZERO       # consumed each frame by the camera
var prompt := ""               # action pill label; empty hides it
var look_info := ""            # name of whatever the crosshair is on
var look_stat := ""            # small grey stat line, e.g. "+1 power"
var look_cost := ""            # price or status, drawn in gold
var crosshair := true
var sens_scale := 1.0

var _view: Painter
var _joy_index := -1
var _joy_home := Vector2.ZERO
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _btn_rect := Rect2()
var _btn_held := false
var _toast := ""
var _toast_t := 0.0


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
	_joy_home = Vector2(205, s.y - 195)
	_btn_rect = Rect2(Vector2(s.x - BTN_SIZE.x - 60, s.y - BTN_SIZE.y - 170), BTN_SIZE)


func flash(text: String) -> void:
	_toast = text
	_toast_t = 2.4


func consume_look() -> Vector2:
	var l := look
	look = Vector2.ZERO
	return l


func _process(d: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= d
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5

	if event is InputEventScreenTouch:
		if event.pressed:
			if prompt != "" and _btn_rect.has_point(event.position):
				_btn_held = true
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
			_btn_held = false
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
			look += (event.position - _look_last) * LOOK_SENS * sens_scale
			_look_last = event.position


class Painter extends Control:
	var ui

	func _pill(rect: Rect2, color: Color, radius := 22, border := Color(1, 1, 1, 0.16)) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(radius)
		sb.set_border_width_all(2)
		sb.border_color = border
		draw_style_box(sb, rect)

	func _centred(font: Font, text: String, mid: Vector2, size: int, color: Color, outline := 0) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p := Vector2(mid.x - w * 0.5, mid.y + size * 0.35)
		if outline > 0:
			draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.75))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font
		var mid := vp * 0.5
		var targeting: bool = ui.look_info != ""

		# ---- Crosshair ----
		if ui.crosshair:
			var r := 9.0 if targeting else 6.0
			var c := UITheme.ACCENT if targeting else Color(1, 1, 1, 0.65)
			draw_arc(mid, r, 0, TAU, 28, Color(0, 0, 0, 0.45), 4.0)
			draw_arc(mid, r, 0, TAU, 28, c, 2.0)
			draw_circle(mid, 2.2, c)

		# ---- What you're looking at ----
		if targeting:
			var name_size := 27
			var sub_size := 20
			var nw := font.get_string_size(ui.look_info, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
			var sw := font.get_string_size(ui.look_stat, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
			var cwid := font.get_string_size(ui.look_cost, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
			var gap := 14.0 if (ui.look_stat != "" and ui.look_cost != "") else 0.0
			var sub_w := sw + gap + cwid
			var pw: float = maxf(nw, sub_w) + 40.0
			var ph := 74.0 if sub_w > 0.0 else 50.0
			var rect := Rect2(Vector2(mid.x - pw * 0.5, mid.y + 32), Vector2(pw, ph))
			_pill(rect, UITheme.PANEL, 24)
			var cx := rect.position.x + rect.size.x * 0.5
			_centred(font, ui.look_info, Vector2(cx, rect.position.y + 24), name_size, UITheme.TEXT)
			if sub_w > 0.0:
				var sx := cx - sub_w * 0.5
				var sy := rect.position.y + 52 + sub_size * 0.35
				if ui.look_stat != "":
					draw_string(font, Vector2(sx, sy), ui.look_stat,
						HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, UITheme.TEXT_DIM)
				if ui.look_cost != "":
					draw_string(font, Vector2(sx + sw + gap, sy), ui.look_cost,
						HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, UITheme.GOLD)

		# ---- Toast ----
		if ui._toast_t > 0.0 and ui._toast != "":
			var fade: float = clampf(ui._toast_t / 0.5, 0.0, 1.0)
			var tw := font.get_string_size(ui._toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			var trect := Rect2(Vector2(mid.x - tw * 0.5 - 26, vp.y * 0.17), Vector2(tw + 52, 58))
			var bg := UITheme.PANEL
			bg.a *= fade
			_pill(trect, bg, 29, Color(1, 1, 1, 0.14 * fade))
			var tc := UITheme.TEXT_WARM
			tc.a = fade
			_centred(font, ui._toast, trect.position + trect.size * 0.5, 30, tc)

		# ---- Joystick ----
		var active: bool = ui._joy_index != -1
		var centre: Vector2 = ui._joy_origin if active else ui._joy_home
		var base_a := 0.20 if active else 0.11
		draw_circle(centre, float(ui.JOY_RADIUS), Color(0.02, 0.06, 0.12, base_a + 0.12))
		draw_arc(centre, float(ui.JOY_RADIUS), 0, TAU, 56, Color(1, 1, 1, 0.30 if active else 0.18), 3.0)
		var knob: Vector2 = centre + ui._joy_knob
		draw_circle(knob, float(ui.JOY_KNOB) + 2.0, Color(0, 0, 0, 0.25))
		draw_circle(knob, float(ui.JOY_KNOB), Color(1, 1, 1, 0.55 if active else 0.26))

		# ---- Action pill ----
		if ui.prompt != "":
			var held: bool = ui._btn_held
			var col: Color = UITheme.ACCENT_LO if held else UITheme.ACCENT
			_pill(ui._btn_rect, col, 26, Color(1, 1, 1, 0.28))
			_centred(font, ui.prompt, ui._btn_rect.position + ui._btn_rect.size * 0.5, 34,
				Color(0.12, 0.07, 0.03))
