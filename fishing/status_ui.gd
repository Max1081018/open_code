extends CanvasLayer
## Player status overlay: health and breath bars, the red hit flash, the
## underwater tint, and the death screen. Sits above the HUDs, below menus.

signal respawn_pressed

var health := 100.0
var max_health := 100.0
var breath := 1.0
var show_breath := false
var underwater := false
var visible_bars := true
var show_fps := false

var _hit := 0.0               # 0..1 red flash strength
var _shake := 0.0
var _dead := false
var _dead_t := 0.0
var _dead_title := ""
var _dead_sub := ""
var _view: Painter


func _ready() -> void:
	layer = 8
	_view = Painter.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


func hit(amount: float) -> void:
	_hit = clampf(0.35 + amount / 40.0, 0.35, 1.0)
	_shake = 1.0


func shake_amount() -> float:
	return _shake


func show_death(title: String, sub: String) -> void:
	_dead = true
	_dead_t = 0.0
	_dead_title = title
	_dead_sub = sub


func hide_death() -> void:
	_dead = false


func is_dead_screen() -> bool:
	return _dead


var _sig := ""
var _fps_t := 0.0

func _process(d: float) -> void:
	_hit = maxf(_hit - d * 1.6, 0.0)
	_shake = maxf(_shake - d * 3.0, 0.0)
	if _dead:
		_dead_t += d
	_fps_t += d
	# Only redraw when the bars / flash / death screen change (FPS twice a second).
	var fps_tick := 0
	if show_fps:
		fps_tick = int(_fps_t * 2.0)
	var sig := "%.1f|%.2f|%s|%s|%s|%s|%d" % [health, breath, show_breath, underwater, visible_bars, show_fps, fps_tick]
	if _hit > 0.0 or _dead or sig != _sig:
		_sig = sig
		_view.queue_redraw()


func _input(event: InputEvent) -> void:
	if _dead and _dead_t > 1.6 and event is InputEventScreenTouch and event.pressed:
		_dead = false
		respawn_pressed.emit()
		get_viewport().set_input_as_handled()


class Painter extends Control:
	var ui

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var font := ThemeDB.fallback_font

		# Underwater: murky green-blue wash.
		if ui.underwater:
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.28, 0.32, 0.55))

		# Hit: red vignette from the edges.
		if ui._hit > 0.0:
			var a: float = ui._hit
			var bands := 10
			for i in bands:
				var t := float(i) / bands
				var inset := t * minf(vp.x, vp.y) * 0.22
				var c := Color(0.85, 0.05, 0.05, a * 0.10 * (1.0 - t))
				draw_rect(Rect2(Vector2(inset, inset), vp - Vector2(inset, inset) * 2.0), c, false, minf(vp.x, vp.y) * 0.022)

		# Health and breath, top-left beside the pause button.
		if ui.visible_bars and not ui._dead:
			var x := 128.0
			var y := 30.0
			var frac: float = ui.health / ui.max_health
			var hc := UITheme.GOOD.lerp(UITheme.DANGER, clampf(1.0 - frac * 1.4, 0.0, 1.0))
			var panel := Rect2(Vector2(x, y - 4), Vector2(250, 44 if not ui.show_breath else 76))
			UIDraw.pill(self, panel, UITheme.PANEL, 20)
			UIDraw.icon(self, "heart", Vector2(x + 26, y + 18), 14, hc)
			UIDraw.bar(self, Rect2(Vector2(x + 48, y + 11), Vector2(184, 14)), frac, hc)
			if ui.show_breath:
				UIDraw.icon(self, "bubble", Vector2(x + 26, y + 50), 14, Color(0.6, 0.9, 1.0))
				UIDraw.bar(self, Rect2(Vector2(x + 48, y + 43), Vector2(184, 14)), ui.breath, Color(0.45, 0.82, 1.0))

		# Frame rate (Settings > Show FPS).
		if ui.show_fps:
			var fps := Engine.get_frames_per_second()
			var fc := UITheme.GOOD if fps >= 55 else (UITheme.GOLD if fps >= 30 else UITheme.DANGER)
			var fr := Rect2(Vector2(128, 116 if ui.show_breath else 84), Vector2(96, 30))
			UIDraw.pill(self, fr, UITheme.PANEL, 15)
			UIDraw.text_c(self, font, "%d FPS" % fps, fr.position + fr.size * 0.5, 17, fc)

		# Death screen.
		if ui._dead:
			var k := clampf(ui._dead_t / 1.2, 0.0, 1.0)
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.10, 0.0, 0.02, 0.78 * k))
			var tc := Color(1.0, 0.82, 0.78, k)
			UIDraw.text_c(self, font, ui._dead_title, Vector2(vp.x * 0.5, vp.y * 0.40), 64, tc)
			var sc := Color(0.95, 0.85, 0.85, k * 0.85)
			UIDraw.text_c(self, font, ui._dead_sub, Vector2(vp.x * 0.5, vp.y * 0.40 + 58), 26, sc)
			if ui._dead_t > 1.6:
				var t := "Tap to wake up on the jetty"
				var w := UIDraw.text_w(font, t, 24) + 56
				var r := Rect2(Vector2(vp.x * 0.5 - w * 0.5, vp.y * 0.62), Vector2(w, 52))
				UIDraw.pill(self, r, UITheme.ACCENT, 26, Color(1, 1, 1, 0.3))
				UIDraw.text_c(self, font, t, r.position + r.size * 0.5, 24, UIDraw.INK)
