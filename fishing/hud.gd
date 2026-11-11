extends CanvasLayer
## Fishing HUD for Reel Trouble (shown while you're at the rod).
##
## One big round action button (CAST / REEL / WHACK) under the right thumb, a
## smaller back button beside it, a compact message pill, a catch card for what
## you've landed, and slim fight meters. The game drives everything by setting
## `mode`, the meters and the card fields; the HUD only reports touches back.

enum { M_IDLE, M_CHARGING, M_WAITING, M_BITE, M_FIGHT, M_CAUGHT, M_SNAP, M_WHACK }

var mode := M_IDLE
var power := 0.0      # 0..1 cast charge
var distance := 1.0   # 1 = fish far, 0 = landed
var tension := 0.0    # 0..1, snaps at 1
var info := ""        # (unused on screen now; kept for callers)
var message := ""     # short status line(s): "Waiting for a bite..."
var coins := 0

# Catch card (shown while whacking / after a catch)
var card_title := ""
var card_sub := ""
var card_color := Color.WHITE
var card_hint := ""
var windup := 0.0     # 0..1 while the fish is about to leap at you
var streak := 0       # catches in a row (shown as a chip when 2+)
var _toast := ""
var _toast_t := 0.0

var _view: Painter
var _btn_center := Vector2.ZERO
var btn_radius := 84.0
var _action_index := -1
var _tapped := false
var _leave_pressed := false
var _leave_center := Vector2.ZERO
var leave_radius := 50.0

var enabled := true
var left_handed := false
var hud_scale := 1.0
var hud_opacity := 1.0


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
	btn_radius = 84.0 * hud_scale
	leave_radius = 46.0 * hud_scale
	var m := 64.0 + btn_radius
	var x := m if left_handed else s.x - m
	_btn_center = Vector2(x, s.y - m)
	var dir := 1.0 if left_handed else -1.0
	_leave_center = _btn_center + Vector2(dir * (btn_radius + leave_radius + 40.0), 30.0)


func recalc_layout() -> void:
	_recalc()


func set_hud_visible(v: bool) -> void:
	_view.visible = v


func clear_card() -> void:
	card_title = ""
	card_sub = ""
	card_hint = ""
	windup = 0.0


## A short message that pops in under the top bar for a couple of seconds.
func toast(text: String) -> void:
	_toast = text
	_toast_t = 2.6


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
	if _view.visible:
		_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if show_leave() and event.position.distance_to(_leave_center) <= leave_radius * 1.15:
				_leave_pressed = true
				return
			# The pause button (top-left) isn't a fishing tap.
			if Rect2(0, 0, 140, 140).has_point(event.position):
				return
			_tapped = true
			if event.position.distance_to(_btn_center) <= btn_radius * 1.1 and _action_index == -1:
				_action_index = event.index
		elif event.index == _action_index:
			_action_index = -1


# --- Queried by the game ------------------------------------------------------

func action_down() -> bool:
	return _action_index != -1


func show_leave() -> bool:
	return mode == M_IDLE or mode == M_CHARGING


func consume_leave() -> bool:
	var l := _leave_pressed
	_leave_pressed = false
	return l


func consume_tap() -> bool:
	var t := _tapped
	_tapped = false
	return t


func button_label() -> String:
	match mode:
		M_IDLE, M_CHARGING: return "CAST"
		M_FIGHT: return "REEL"
		M_WHACK: return "WHACK"
		_: return ""


func button_icon() -> String:
	match mode:
		M_IDLE, M_CHARGING: return "cast"
		M_FIGHT: return "reel"
		M_WHACK: return "whack"
		_: return ""


class Painter extends Control:
	var hud

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font
		var mid_x := vp.x * 0.5

		# ---- coins chip, top-right ----
		var ct := "%d" % hud.coins
		var cw := UIDraw.text_w(font, ct, 26)
		var crect := Rect2(Vector2(vp.x - cw - 92, 26), Vector2(cw + 66, 48))
		UIDraw.pill(self, crect, UITheme.PANEL, 24)
		UIDraw.icon(self, "coin", crect.position + Vector2(26, 24), 16, UITheme.GOLD)
		draw_string(font, crect.position + Vector2(48, 24 + 26 * 0.35), ct,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UITheme.GOLD)

		# ---- streak chip, top-left beside the coins (only when on a run) ----
		if hud.streak >= 2:
			var st := "STREAK x%d" % hud.streak
			var sw := UIDraw.text_w(font, st, 20) + 36
			var srect := Rect2(Vector2(vp.x - cw - 92 - sw - 12, 30), Vector2(sw, 40))
			UIDraw.pill(self, srect, UITheme.ACCENT, 20, Color(1, 1, 1, 0.3))
			UIDraw.text_c(self, font, st, srect.position + srect.size * 0.5, 20, UIDraw.INK)

		var top := 96.0

		# ---- fight meters ----
		if hud.mode == hud.M_FIGHT:
			var bw := minf(vp.x * 0.42, 440.0)
			var bx := mid_x - bw * 0.5
			var panel := Rect2(Vector2(bx - 22, top - 14), Vector2(bw + 44, 104))
			UIDraw.pill(self, panel, UITheme.PANEL, 20)
			draw_string(font, Vector2(bx, top + 10), "REELED IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.TEXT_DIM)
			UIDraw.bar(self, Rect2(Vector2(bx, top + 18), Vector2(bw, 14)), 1.0 - hud.distance, UITheme.PRIMARY_HI)
			var tcol := UITheme.GOOD.lerp(UITheme.DANGER, clampf(hud.tension * 1.15, 0.0, 1.0))
			draw_string(font, Vector2(bx, top + 56), "LINE TENSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UITheme.TEXT_DIM)
			UIDraw.bar(self, Rect2(Vector2(bx, top + 64), Vector2(bw, 14)), hud.tension, tcol)
			top += 118.0

		# ---- catch card ----
		if hud.card_title != "":
			var tw := UIDraw.text_w(font, hud.card_title, 32)
			var sw := UIDraw.text_w(font, hud.card_sub, 21)
			var w := maxf(tw, sw) + 70.0
			var r := Rect2(Vector2(mid_x - w * 0.5, top - 8), Vector2(w, 88))
			UIDraw.pill(self, r, UITheme.PANEL, 20, hud.card_color * Color(1, 1, 1, 0.55), 2)
			draw_rect(Rect2(r.position + Vector2(14, 16), Vector2(6, 56)), hud.card_color)
			UIDraw.text_c(self, font, hud.card_title, Vector2(mid_x + 6, r.position.y + 32), 32, UITheme.TEXT)
			UIDraw.text_c(self, font, hud.card_sub, Vector2(mid_x + 6, r.position.y + 64), 21, hud.card_color)
			top += 98.0
			if hud.card_hint != "":
				var hw := UIDraw.text_w(font, hud.card_hint, 22) + 44
				var hr := Rect2(Vector2(mid_x - hw * 0.5, top), Vector2(hw, 42))
				var bg := UITheme.PANEL
				var col := UITheme.TEXT_WARM
				if hud.windup > 0.0:
					bg = UITheme.DANGER.lerp(UITheme.PANEL, 0.25)
					col = Color.WHITE
				UIDraw.pill(self, hr, bg, 21)
				UIDraw.text_c(self, font, hud.card_hint, hr.position + hr.size * 0.5, 22, col)
				top += 52.0

		# ---- short message ----
		if hud.message != "":
			var lines: PackedStringArray = hud.message.split("\n")
			var l1: String = lines[0]
			var l2: String = lines[1] if lines.size() > 1 else ""
			var w1 := UIDraw.text_w(font, l1, 28)
			var w2 := UIDraw.text_w(font, l2, 21)
			var w := maxf(w1, w2) + 52.0
			var h := 54.0 if l2 == "" else 82.0
			var r := Rect2(Vector2(mid_x - w * 0.5, top), Vector2(w, h))
			UIDraw.pill(self, r, UITheme.PANEL, 22)
			UIDraw.text_c(self, font, l1, Vector2(mid_x, r.position.y + 27), 28, UITheme.TEXT_WARM)
			if l2 != "":
				UIDraw.text_c(self, font, l2, Vector2(mid_x, r.position.y + 58), 21, UITheme.TEXT_DIM)

		# ---- toast ----
		if hud._toast_t > 0.0 and hud._toast != "":
			var a := clampf(hud._toast_t / 0.4, 0.0, 1.0)
			var tw2 := UIDraw.text_w(font, hud._toast, 24) + 48
			var tr := Rect2(Vector2(mid_x - tw2 * 0.5, vp.y * 0.60), Vector2(tw2, 48))
			UIDraw.pill(self, tr, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.92 * a), 24, Color(1, 1, 1, 0.35 * a))
			UIDraw.text_c(self, font, hud._toast, tr.position + tr.size * 0.5, 24, Color(UIDraw.INK.r, UIDraw.INK.g, UIDraw.INK.b, a))

		# ---- buttons ----
		var op: float = hud.hud_opacity
		if hud.show_leave():
			UIDraw.round_button(self, font, hud._leave_center, hud.leave_radius, "BACK", "back",
				false, false, op)
		var label: String = hud.button_label()
		if label != "":
			var held: bool = hud.action_down()
			UIDraw.round_button(self, font, hud._btn_center, hud.btn_radius, label, hud.button_icon(),
				true, held, op)
			if hud.mode == hud.M_CHARGING and hud.power > 0.0:
				draw_arc(hud._btn_center, hud.btn_radius + 9, -PI / 2, -PI / 2 + TAU * hud.power,
					64, UITheme.GOLD, 7.0, true)
		elif hud.mode == hud.M_BITE:
			# Tap anywhere: show a pulsing prompt instead of a button.
			var t := Time.get_ticks_msec() / 1000.0
			var pr: float = hud.btn_radius * (1.0 + sin(t * 14.0) * 0.06)
			UIDraw.round_button(self, font, hud._btn_center, pr, "HOOK!", "fish", true, false, op)
