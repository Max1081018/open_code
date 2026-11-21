extends Node3D
## The open-world game: sky and sun, the streamed world, water, the hero, the
## camera and the HUD. Also an automated capture harness: run the real game
## with a script of inputs and save screenshots, e.g.
##   godot --path . res://scenes/main3d.tscn -- --shot=out.png --frames=120 --action=run --at=40,-30
## --action: idle, walk, run, sprint, jump, dodge, swim, look, fp, attack, heavy, chop, mine, tour
## --at=x,z spawn point; --yaw / --pitch camera; --hold=item; --time=0..1 time of day.

var world: OpenWorld
var player: Player3D
var cam: CameraRig
var input: Input3D
var hud: Hud3D
var play: Play3D
var islands: SkyIslands
var features: WorldFeatures
var town: Town
var sun: DirectionalLight3D
var environment: Environment
var _sky_mat: ShaderMaterial
var water: MeshInstance3D
var time_of_day := 0.32     ## 0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset
var day_length := 900.0     ## seconds for a full day

var _args := {}
var _frames := 0
var _strip: Array[Image] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("time"):
		time_of_day = float(_args.time)
	# Crisp edges: MSAA on capable settings, FXAA otherwise; full resolution.
	var vp := get_viewport()
	vp.scaling_3d_scale = 1.0
	if Settings.quality >= 2:
		vp.msaa_3d = Viewport.MSAA_4X
	else:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_build_environment()
	world = OpenWorld.new()
	add_child(world)
	world.setup(int(_args.get("seed", "1337")))
	var spawn := Vector3(10, 0, 14)
	if _args.has("at"):
		var p: PackedStringArray = _args.at.split(",")
		spawn = Vector3(float(p[0]), 0, float(p[1]))
	spawn.y = world.height_at(spawn.x, spawn.z) + 0.2
	world.warm(spawn)
	islands = SkyIslands.new()
	add_child(islands)
	islands.build(world.gen)
	input = Input3D.new()
	add_child(input)
	cam = CameraRig.new()
	add_child(cam)
	player = Player3D.new()
	player.input = input
	player.cam = cam
	player.world = world
	add_child(player)
	player.global_position = spawn
	cam.target = player
	cam.head = player.head_anchor
	cam.global_position = spawn + Vector3(0, 2, 4)
	if _args.has("dist"):
		cam.distance = float(_args.dist)
	cam.set_view(float(_args.get("yaw", "0")), float(_args.get("pitch", "-0.16")))
	_build_water()
	play = Play3D.new()
	add_child(play)
	play.setup(self)
	if _args.has("hold"):
		play.inventory.slots[0] = {"id": _args.hold, "count": 1}
		play.select(0)
	features = WorldFeatures.new()
	add_child(features)
	features.build(self)
	hud = Hud3D.new()
	add_child(hud)
	hud.setup(self)
	town = Town.new()
	add_child(town)
	town.build(self)
	if _args.has("shot"):
		input.scripted = true
		Engine.max_fps = 0


func _build_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://scripts/shaders/anime_sky.gdshader")
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.ambient_light_sky_contribution = 0.85
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.9
	environment.tonemap_white = 6.0
	environment.glow_enabled = Settings.bloom
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.08
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.72, 0.82, 0.95)
	environment.fog_density = 0.0006
	environment.fog_aerial_perspective = 0.35
	environment.fog_sky_affect = 0.0
	environment.fog_height = 30.0
	environment.fog_height_density = 0.004
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.02
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Settings.shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.18
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# The final grade over the 3D frame (bloom, sharpen, split toning).
	var post_layer := CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://scripts/shaders/post3d.gdshader")
	pm.set_shader_parameter("bloom", 0.22 if Settings.bloom else 0.0)
	post.material = pm
	post_layer.add_child(post)
	_update_sun(0.0)


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/water3d.gdshader")
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_8:
			play.select(k - KEY_1)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			play.select((play.hotbar_index + 1) % Inventory.HOTBAR_SIZE)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			play.select((play.hotbar_index + Inventory.HOTBAR_SIZE - 1) % Inventory.HOTBAR_SIZE)


func _process(delta: float) -> void:
	_frames += 1
	if _args.has("shot"):
		_script_input()
		# --strip=N --every=K: N frames K apart ending at --frames, side by side.
		var last := int(_args.get("frames", "120"))
		var count := int(_args.get("strip", "1"))
		var every := int(_args.get("every", "10"))
		var first := last - (count - 1) * every
		if _frames >= first and (_frames - first) % every == 0 and _frames <= last:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if count > 1:
				img.resize(img.get_width() / 2, img.get_height() / 2)
			_strip.append(img)
			if _frames == last:
				var w := img.get_width()
				var out := Image.create(w * _strip.size(), img.get_height(), false, img.get_format())
				for i in _strip.size():
					out.blit_rect(_strip[i], Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * w, 0))
				out.save_png(_args.shot)
				get_tree().quit()
	time_of_day = fposmod(time_of_day + delta / day_length, 1.0)
	_update_sun(delta)
	world.focus = player.global_position
	water.global_position = Vector3(snappedf(player.global_position.x, 50.0), TerrainGen.WATER, snappedf(player.global_position.z, 50.0))


func _update_sun(_delta: float) -> void:
	# The sun arcs east to west; low and golden at dawn and dusk, the moon's
	# cool light at night.
	var angle := (time_of_day - 0.25) * TAU
	var elevation := sin(angle)
	var day := clampf(elevation * 3.0 + 0.2, 0.0, 1.0)
	var low := clampf(1.0 - absf(elevation) * 2.2, 0.0, 1.0) * day
	sun.rotation = Vector3(-maxf(absf(elevation), 0.12) * 1.25 - 0.1, deg_to_rad(-35.0) + cos(angle) * 0.9, 0)
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.34), low).lerp(Color(0.45, 0.55, 0.85), 1.0 - day)
	sun.light_energy = lerpf(0.18, 1.35, day)
	environment.ambient_light_energy = lerpf(0.2, 0.55, day)
	environment.fog_light_color = Color(0.7, 0.74, 0.78).lerp(Color(0.95, 0.66, 0.46), low).lerp(Color(0.08, 0.1, 0.18), 1.0 - day)
	var night := clampf(1.0 - day, 0.0, 1.0)
	_sky_mat.set_shader_parameter("night", night)
	_sky_mat.set_shader_parameter("dusk", low)
	_sky_mat.set_shader_parameter("top_color", Color(0.15, 0.36, 0.85).lerp(Color(0.35, 0.32, 0.6), low))
	_sky_mat.set_shader_parameter("horizon_color", Color(0.74, 0.86, 0.99).lerp(Color(1.0, 0.66, 0.45), low))
	_sky_mat.set_shader_parameter("cloud_shade", Color(0.7, 0.74, 0.92).lerp(Color(0.75, 0.55, 0.7), low))


## The capture harness's scripted inputs.
func _script_input() -> void:
	var f := _frames
	input.move = Vector2.ZERO
	input.look = Vector2.ZERO
	input.jump = false
	input.dodge = false
	input.attack = false
	input.heavy = false
	input.toggle_view = false
	input.sprint = false
	input.skill = false
	input.burst = false
	match _args.get("action", "idle"):
		"walk":
			input.move = Vector2(0, 0.45) if f > 20 else Vector2.ZERO
		"run":
			input.move = Vector2(0, 1) if f > 20 else Vector2.ZERO
		"sprint":
			input.move = Vector2(0, 1) if f > 20 else Vector2.ZERO
			input.sprint = true
		"jump":
			input.move = Vector2(0, 1) if f > 20 else Vector2.ZERO
			input.jump = f == 40
		"dodge":
			input.move = Vector2(0.6, 0.8) if f > 20 else Vector2.ZERO
			input.dodge = f == 40
		"look":
			input.look = Vector2(0.03, 0.0)
		"fp":
			input.toggle_view = f == 10
			input.look = Vector2(0.004, 0.0) if f > 20 else Vector2.ZERO
			input.attack = f == 40
		"attack":
			input.attack = f > 20 and f % 30 == 0
		"heavy":
			input.heavy = f == 30
		"chop", "mine":
			if f == 2:
				play.select(1 if _args.action == "chop" else 2)
			input.attack = f > 20 and f % 40 == 0
		"glide":
			# Jump off a slope, then spread the wings and fly forward.
			input.move = Vector2(0, 1) if f > 10 else Vector2.ZERO
			input.jump = f == 20 or f == 45
		"skills":
			if f == 2:
				for k in 3:
					play.spawn_enemy("zombie", player.global_position + Vector3(k * 1.5 - 1.5, 0, -3.5))
				play.energy = Play3D.BURST_COST
			input.skill = f == 30
			input.burst = f == 80
		"fight":
			if f == 2:
				play.spawn_enemy(_args.get("enemy", "zombie"), player.global_position + Vector3(0, 0, -5))
			input.attack = f > 30 and f % 36 == 0
		"tour":
			input.move = Vector2(0.15, 1)
			input.sprint = true
			input.look = Vector2(0.002, 0)
