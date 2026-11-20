extends Control
## Title screen: the forest at dusk behind the title, a lantern swaying in
## the foreground, and the buttons.

var main: Node

var _lantern: Sprite2D
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	Sfx.play_music("title")
	_build_scene()
	_build_buttons()


func _build_scene() -> void:
	var sky := ColorRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/sky.gdshader")
	material.set_shader_parameter("top", Color(0.10, 0.12, 0.30))
	material.set_shader_parameter("bottom", Color(0.98, 0.58, 0.42))
	material.set_shader_parameter("horizon", 0.72)
	sky.material = material
	add_child(sky)

	var fog_shader: Shader = load("res://scripts/shaders/fog_layer.gdshader")
	var screen := get_viewport_rect().size
	var layers := [["fade_trees", 0.70, 1.9, 0.70], ["color_trees", 0.42, 2.4, 0.80],
		["color_hills", 0.12, 3.0, 0.90]]
	for spec in layers:
		var tex: Texture2D = load("res://assets/scenery/parallax/%s.png" % spec[0])
		var fog := ShaderMaterial.new()
		fog.shader = fog_shader
		fog.set_shader_parameter("fog", Color(0.62, 0.38, 0.46))
		fog.set_shader_parameter("amount", spec[1])
		fog.set_shader_parameter("light", 0.75)
		var w: float = tex.get_width() * spec[2]
		for n in int(ceil(screen.x / w)) + 2:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.centered = false
			sprite.scale = Vector2(spec[2], spec[2])
			sprite.material = fog
			sprite.position = Vector2(n * w - 100, screen.y * spec[3] - tex.get_height() * spec[2] * 0.56)
			sprite.set_meta("drift", 6.0 + spec[1] * -6.0 + 8.0)
			add_child(sprite)

	var motes := CPUParticles2D.new()
	motes.texture = load("res://assets/fx/circle_05.png")
	motes.material = Effects.additive()
	motes.amount = 30
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = screen * 0.5
	motes.position = screen * 0.5
	motes.gravity = Vector2(4, -10)
	motes.scale_amount_min = 0.012
	motes.scale_amount_max = 0.03
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(1, 0.8, 0.5, 0), Color(1, 0.85, 0.5, 0.9),
		Color(1, 0.7, 0.4, 0.5), Color(1, 0.7, 0.4, 0)])
	motes.color_ramp = gradient
	add_child(motes)

	_lantern = Sprite2D.new()
	_lantern.texture = load("res://assets/rendered/lantern-glass.png")
	_lantern.scale = Vector2(1.6, 1.6)
	_lantern.offset = Vector2(0, 90)
	_lantern.position = Vector2(screen.x * 0.80, -20)
	add_child(_lantern)
	_lantern.add_child(Glow.make(Color(1.0, 0.8, 0.45), 4.0))
	_lantern.get_child(0).position = Vector2(0, 130)

	var hero := AnimatedSprite2D.new()
	hero.sprite_frames = CharacterFrames.build("player")
	hero.play("idle")
	hero.scale = Vector2(1.5, 1.5)
	hero.position = Vector2(screen.x * 0.80, screen.y * 0.86 - 190)
	add_child(hero)


func _build_buttons() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.position = Vector2(150, 140)
	add_child(column)

	var title := UITheme.title("Lanternbound", 150, UITheme.PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)
	var subtitle := UITheme.text("Carry the only light there is.", 40, Color(1.0, 0.86, 0.66))
	subtitle.add_theme_color_override("font_outline_color", Color(0.15, 0.06, 0.08))
	subtitle.add_theme_constant_override("outline_size", 10)
	column.add_child(subtitle)
	column.add_child(Control.new())

	if Game.has_save():
		_button(column, "Continue", func():
			var saved := Game.load_game()
			if saved.is_empty():
				Game.toast("That save could not be read")
				return
			main.start_game(0, saved))
	_button(column, "New World", func():
		if Game.has_save():
			Game.delete_save()
		Game.playtime = 0.0
		main.start_game(randi()))
	_button(column, "Settings", _open_settings)
	if not OS.has_feature("web"):
		_button(column, "Quit", func(): get_tree().quit())


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(520, 110)
	button.add_theme_font_size_override("font_size", 48)
	button.pressed.connect(func():
		Sfx.play("click")
		action.call())
	parent.add_child(button)


func _open_settings() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.06, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	panel.add_child(column)
	column.add_child(UITheme.title("Settings", 60, UITheme.PAPER))
	column.add_child(PauseMenu.scrolling(PauseMenu.settings_grid(), 600))
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(300, 96)
	done.pressed.connect(func():
		Settings.save_settings()
		shade.queue_free())
	column.add_child(done)


func _process(delta: float) -> void:
	_t += delta
	if _lantern:
		_lantern.rotation = sin(_t * 1.1) * 0.06
	for child in get_children():
		if child is Sprite2D and child.has_meta("drift"):
			child.position.x -= child.get_meta("drift") * delta
