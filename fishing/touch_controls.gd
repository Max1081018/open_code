extends CanvasLayer
## Mobile controls for walking around.
##
## Left: a joystick (floating under your thumb, or fixed in place).
## Above it: a RUN toggle. Releasing the stick drops back to walking.
## Right half: drag to look.
## Bottom right: a context action pill (FISH / BUY / SELL 3 ...).
## Centre: a crosshair with a compact info pill for whatever it's on.
##
## Multi-touch: stick, look, RUN and the action pill each track their own
## finger, so you can walk, aim and act at the same time.
##
## HUD options (from Settings): hud_scale, fixed_joystick, hud_opacity.

signal interact_pressed
signal secondary_pressed

const BASE_JOY_R := 100.0
const BASE_KNOB_R := 40.0
const BASE_RUN_R := 44.0
const BASE_ACT_R := 80.0
const BASE_SEC_R := 50.0
const LOOK_SENS := 0.0048

var move := Vector2.ZERO       # -1..1, screen space
var look := Vector2.ZERO       # consumed each frame by the camera
var sprint := false            # RUN toggle
var prompt := ""               # main action label; empty hides it
var secondary := ""            # second action (e.g. DROP / THROW); empty hides it
var look_info := ""            # name of whatever the crosshair is on
var look_stat := ""            # small grey stat line, e.g. "+1 power"
var look_cost := ""            # price or status, drawn in gold
var carry_info := ""           # "Carrying 3/5 - worth 120"
var crosshair := true
var sens_scale := 1.0

# HUD customisation
var hud_scale := 1.0
var fixed_joystick := false
var hud_opacity := 1.0

var _view: Painter
var _joy_index := -1
var _joy_home := Vector2.ZERO
var _joy_origin := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _look_index := -1
var _look_last := Vector2.ZERO
var _act_center := Vector2.ZERO
var _sec_center := Vector2.ZERO
var _btn_held := false
var _run_center := Vector2.ZERO
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


func joy_r() -> float:
	return BASE_JOY_R * hud_scale


func knob_r() -> float:
	return BASE_KNOB_R * hud_scale


func run_r() -> float:
	return BASE_RUN_R * hud_scale


func act_r() -> float:
	return BASE_ACT_R * hud_scale


func sec_r() -> float:
	return BASE_SEC_R * hud_scale


## Icon for whatever the action button says.
static func icon_for(label: String) -> String:
	var l := label.split(" ")[0]
	match l:
		"FISH": return "cast"
		"BUY": return "buy"
		"EQUIP": return "equip"
		"UNEQUIP": return "back"
		"SELL": return "coin"
		"DROP": return "drop"
		"THROW": return "run"
		"GRAB": return "hand"
		"SAIL": return "boat"
		"LOCKED", "TOO": return "lock"
		_: return "hand"


func apply_layout() -> void:
	_recalc()


func _recalc() -> void:
	var s := get_viewport().get_visible_rect().size
	var m := 56.0
	_joy_home = Vector2(m + joy_r() + 36.0, s.y - m - joy_r() - 20.0)
	# Right-thumb cluster: big action, secondary above-left, RUN to the left.
	_act_center = Vector2(s.x - m - act_r() - 10.0, s.y - m - act_r() - 10.0)
	_sec_center = _act_center + Vector2(-act_r() * 0.55, -(act_r() + sec_r() + 22.0))
	_run_center = _act_center + Vector2(-(act_r() + run_r() + 36.0), act_r() * 0.35)


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


func _release_stick() -> void:
	_joy_index = -1
	_joy_knob = Vector2.ZERO
	move = Vector2.ZERO
	sprint = false          # letting go drops back to a walk


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5

	if event is InputEventScreenTouch:
		if event.pressed:
			if prompt != "" and event.position.distance_to(_act_center) <= act_r() * 1.08:
				_btn_held = true
				interact_pressed.emit()
				return
			if secondary != "" and event.position.distance_to(_sec_center) <= sec_r() * 1.15:
				secondary_pressed.emit()
				return
			if event.position.distance_to(_run_center) <= run_r() * 1.25:
				sprint = not sprint
				return
			var on_stick: bool = event.position.x < half
			if fixed_joystick:
				on_stick = event.position.distance_to(_joy_home) <= joy_r() * 1.6
			if on_stick and _joy_index == -1:
				_joy_index = event.index
				_joy_origin = _joy_home if fixed_joystick else event.position
				_joy_knob = Vector2.ZERO
				move = Vector2.ZERO
			elif event.position.x >= half and _look_index == -1:
				_look_index = event.index
				_look_last = event.position
		else:
			_btn_held = false
			if event.index == _joy_index:
				_release_stick()
			elif event.index == _look_index:
				_look_index = -1

	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_joy_knob = (event.position - _joy_origin).limit_length(joy_r())
			move = _joy_knob / joy_r()
		elif event.index == _look_index:
			look += (event.position - _look_last) * LOOK_SENS * sens_scale
			_look_last = event.position


class Painter extends Control:
	var ui

	func _a(c: Color) -> Color:
		var o := c
		o.a *= float(ui.hud_opacity)
		return o

	func _pill(rect: Rect2, color: Color, radius := 22, border := Color(1, 1, 1, 0.16)) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(radius)
		sb.set_border_width_all(2)
		sb.border_color = border
		draw_style_box(sb, rect)

	func _centred(font: Font, text: String, mid: Vector2, size: int, color: Color) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(mid.x - w * 0.5, mid.y + size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

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

		# ---- What you're carrying ----
		if ui.carry_info != "":
			var cw2 := font.get_string_size(ui.carry_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var crect := Rect2(Vector2(mid.x - cw2 * 0.5 - 22, 22), Vector2(cw2 + 44, 46))
			_pill(crect, UITheme.PANEL, 23, Color(1, 0.8, 0.3, 0.35))
			_centred(font, ui.carry_info, crect.position + crect.size * 0.5, 22, UITheme.GOLD)

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
		var op: float = ui.hud_opacity
		var jr: float = ui.joy_r()
		var kr: float = ui.knob_r()
		var active: bool = ui._joy_index != -1
		var centre: Vector2 = ui._joy_origin if active else ui._joy_home
		draw_circle(centre, jr, Color(0.03, 0.07, 0.13, (0.40 if active else 0.26) * op))
		draw_arc(centre, jr - 1.5, 0, TAU, 64, Color(1, 1, 1, (0.45 if active else 0.25) * op), 3.0, true)
		# direction ticks
		for i in 4:
			var a := i * PI * 0.5
			var p := centre + Vector2(cos(a), sin(a)) * (jr - 14.0)
			draw_circle(p, 3.0, Color(1, 1, 1, 0.35 * op))
		var knob: Vector2 = centre + ui._joy_knob
		draw_circle(knob + Vector2(0, 3), kr, Color(0, 0, 0, 0.25 * op))
		draw_circle(knob, kr, Color(1, 1, 1, (0.85 if active else 0.45) * op))
		draw_arc(knob, kr * 0.62, 0, TAU, 32, Color(0.03, 0.07, 0.13, 0.25 * op), 2.0, true)

		# ---- right cluster ----
		UIDraw.round_button(self, font, ui._run_center, ui.run_r(), "RUN", "run", ui.sprint, false, op)
		if ui.secondary != "":
			UIDraw.round_button(self, font, ui._sec_center, ui.sec_r(), ui.secondary,
				ui.icon_for(ui.secondary), false, false, op)
		if ui.prompt != "":
			var dim: bool = ui.prompt == "LOCKED" or ui.prompt == "TOO DEAR"
			UIDraw.round_button(self, font, ui._act_center, ui.act_r(), ui.prompt,
				ui.icon_for(ui.prompt), not dim, ui._btn_held, op)
