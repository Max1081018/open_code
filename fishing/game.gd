extends Node3D
## Lazy Lake — a calm, funny, low-poly first-person fishing game.
##
## Loop: HOLD the button to charge a cast, release to fling the bobber out, wait
## for a bite, TAP to hook it, then HOLD to reel while keeping the line tension
## out of the red. Land it and a goofy fish pops up with its name and weight.
##
## Everything (island, water, rod, fish, sounds) is generated in code from
## primitives and sine-wave shaders, so there are no assets to import.
##
## Headless self-test (game/tools/play.sh calls this):
##   godot --path fishing -- --autotest --frames=1800 --shot=out.png
## plays several full casts with synthetic input, screenshots, and prints
## "AUTOTEST ..." before quitting.

const Hud := preload("res://hud.gd")
const MenuUI := preload("res://menu_ui.gd")

# App screen: "menu" (title over the live lake), "playing", or "paused".
var app_state := "menu"
var menu_ui

# Shared wave parameters — MUST match water.gdshader (WAVES) so the bobber sits
# on the surface. Each is direction.xy, wavelength, amplitude.
const WATER_WAVES := [
	Vector4(0.8, 0.6, 16.0, 0.28),
	Vector4(-0.7, 0.7, 10.0, 0.16),
	Vector4(0.2, -0.95, 6.0, 0.09),
	Vector4(-0.95, -0.25, 3.5, 0.05),
]
const TIME_SCALE := 1.0

const DOCK_TIP := Vector3(0, 0, 4)       # end of the jetty, where we stand
const EYE := Vector3(0, 2.1, 5.2)        # camera position
const MIN_CAST := 9.0
const MAX_CAST := 40.0

var camera: Camera3D
var rod: Node3D
var rod_tip: Marker3D
var line: MeshInstance3D
var bobber: Node3D
var hud
var caught_fish: Node3D

var players := {}  # name -> AudioStreamPlayer
var reel_click_t := 0.0

# Fish table: name, colour, weight range (kg). A few junk "catches" for laughs.
var fish_table := [
	{"name": "Dizzy Perch", "color": Color(0.5, 0.8, 0.4), "min": 0.2, "max": 1.1, "junk": false},
	{"name": "Grumpy Carp", "color": Color(0.8, 0.6, 0.3), "min": 0.8, "max": 3.5, "junk": false},
	{"name": "Rubber Trout", "color": Color(0.9, 0.4, 0.5), "min": 0.4, "max": 2.0, "junk": false},
	{"name": "Lord Bassington", "color": Color(0.3, 0.5, 0.7), "min": 1.5, "max": 5.0, "junk": false},
	{"name": "Tiny Terror", "color": Color(0.95, 0.75, 0.2), "min": 0.05, "max": 0.3, "junk": false},
	{"name": "a Soggy Boot", "color": Color(0.3, 0.25, 0.22), "min": 0.6, "max": 0.9, "junk": true},
	{"name": "an Old Tin Can", "color": Color(0.6, 0.62, 0.65), "min": 0.2, "max": 0.4, "junk": true},
]

enum { IDLE, CHARGING, FLYING, WAITING, BITE, FIGHT, CAUGHT, SNAP }
var state := IDLE
var power := 0.0
var elapsed := 0.0

var cast_from := Vector3.ZERO
var cast_to := Vector3.ZERO
var flight_t := 0.0

var bite_timer := 0.0
var bite_window := 0.0

var distance := 1.0
var tension := 0.0
var lunge_timer := 0.0
var fish_strength := 1.0
var pending_fish := {}

var catches := 0
var best_weight := 0.0
var best_name := ""

# --- Economy / progression ----------------------------------------------------
const SAVE_PATH := "user://save.cfg"
# Each upgrade: display name, blurb, number of levels, and base cost (cost grows
# per level). Effects are applied in the gameplay formulas below.
const UPGRADES := {
	"rod":  {"name": "Rod",  "desc": "Cast farther",        "levels": 5, "cost": 40},
	"line": {"name": "Line", "desc": "Line resists tension", "levels": 5, "cost": 55},
	"bait": {"name": "Bait", "desc": "Fish bite sooner",     "levels": 5, "cost": 50},
	"luck": {"name": "Luck", "desc": "Bigger, rarer catches", "levels": 5, "cost": 70},
}
var coins := 0
var upgrades := {"rod": 0, "line": 0, "bait": 0, "luck": 0}


func upgrade_cost(key: String) -> int:
	# Rising cost: base * (level+1), e.g. 40, 80, 120, ...
	return int(UPGRADES[key]["cost"]) * (int(upgrades[key]) + 1)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		coins = int(cfg.get_value("save", "coins", 0))
		catches = int(cfg.get_value("save", "catches", 0))
		best_weight = float(cfg.get_value("save", "best_weight", 0.0))
		best_name = str(cfg.get_value("save", "best_name", ""))
		for key in upgrades:
			upgrades[key] = int(cfg.get_value("upgrades", key, 0))


func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "coins", coins)
	cfg.set_value("save", "catches", catches)
	cfg.set_value("save", "best_weight", best_weight)
	cfg.set_value("save", "best_name", best_name)
	for key in upgrades:
		cfg.set_value("upgrades", key, upgrades[key])
	cfg.save(SAVE_PATH)


func _refresh_shop() -> void:
	var rows := []
	for key in ["rod", "line", "bait", "luck"]:
		var lvl: int = upgrades[key]
		var maxed: bool = lvl >= int(UPGRADES[key]["levels"])
		var cost := upgrade_cost(key)
		rows.append({
			"key": key,
			"name": UPGRADES[key]["name"],
			"desc": UPGRADES[key]["desc"],
			"level": lvl,
			"max": int(UPGRADES[key]["levels"]),
			"cost": cost,
			"maxed": maxed,
			"afford": coins >= cost,
		})
	menu_ui.set_shop_model(coins, rows)


func _buy_upgrade(key: String) -> void:
	if not upgrades.has(key):
		return
	if upgrades[key] >= int(UPGRADES[key]["levels"]):
		return
	var cost := upgrade_cost(key)
	if coins < cost:
		return
	coins -= cost
	upgrades[key] += 1
	_play("caught")
	_save_game()
	_refresh_shop()
	_update_info()

# Autotest
var autotest := false
var autotest_frames := 1800
var autotest_shot := ""
var shot_on := "end"  # "end" or "caught": when to grab the screenshot
var sim_action := false
var sim_tap := false
var frame := 0
var start_screen := "menu"  # autotest can jump straight to a screen


func _ready() -> void:
	_parse_args()
	if autotest:
		seed(7)
	else:
		randomize()
	_load_save()
	_build_world()
	_build_player_view()
	_build_sounds()
	hud = Hud.new()
	add_child(hud)

	menu_ui = MenuUI.new()
	add_child(menu_ui)
	menu_ui.play_pressed.connect(_start_play)
	menu_ui.resume_pressed.connect(_resume)
	menu_ui.to_main_menu.connect(_go_main_menu)
	menu_ui.settings_changed.connect(_apply_settings)
	menu_ui.shop_opened.connect(_refresh_shop)
	menu_ui.buy_pressed.connect(_buy_upgrade)
	menu_ui.set_coins(coins)

	_enter_idle()
	_apply_settings()
	# Players always start at the menu; autotest can jump to a screen to shoot it.
	if autotest:
		match start_screen:
			"play": _start_play()
			"settings": _go_main_menu(); menu_ui.open_settings_for_test()
			"pause": _start_play(); _pause()
			"shop":
				coins = 500
				_go_main_menu()
				menu_ui.open_shop_for_test()
			_: _go_main_menu()
	else:
		_go_main_menu()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest": autotest = true
		elif a.begins_with("--frames="): autotest_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--shot="): autotest_shot = a.get_slice("=", 1)
		elif a.begins_with("--shot-on="): shot_on = a.get_slice("=", 1)
		elif a.begins_with("--screen="): start_screen = a.get_slice("=", 1)


# --- Wave height (mirror of the shader) --------------------------------------

func wave_height(x: float, z: float) -> float:
	# Vertical part of the Gerstner sum in water.gdshader.
	var t := elapsed * TIME_SCALE
	var y := 0.0
	for w in WATER_WAVES:
		var dir := Vector2(w.x, w.y).normalized()
		var k: float = TAU / w.z
		var amp: float = w.w
		var speed := sqrt(9.8 / k)
		y += amp * sin(k * dir.dot(Vector2(x, z)) + t * speed)
	return y


# --- World --------------------------------------------------------------------

func _mat(color: Color, rough := 0.9, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	# Sky + warm light.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.86)
	sky_mat.sky_horizon_color = Color(0.85, 0.9, 0.95)
	sky_mat.ground_horizon_color = Color(0.85, 0.9, 0.95)
	sky_mat.ground_bottom_color = Color(0.6, 0.72, 0.8)
	sky_mat.sun_angle_max = 40.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.82, 0.92)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	# Water: a big subdivided plane with the wave shader.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	plane.subdivide_width = 90
	plane.subdivide_depth = 90
	var smat := ShaderMaterial.new()
	smat.shader = load("res://water.gdshader")
	smat.set_shader_parameter("time_scale", TIME_SCALE)
	smat.set_shader_parameter("sun_dir", Vector3(0.45, 0.7, 0.35))
	plane.material = smat
	water.mesh = plane
	water.position = Vector3(0, 0, -20)
	add_child(water)

	_build_island()
	_build_scenery()


## A smooth rounded island: a grass dome ringed by a sand beach, rising out of
## the water. `center` is at the waterline.
func _make_island(center: Vector3, radius: float, height: float,
		grass_color := Color(0.40, 0.70, 0.34)) -> void:
	var beach_top := 0.12

	# Sand beach ring (slightly wider than the grass so a shore shows).
	var sand := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = radius * 1.18
	sc.bottom_radius = radius * 1.05
	sc.height = 0.6
	sc.radial_segments = 28
	sc.material = _mat(Color(0.82, 0.72, 0.52))
	sand.mesh = sc
	sand.position = center + Vector3(0, beach_top - 0.3, 0)
	add_child(sand)

	# Grass dome (a vertically-squashed sphere).
	var grass := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = radius
	gm.height = radius * 2.0
	gm.radial_segments = 30
	gm.rings = 16
	gm.material = _mat(grass_color)
	grass.mesh = gm
	grass.scale = Vector3(1, height / radius, 1)
	grass.position = center + Vector3(0, beach_top, 0)
	add_child(grass)


func _rock(pos: Vector3, size: float, color := Color(0.55, 0.56, 0.6)) -> void:
	var rock := MeshInstance3D.new()
	var rm := SphereMesh.new()
	rm.radius = size
	rm.height = size * 1.6
	rm.radial_segments = 7
	rm.rings = 4
	rm.material = _mat(color)
	rock.mesh = rm
	rock.scale = Vector3(1.0, 0.7, 1.1)
	rock.position = pos + Vector3(0, size * 0.3, 0)
	rock.rotation.y = randf() * TAU
	add_child(rock)


func _build_island() -> void:
	# Home island sits behind the camera (positive Z) so we look over open water.
	_make_island(Vector3(0, 0, 14), 12.0, 4.5)

	# Wooden jetty reaching out to where we stand.
	for i in 5:
		_box(self, Vector3(0, 0.08, 9.5 - i * 1.6), Vector3(2.2, 0.25, 1.5), Color(0.62, 0.45, 0.28))
	_box(self, Vector3(-1.0, -0.3, 4.2), Vector3(0.25, 1.4, 0.25), Color(0.5, 0.36, 0.22))
	_box(self, Vector3(1.0, -0.3, 4.2), Vector3(0.25, 1.4, 0.25), Color(0.5, 0.36, 0.22))


func _tree(pos: Vector3, scale := 1.0) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18 * scale
	tm.bottom_radius = 0.26 * scale
	tm.height = 1.6 * scale
	tm.material = _mat(Color(0.45, 0.32, 0.2))
	trunk.mesh = tm
	trunk.position = pos + Vector3(0, 0.8 * scale, 0)
	add_child(trunk)
	for k in 3:
		var leaf := MeshInstance3D.new()
		var lm := CylinderMesh.new()  # cone = top_radius 0
		lm.top_radius = 0.0
		lm.bottom_radius = (1.1 - k * 0.22) * scale
		lm.height = 1.1 * scale
		lm.radial_segments = 6
		lm.material = _mat(Color(0.26, 0.56, 0.3).lerp(Color(0.4, 0.7, 0.4), k / 3.0))
		leaf.mesh = lm
		leaf.position = pos + Vector3(0, (1.6 + k * 0.6) * scale, 0)
		add_child(leaf)


func _build_scenery() -> void:
	# Trees and rocks on the home island (to the sides, behind the camera).
	_tree(Vector3(-6.5, 1.8, 15), 1.2)
	_tree(Vector3(6.0, 1.8, 16), 1.0)
	_tree(Vector3(-2.5, 2.4, 18.5), 1.15)
	_tree(Vector3(3.0, 2.2, 19), 0.9)
	_rock(Vector3(-8.5, 0.1, 10), 0.9)
	_rock(Vector3(8.0, 0.1, 11), 0.7)

	# Rounded islands across the lake, each with its own greenery.
	var isles := [
		{"c": Vector3(-36, 0, -42), "r": 9.0, "h": 5.0},
		{"c": Vector3(34, 0, -55), "r": 7.0, "h": 4.0},
		{"c": Vector3(-6, 0, -74), "r": 11.0, "h": 6.5},
		{"c": Vector3(48, 0, -30), "r": 6.0, "h": 3.5},
	]
	for isle in isles:
		var c: Vector3 = isle["c"]
		var r: float = isle["r"]
		_make_island(c, r, isle["h"], Color(0.36, 0.64, 0.33).lerp(Color(0.5, 0.72, 0.4), randf()))
		var trees := 2 + randi() % 3
		for i in trees:
			var a := randf() * TAU
			var rr := randf_range(0.2, 0.6) * r
			_tree(c + Vector3(cos(a) * rr, isle["h"] * 0.5 + 0.5, sin(a) * rr), randf_range(1.4, 2.4))
		_rock(c + Vector3(r * 0.8, 0.1, r * 0.2), randf_range(0.8, 1.6))

	# A funny rubber duck bobbing nearby.
	var duck := _make_duck()
	duck.position = Vector3(-4.5, 0, -2)
	add_child(duck)
	duck.set_meta("duck", true)


func _make_duck() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.5
	bm.height = 0.8
	bm.material = _mat(Color(1.0, 0.85, 0.1))
	body.mesh = bm
	n.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	hm.material = bm.material
	head.mesh = hm
	head.position = Vector3(0, 0.45, 0.25)
	n.add_child(head)
	var beak := _box(n, Vector3(0, 0.45, 0.55), Vector3(0.18, 0.1, 0.22), Color(0.95, 0.5, 0.1))
	return n


# --- Player view: camera, rod, line, bobber ----------------------------------

func _build_player_view() -> void:
	camera = Camera3D.new()
	camera.fov = 62
	camera.position = EYE
	camera.rotation_degrees = Vector3(-6, 0, 0)  # look slightly down at the water
	add_child(camera)

	# First-person rod, held in the bottom-right, angled out over the water.
	rod = Node3D.new()
	camera.add_child(rod)
	rod.position = Vector3(0.6, -0.5, -0.8)
	rod.rotation_degrees = Vector3(28, -8, -10)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.012
	pm.bottom_radius = 0.045
	pm.height = 2.6
	pm.material = _mat(Color(0.15, 0.12, 0.12), 0.5)
	pole.mesh = pm
	pole.position = Vector3(0, 0, -1.3)
	pole.rotation_degrees = Vector3(90, 0, 0)  # lay it along -Z
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no weird line on the water
	rod.add_child(pole)
	# Handle grip.
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.05
	gm.bottom_radius = 0.05
	gm.height = 0.4
	gm.material = _mat(Color(0.3, 0.2, 0.1), 0.7)
	grip.mesh = gm
	grip.rotation_degrees = Vector3(90, 0, 0)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rod.add_child(grip)
	rod_tip = Marker3D.new()
	rod_tip.position = Vector3(0, 0, -2.6)
	rod.add_child(rod_tip)

	# The line (updated every frame).
	line = MeshInstance3D.new()
	line.material_override = _mat(Color(0.95, 0.95, 0.95), 0.4)
	add_child(line)

	# Bobber: classic red-over-white.
	bobber = Node3D.new()
	var top := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 0.16
	tsm.height = 0.32
	tsm.material = _mat(Color(0.9, 0.2, 0.2))
	top.mesh = tsm
	top.position = Vector3(0, 0.08, 0)
	bobber.add_child(top)
	var bot := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.16
	bsm.height = 0.32
	bsm.material = _mat(Color(0.95, 0.95, 0.95))
	bot.mesh = bsm
	bot.position = Vector3(0, -0.08, 0)
	bobber.add_child(bot)
	add_child(bobber)
	bobber.visible = false


# --- Sound --------------------------------------------------------------------

func _build_sounds() -> void:
	var streams := {
		"whoosh": Sfx.whoosh(), "splash": Sfx.splash(), "bite": Sfx.bite(),
		"click": Sfx.click(), "caught": Sfx.caught(), "snap": Sfx.snap(),
	}
	for key in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		add_child(p)
		players[key] = p


func _play(key: String) -> void:
	if players.has(key):
		players[key].play()


# --- State helpers ------------------------------------------------------------

func _enter_idle() -> void:
	state = IDLE
	power = 0.0
	bobber.visible = false
	hud.mode = Hud.M_IDLE
	hud.message = ""
	hud.power = 0.0
	hud.distance = 1.0
	hud.tension = 0.0
	if caught_fish:
		caught_fish.queue_free()
		caught_fish = null
	_update_info()


func _update_info() -> void:
	var s := "Catches: %d" % catches
	if best_name != "":
		s += "   Best: %s (%.2f kg)" % [best_name, best_weight]
	hud.info = s
	hud.coins = coins
	if menu_ui:
		menu_ui.set_coins(coins)


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	if autotest:
		_autotest(delta)

	# Pause from the in-game button.
	if app_state == "playing" and menu_ui and menu_ui.consume_pause():
		_pause()

	if app_state == "menu":
		_menu_camera(delta)
		return
	if app_state == "paused":
		_update_line()
		return

	var action: bool = hud.action_down() or sim_action
	var tap: bool = hud.consume_tap() or sim_tap
	sim_tap = false

	match state:
		IDLE, CHARGING:
			if action:
				state = CHARGING
				hud.mode = Hud.M_CHARGING
				power = min(power + delta * 1.1, 1.0)
				hud.power = power
				hud.message = ""
			elif power > 0.0:
				_do_cast(power)
		FLYING:
			_update_flight(delta)
		WAITING:
			_update_bobber()
			bite_timer -= delta
			if bite_timer <= 0.0:
				_start_bite()
		BITE:
			_update_bobber()
			bite_window -= delta
			if tap:
				_hook_fish()
			elif bite_window <= 0.0:
				hud.message = "...it got away"
				_play("splash")
				await_then_idle(1.0)
		FIGHT:
			_update_fight(delta, action)
			_update_bobber()
		CAUGHT, SNAP:
			if caught_fish:
				caught_fish.rotation.y += delta * 1.5
				caught_fish.position.y = lerpf(caught_fish.position.y, _fish_display_y, delta * 4.0)
			if tap:
				_enter_idle()

	# Subtle first-person sway while playing.
	if _camera_sway:
		camera.position = EYE + Vector3(sin(elapsed * 0.8) * 0.05, sin(elapsed * 1.1) * 0.04, 0)
		camera.rotation_degrees.z = sin(elapsed * 0.6) * 0.3

	_update_line()
	_hud_sync()


# --- Screen transitions -------------------------------------------------------

var _camera_sway := true
var _menu_cam_t := 0.0

func _menu_camera(delta: float) -> void:
	# Slow cinematic drift over the lake toward the distant islands.
	_menu_cam_t += delta * 0.09
	var a := _menu_cam_t
	camera.position = Vector3(sin(a) * 7.0, 3.4 + sin(a * 0.7) * 0.7, 2.0 + cos(a) * 4.0)
	camera.look_at(Vector3(sin(a * 0.5) * 10.0, 0.6, -45.0))


func _start_play() -> void:
	app_state = "playing"
	_enter_idle()
	camera.position = EYE
	camera.rotation_degrees = Vector3(-6, 0, 0)
	rod.visible = true
	hud.enabled = true
	hud.set_hud_visible(true)
	menu_ui.show_play()


func _pause() -> void:
	app_state = "paused"
	hud.enabled = false
	hud.set_hud_visible(false)
	menu_ui.show_pause()


func _resume() -> void:
	app_state = "playing"
	hud.enabled = true
	hud.set_hud_visible(true)
	menu_ui.show_play()


func _go_main_menu() -> void:
	app_state = "menu"
	_enter_idle()
	rod.visible = false
	bobber.visible = false
	line.visible = false
	hud.enabled = false
	hud.set_hud_visible(false)
	_menu_cam_t = 0.0
	menu_ui.show_main()


func _apply_settings() -> void:
	if not menu_ui:
		return
	_camera_sway = menu_ui.settings["camera_sway"]
	hud.left_handed = menu_ui.settings["left_handed"]
	hud.recalc_layout()


var _idle_delay := 0.0
func await_then_idle(t: float) -> void:
	_idle_delay = t
	state = -1 as int  # transient; handled below
	set_process(true)


func _physics_process(_d: float) -> void:
	# Handle the little post-message pause without a coroutine.
	if _idle_delay > 0.0:
		_idle_delay -= get_physics_process_delta_time()
		if _idle_delay <= 0.0:
			_enter_idle()


func _hud_sync() -> void:
	hud.distance = distance
	hud.tension = tension


# --- Casting ------------------------------------------------------------------

func _do_cast(p: float) -> void:
	var max_cast: float = MAX_CAST + float(upgrades["rod"]) * 6.0  # Rod upgrade
	var dist: float = lerpf(MIN_CAST, max_cast, p)
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	# Slight random spread so no two casts land the same.
	fwd = fwd.rotated(Vector3.UP, randf_range(-0.12, 0.12))
	cast_from = rod_tip.global_position
	cast_to = DOCK_TIP + fwd * dist
	cast_to.y = 0.0
	flight_t = 0.0
	state = FLYING
	power = 0.0
	bobber.visible = true
	bobber.scale = Vector3.ONE
	hud.mode = Hud.M_WAITING
	hud.message = ""
	_play("whoosh")


func _update_flight(delta: float) -> void:
	flight_t = min(flight_t + delta * 1.4, 1.0)
	var flat := cast_from.lerp(cast_to, flight_t)
	var arc := sin(PI * flight_t) * cast_from.distance_to(cast_to) * 0.12
	bobber.position = flat + Vector3.UP * arc
	if flight_t >= 1.0:
		_play("splash")
		# Bait upgrade shortens the wait.
		var bait_factor: float = 1.0 - float(upgrades["bait"]) * 0.13
		bite_timer = randf_range(2.5, 6.5) * bait_factor
		state = WAITING
		hud.message = "Waiting for a bite..."


func _update_bobber() -> void:
	var x := bobber.position.x
	var z := bobber.position.z
	bobber.position.y = wave_height(x, z)
	# Gentle bob tilt.
	bobber.rotation.z = sin(elapsed * 2.0 + x) * 0.15


func _start_bite() -> void:
	state = BITE
	bite_window = 1.6
	hud.mode = Hud.M_BITE
	hud.message = "!!  TAP  !!"
	_play("bite")
	# Tug the bobber under briefly.
	bobber.position.y -= 0.25


func _hook_fish() -> void:
	# Choose a fish (junk is rarer).
	var pick: Dictionary = fish_table[randi() % fish_table.size()]
	while pick.get("junk", false) and randf() > 0.35:
		pick = fish_table[randi() % fish_table.size()]
	# Luck upgrade: take the better of extra rolls, so bigger fish appear more.
	var luck: int = int(upgrades["luck"])
	for i in luck:
		var other: Dictionary = fish_table[randi() % fish_table.size()]
		if not other.get("junk", false) and float(other["max"]) > float(pick["max"]):
			pick = other
	pending_fish = pick
	fish_strength = lerpf(0.5, 1.4, randf()) * (1.0 + float(pick["max"]) * 0.12)
	distance = 1.0
	tension = 0.35
	lunge_timer = randf_range(0.8, 1.8)
	state = FIGHT
	hud.mode = Hud.M_FIGHT
	hud.message = ""


# --- The fight ----------------------------------------------------------------

func _update_fight(delta: float, reeling: bool) -> void:
	if reeling:
		distance = max(distance - delta * 0.17, 0.0)
		# Line upgrade reduces how fast tension builds.
		var line_factor: float = 1.0 - float(upgrades["line"]) * 0.12
		tension += delta * (0.42 * fish_strength) * line_factor
		reel_click_t -= delta
		if reel_click_t <= 0.0:
			_play("click")
			reel_click_t = 0.09
	else:
		# Let the line rest: tension falls, but the fish may swim back out.
		tension = max(tension - delta * 0.6, 0.0)
		distance = min(distance + delta * 0.05 * fish_strength, 1.0)

	lunge_timer -= delta
	if lunge_timer <= 0.0:
		tension += 0.22 * fish_strength
		distance = min(distance + 0.06, 1.0)
		lunge_timer = randf_range(1.0, 2.6)

	if tension >= 1.0:
		_snap_line()
	elif distance <= 0.0:
		_land_fish()


func _snap_line() -> void:
	state = SNAP
	hud.mode = Hud.M_SNAP
	var nm: String = pending_fish.get("name", "it")
	hud.message = "SNAP!  %s got away\n(tap to try again)" % nm
	_play("snap")
	bobber.visible = false


func _land_fish() -> void:
	state = CAUGHT
	hud.mode = Hud.M_CAUGHT
	bobber.visible = false
	var weight: float = lerpf(pending_fish["min"], pending_fish["max"], randf())
	catches += 1
	if weight > best_weight:
		best_weight = weight
		best_name = pending_fish["name"]
	# Coins: by weight, with junk worth little.
	var value := 1
	if pending_fish.get("junk", false):
		value = 1 + randi() % 3
	else:
		value = maxi(1, int(round(weight * 14.0)))
	coins += value
	_save_game()
	var verb := "Caught" if not pending_fish.get("junk", false) else "Reeled up"
	hud.message = "%s %s!\n%.2f kg   +%d coins\n(tap to continue)" % [verb, pending_fish["name"], weight, value]
	_play("caught")
	_show_catch(pending_fish)
	_update_info()


var _fish_display_y := 0.0

func _show_catch(info: Dictionary) -> void:
	if caught_fish:
		caught_fish.queue_free()
	caught_fish = _make_fish(info["color"], info.get("junk", false))
	# Hold it up in front of the camera.
	var in_front := camera.global_position - camera.global_transform.basis.z * 2.4
	in_front += camera.global_transform.basis.x * 0.3
	caught_fish.position = in_front - Vector3(0, 0.6, 0)
	caught_fish.rotation.y = PI * 0.5  # side profile so the face and tail both read
	_fish_display_y = in_front.y - 0.1
	add_child(caught_fish)


func _make_fish(color: Color, junk: bool) -> Node3D:
	var n := Node3D.new()
	if junk:
		# A boot-ish block for the gag catches.
		_box(n, Vector3.ZERO, Vector3(0.5, 0.4, 0.8), color)
		_box(n, Vector3(0, -0.25, 0.4), Vector3(0.5, 0.2, 0.5), color)
		return n
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.4
	bm.height = 0.8
	bm.material = _mat(color)
	body.mesh = bm
	body.scale = Vector3(1.0, 0.75, 1.7)
	n.add_child(body)
	# Tail.
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.35
	tm.height = 0.5
	tm.radial_segments = 4
	tm.material = _mat(color.darkened(0.1))
	tail.mesh = tm
	tail.rotation_degrees = Vector3(90, 0, 0)
	tail.position = Vector3(0, 0, 0.75)
	n.add_child(tail)
	# Googly eyes.
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.12
		em.height = 0.24
		em.material = _mat(Color.WHITE, 0.3)
		eye.mesh = em
		eye.position = Vector3(0.18 * sx, 0.12, -0.5)
		n.add_child(eye)
		var pup := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.055
		pm.height = 0.11
		pm.material = _mat(Color.BLACK, 0.3)
		pup.mesh = pm
		pup.position = Vector3(0.18 * sx, 0.12, -0.6)
		n.add_child(pup)
	return n


# --- Line mesh ----------------------------------------------------------------

func _update_line() -> void:
	var show := state in [FLYING, WAITING, BITE, FIGHT]
	line.visible = show
	if not show:
		return
	var a := rod_tip.global_position
	var b := bobber.global_position
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	# A little sag in the middle.
	var steps := 8
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		p.y -= sin(PI * t) * 0.25
		im.surface_add_vertex(p)
	im.surface_end()
	line.mesh = im


# --- Autotest -----------------------------------------------------------------

func _autotest(_delta: float) -> void:
	frame += 1
	sim_action = false

	# For non-gameplay screens, just let them settle and screenshot.
	if start_screen in ["menu", "settings", "pause", "shop"]:
		if frame > 40:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST(%s) frame=%d" % [start_screen, frame])
			get_tree().quit()
		return

	match state:
		IDLE, CHARGING:
			# Charge ~0.8s then release.
			sim_action = power < 0.75
		BITE:
			sim_tap = true
		FIGHT:
			# Reel in bursts: pull unless tension is high.
			sim_action = tension < 0.72
			# Test-only: hurry the catch along so a short headless run lands a fish.
			distance = max(distance - 0.012, 0.0)
		CAUGHT, SNAP:
			if frame % 40 == 0:
				sim_tap = true
	if shot_on == "caught" and state == CAUGHT and frame > 30:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(caught) frames=%d catches=%d best=%.2f" % [frame, catches, best_weight])
		get_tree().quit()
	if frame >= autotest_frames:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST frames=%d catches=%d best=%.2f state=%d" % [frame, catches, best_weight, state])
		get_tree().quit()
