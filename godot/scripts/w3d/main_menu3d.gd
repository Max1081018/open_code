extends Control
## The title screen: the key art (the heroine over the crystal city and
## floating isles) slowly drifting, light petals in the air, a soft dark veil
## on the left, the star emblem and title, and the menu as gold-edged rows
## with diamond markers. The hovered or focused row glows.

const GAME := "res://scenes/main3d.tscn"
const GOLD := Color(0.96, 0.84, 0.56)
const PALE := Color(0.95, 0.93, 1.0)

var _art: TextureRect
var _time := 0.0
var _rows: Array = []
var _selected := 0
var _settings: Control
var _emblem: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var title_font: Font = load("res://assets/fonts/CinzelDecorative-Bold.ttf")
	var menu_font := FontVariation.new()
	menu_font.base_font = load("res://assets/fonts/Cinzel.ttf")
	menu_font.variation_opentype = {"wght": 600}
	var italic: Font = load("res://assets/fonts/Cormorant-Italic.ttf")

	_art = TextureRect.new()
	_art.texture = load("res://assets/ui/menu/keyart.jpg")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.pivot_offset = Vector2(960, 540)
	add_child(_art)

	# Veil: deep blue-violet on the left, fading out by the middle.
	var veil := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.04, 0.05, 0.14, 0.82))
	grad.set_color(1, Color(0.04, 0.05, 0.14, 0.0))
	grad.add_point(0.38, Color(0.05, 0.06, 0.16, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 0)
	gt.width = 512
	gt.height = 4
	veil.texture = gt
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.anchor_right = 0.62
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(veil)

	_petals()

	var column := VBoxContainer.new()
	column.position = Vector2(96, 70)
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	column.add_child(head)
	var emblem := Control.new()
	emblem.custom_minimum_size = Vector2(150, 150)
	emblem.draw.connect(_draw_emblem.bind(emblem))
	_emblem = emblem
	head.add_child(emblem)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(titles)
	var title := _text("Lanternbound", title_font, 92, PALE)
	title.add_theme_color_override("font_shadow_color", Color(0.3, 0.4, 0.9, 0.6))
	title.add_theme_constant_override("shadow_outline_size", 14)
	titles.add_child(title)
	titles.add_child(_text("—  REALMS OF THE STARFALL  —", menu_font, 22, GOLD))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 70)
	column.add_child(spacer)

	var entries := [["Continue", _start], ["New Journey", _start], ["Settings", _open_settings], ["Credits", _credits], ["Quit", _quit]]
	for i in entries.size():
		var row := _row(entries[i][0], menu_font, entries[i][1], i)
		column.add_child(row)
		_rows.append(row)

	var tag := _text("A journey beyond the stars...", italic, 34, Color(0.9, 0.9, 1.0, 0.85))
	tag.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tag.position = Vector2(100, -110)
	add_child(tag)
	var version := _text("v0.3  ·  3D preview", menu_font, 16, Color(1, 1, 1, 0.45))
	version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(100, -54)
	add_child(version)
	_select(0)
	Sfx.play_music("title")


func _text(t: String, font: Font, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.15, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row(label: String, font: Font, action: Callable, index: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(520, 66)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var text := _text(label, font, 36, PALE)
	text.position = Vector2(84, 10)
	row.add_child(text)
	row.set_meta("text", text)
	row.draw.connect(_draw_row.bind(row))
	row.mouse_entered.connect(_select.bind(index))
	row.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			Sfx.play("click")
			action.call())
	row.set_meta("action", action)
	return row


func _select(index: int) -> void:
	_selected = index
	for i in _rows.size():
		var r: Control = _rows[i]
		(r.get_meta("text") as Label).add_theme_color_override("font_color", Color(0.15, 0.1, 0.05) if i == index else PALE)
		r.queue_redraw()


func _draw_row(row: Control) -> void:
	var i := _rows.find(row)
	var on := i == _selected
	var h := row.size.y
	var w := row.size.x
	if on:
		# A gold bar with pointed ends and a soft glow behind it.
		var pts := PackedVector2Array([Vector2(18, h * 0.5), Vector2(44, 4), Vector2(w - 40, 4), Vector2(w - 12, h * 0.5),
			Vector2(w - 40, h - 4), Vector2(44, h - 4)])
		for g in 3:
			var grow := 6.0 + g * 6.0
			var glow := PackedVector2Array()
			for p in pts:
				glow.append(p + (p - Vector2(w * 0.5, h * 0.5)).normalized() * grow)
			row.draw_colored_polygon(glow, Color(1.0, 0.85, 0.5, 0.08))
		row.draw_colored_polygon(pts, Color(0.97, 0.86, 0.6, 0.95))
		row.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.97, 0.85), 2.0, true)
	else:
		row.draw_line(Vector2(70, h - 2), Vector2(w - 60, h - 2), Color(1, 1, 1, 0.12), 1.0)
	# Diamond marker.
	var c := Vector2(52, h * 0.5)
	var r := 13.0
	var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	row.draw_colored_polygon(diamond, Color(0.3, 0.2, 0.08) if on else Color(0.85, 0.88, 1.0, 0.9))
	row.draw_circle(c, 4.0, Color(1.0, 0.95, 0.75) if on else Color(0.2, 0.3, 0.7))


func _draw_emblem(e: Control) -> void:
	var c := e.size * 0.5
	var t := _time
	# A four-pointed compass star with a tilted ring, gently turning light.
	e.draw_arc(c, 64, 0, TAU, 64, Color(1, 0.9, 0.65, 0.35), 2.0, true)
	for k in 4:
		var a := k * PI * 0.5 - PI * 0.5
		var tip := c + Vector2.from_angle(a) * (70 if k % 2 == 0 else 52)
		var l := c + Vector2.from_angle(a - 0.32) * 14
		var r := c + Vector2.from_angle(a + 0.32) * 14
		e.draw_colored_polygon(PackedVector2Array([c, l, tip]), Color(1.0, 0.92, 0.7))
		e.draw_colored_polygon(PackedVector2Array([c, tip, r]), Color(0.86, 0.68, 0.38))
	for k in 4:
		var a := k * PI * 0.5 - PI * 0.25
		e.draw_line(c, c + Vector2.from_angle(a) * 32, Color(1, 0.92, 0.7, 0.8), 2.0, true)
	e.draw_circle(c, 6 + sin(t * 2.0) * 1.5, Color(1, 1, 0.95))


func _petals() -> void:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1200, 10)
	p.position = Vector2(1100, -40)
	p.direction = Vector2(-0.6, 1)
	p.spread = 25
	p.gravity = Vector2(-6, 18)
	p.initial_velocity_min = 20
	p.initial_velocity_max = 60
	p.angular_velocity_min = -90
	p.angular_velocity_max = 90
	p.scale_amount_min = 3
	p.scale_amount_max = 6
	p.color = Color(1, 0.9, 0.97, 0.75)
	add_child(p)


var _frames := 0


func _process(delta: float) -> void:
	_time += delta
	_frames += 1
	# Capture harness: --shot=path saves the menu after 40 frames.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") and _frames == 40:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()
	# Slow drift, as if the camera breathes over the vista.
	var s := 1.04 + sin(_time * 0.12) * 0.02
	_art.scale = Vector2(s, s)
	_art.position = Vector2(sin(_time * 0.07) * 14.0, cos(_time * 0.05) * 8.0)
	_art.pivot_offset = size * 0.5
	if _emblem:
		_emblem.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _settings and _settings.visible:
		return
	if event.is_action_pressed("ui_down"):
		_select((_selected + 1) % _rows.size())
	elif event.is_action_pressed("ui_up"):
		_select((_selected + _rows.size() - 1) % _rows.size())
	elif event.is_action_pressed("ui_accept"):
		(_rows[_selected].get_meta("action") as Callable).call()


func _start() -> void:
	var fade := ColorRect.new()
	fade.color = Color(1, 1, 1, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.6)
	t.tween_callback(func(): get_tree().change_scene_to_file(GAME))


func _open_settings() -> void:
	if _settings == null:
		_settings = _panel("Settings", [
			["Graphics quality", ["Low", "Medium", "High"], 2],
			["Shadows", ["Off", "On"], 1 if Settings.shadows else 0],
			["Bloom", ["Off", "On"], 1 if Settings.bloom else 0],
		])
	_settings.visible = true


func _credits() -> void:
	var p := _panel("Credits", [])
	var l := Label.new()
	l.text = "Characters, weapons and scenery: free models from Sketchfab creators (CC BY)\nNature: Quaternius (CC0) · Terrain textures: ambientCG (CC0)\nKey art made with Higgsfield · Fonts: Cinzel, Cormorant (OFL)\nFull list in ASSET_CATALOG.md"
	l.add_theme_font_size_override("font_size", 24)
	p.get_child(0).get_child(0).add_child(l)


func _panel(title: String, options: Array) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.08, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.22, 0.92)
	style.border_color = Color(0.96, 0.84, 0.56, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 420)
	panel.position -= Vector2(450, 210)
	shade.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_text(title, load("res://assets/fonts/CinzelDecorative-Bold.ttf"), 48, GOLD))
	for o in options:
		var line := HBoxContainer.new()
		var name := Label.new()
		name.text = o[0]
		name.custom_minimum_size = Vector2(420, 0)
		name.add_theme_font_size_override("font_size", 28)
		line.add_child(name)
		var pick := OptionButton.new()
		for v in o[1]:
			pick.add_item(v)
		pick.select(o[2])
		pick.add_theme_font_size_override("font_size", 26)
		var key: String = o[0]
		pick.item_selected.connect(func(i):
			match key:
				"Shadows":
					Settings.shadows = i == 1
				"Bloom":
					Settings.bloom = i == 1
				"Graphics quality":
					Settings.quality = i
			if Settings.has_method("save_settings"):
				Settings.save_settings())
		line.add_child(pick)
		box.add_child(line)
	var close := Button.new()
	close.text = "Close"
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(func(): shade.visible = false)
	box.add_child(close)
	return shade


func _quit() -> void:
	get_tree().quit()
