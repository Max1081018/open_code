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
var quests: Quests3D
var grass: GrassField
var fill: DirectionalLight3D
var starstones: Starstones
var nav: NavField
var weather: Weather3D
var realms: RealmFeatures
var footprints: Footprints
var adventure: Adventure
var secrets: Secrets
var bosses: IslandBosses
var _post: ShaderMaterial
var _heat := 0.0
## The chosen hero and starting land (from the profile, or --start= in captures).
var character_id := "heroine"
var start_island := ""
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
	# Crisp edges and resolution as the player set them (Settings).
	Settings.apply_display(vp)
	_build_environment()
	world = OpenWorld.new()
	add_child(world)
	world.setup(int(_args.get("seed", "1337")))
	var dense_grass: bool = Settings.quality >= 1 and _args.get("grass", "dense") != "clumps"
	world.clump_grass = not dense_grass
	var spawn := Vector3(10, 0, 14)
	var saved := Save3D.read() if Save3D.load_on_start and not _args.has("shot") else {}
	if saved.has("pos"):
		var sp: Vector3 = saved.pos
		spawn = Vector3(sp.x, 0, sp.z)
	character_id = String(Account.profile.get("selected_character", "heroine"))
	start_island = String(_args.get("start", Account.profile.get("start_island", "")))
	if saved.has("start_island") and String(saved.start_island) != "":
		start_island = String(saved.start_island)
	var start_spot := Vector3.INF
	if not saved.has("pos") and Realms.STARTS.has(start_island) and not _args.has("at"):
		start_spot = Realms.spawn_point(world.gen, start_island)
		spawn = start_spot
	if _args.has("at"):
		var p: PackedStringArray = _args.at.split(",")
		spawn = Vector3(float(p[0]), 0, float(p[1]))
	spawn.y = world.height_at(spawn.x, spawn.z) + 0.2
	if start_spot != Vector3.INF:
		spawn.y = start_spot.y + 0.3  # Skybound starts on a floating isle
	if saved.has("pos"):
		spawn.y = maxf(spawn.y, (saved.pos as Vector3).y + 0.2)  # saved on an isle
	world.warm(spawn)
	nav = NavField.new()
	add_child(nav)
	nav.setup(world)
	if dense_grass:
		grass = GrassField.new()
		add_child(grass)
		grass.setup(world.gen, Settings.quality)
		grass.warm(spawn)
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
	_build_depth_fx()
	_build_water()
	play = Play3D.new()
	add_child(play)
	play.setup(self)
	if _args.has("level"):
		play.prog.level = clampi(int(_args.level), 1, Progression.MAX_LEVEL)
		player.max_health = Progression.max_health_at(play.prog.level)
		player.health = player.max_health
	if _args.has("give"):
		for pair in String(_args.give).split(","):
			var kv := pair.split(":")
			play.inventory.add(kv[0], int(kv[1]) if kv.size() > 1 else 1)
	if _args.has("hold"):
		play.inventory.slots[0] = {"id": _args.hold, "count": 1}
		play.select(0)
	quests = Quests3D.new()
	add_child(quests)
	quests.setup(self)
	var ash := Ashlands.new()
	add_child(ash)
	ash.build(self)
	features = WorldFeatures.new()
	add_child(features)
	features.build(self)
	realms = RealmFeatures.new()
	add_child(realms)
	realms.build(self)
	footprints = Footprints.new()
	add_child(footprints)
	hud = Hud3D.new()
	add_child(hud)
	hud.setup(self)
	town = Town.new()
	add_child(town)
	town.build(self)
	_place_townsfolk()
	starstones = Starstones.new()
	add_child(starstones)
	starstones.build(self)
	var life := AmbientLife.new()
	add_child(life)
	life.setup(self)
	weather = Weather3D.new()
	add_child(weather)
	weather.setup(self)
	if _args.has("weather"):
		weather.force(Weather3D.NAMES.map(func(n: String) -> String: return n.to_lower().replace(" ", "")).find(String(_args.weather).to_lower()))
	# What the world hides (discoveries, chests, rune shrines, veins, the
	# night colossus) and the islands' guardians.
	if realms and realms.get("landmarks") != null:
		secrets = Secrets.new()
		add_child(secrets)
		secrets.build(self)
		bosses = IslandBosses.new()
		add_child(bosses)
		bosses.build(self)
	# The first adventure on the chosen starting island.
	if Realms.STARTS.has(start_island):
		adventure = Adventure.new()
		add_child(adventure)
		var fresh := saved.is_empty() and (not _args.has("shot") or _args.has("arrival"))
		adventure.setup(self, start_island, fresh)
	if not saved.is_empty():
		Save3D.restore(self, saved)
		play.toast.emit("Welcome back to the Starfall")
	if _args.has("cam"):
		# A free camera for inspecting scenery: --cam=x,y,z --look=x,y,z
		var c: PackedStringArray = _args.cam.split(",")
		var l: PackedStringArray = _args.get("look", "0,0,0").split(",")
		var free := Camera3D.new()
		free.far = 4000.0
		free.fov = 60.0
		add_child(free)
		free.look_at_from_position(Vector3(float(c[0]), float(c[1]), float(c[2])), Vector3(float(l[0]), float(l[1]), float(l[2])))
		free.make_current()
		world.focus = free.global_position
	if _args.has("float"):
		player.force_float = true  # she settles into the floating repose at once
	if _args.has("shot"):
		input.scripted = true
		Engine.max_fps = 0
		process_mode = Node.PROCESS_MODE_ALWAYS  # keep capturing while a menu pauses


## Wren by the fountain, Mira at her herb corner by the wall fountain, Tobin
## at the east stall, Sir Aldous on guard by the statue below the tower.
func _place_townsfolk() -> void:
	var folk := [
		["wren", Vector2(3.6, 7.0), 0.4, [["Idle", 6.0], ["Idle_Talking", 4.0], ["Yes", 2.0]],
			[Vector2(3.65, 6.32), Vector2(-5.16, 5.16), Vector2(-5.98, -4.19), Vector2(2.5, -6.86)]],
		["mira", Vector2(-12.6, -1.8), 1.4, [["Idle", 5.0], ["Interact", 3.0], ["PickUp_Table", 3.5]]],
		["tobin", Vector2(6.4, -8.6), 0.0, [["Fixing_Kneeling", 7.0], ["Idle_FoldArms", 5.0]]],
		["aldous", Vector2(6.0, -39.0), -0.5, [["Sword_Idle", 8.0], ["Idle", 4.0]],
			[Vector2(6.0, -39.0), Vector2(6.0, -24.0)]],
	]
	for f in folk:
		var at := Vector3(f[1].x, world.height_at(f[1].x, f[1].y), f[1].y)
		var npc := Npc3D.new()
		add_child(npc)
		npc.setup(self, f[0], at, f[2], f[3])
		quests.npcs[f[0]] = npc
		if f.size() > 4:
			npc.route = f[4]


var _autosave_timer := 45.0


## Save the journey (not while the capture harness runs).
func autosave() -> void:
	if _args.has("shot") or player == null or OS.get_cmdline_args().has("res://tests/run_tests.gd"):
		return
	Save3D.write(Save3D.capture(self))


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		autosave()


func _exit_tree() -> void:
	autosave()


func _build_environment() -> void:
	environment = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://scripts/shaders/anime_sky.gdshader")
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Ambient from a colour driven by the current sky each frame (zenith,
	# horizon and light bounced off the ground): the sky's radiance map comes
	# through far too weakly in the Compatibility renderer, leaving shade black.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 2.1
	# Sky light plus light bounced off the sunlit ground: shade stays green
	# and warm instead of sinking into blue-black.
	environment.ambient_light_color = Color(0.48, 0.6, 0.78)
	# ACES: a filmic contrast curve with saturated mid-tones (AgX looked
	# flat and milky); a strong sun against cooler, deeper shade.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.glow_enabled = Settings.bloom
	environment.glow_intensity = 0.35
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.6, 0.72, 0.9)
	environment.fog_density = BASE_FOG
	# Distant land takes the sky's colour (aerial perspective), not a milky veil.
	environment.fog_aerial_perspective = 0.55
	environment.fog_sky_affect = 0.0
	# Low mist pooling in valleys and over water, not over the whole world.
	environment.fog_height = 6.0
	environment.fog_height_density = 0.0012
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.0
	environment.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = Settings.shadows and _args.get("shadows", "1") != "0"
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_split_1 = 0.18
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	# A soft cool fill from the open sky opposite the sun: shade stays
	# luminous (anime lighting), never a dead grey. No shadows.
	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_specular = 0.0
	add_child(fill)
	# The final grade over the 3D frame (bloom, sharpen, split toning).
	var post_layer := CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://scripts/shaders/post3d.gdshader")
	pm.set_shader_parameter("bloom", 0.14 if Settings.bloom else 0.0)
	post.material = pm
	_post = pm
	post_layer.add_child(post)
	post.visible = _args.get("post", "1") != "0"   # capture harness: compare without the grade
	_update_sun(0.0)


## Depth-buffer effects drawn as full-screen quads after the scene:
## ambient occlusion (multiplied in; High and Ultra) and sun shafts (added;
## Medium and up). They blend over the frame instead of replacing it, so
## water and particles drawn before them are kept.
var _ao_mat: ShaderMaterial
var _shaft_mat: ShaderMaterial
var _depth_quads: Array[MeshInstance3D] = []


## Rebuild the depth effects after the player changes them.
func refresh_depth_fx() -> void:
	_build_depth_fx()


func _build_depth_fx() -> void:
	for q in _depth_quads:
		q.queue_free()
	_depth_quads.clear()
	_ao_mat = null
	_shaft_mat = null
	if _args.get("depthfx", "1") == "0":
		return
	if Settings.ao:
		_ao_mat = ShaderMaterial.new()
		_ao_mat.shader = load("res://scripts/shaders/depth_ao.gdshader")
		_ao_mat.render_priority = 120
		_ao_mat.set_shader_parameter("strength", 1.0 if Settings.quality >= 3 else 0.85)
		cam.camera.add_child(_screen_quad(_ao_mat))
	if Settings.sun_shafts:
		_shaft_mat = ShaderMaterial.new()
		_shaft_mat.shader = load("res://scripts/shaders/sun_shafts.gdshader")
		_shaft_mat.render_priority = 121
		cam.camera.add_child(_screen_quad(_shaft_mat))


func _screen_quad(mat: ShaderMaterial) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = Vector2(2, 2)
	q.mesh = m
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.extra_cull_margin = 16384.0
	q.position = Vector3(0, 0, -1)
	_depth_quads.append(q)
	return q


## Where the sun stands on screen, for the shafts.
func _update_shafts(day: float, low: float) -> void:
	if _shaft_mat == null or cam == null:
		return
	var c := cam.camera
	var toward := sun.global_transform.basis.z
	var strength := 0.0
	if toward.y > -0.05:
		var far := c.global_position + toward * 1000.0
		if not c.is_position_behind(far):
			var sp := c.unproject_position(far)
			var vs := get_viewport().get_visible_rect().size
			var uv := sp / vs
			_shaft_mat.set_shader_parameter("sun_uv", uv)
			# Fade as the sun leaves the screen, and in cloud and storm.
			var off := maxf(maxf(-uv.x, uv.x - 1.0), maxf(-uv.y, uv.y - 1.0))
			strength = (1.0 - smoothstep(0.0, 0.6, off)) * day
			if weather:
				strength *= weather.sun_mul
	_shaft_mat.set_shader_parameter("intensity", strength * lerpf(0.55, 0.9, low))
	_shaft_mat.set_shader_parameter("sun_color", sun.light_color)


func _build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/water3d.gdshader")
	# Where the land is volcanic the water is lava (a mask over the island).
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	var span := TerrainGen.HALF * 2.0
	for j in n:
		for i in n:
			var v := world.gen.volcanic(-span * 0.5 + (i + 0.5) * span / n, -span * 0.5 + (j + 0.5) * span / n)
			img.set_pixel(i, j, Color(v, v, v))
	mat.set_shader_parameter("lava_map", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("island_span", span)
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
	# Foliage between the camera and the heroine thins out (foliage3d).
	if player and cam:
		var d := cam.camera.global_position.distance_to(player.global_position + Vector3(0, 1.0, 0))
		RenderingServer.global_shader_parameter_set("occlude_depth", d - 0.8 if d > 1.5 and d < 16.0 else 0.0)
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
			if _frames == last and _args.has("stats"):
				print("STATS draw_calls=%d objects=%d primitives=%d nodes=%d lights=%d" % [
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
					get_tree().root.find_children("*", "Light3D", true, false).size()])
			if _frames == last and _args.has("stats"):
				_breakdown()
			if _frames == last:
				var w := img.get_width()
				var out := Image.create(w * _strip.size(), img.get_height(), false, img.get_format())
				for i in _strip.size():
					out.blit_rect(_strip[i], Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * w, 0))
				out.save_png(_args.shot)
				get_tree().quit()
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = 45.0
		autosave()
	time_of_day = fposmod(time_of_day + delta / day_length, 1.0)
	_update_sun(delta)
	world.focus = player.global_position
	if grass:
		grass.set_player(player.global_position)
	water.global_position = Vector3(snappedf(player.global_position.x, 50.0), TerrainGen.WATER, snappedf(player.global_position.z, 50.0))


## Draw items by system, for the --stats capture: [nodes, surfaces, shadow casters].
func _breakdown() -> void:
	var groups := {}
	var cam_pos: Vector3 = get_viewport().get_camera_3d().global_position
	for g in find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		if gi.visibility_range_end > 0.0 and gi.global_position.distance_to(cam_pos) > gi.visibility_range_end + 64.0:
			continue
		var key := "other"
		var n: Node = gi
		while n != null and n != self:
			if n is OpenWorld or n is SkyIslands or n is Town or n is WorldFeatures or n is Npc3D or n is Player3D or n is Enemy3D:
				key = n.get_class() + ":" + String(n.get_script().get_global_name())
				break
			n = n.get_parent()
		var surf := 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			surf = (gi as MeshInstance3D).mesh.get_surface_count()
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			surf = (gi as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		var e: Array = groups.get(key, [0, 0, 0])
		e[0] += 1
		e[1] += surf
		e[2] += surf if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
		groups[key] = e
	for k in groups:
		print("BREAKDOWN %s nodes=%d surfaces=%d shadow_surfaces=%d" % [k, groups[k][0], groups[k][1], groups[k][2]])


const BASE_FOG := 0.0002
## Region air: [fog tint (alpha = how strongly), extra fog density].
const REGION_MOOD := {
	TerrainGen.Biome.CORRUPTED: [Color(0.36, 0.28, 0.5, 0.55), 0.0014],
	TerrainGen.Biome.DARK_FOREST: [Color(0.3, 0.5, 0.52, 0.5), 0.0018],
	TerrainGen.Biome.VOLCANIC: [Color(0.42, 0.36, 0.38, 0.4), 0.0008],
	TerrainGen.Biome.SNOW: [Color(0.7, 0.8, 0.95, 0.4), 0.0012],
	TerrainGen.Biome.JUNGLE: [Color(0.36, 0.6, 0.62, 0.3), 0.00025],
	TerrainGen.Biome.CRYSTAL: [Color(0.5, 0.78, 0.95, 0.3), 0.0004],
	TerrainGen.Biome.DRY: [Color(0.95, 0.78, 0.56, 0.25), 0.0002],
}
## Each region's sky: [zenith, horizon]; blended in by the mood's weight.
const REGION_SKY := {
	TerrainGen.Biome.CORRUPTED: [Color(0.27, 0.24, 0.42), Color(0.7, 0.63, 0.78)],
	TerrainGen.Biome.DARK_FOREST: [Color(0.2, 0.34, 0.44), Color(0.56, 0.7, 0.68)],
	TerrainGen.Biome.VOLCANIC: [Color(0.3, 0.33, 0.46), Color(0.8, 0.68, 0.6)],
	TerrainGen.Biome.SNOW: [Color(0.36, 0.56, 0.9), Color(0.9, 0.95, 1.0)],
	TerrainGen.Biome.JUNGLE: [Color(0.12, 0.38, 0.74), Color(0.66, 0.84, 0.9)],
	TerrainGen.Biome.CRYSTAL: [Color(0.08, 0.36, 0.86), Color(0.64, 0.86, 1.0)],
	TerrainGen.Biome.DRY: [Color(0.1, 0.34, 0.82), Color(0.92, 0.88, 0.78)],
}
var _sky_top := Color(0.1, 0.3, 0.8)
var _sky_hor := Color(0.7, 0.84, 0.98)
var _mood_col := Color(0, 0, 0, 0)
var _mood_fog := 0.0
var _mood_ready := false


func _update_sun(_delta: float) -> void:
	# The sun arcs east to west; low and golden at dawn and dusk, the moon's
	# cool light at night.
	var angle := (time_of_day - 0.25) * TAU
	var elevation := sin(angle)
	var day := clampf(elevation * 3.0 + 0.2, 0.0, 1.0)
	var low := clampf(1.0 - absf(elevation) * 2.2, 0.0, 1.0) * day
	sun.rotation = Vector3(-maxf(absf(elevation), 0.12) * 1.25 - 0.1, deg_to_rad(-35.0) + cos(angle) * 0.9, 0)
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.34), low).lerp(Color(0.52, 0.62, 1.0), 1.0 - day)
	# Anime nights stay readable: a strong blue moon and a lifted ambient.
	sun.light_energy = lerpf(0.42, 1.55, day)
	environment.ambient_light_energy = lerpf(0.9, 2.1, day)
	if fill:
		# Opposite the sun in yaw, from higher up.
		fill.rotation = Vector3(-0.75, sun.rotation.y + PI, 0)
		fill.light_energy = lerpf(0.08, 0.3, day)
	# Each region has its own air: the fog and light lean toward its colour,
	# blended smoothly as the heroine crosses a border.
	var region: int = world.biome_at(player.global_position) if player else -1
	var mood: Array = REGION_MOOD.get(region, [Color(0, 0, 0, 0), 0.0])
	var region_sky: Array = REGION_SKY.get(region, [Color(0.1, 0.3, 0.8), Color(0.7, 0.84, 0.98)])
	var blend := minf(1.0, _delta * 0.8) if _mood_ready else 1.0
	_mood_ready = player != null
	_mood_col = _mood_col.lerp(mood[0], blend)
	_mood_fog = lerpf(_mood_fog, float(mood[1]), blend)
	_sky_top = _sky_top.lerp(region_sky[0], blend)
	_sky_hor = _sky_hor.lerp(region_sky[1], blend)
	var fog_base := Color(0.56, 0.68, 0.86).lerp(Color(0.95, 0.62, 0.42), low).lerp(Color(0.06, 0.08, 0.16), 1.0 - day)
	environment.fog_light_color = fog_base.lerp(Color(_mood_col.r, _mood_col.g, _mood_col.b) * lerpf(0.25, 1.0, day), _mood_col.a)
	environment.fog_density = BASE_FOG + _mood_fog
	if region == TerrainGen.Biome.DRY:
		# The Sunscar's sun: hard and bright.
		sun.light_energy *= lerpf(1.0, 1.25, day)
	if weather:
		# The weather thickens and tints the air and dims the sun.
		var wt := weather.fog_tint
		environment.fog_light_color = environment.fog_light_color.lerp(Color(wt.r, wt.g, wt.b) * lerpf(0.3, 1.0, day), wt.a)
		environment.fog_density += weather.fog_extra
		sun.light_energy *= weather.sun_mul
		environment.ambient_light_energy += weather.flash * 1.6
		sun.light_energy += weather.flash * 1.2
		_sky_mat.set_shader_parameter("cloud_cover", weather.cloud_cover)
	sun.light_color = sun.light_color.lerp(sun.light_color * Color(_mood_col.r * 1.3, _mood_col.g * 1.3, _mood_col.b * 1.3), _mood_col.a * 0.2)
	var night := clampf(1.0 - day, 0.0, 1.0)
	_update_shafts(day, low)
	if world:
		world.set_sun(sun.global_transform.basis.z, day)
	# Heat shimmer over the open sand by day.
	if _post and player:
		var hot := 1.0 if region == TerrainGen.Biome.DRY else 0.0
		_heat = lerpf(_heat, hot * day * (1.0 - low), minf(1.0, _delta * 0.5))
		_post.set_shader_parameter("heat", _heat)
	_sky_mat.set_shader_parameter("night", night)
	if town:
		town.set_night(night)
	if water:
		(water.material_override as ShaderMaterial).set_shader_parameter("night", night)
	if islands:
		islands.set_night(night)
	_sky_mat.set_shader_parameter("dusk", low)
	var top := _sky_top.lerp(Color(0.35, 0.32, 0.6), low)
	var hor := _sky_hor.lerp(Color(1.0, 0.66, 0.45), low)
	if weather:
		# Storm, dust or snow: the whole sky takes the weather's colour.
		var wc := Color(weather.fog_tint.r, weather.fog_tint.g, weather.fog_tint.b) * lerpf(0.3, 1.0, day)
		top = top.lerp(wc * 0.85, weather.fog_tint.a * 0.6)
		hor = hor.lerp(wc, weather.fog_tint.a * 0.75)
	_sky_mat.set_shader_parameter("top_color", top)
	var bounce := Color(0.56, 0.6, 0.44).lerp(Color(0.1, 0.12, 0.2), 1.0 - day)
	environment.ambient_light_color = top * 0.3 + hor * 0.45 + bounce * 0.25
	_sky_mat.set_shader_parameter("horizon_color", hor)
	var shade := Color(0.7, 0.74, 0.92).lerp(Color(0.75, 0.55, 0.7), low)
	if weather:
		# Rain clouds hang grey and heavy.
		shade = shade.lerp(Color(0.42, 0.45, 0.52), clampf(weather.cloud_cover - 0.42, 0.0, 0.55) * 1.6)
	_sky_mat.set_shader_parameter("cloud_shade", shade)


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
	input.skill2 = false
	input.skill3 = false
	input.burst = false
	if _args.has("menu") and f == 30:
		hud.menu.open(_args.menu)
	if _args.has("hold") and f == 2:
		player.hold(_args.hold)
	match _args.get("action", "idle"):
		"walk":
			input.move = Vector2(0, 0.45) if f > 20 else Vector2.ZERO
		"run":
			input.move = Vector2(0, 1) if f > 20 else Vector2.ZERO
		"sprint":
			input.move = Vector2(0, 1) if f > 20 else Vector2.ZERO
			input.sprint = true
		"die":
			if f == 30:
				player.hurt(999.0, player.global_position + Vector3(0, 0, -1))
		"stop":
			# Run, then let go: the stop.
			input.move = Vector2(0, 1) if f > 20 and f < 70 else Vector2.ZERO
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
				play.select(0)  # the Moonblade gathers
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
		"defend":
			# A foe walks up and swings: its blows are telegraphed on the ground.
			if f == 2:
				play.spawn_enemy(_args.get("enemy", "zombie"), player.global_position + Vector3(0, 0, -4))
		"fight":
			if f == 2:
				play.spawn_enemy(_args.get("enemy", "zombie"), player.global_position + Vector3(0, 0, -5))
			input.attack = f > 30 and f % 36 == 0
		"talk":
			# Walk up to Wren and speak; the dialogue is captured mid-line.
			if f == 2:
				var w: Npc3D = quests.npcs["wren"]
				player.global_position = w.global_position + Vector3(0.4, 0.2, 2.0)
			if f == 20:
				quests.start_talk(quests.npcs[_args.get("npc", "wren")])
			if f > 20 and f % int(_args.get("every_line", "30")) == 0:
				hud.dialogue.advance()
		"tour":
			input.move = Vector2(0.15, 1)
			input.sprint = true
			input.look = Vector2(0.002, 0)
	# --side: the same moves, but across the view (to film the gait side-on).
	if _args.has("side"):
		input.move = Vector2(input.move.y, 0)
