extends Control
## The title screen. The painted vista of the Starfall (World Tree, dune sea,
## sky isles, crystal coast) drifts slowly under a violet veil, petals fall,
## the Lanternbound logo glows top-left. Signed out, the sign-in panel shows
## (LoginPanel); signed in, a column of gem-plate buttons:
##   Continue (if this account has a journey), New Journey (→ character →
##   starting island → loading → world), Settings, Credits, Sign Out, Quit.
## Capture harness: --shot=path [--frames=N] [--front=login|menu|character|island].

const GAME := "res://scenes/main3d.tscn"

var _stage: MenuStage
var _time := 0.0
var _menu: VBoxContainer
var _login: LoginPanel
var _overlay: Control
var _who: Label
var _chip: PanelContainer
var _frames := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The live world behind everything: Lyra on Skybound's rim at dusk.
	_stage = MenuStage.new()
	add_child(_stage)
	# A soft veil on the left for the menu column.
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = Shader.new()
	vm.shader.code = """shader_type canvas_item;
void fragment() { COLOR = vec4(0.01, 0.01, 0.03, (1.0 - smoothstep(0.0, 0.5, UV.x)) * 0.62 + (1.0 - smoothstep(0.75, 1.0, 1.0 - UV.y)) * 0.25); }"""
	veil.material = vm
	add_child(veil)
	var logo := UiKit.logo(620)
	logo.position = Vector2(90, 110)
	add_child(logo)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(110, 420)
	_menu.add_theme_constant_override("separation", 14)
	add_child(_menu)
	var tag := UiKit.label("A journey beyond the stars…", 30, Color(0.88, 0.86, 0.92, 0.8), "italic")
	tag.position = Vector2(110, 960)
	add_child(tag)
	var version := UiKit.label("v0.4  ·  development build", 18, Color(1, 1, 1, 0.45))
	version.position = Vector2(102, 1022)
	add_child(version)
	_chip = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.03, 0.035, 0.06, 0.6)
	cs.border_color = Color(1, 1, 1, 0.16)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 26
	cs.content_margin_right = 26
	cs.content_margin_top = 10
	cs.content_margin_bottom = 10
	_chip.add_theme_stylebox_override("panel", cs)
	_chip.position = Vector2(1400, 36)
	add_child(_chip)
	_who = UiKit.label("", 20, UiKit.PALE, "bold")
	_chip.add_child(_who)
	_build()
	Sfx.play_music("title")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--front="):
			var what := a.substr(8)
			if what == "login":
				Account.sign_out()
				_build()
			elif not Account.signed_in():
				Account.sign_in_guest()
				_build()
			if what == "character":
				_choose_character()
			elif what == "island":
				_choose_island()


## The buttons for the signed-in account, or the sign-in panel.
func _build() -> void:
	for c in _menu.get_children():
		c.queue_free()
	if not Account.signed_in():
		_chip.visible = false
		_menu.visible = false
		if _login == null:
			_login = LoginPanel.new()
			add_child(_login)
			_login.signed_in.connect(func():
				_login.queue_free()
				_login = null
				_build())
		return
	_menu.visible = true
	_chip.visible = true
	var p := Account.profile
	var kind: String = {"guest": "Guest", "email": "Email · dev", "google": "Google", "apple": "Apple"}.get(String(p.provider), "")
	_who.text = "✦  %s   ·   %s" % [String(p.display_name), kind]
	_chip.position.x = 1880 - _who.get_minimum_size().x - 52
	var entries := []
	if Save3D.exists():
		entries.append(["Continue", _continue, "primary"])
	entries.append_array([["New Journey", _new_journey, "normal" if Save3D.exists() else "primary"],
		["Settings", _open_settings, "normal"], ["Credits", _credits, "normal"],
		["Sign Out", _sign_out, "normal"], ["Quit", _quit, "normal"]])
	var i := 0
	for e in entries:
		var b := UiKit.button(e[0], e[1], e[2], 440, 66)
		_menu.add_child(b)
		UiKit.appear(b, 0.05 * i)
		i += 1
	(_menu.get_child(0) as Button).grab_focus.call_deferred()


func _sign_out() -> void:
	Account.sign_out()
	_build()


func _continue() -> void:
	Save3D.load_on_start = true
	Account.touch()
	_start()


## New Journey: (confirm replacing a journey) → character → island → world.
func _new_journey() -> void:
	if Save3D.exists():
		_confirm("Begin a new journey? Your current journey on this account will be replaced.", _choose_character)
		return
	_choose_character()


func _choose_character() -> void:
	_close_overlay()
	var cs := CharacterSelect.new()
	cs.stage = _stage
	_set_menu_visible(false)
	_overlay = cs
	add_child(cs)
	cs.back.connect(func():
		_close_overlay()
		_set_menu_visible(true))
	cs.chosen.connect(func(_id): _choose_island())


func _choose_island() -> void:
	_close_overlay()
	var isl := IslandSelect.new()
	_set_menu_visible(false)
	_overlay = isl
	add_child(isl)
	isl.back.connect(_choose_character)
	isl.chosen.connect(func(_id):
		Save3D.load_on_start = false
		if FileAccess.file_exists(Save3D.path()):
			DirAccess.remove_absolute(Save3D.path())
		Account.touch()
		_start())


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


## The logo, menu column and tagline hide while a full screen is open.
func _set_menu_visible(on: bool) -> void:
	for c in get_children():
		if c != _stage and c != _overlay and not (c is ColorRect) and c != _login:
			(c as CanvasItem).visible = on
	if on:
		_build()


func _shade() -> ColorRect:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	return shade


func _confirm(text: String, yes: Callable) -> void:
	_close_overlay()
	var shade := _shade()
	_overlay = shade
	var p := UiKit.panel(Vector2(900, 0))
	p.position = Vector2(510, 330)
	shade.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	p.add_child(box)
	var l := UiKit.label(text, 30, UiKit.PALE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(780, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.add_child(UiKit.divider(600))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(UiKit.button("Keep it", _close_overlay, "normal", 360, 80))
	row.add_child(UiKit.button("Begin anew", yes, "primary", 380, 80))
	box.add_child(row)
	UiKit.appear(p)


func _start() -> void:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fade)
	var t := create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.5)
	t.tween_callback(func(): LoadingScreen.go(get_tree(), GAME, ["res://assets/models/heroes/"]))


# ---------------------------------------------------------- settings ---

func _open_settings() -> void:
	_close_overlay()
	var shade := _shade()
	_overlay = shade
	var p := UiKit.panel(Vector2(980, 0))
	p.position = Vector2(470, 120)
	shade.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	p.add_child(box)
	var t := UiKit.label("Settings", 52, UiKit.GOLD, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(UiKit.divider(700))
	_choice(box, "Graphics", ["Low", "Medium", "High", "Ultra"], Settings.quality, func(i):
		Settings.apply_preset(i))
	_choice(box, "Shadows", ["Off", "On"], 1 if Settings.shadows else 0, func(i): Settings.shadows = i == 1)
	_choice(box, "Bloom", ["Off", "On"], 1 if Settings.bloom else 0, func(i): Settings.bloom = i == 1)
	_slider(box, "Music", Settings.music_volume, func(v): Settings.music_volume = v)
	_slider(box, "Effects", Settings.sfx_volume, func(v): Settings.sfx_volume = v)
	_slider(box, "Voices", Settings.voice_volume, func(v): Settings.voice_volume = v)
	var close := UiKit.button("Done", func():
		Settings.save_settings()
		_close_overlay(), "primary", 420, 80)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(close)
	box.add_child(row)
	UiKit.appear(p)


func _choice(box: VBoxContainer, name: String, options: Array, current: int, on_pick: Callable) -> void:
	var line := HBoxContainer.new()
	var l := UiKit.label(name, 30, UiKit.PALE, "bold")
	l.custom_minimum_size = Vector2(300, 0)
	line.add_child(l)
	var group := []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(130, 56)
		b.add_theme_font_override("font", UiKit.font("bold"))
		b.add_theme_font_size_override("font_size", 22)
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			s.set_corner_radius_all(28)
			s.set_border_width_all(2)
			var on: bool = state in ["pressed", "hover_pressed"]
			s.bg_color = Color(0.42, 0.26, 0.72, 0.9) if on else Color(0.08, 0.06, 0.18, 0.8)
			s.border_color = Color(UiKit.GOLD, 0.9 if on or state in ["hover", "focus"] else 0.35)
			b.add_theme_stylebox_override(state, s)
		b.add_theme_color_override("font_pressed_color", Color(1, 0.95, 0.8))
		group.append(b)
		b.pressed.connect(func():
			for o in group:
				(o as Button).button_pressed = o == b
			Sfx.play("click", -8.0)
			on_pick.call(i))
		line.add_child(b)
	box.add_child(line)


func _slider(box: VBoxContainer, name: String, value: float, on_change: Callable) -> void:
	var line := HBoxContainer.new()
	var l := UiKit.label(name, 30, UiKit.PALE, "bold")
	l.custom_minimum_size = Vector2(300, 0)
	line.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(540, 56)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.VIOLET
	fill.set_corner_radius_all(4)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(func(v):
		on_change.call(v)
		Settings._apply_audio())
	line.add_child(s)
	box.add_child(line)


func _credits() -> void:
	_close_overlay()
	var shade := _shade()
	_overlay = shade
	var p := UiKit.panel(Vector2(980, 0))
	p.position = Vector2(470, 200)
	shade.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	p.add_child(box)
	var t := UiKit.label("Credits", 52, UiKit.GOLD, "title")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(UiKit.divider(700))
	var l := UiKit.label("Characters, weapons and scenery: free models from Sketchfab creators (CC BY)\nNature: Quaternius (CC0) · Terrain textures: ambientCG (CC0)\nTitle art, logo and UI frames made with Higgsfield\nSounds: Soundza · Fonts: Cinzel, Cormorant (OFL)\nEngine: Godot 4 with Jolt Physics and Recast navigation\nThe full list is in ASSET_CATALOG.md", 26, UiKit.PALE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(860, 0)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.button("Close", _close_overlay, "normal", 360, 80))
	box.add_child(row)
	UiKit.appear(p)


func _quit() -> void:
	get_tree().quit()


# ------------------------------------------------------------ motion ---

func _petals() -> void:
	var p := CPUParticles2D.new()
	p.amount = 46
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
	p.color = Color(1, 0.88, 0.98, 0.75)
	add_child(p)


func _shot_frame() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			return int(a.substr(9))
	return 40


func _process(delta: float) -> void:
	_time += delta
	_frames += 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") and _frames == _shot_frame():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _overlay:
		_close_overlay()
