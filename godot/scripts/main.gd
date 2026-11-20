extends Node
## Entry point. Shows the menu, or — with capture arguments — runs a
## scripted scenario and saves a screenshot, so every screen can be
## inspected without a person at the controls:
##
##   godot --path godot -- --shot=out.png --scenario=surface --frames=90 --time=0.35

var level: Level
var _args := {}
var _frames := 0
var _scenario_step := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "true"

	if _args.has("shot"):
		# The capture driver must keep counting through a paused game.
		process_mode = Node.PROCESS_MODE_ALWAYS
	if _args.has("menu"):
		var menu: Control = load("res://scripts/ui/main_menu.gd").new()
		menu.main = self
		add_child(menu)
		if _args.has("shot"):
			for i in int(_args.get("frames", "40")):
				await get_tree().process_frame
			_capture(_args.shot)
		return
	if _args.has("shot") or _args.has("play"):
		start_game(int(_args.get("seed", "20261120")))
		if _args.has("time"):
			level.world.time_of_day = float(_args.time)
		_apply_scenario()
	else:
		var menu_script := load("res://scripts/ui/main_menu.gd")
		if menu_script:
			var menu: Control = menu_script.new()
			menu.main = self
			add_child(menu)
		else:
			start_game(randi())


func start_game(seed_value: int, saved := {}) -> void:
	for child in get_children():
		child.queue_free()
	level = Level.new()
	add_child(level)
	level.start(seed_value, saved)
	var hud_script := load("res://scripts/ui/hud.gd")
	if hud_script:
		var hud: Node = hud_script.new()
		hud.level = level
		level.hud = hud
		add_child(hud)


func _process(_delta: float) -> void:
	if level == null or level.player == null:
		return
	_desktop_input()
	if _args.has("shot"):
		_frames += 1
		_run_scenario()
		if _args.has("panel") and _frames == int(_args.get("frames", "90")) - 20:
			match _args.panel:
				"inventory":
					level.hud.toggle_inventory()
				"craft":
					level.hud.open_crafting()
				"pause":
					level.hud.open_pause()
				"chest":
					level.hud.open_chest(Vector2i.ZERO, {"type": "chest", "loot": [
						{"id": "glowshard", "count": 6}, {"id": "heart_crystal", "count": 1},
						{"id": "iron_ore", "count": 9}, {"id": "vault_key", "count": 1}]})
		var last := int(_args.get("frames", "90"))
		if _args.has("strip"):
			# A filmstrip: crops around the player every third frame up to
			# the last, to check an animation rather than a single pose.
			var count := int(_args.strip)
			var first := last - (count - 1) * 3
			if _frames >= first and (_frames - first) % 3 == 0 and _frames <= last:
				_grab_strip_frame(_frames == last)
		elif _frames == last:
			_capture(_args.shot)


func _desktop_input() -> void:
	# Once a real touch has been seen this is a phone: the touch controls
	# own the player's input, and mouse events (which Godot emulates from
	# touches for the GUI's sake) must not double it.
	if level.hud and level.hud.get("touch_active"):
		return
	var input := level.player.input
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0
	if not _args.has("shot"):
		input.move = axis

	var jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W)
	if jump and not input.jump_held:
		input.jump_pressed = true
	if not _args.has("shot"):
		input.jump_held = jump

	if not _args.has("shot"):
		input.block_held = Input.is_key_pressed(KEY_K) or Input.is_key_pressed(KEY_SHIFT) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	var over_ui: bool = level.hud != null and level.hud.get("pointer_over_ui") == true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not over_ui:
		input.use_held = true
		input.aim = level.get_global_mouse_position()
	elif not _args.has("shot"):
		input.use_held = false

	for i in 8:
		if Input.is_key_pressed(KEY_1 + i):
			input.hotbar_select = i


func _unhandled_input(event: InputEvent) -> void:
	if level == null or level.player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F, KEY_J:
				level.player.input.attack_pressed = true
			KEY_E:
				level.player.input.interact_pressed = true


# =============================================================================
# Capture scenarios
# =============================================================================

func _apply_scenario() -> void:
	var player := level.player
	var data := level.data
	match _args.get("scenario", "surface"):
		"cave", "crystal", "deep", "ruin", "mushroom":
			var target := _find_scenario_cell(_args.scenario)
			player.global_position = World.foot_of(target)
			player.glow = player.max_glow()
			level.camera.global_position = player.global_position
			level.camera.reset_smoothing()
			level.world.load_area(target, 2)
		"cabin":
			player.global_position = World.foot_of(data.spawn) + Vector2(-13 * 128, 0)
			level.world.load_area(World.cell_of(player.global_position), 2)
	if _args.has("weather"):
		level.life.set_weather(WorldLife.Weather.RAIN if _args.weather == "rain" else WorldLife.Weather.SNOW, 1.0)
	if _args.has("x"):
		var target := Vector2i(int(_args.x), 0)
		target.y = level.data.surface[target.x] - 1
		player.global_position = World.foot_of(target)
		level.world.load_area(target, 2)
	if _args.has("spawn"):
		var offset := 360.0
		for kind in _args.spawn.split(","):
			level.spawn_enemy(kind, player.global_position + Vector2(offset, -40))
			offset += 260.0
	if _args.has("boss"):
		level.boss = level.spawn_enemy(_args.boss, player.global_position + Vector2(700, -80))
	if _args.has("give"):
		for id in _args.give.split(","):
			player.inventory.add(id, 20)
	if _args.get("action", "") == "chop":
		# Stand beside the nearest tree, facing it.
		var tree := World.cell_of(_nearest_tree())
		var stand := Vector2i(tree.x - 2, tree.y)
		player.global_position = World.foot_of(stand)
		level.camera.global_position = player.global_position
		level.camera.reset_smoothing()
	if _args.has("hold"):
		# Put this item in the last hotbar slot and select it.
		player.inventory.slots[Inventory.HOTBAR_SIZE - 1] = {"id": _args.hold, "count": 1}
		player.inventory.changed.emit()
		player.select_hotbar(Inventory.HOTBAR_SIZE - 1)


func _find_scenario_cell(kind: String) -> Vector2i:
	var data := level.data
	if kind == "mushroom":
		# Beside the first cave mushroom that glows, two cells to its left.
		for key in data.objects:
			var cell := Vector2i(key % data.width, key / data.width)
			if ObjectArt.glows(data.objects[key], cell) and not data.is_solid(cell.x - 2, cell.y) \
					and data.is_solid(cell.x - 2, cell.y + 1):
				return cell - Vector2i(2, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for attempt in 40000:
		var x := rng.randi_range(40, data.width - 40)
		var y := rng.randi_range(WorldData.SURFACE_Y + 25, data.height - 6)
		if kind == "deep" and y < WorldData.DEEP_Y + 8:
			continue
		if kind == "crystal" and data.biome_at(x, y) != WorldData.Biome.CRYSTAL:
			continue
		if kind == "cave" and (y > WorldData.DEEP_Y or data.biome_at(x, y) == WorldData.Biome.CRYSTAL):
			continue
		if kind == "ruin" and data.get_wall(x, y) != WorldData.BRICK:
			continue
		# Standing room: two open cells over solid ground.
		if data.is_solid(x, y) or data.is_solid(x, y - 1) or not data.is_solid(x, y + 1):
			continue
		if data.get_liquid(x, y) != WorldData.DRY:
			continue
		var open := 0
		for dx in range(-4, 5):
			for dy in range(-3, 1):
				if not data.is_solid(x + dx, y + dy):
					open += 1
		if open > 28:
			return Vector2i(x, y)
	return data.spawn


func _run_scenario() -> void:
	var input := level.player.input
	match _args.get("action", ""):
		"walk":
			input.move = 1.0 if _frames > 20 else 0.0
		"dig":
			if _frames > 20:
				input.use_held = true
				input.aim = level.player.global_position + Vector2(170, 40)
		"attack":
			if _frames % 25 == 0:
				input.attack_pressed = true
		"block":
			input.block_held = _frames > 10
		"chop":
			if _frames > 20:
				input.use_held = true
				input.aim = _nearest_tree()
		"turn":
			input.move = -0.3 if _frames > 20 else 0.0
		"jump":
			input.move = 1.0
			if _frames % 40 == 5:
				input.jump_pressed = true
			input.jump_held = _frames % 40 < 25


func _nearest_tree() -> Vector2:
	var player := level.player
	var best := player.global_position + Vector2(170, -60)
	var best_d := 1e9
	for key in level.data.objects:
		if level.data.objects[key].get("type", "") != "tree":
			continue
		var cell := Vector2i(key % level.data.width, key / level.data.width)
		var d := World.centre_of(cell).distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = World.centre_of(cell)
	return best


var _strip: Array[Image] = []


func _grab_strip_frame(final: bool) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var at := level.get_viewport().get_canvas_transform() * (level.player.global_position + Vector2(0, -130))
	var box := Rect2i(Vector2i(at) - Vector2i(260, 260), Vector2i(520, 400))
	box = box.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	_strip.append(image.get_region(box))
	if not final:
		return
	var w := _strip[0].get_width()
	var strip := Image.create(w * _strip.size(), _strip[0].get_height(), false, _strip[0].get_format())
	for i in _strip.size():
		strip.blit_rect(_strip[i], Rect2i(Vector2i.ZERO, _strip[i].get_size()), Vector2i(i * w, 0))
	strip.save_png(_args.shot)
	print("captured ", _args.shot, " strip of ", _strip.size())
	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("captured ", path, " ", image.get_size())
	get_tree().quit()
