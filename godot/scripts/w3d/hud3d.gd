class_name Hud3D
extends CanvasLayer
## The on-screen layer of the open world: health and stamina, the hotbar,
## a feed of pickups and events, region names as you enter them, the boss's
## bar, a crosshair in first person, and touch controls on phones (move stick
## on the left, drag the right half to look, action buttons).

var game: Node
var root: Control
var _health: ProgressBar
var _stamina: ProgressBar
var _region: Label
var _region_time := 0.0
var _last_biome := -1
var _crosshair: Control
var _slots: Array = []
var _feed: VBoxContainer
var _boss_box: Control
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss: Enemy3D
var _title_font: Font
var _body_font: Font
var touch := false
var _stick_center := Vector2.ZERO
var _stick_touch := -1
var _look_touch := -1
var _stick_knob: Control
var _stick_base: Control

const GOLD := Color(0.95, 0.8, 0.45)


func setup(the_game: Node) -> void:
	game = the_game
	layer = 10
	_title_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_body_font = load("res://assets/fonts/Fredoka.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_health = _bar(Color(0.82, 0.2, 0.2), Vector2(36, 32), Vector2(380, 22))
	_stamina = _bar(Color(0.95, 0.76, 0.28), Vector2(36, 62), Vector2(300, 12))
	_region = _label("", 58, Color(1.0, 0.94, 0.8), _title_font)
	_region.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_region.offset_left = -500
	_region.offset_right = 500
	_region.offset_top = 110
	_region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_region)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.draw.connect(func():
		_crosshair.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		_crosshair.draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.35), 2.0))
	root.add_child(_crosshair)
	_build_hotbar()
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_feed.offset_left = 36
	_feed.offset_top = -60
	_feed.add_theme_constant_override("separation", 6)
	root.add_child(_feed)
	_build_boss_bar()
	touch = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")
	if touch:
		_build_touch()
	game.play.toast.connect(_toast)
	game.play.inventory_changed.connect(_refresh_hotbar)
	_refresh_hotbar()


func _label(text: String, size: int, colour: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 9))
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(bg: Color, radius: int, border := Color(0, 0, 0, 0), width := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(width)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


func _bar(colour: Color, at: Vector2, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = at
	bar.custom_minimum_size = size
	bar.size = size
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", _panel(colour, 6))
	bar.add_theme_stylebox_override("background", _panel(Color(0.04, 0.04, 0.06, 0.65), 6, Color(1, 1, 1, 0.22), 2))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return bar


func _build_hotbar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.add_theme_constant_override("separation", 8)
	var slot_size := 84
	var width := Inventory.HOTBAR_SIZE * slot_size + (Inventory.HOTBAR_SIZE - 1) * 8
	row.offset_left = -width / 2.0
	row.offset_right = width / 2.0
	row.offset_top = -(slot_size + 26)
	row.offset_bottom = -26
	root.add_child(row)
	for i in Inventory.HOTBAR_SIZE:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 10
		icon.offset_top = 10
		icon.offset_right = -10
		icon.offset_bottom = -10
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var count := _label("", 24, Color.WHITE, _body_font)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -50
		count.offset_top = -34
		count.offset_right = -6
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot.add_child(count)
		var key := _label(str(i + 1), 18, Color(1, 1, 1, 0.55), _body_font)
		key.position = Vector2(7, 2)
		slot.add_child(key)
		var index := i
		slot.gui_input.connect(func(e):
			if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
				game.play.select(index))
		row.add_child(slot)
		_slots.append([slot, icon, count])


## A rendered 3D icon (tools/render_icons.gd) where there is one.
static func icon_for(id: String) -> Texture2D:
	var path := "res://assets/icons3d/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else Items.icon(id)


func _refresh_hotbar() -> void:
	var inv: Inventory = game.play.inventory
	for i in _slots.size():
		var s: Array = _slots[i]
		var stack = inv.get_slot(i)
		(s[1] as TextureRect).texture = icon_for(stack.id) if stack != null else null
		(s[2] as Label).text = str(stack.count) if stack != null and stack.count > 1 else ""
		var selected: bool = i == game.play.hotbar_index
		(s[0] as Panel).add_theme_stylebox_override("panel", _panel(Color(0.08, 0.07, 0.06, 0.72), 14,
			GOLD if selected else Color(1, 1, 1, 0.18), 4 if selected else 2))


func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -420
	_boss_box.offset_right = 420
	_boss_box.offset_top = 26
	_boss_name = _label("", 40, Color(1.0, 0.86, 0.7), _title_font)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(840, 20)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("fill", _panel(Color(0.75, 0.15, 0.12), 4))
	_boss_bar.add_theme_stylebox_override("background", _panel(Color(0.04, 0.03, 0.03, 0.75), 4, Color(0.95, 0.8, 0.45, 0.6), 2))
	_boss_box.add_child(_boss_bar)
	_boss_box.visible = false
	root.add_child(_boss_box)


func boss_bar(e: Enemy3D) -> void:
	_boss = e
	_boss_box.visible = e != null
	if e:
		_boss_name.text = e.spec.boss


func _toast(text: String) -> void:
	var l := _label(text, 30, Color(1.0, 0.95, 0.85), _body_font)
	_feed.add_child(l)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var t := l.create_tween()
	t.tween_interval(2.6)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _process(delta: float) -> void:
	var p: Player3D = game.player
	if p == null:
		return
	_health.value = p.health / p.max_health * 100.0
	_stamina.value = p.stamina / p.max_stamina * 100.0
	_stamina.modulate.a = 1.0 if p.stamina < p.max_stamina - 0.5 else 0.4
	_crosshair.visible = game.cam.first_person
	if _boss:
		_boss_bar.value = maxf(_boss.health, 0.0) / _boss.max_health * 100.0
	var b: int = game.world.biome_at(p.global_position)
	if b != _last_biome:
		_last_biome = b
		_region.text = game.world.gen.biome_name(b)
		_region_time = 3.5
	_region_time -= delta
	_region.modulate.a = clampf(_region_time, 0.0, 1.0)


# ------------------------------------------------------------ touch ---

func _build_touch() -> void:
	_stick_base = Control.new()
	_stick_base.size = Vector2(240, 240)
	_stick_base.position = Vector2(90, 0)
	_stick_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.position = Vector2(90, -330)
	_stick_base.draw.connect(func(): _stick_base.draw_circle(Vector2(120, 120), 120, Color(1, 1, 1, 0.12)))
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stick_base)
	_stick_knob = Control.new()
	_stick_knob.size = Vector2(100, 100)
	_stick_knob.draw.connect(func(): _stick_knob.draw_circle(Vector2(50, 50), 50, Color(1, 1, 1, 0.35)))
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.add_child(_stick_knob)
	_stick_knob.position = Vector2(70, 70)
	var buttons := [["attack", "⚔", Vector2(-230, -260), 150], ["heavy", "✦", Vector2(-410, -200), 96],
		["jump", "⤒", Vector2(-170, -420), 100], ["dodge", "↻", Vector2(-330, -380), 96],
		["sprint", "»", Vector2(-480, -340), 86], ["interact", "✋", Vector2(-400, -520), 86],
		["view", "👁", Vector2(-150, -560), 80]]
	for spec in buttons:
		var b := Button.new()
		b.text = spec[1]
		b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		b.position = spec[2]
		b.size = Vector2(spec[3], spec[3])
		b.add_theme_font_size_override("font_size", int(spec[3] * 0.42))
		var style := _panel(Color(0.1, 0.09, 0.08, 0.55), int(spec[3] / 2), Color(1, 1, 1, 0.3), 3)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("pressed", _panel(Color(0.95, 0.8, 0.45, 0.6), int(spec[3] / 2)))
		b.add_theme_stylebox_override("hover", style)
		var action: String = spec[0]
		b.button_down.connect(func(): game.input.touch_buttons[action] = true)
		if action in ["attack", "sprint"]:
			b.button_up.connect(func(): game.input.touch_buttons.erase(action))
		root.add_child(b)


func _input(event: InputEvent) -> void:
	if not touch:
		return
	var screen := root.get_viewport_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < screen.x * 0.4 and event.position.y > screen.y * 0.35 and _stick_touch < 0:
				_stick_touch = event.index
				_stick_center = event.position
			elif event.position.x >= screen.x * 0.4 and _look_touch < 0:
				_look_touch = event.index
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				game.input.touch_move = Vector2.ZERO
				_stick_knob.position = Vector2(70, 70)
			if event.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			var v: Vector2 = (event.position - _stick_center) / 110.0
			v = v.limit_length(1.0)
			game.input.touch_move = Vector2(v.x, -v.y)
			_stick_knob.position = Vector2(70, 70) + v * 70.0
		elif event.index == _look_touch:
			game.input.touch_look += event.relative * 0.005
