class_name PauseMenu
extends RefCounted
## Pause and settings.


static func build(hud: Node) -> Control:
	var panel: Control = hud.make_panel(Vector2(1100, 0), "Paused")
	var content: VBoxContainer = panel.get_meta("content")

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(buttons)
	for spec in [["Resume", func(): hud.close_panel()],
			["Save", func():
				if hud.level.save():
					Game.toast("Saved")],
			["Save & Quit", func():
				hud.level.save()
				hud.get_tree().paused = false
				hud.get_tree().reload_current_scene()]]:
		var button := Button.new()
		button.text = spec[0]
		button.custom_minimum_size = Vector2(300, 96)
		button.pressed.connect(spec[1])
		buttons.add_child(button)

	content.add_child(scrolling(settings_grid(), 560))
	panel.set_meta("on_close_callable", func(): Settings.save_settings())
	return panel


## Wrap tall content so a panel never runs off a short screen.
static func scrolling(inner: Control, height: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(inner)
	return scroll


## The settings controls, shared by the pause menu and the main menu.
static func settings_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 14)

	_graphics(grid)
	_slider(grid, "Music", Settings.music_volume, 0.0, 1.0, func(v):
		Settings.music_volume = v
		Settings.save_settings())
	_slider(grid, "Effects", Settings.sfx_volume, 0.0, 1.0, func(v):
		Settings.sfx_volume = v
		Settings.save_settings())
	_slider(grid, "Control size", Settings.control_scale, 0.7, 1.4, func(v):
		Settings.control_scale = v
		Settings.save_settings())
	_slider(grid, "Control opacity", Settings.control_opacity, 0.3, 1.0, func(v):
		Settings.control_opacity = v
		Settings.save_settings())
	_slider(grid, "Camera zoom", Settings.camera_zoom, 0.8, 1.25, func(v):
		Settings.camera_zoom = v
		Settings.save_settings())
	_toggle(grid, "Left-handed controls", Settings.left_handed, func(on):
		Settings.left_handed = on
		Settings.save_settings())
	_toggle(grid, "Screen shake", Settings.screen_shake, func(on):
		Settings.screen_shake = on
		Settings.save_settings())
	_toggle(grid, "Show FPS", Settings.show_fps, func(on):
		Settings.show_fps = on
		Settings.save_settings())
	_toggle(grid, "Debug: collision shapes", Settings.debug_collision, func(on):
		Settings.debug_collision = on
		Settings.save_settings())
	return grid


## The preset row, and the separate controls it sets. Choosing a preset
## rebuilds the controls beneath it so they show what it chose.
static func _graphics(grid: GridContainer) -> void:
	var levels := ["Low", "Med", "High", "Ultra"]
	var rows := []
	var rebuild := func(): pass
	_option(grid, "Graphics preset", Settings.PRESET_NAMES, Settings.quality, func(i):
		Settings.apply_preset(i)
		Settings.save_settings()
		for row in rows:
			row.queue_free()
		rows.clear()
		rebuild.call())
	rebuild = func():
		var start := grid.get_child_count()
		_option(grid, "  Lighting", levels, Settings.lighting, func(i):
			Settings.lighting = i
			Settings.save_settings())
		_option(grid, "  Particles", levels, Settings.particles, func(i):
			Settings.particles = i
			Settings.save_settings())
		_option(grid, "  Shader effects", levels, Settings.shader_fx, func(i):
			Settings.shader_fx = i
			Settings.save_settings())
		_option(grid, "  Background", levels, Settings.background, func(i):
			Settings.background = i
			Settings.save_settings())
		_toggle(grid, "  Soft shadows", Settings.shadows, func(on):
			Settings.shadows = on
			Settings.save_settings())
		_toggle(grid, "  Bloom", Settings.bloom, func(on):
			Settings.bloom = on
			Settings.save_settings())
		_toggle(grid, "  Weather", Settings.weather, func(on):
			Settings.weather = on
			Settings.save_settings())
		# Keep the rebuilt rows directly under the preset row.
		var added := []
		for i in range(start, grid.get_child_count()):
			added.append(grid.get_child(i))
		for n in added.size():
			grid.move_child(added[n], 2 + n)
		rows.append_array(added)
	rebuild.call()


static func _label(grid: GridContainer, text: String) -> void:
	var label := UITheme.text(text, 34, UITheme.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2(380, 0)
	grid.add_child(label)


static func _slider(grid: GridContainer, text: String, value: float, low: float, high: float,
		on_change: Callable) -> void:
	_label(grid, text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(520, 64)
	slider.value_changed.connect(on_change)
	grid.add_child(slider)


static func _option(grid: GridContainer, text: String, choices: Array, selected: int,
		on_change: Callable) -> void:
	_label(grid, text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	grid.add_child(row)
	var buttons := []
	for i in choices.size():
		var button := Button.new()
		button.text = choices[i]
		button.toggle_mode = true
		button.button_pressed = i == selected
		button.custom_minimum_size = Vector2(130 if choices.size() > 3 else 166, 70)
		button.add_theme_font_size_override("font_size", 30)
		buttons.append(button)
		row.add_child(button)
	for i in buttons.size():
		buttons[i].pressed.connect(func():
			for j in buttons.size():
				buttons[j].set_pressed_no_signal(j == i)
			on_change.call(i))


static func _toggle(grid: GridContainer, text: String, on: bool, on_change: Callable) -> void:
	_label(grid, text)
	var button := CheckButton.new()
	button.button_pressed = on
	button.custom_minimum_size = Vector2(120, 64)
	button.toggled.connect(on_change)
	grid.add_child(button)
