extends CanvasLayer
## Touch UI for Lazy Lake. One big thumb button bottom-right is the context
## action (HOLD to charge a cast / HOLD to reel), and a tap anywhere advances
## bites and result screens. The game drives everything by setting `mode` and
## the meter values; the HUD only reports raw touch back.

enum { M_IDLE, M_CHARGING, M_WAITING, M_BITE, M_FIGHT, M_CAUGHT, M_SNAP, M_WHACK }

var mode := M_IDLE
var power := 0.0      # 0..1 cast charge
var distance := 1.0   # 1 = fish far, 0 = landed
var tension := 0.0    # 0..1, snaps at 1
var info := ""        # top-left persistent text
var message := ""     # big centre text

var _view: Painter
var _btn_center := Vector2.ZERO
const BTN_RADIUS := 110.0

var _action_index := -1
var _tapped := false

var enabled := true        # gameplay input only when playing
var left_handed := false   # mirror the action button to the left
var coins := 0


func _ready() -> void:
	_view = Painter.new()
	_view.hud = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_recalc()
	get_viewport().size_changed.connect(_recalc)


func _recalc() -> void:
	var s := get_viewport().get_visible_rect().size
	# Keep a thumb-sized margin from the bottom corner; honour left-handed mode.
	var x := 170.0 if left_handed else s.x - 170.0
	_btn_center = Vector2(x, s.y - 170)


func recalc_layout() -> void:
	_recalc()


func set_hud_visible(v: bool) -> void:
	_view.visible = v


func _process(_delta: float) -> void:
	_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_tapped = true
			if event.position.distance_to(_btn_center) <= BTN_RADIUS and _action_index == -1:
				_action_index = event.index
		elif event.index == _action_index:
			_action_index = -1


# --- Queried by the game ------------------------------------------------------

func action_down() -> bool:
	return _action_index != -1


func consume_tap() -> bool:
	var t := _tapped
	_tapped = false
	return t


func button_label() -> String:
	match mode:
		M_IDLE, M_CHARGING: return "CAST"
		M_FIGHT: return "REEL"
		M_WHACK: return "WHACK!"
		_: return ""


## Draws meters and the action button. Separate Control so it owns _draw.
class Painter extends Control:
	var hud

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font

		# Top-left info (clear of the pause button).
		if hud.info != "":
			_text(font, Vector2(130, 44), hud.info, 30, Color(1, 1, 1, 0.95))

		# Coins, top-right.
		var ctext := "Coins: %d" % hud.coins
		var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		_text(font, Vector2(vp.x - cw - 28, 46), ctext, 32, Color(1, 0.9, 0.4))

		# Big centre message — multi-line, auto-shrunk to fit the width.
		if hud.message != "":
			var lines: PackedStringArray = hud.message.split("\n")
			var size := 54
			for ln in lines:
				while size > 22 and font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > vp.x * 0.9:
					size -= 2
			var y := vp.y * 0.28
			for ln in lines:
				var w := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				_text(font, Vector2(vp.x * 0.5 - w * 0.5, y), ln, size, Color(1, 1, 0.85))
				y += size + 10

		# Fight meters, top-centre.
		if hud.mode == hud.M_FIGHT:
			var bw := minf(vp.x * 0.5, 460.0)
			var bx := vp.x * 0.5 - bw * 0.5
			_meter(Vector2(bx, 96), bw, 1.0 - hud.distance, Color(0.4, 0.85, 1.0), "REELED IN")
			var tcol := Color(0.4, 0.9, 0.4).lerp(Color(1.0, 0.25, 0.2), hud.tension)
			_meter(Vector2(bx, 150), bw, hud.tension, tcol, "LINE TENSION")

		# Action button.
		var label: String = hud.button_label()
		if label != "":
			var held: bool = hud.action_down()
			var base := Color(1, 1, 1, 0.16 if not held else 0.28)
			draw_circle(hud._btn_center, hud.BTN_RADIUS, base)
			draw_arc(hud._btn_center, hud.BTN_RADIUS, 0, TAU, 56, Color(1, 1, 1, 0.6), 4.0)
			# Charge ring while casting.
			if hud.mode == hud.M_CHARGING and hud.power > 0.0:
				draw_arc(hud._btn_center, hud.BTN_RADIUS - 10, -PI / 2, -PI / 2 + TAU * hud.power,
					56, Color(1.0, 0.85, 0.3), 8.0)
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 34).x
			_text(font, hud._btn_center + Vector2(-lw * 0.5, 12), label, 34, Color(1, 1, 1, 0.9))

	func _meter(pos: Vector2, w: float, value: float, color: Color, label: String) -> void:
		var h := 26.0
		draw_rect(Rect2(pos, Vector2(w, h)), Color(0, 0, 0, 0.4), true)
		draw_rect(Rect2(pos, Vector2(w * clampf(value, 0, 1), h)), color, true)
		draw_rect(Rect2(pos, Vector2(w, h)), Color(1, 1, 1, 0.5), false, 2.0)
		_text(ThemeDB.fallback_font, pos + Vector2(6, h + 22), label, 20, Color(1, 1, 1, 0.8))

	func _text(font, pos: Vector2, s: String, size: int, color: Color) -> void:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.7))
		draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
