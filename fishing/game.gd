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
const PlayerScene := preload("res://player.gd")
const TouchControls := preload("res://touch_controls.gd")

# App screen: "menu" (title over the live lake), "playing", or "paused".
var app_state := "menu"
var menu_ui

# Within "playing": "explore" (walking around) or "fishing" (at the rod).
var play_mode := "explore"
var player: CharacterBody3D
var touch: CanvasLayer
var cam_yaw := 0.0
var cam_pitch := -0.12
var near_fishing_spot := false
const PLAYER_SPAWN := Vector3(0, 1.2, 11.0)       # on the jetty
const FISHING_SPOT := Vector3(0, 0.72, 4.6)     # where you stand to cast
const EYE_HEIGHT := 1.62   # first-person camera height above the player's feet

# Shared wave parameters — MUST match water.gdshader (WAVES) so the bobber sits
# on the surface. Each is direction.xy, wavelength, amplitude.
const WATER_WAVES := [
	Vector4(0.8, 0.6, 16.0, 0.28),
	Vector4(-0.7, 0.7, 10.0, 0.16),
	Vector4(0.2, -0.95, 6.0, 0.09),
	Vector4(-0.95, -0.25, 3.5, 0.05),
]
const TIME_SCALE := 1.0

const DOCK_TIP := Vector3(0, 0, 3.0)     # end of the jetty, where we cast from
const EYE := Vector3(0, 2.40, 5.6)       # camera position (standing on the deck)
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
var floaters: Array[Node3D] = []  # buoys etc. that ride the waves

# Whacking the catch on the dock
var paddle: Node3D
var whacks_left := 0
var whack_anim := 0.0          # 0..1 swing progress
var catch_hop := 0.0           # bounce applied to the catch
var pending_weight := 0.0
var pending_value := 0
var cam_pitch_target := -10.0  # degrees; eased each frame
const WHACK_SPOT := Vector3(0, 0.72, 3.55)  # on the deck, just in front of us

# Fish table: name, colour, weight range (kg). A few junk "catches" for laughs.
var fish_table := [
	{"name": "Dizzy Perch", "color": Color(0.5, 0.8, 0.4), "min": 0.2, "max": 1.1, "junk": false},
	{"name": "Grumpy Carp", "color": Color(0.8, 0.6, 0.3), "min": 0.8, "max": 3.5, "junk": false},
	{"name": "Rubber Trout", "color": Color(0.9, 0.4, 0.5), "min": 0.4, "max": 2.0, "junk": false},
	{"name": "Lord Bassington", "color": Color(0.3, 0.5, 0.7), "min": 1.5, "max": 5.0, "junk": false},
	{"name": "Tiny Terror", "color": Color(0.95, 0.75, 0.2), "min": 0.05, "max": 0.3, "junk": false},
	{"name": "an Old Crate", "color": Color(0.6, 0.45, 0.3), "min": 0.6, "max": 1.2, "junk": true, "model": "crate"},
	{"name": "a Rusty Barrel", "color": Color(0.6, 0.45, 0.3), "min": 1.0, "max": 2.0, "junk": true, "model": "barrel"},
	{"name": "a TREASURE CHEST", "color": Color(0.9, 0.75, 0.3), "min": 2.0, "max": 4.0, "junk": true, "model": "chest", "treasure": true},
]

enum { IDLE, CHARGING, FLYING, WAITING, BITE, FIGHT, CAUGHT, SNAP, WHACK }
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
var seen_help := false


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
		seen_help = bool(cfg.get_value("save", "seen_help", false))
		for key in upgrades:
			upgrades[key] = int(cfg.get_value("upgrades", key, 0))


func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "coins", coins)
	cfg.set_value("save", "catches", catches)
	cfg.set_value("save", "best_weight", best_weight)
	cfg.set_value("save", "best_name", best_name)
	cfg.set_value("save", "seen_help", seen_help)
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
	menu_ui.first_help_done.connect(_on_first_help_done)
	menu_ui.set_coins(coins)

	player = PlayerScene.new()
	player.position = PLAYER_SPAWN
	add_child(player)

	touch = TouchControls.new()
	add_child(touch)
	touch.interact_pressed.connect(_on_interact)
	touch.visible = false

	_enter_idle()
	_apply_settings()
	# Players always start at the menu; autotest can jump to a screen to shoot it.
	if autotest:
		seen_help = true  # don't let the first-time card block play tests
		match start_screen:
			"play": _start_play(); _enter_fishing()
			"explore": _start_play()
			"settings": _go_main_menu(); menu_ui.open_settings_for_test()
			"pause": _start_play(); _pause()
			"help": _go_main_menu(); menu_ui.open_help_for_test()
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


# --- Kenney model library (CC0, see assets/CREDITS.md) ------------------------
const MDL := {
	"dock": "res://assets/models/pirate/dock.glb",
	"dock_small": "res://assets/models/pirate/dock_small.glb",
	"palm": "res://assets/models/pirate/palm_straight.glb",
	"palm_bend": "res://assets/models/pirate/palm_bend.glb",
	"rocks": "res://assets/models/pirate/rocks_a.glb",
	"rocks_sand": "res://assets/models/pirate/rocks_sand.glb",
	"barrel": "res://assets/models/pirate/barrel.glb",
	"crate": "res://assets/models/pirate/crate.glb",
	"chest": "res://assets/models/pirate/chest.glb",
	"paddle": "res://assets/models/pirate/paddle.glb",
	"grass": "res://assets/models/pirate/grass_patch.glb",
	"tower": "res://assets/models/pirate/tower.glb",
	"wreck": "res://assets/models/pirate/shipwreck.glb",
	"boat": "res://assets/models/watercraft/boat_fishing.glb",
	"buoy": "res://assets/models/watercraft/buoy.glb",
	"buoy_flag": "res://assets/models/watercraft/buoy_flag.glb",
}

const DECK_Y := 0.72   # top of the dock planks, in world units


## Instance a model from the library. Model origins sit at their base, so `pos`
## is where the object stands.
func _spawn(key: String, pos: Vector3, rot_y := 0.0, scl := 1.0, parent: Node = null) -> Node3D:
	var packed: PackedScene = load(MDL[key])
	var n: Node3D = packed.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = Vector3.ONE * scl
	if parent == null:
		add_child(n)
	else:
		parent.add_child(n)
	return n


## Height of an island dome at a world x/z (for standing props on it).
func _island_y(center: Vector3, radius: float, vheight: float, x: float, z: float) -> float:
	var d := Vector2(x - center.x, z - center.z).length()
	if d >= radius:
		return center.y
	var t := d / radius
	return center.y + vheight * sqrt(max(0.0, 1.0 - t * t))


## A smooth island: a sand dome with a grass cap, leaving a beach ring.
func _make_island(center: Vector3, radius: float, height: float, grassy := true,
		walkable := false) -> void:
	var sand := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	sm.material = _mat(Color(0.88, 0.80, 0.58), 1.0)
	sand.mesh = sm
	sand.scale = Vector3(1, (height * 0.85) / radius, 1)
	sand.position = center
	add_child(sand)
	if walkable:
		sand.create_trimesh_collision()

	if grassy:
		var grass := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = radius * 0.80
		gm.height = radius * 1.6
		gm.radial_segments = 36
		gm.rings = 18
		gm.material = _mat(Color(0.40, 0.66, 0.33), 1.0)
		grass.mesh = gm
		grass.scale = Vector3(1, height / (radius * 0.80), 1)
		grass.position = center + Vector3(0, 0.05, 0)
		add_child(grass)
		if walkable:
			grass.create_trimesh_collision()


const HOME := Vector3(0, 0, 28)
const HOME_R := 15.0
const HOME_H := 3.6


func _build_island() -> void:
	_make_island(HOME, HOME_R, HOME_H, true, true)

	# Wooden jetty out over the water (tile depth ~2.5).
	for i in 5:
		_spawn("dock", Vector3(0, -0.59, 14.0 - i * 2.5))

	# Dockside clutter.
	_spawn("barrel", Vector3(-1.5, DECK_Y, 13.4), 0.3, 0.75)
	_spawn("crate", Vector3(1.55, DECK_Y, 14.2), -0.4, 0.8)
	_spawn("chest", Vector3(1.5, DECK_Y, 11.8), 0.9, 0.7)
	_spawn("barrel", Vector3(-1.6, DECK_Y, 10.8), -0.2, 0.65)

	# A little fishing boat moored alongside.
	_spawn("boat", Vector3(3.6, -0.35, 10.0), -PI / 2.0 + 0.12, 0.9)

	# Walkable surface for the jetty: one flat box rather than trimeshing every
	# plank, so the player glides along it.
	var dock_body := StaticBody3D.new()
	var dock_col := CollisionShape3D.new()
	var dock_box := BoxShape3D.new()
	dock_box.size = Vector3(2.3, 0.4, 13.6)
	dock_col.shape = dock_box
	dock_body.add_child(dock_col)
	dock_body.position = Vector3(0, DECK_Y - 0.2, 8.6)
	add_child(dock_body)


func _build_scenery() -> void:
	# Palms and rocks on the home island, standing on the dome surface.
	var home_props := [
		{"k": "palm", "x": -7.0, "z": 29.0, "s": 1.05, "r": 0.4},
		{"k": "palm_bend", "x": 6.5, "z": 31.0, "s": 0.95, "r": 2.1},
		{"k": "palm", "x": -3.0, "z": 34.0, "s": 1.15, "r": 1.2},
		{"k": "palm_bend", "x": 9.5, "z": 25.5, "s": 0.85, "r": 3.4},
		{"k": "palm", "x": -10.0, "z": 25.0, "s": 0.8, "r": 5.0},
		{"k": "rocks_sand", "x": -9.5, "z": 33.0, "s": 0.7, "r": 1.0},
		{"k": "rocks", "x": 10.5, "z": 33.5, "s": 0.55, "r": 2.4},
		{"k": "grass", "x": -4.5, "z": 26.5, "s": 1.0, "r": 0.0},
		{"k": "grass", "x": 4.0, "z": 27.5, "s": 0.9, "r": 1.5},
		{"k": "grass", "x": 0.0, "z": 32.0, "s": 1.1, "r": 2.8},
	]
	for pr in home_props:
		var x: float = pr["x"]
		var z: float = pr["z"]
		var y := _island_y(HOME, HOME_R, HOME_H, x, z)
		_spawn(pr["k"], Vector3(x, y - 0.15, z), pr["r"], pr["s"])

	# A watchtower landmark set back on the island.
	var ty := _island_y(HOME, HOME_R, HOME_H, 2.5, 36.0)
	_spawn("tower", Vector3(2.5, ty - 0.2, 36.0), -0.5, 1.0)

	# Buoys bobbing on the open water (they float at their origin).
	for b in [
		{"k": "buoy", "p": Vector3(-6.5, 0, -7.0), "s": 0.85},
		{"k": "buoy_flag", "p": Vector3(10.0, 0, -17.0), "s": 0.9},
		{"k": "buoy", "p": Vector3(-15.0, 0, -24.0), "s": 0.8},
	]:
		var n := _spawn(b["k"], b["p"], randf() * TAU, b["s"])
		floaters.append(n)

	# A wrecked ship on the horizon for silhouette.
	_spawn("wreck", Vector3(-38, -1.0, -60), 0.7, 1.3)

	# Outlying islands with their own palms and rocks.
	var isles := [
		{"c": Vector3(-40, 0, -46), "r": 11.0, "h": 3.4},
		{"c": Vector3(36, 0, -58), "r": 9.0, "h": 3.0},
		{"c": Vector3(-8, 0, -82), "r": 13.0, "h": 4.2},
		{"c": Vector3(54, 0, -32), "r": 8.0, "h": 2.6},
	]
	for isle in isles:
		var c: Vector3 = isle["c"]
		var r: float = isle["r"]
		var h: float = isle["h"]
		_make_island(c, r, h)
		for i in 3 + randi() % 3:
			var a := randf() * TAU
			var rr := randf_range(0.15, 0.6) * r
			var px := c.x + cos(a) * rr
			var pz := c.z + sin(a) * rr
			var py := _island_y(c, r, h, px, pz)
			_spawn("palm" if randf() < 0.6 else "palm_bend",
				Vector3(px, py - 0.15, pz), randf() * TAU, randf_range(0.9, 1.3))
		var ra := randf() * TAU
		_spawn("rocks_sand", c + Vector3(cos(ra) * r * 0.8, -0.3, sin(ra) * r * 0.8),
			randf() * TAU, randf_range(0.6, 0.9))


# --- Player view: camera, rod, line, bobber ----------------------------------

func _build_player_view() -> void:
	camera = Camera3D.new()
	camera.fov = 68
	camera.position = EYE
	camera.rotation_degrees = Vector3(-10, 0, 0)  # look slightly down at the water
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

	# Paddle used to whack the catch on the deck (hidden until needed).
	paddle = Node3D.new()
	camera.add_child(paddle)
	paddle.position = Vector3(0.60, -0.50, -1.18)
	var paddle_model: Node3D = load(MDL["paddle"]).instantiate()
	paddle_model.scale = Vector3.ONE * 0.40
	paddle_model.rotation_degrees = Vector3(0, 0, -38)
	paddle.add_child(paddle_model)
	for m in paddle.find_children("*", "MeshInstance3D", true):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paddle.visible = false

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
	# Back to the rod: put the paddle away and look up at the water again.
	if rod:
		rod.visible = true
	if paddle:
		paddle.visible = false
	cam_pitch_target = -10.0
	whack_anim = 0.0
	catch_hop = 0.0
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

	_update_floaters()

	if app_state == "menu":
		_menu_camera(delta)
		return
	if app_state == "paused":
		_update_line()
		return

	if play_mode == "explore":
		_update_explore(delta)
		return

	if hud.consume_leave():
		_leave_fishing()
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
		WHACK:
			_update_whack(delta)
			if tap and whack_anim <= 0.45:
				_do_whack()
		CAUGHT, SNAP:
			_update_whack(delta)
			if tap:
				_enter_idle()

	# Subtle first-person sway while playing (not while lining up a whack).
	if _camera_sway and state != WHACK:
		camera.position = EYE + Vector3(sin(elapsed * 0.8) * 0.05, sin(elapsed * 1.1) * 0.04, 0)
		camera.rotation_degrees.z = sin(elapsed * 0.6) * 0.3

	# Ease the camera pitch between fishing and whacking.
	camera.rotation_degrees.x = lerpf(camera.rotation_degrees.x, cam_pitch_target, clampf(delta * 6.0, 0, 1))

	_update_line()
	_hud_sync()


# --- Screen transitions -------------------------------------------------------

var _camera_sway := true
var _menu_cam_t := 0.0

## Walking around: drive the character, swing the third-person camera, and
## offer the fishing prompt when we reach the end of the jetty.
func _update_explore(delta: float) -> void:
	var look: Vector2 = touch.consume_look()
	cam_yaw -= look.x
	cam_pitch = clampf(cam_pitch - look.y, -0.95, 0.40)

	player.move_input = touch.move
	player.cam_yaw = cam_yaw

	# Fell in the lake? Put them back on the jetty.
	if player.position.y < -3.0:
		player.velocity = Vector3.ZERO
		player.position = PLAYER_SPAWN

	camera.global_position = player.global_position + Vector3(0, EYE_HEIGHT, 0)
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

	near_fishing_spot = player.global_position.distance_to(FISHING_SPOT) < 3.0
	touch.prompt = "FISH" if near_fishing_spot else ""


func _on_interact() -> void:
	if app_state != "playing":
		return
	if play_mode == "explore" and near_fishing_spot:
		_enter_fishing()


func _enter_fishing() -> void:
	play_mode = "fishing"
	player.frozen = true
	player.visible = false
	touch.visible = false
	touch.prompt = ""
	camera.position = EYE
	camera.rotation_degrees = Vector3(-10, 0, 0)
	cam_pitch_target = -10.0
	rod.visible = true
	hud.enabled = true
	hud.set_hud_visible(true)
	_enter_idle()


func _leave_fishing() -> void:
	play_mode = "explore"
	_enter_idle()
	player.frozen = false
	player.visible = false   # first person
	player.velocity = Vector3.ZERO
	player.position = FISHING_SPOT + Vector3(0, 0.5, 1.6)
	rod.visible = false
	paddle.visible = false
	bobber.visible = false
	line.visible = false
	hud.enabled = false
	hud.set_hud_visible(false)
	touch.visible = true
	cam_yaw = PI  # look back down the jetty


## Buoys ride the same waves the water shader draws.
func _update_floaters() -> void:
	for f in floaters:
		var h := wave_height(f.position.x, f.position.z)
		f.position.y = h
		f.rotation.x = sin(elapsed * 1.3 + f.position.x) * 0.10
		f.rotation.z = cos(elapsed * 1.1 + f.position.z) * 0.10


func _menu_camera(delta: float) -> void:
	# Slow cinematic drift over the lake toward the distant islands.
	_menu_cam_t += delta * 0.09
	var a := _menu_cam_t
	camera.position = Vector3(sin(a) * 7.0, 3.4 + sin(a * 0.7) * 0.7, 2.0 + cos(a) * 4.0)
	camera.look_at(Vector3(sin(a * 0.5) * 10.0, 0.6, -45.0))


func _start_play() -> void:
	app_state = "playing"
	play_mode = "explore"
	_enter_idle()
	rod.visible = false
	paddle.visible = false
	player.visible = false   # first person
	player.frozen = false
	player.velocity = Vector3.ZERO
	player.position = PLAYER_SPAWN
	cam_yaw = 0.0
	cam_pitch = -0.12
	hud.enabled = false
	hud.set_hud_visible(false)
	touch.visible = true
	menu_ui.show_play()
	# First-ever play: show the modal how-to-play card.
	if not seen_help:
		app_state = "paused"
		hud.enabled = false
		hud.set_hud_visible(false)
		menu_ui.show_first_help()


func _on_first_help_done() -> void:
	seen_help = true
	_save_game()
	_resume()


func _pause() -> void:
	app_state = "paused"
	hud.enabled = false
	hud.set_hud_visible(false)
	if touch:
		touch.visible = false
	if player:
		player.frozen = true
	menu_ui.show_pause()


func _resume() -> void:
	app_state = "playing"
	if play_mode == "fishing":
		hud.enabled = true
		hud.set_hud_visible(true)
	else:
		touch.visible = true
		player.frozen = false
	menu_ui.show_play()


func _go_main_menu() -> void:
	app_state = "menu"
	play_mode = "explore"
	_enter_idle()
	if touch:
		touch.visible = false
	if player:
		player.frozen = true
		player.visible = false
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
	# The catch comes out of the water and lands on the deck, where you deal
	# with it the old-fashioned way.
	state = WHACK
	hud.mode = Hud.M_WHACK
	bobber.visible = false
	rod.visible = false
	paddle.visible = true
	cam_pitch_target = -36.0

	pending_weight = lerpf(pending_fish["min"], pending_fish["max"], randf())
	catches += 1
	if pending_weight > best_weight:
		best_weight = pending_weight
		best_name = pending_fish["name"]

	# Coin value: by weight; crates/barrels are near-worthless, chests are not.
	if pending_fish.get("treasure", false):
		pending_value = 60 + randi() % 90
	elif pending_fish.get("junk", false):
		pending_value = 1 + randi() % 3
	else:
		pending_value = maxi(1, int(round(pending_weight * 14.0)))

	# Heavier catches take more whacks.
	whacks_left = clampi(1 + int(round(pending_weight * 0.9)), 1, 5)
	whack_anim = 0.0
	catch_hop = 0.0
	_play("caught")
	_show_catch(pending_fish)
	_whack_message()


func _whack_message() -> void:
	var verb := "Caught" if not pending_fish.get("junk", false) else "Reeled up"
	hud.message = "%s %s!  %.2f kg\nTAP to whack it  (%d left)" % [
		verb, pending_fish["name"], pending_weight, whacks_left]


## One tap = one whack. Swings the paddle, bounces the catch, and when the
## catch is done, pays out and moves to the result screen.
func _do_whack() -> void:
	whacks_left -= 1
	whack_anim = 1.0
	catch_hop = 1.0
	_play("splash")
	if whacks_left > 0:
		_whack_message()
	else:
		_finish_catch()


func _finish_catch() -> void:
	state = CAUGHT
	hud.mode = Hud.M_CAUGHT
	coins += pending_value
	_save_game()
	var extra := ""
	if pending_fish.get("treasure", false):
		extra = "  JACKPOT!"
	hud.message = "+%d coins%s\n(tap to continue)" % [pending_value, extra]
	_play("caught")
	_update_info()


## Animates the paddle swing and the catch bouncing on the deck.
func _update_whack(delta: float) -> void:
	if whack_anim > 0.0:
		whack_anim = maxf(whack_anim - delta * 4.5, 0.0)
	if catch_hop > 0.0:
		catch_hop = maxf(catch_hop - delta * 3.0, 0.0)
	# Paddle rests raised, snaps down on a whack.
	var swing: float = sin(whack_anim * PI)
	paddle.rotation_degrees.x = -12.0 + swing * 58.0
	paddle.position.y = -0.50 - swing * 0.14
	if caught_fish:
		var hop: float = sin(catch_hop * PI)
		caught_fish.position.y = WHACK_SPOT.y + hop * 0.28
		caught_fish.scale = Vector3(1.0 + hop * 0.18, 1.0 - hop * 0.22, 1.0 + hop * 0.18)
		caught_fish.rotation.z = sin(elapsed * 14.0) * 0.07 * (0.3 + hop)


## Drops the catch onto the deck in front of the player, lying side-on so its
## face and tail both read, scaled by how heavy it is.
func _show_catch(info: Dictionary) -> void:
	if caught_fish:
		caught_fish.queue_free()
	caught_fish = _make_fish(info["color"], info.get("junk", false), info.get("model", ""))
	var scl: float = clampf(0.55 + pending_weight * 0.17, 0.55, 1.5)
	caught_fish.scale = Vector3.ONE * scl
	caught_fish.position = WHACK_SPOT
	caught_fish.rotation = Vector3(0, PI * 0.5, 0)  # side profile across the deck
	add_child(caught_fish)


## Builds a smooth, tapered fish: a lofted body with generated normals, a forked
## tail, dorsal and pectoral fins, and googly eyes. Faces -Z, tail toward +Z.
func _make_fish(color: Color, junk: bool, model_key := "") -> Node3D:
	if junk:
		# Gag catches are real props: a crate, a barrel, a treasure chest.
		var holder := Node3D.new()
		var packed: PackedScene = load(MDL[model_key if model_key != "" else "crate"])
		var prop: Node3D = packed.instantiate()
		prop.position = Vector3(0, -0.35, 0)
		prop.scale = Vector3.ONE * 0.85
		holder.add_child(prop)
		return holder

	var n := Node3D.new()
	var mat := _mat(color, 0.55)
	var belly := _mat(color.lightened(0.35), 0.6)
	var fin_mat := _mat(color.darkened(0.18), 0.6)
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# ---- Body: loft ellipse cross-sections along the spine ----
	var rings := 16
	var segs := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in rings:
		var t := float(i) / float(rings - 1)
		var z: float = lerpf(-0.62, 0.62, t)
		# Fat just behind the head, tapering to a thin tail stalk.
		var prof: float = pow(sin(PI * pow(t, 0.78)), 0.80)
		var r: float = maxf(prof * 0.30, 0.012)
		var ring := []
		for j in segs:
			var a := TAU * float(j) / float(segs)
			ring.append(Vector3(cos(a) * r * 0.78, sin(a) * r * 1.30, z))
		pts.append(ring)
	for i in rings - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			var a1: Vector3 = pts[i][j]
			var b1: Vector3 = pts[i][j2]
			var c1: Vector3 = pts[i + 1][j2]
			var d1: Vector3 = pts[i + 1][j]
			st.add_vertex(a1); st.add_vertex(b1); st.add_vertex(c1)
			st.add_vertex(a1); st.add_vertex(c1); st.add_vertex(d1)
	st.generate_normals()
	var body := MeshInstance3D.new()
	body.mesh = st.commit()
	body.material_override = mat
	n.add_child(body)

	# Pale belly: a second, slightly smaller body squashed downward.
	var belly_mi := MeshInstance3D.new()
	belly_mi.mesh = body.mesh
	belly_mi.material_override = belly
	belly_mi.scale = Vector3(0.97, 0.52, 0.985)
	belly_mi.position = Vector3(0, -0.085, 0)
	n.add_child(belly_mi)

	# ---- Fins ----
	n.add_child(_fin([
		Vector3(0, 0.0, 0.52), Vector3(0, 0.34, 0.92), Vector3(0, 0.0, 0.74),
		Vector3(0, 0.0, 0.52), Vector3(0, 0.0, 0.74), Vector3(0, -0.32, 0.92),
	], fin_mat))                                           # forked tail
	n.add_child(_fin([
		Vector3(0, 0.26, -0.10), Vector3(0, 0.52, 0.16), Vector3(0, 0.22, 0.30),
	], fin_mat))                                           # dorsal
	for sx in [-1.0, 1.0]:
		n.add_child(_fin([
			Vector3(0.14 * sx, -0.02, -0.16), Vector3(0.40 * sx, -0.20, 0.10),
			Vector3(0.14 * sx, -0.10, 0.12),
		], fin_mat))                                       # pectorals

	# ---- Googly eyes ----
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.068
		em.height = 0.136
		em.radial_segments = 12
		em.rings = 7
		em.material = _mat(Color(1, 1, 1), 0.25)
		eye.mesh = em
		eye.position = Vector3(0.088 * sx, 0.078, -0.305)
		n.add_child(eye)
		var pup := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.034
		pm.height = 0.068
		pm.radial_segments = 10
		pm.rings = 6
		pm.material = _mat(Color(0.05, 0.05, 0.07), 0.2)
		pup.mesh = pm
		pup.position = Vector3(0.118 * sx, 0.082, -0.345)
		n.add_child(pup)
	return n


## A flat, double-sided fin from a list of triangle corners.
func _fin(tris: Array, mat: StandardMaterial3D) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in tris:
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


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
	# Explore: walk the character forward for a while, then shoot.
	if start_screen == "explore":
		if frame == 10:
			cam_yaw = PI          # turn around to face the island
		if frame < 30:
			touch.move = Vector2.ZERO
		elif frame < 480:
			touch.move = Vector2(0, -1)   # walk forward (now toward the island)
		else:
			touch.move = Vector2.ZERO
		if frame >= 500:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST(explore) pos=%s on_floor=%s prompt='%s' anim=%s" % [
				player.position.snapped(Vector3.ONE * 0.01), player.is_on_floor(),
				touch.prompt, player._cur])
			get_tree().quit()
		return

	if start_screen in ["menu", "settings", "pause", "shop", "help"]:
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
		WHACK:
			if frame % 18 == 0:
				sim_tap = true
		CAUGHT, SNAP:
			if frame % 40 == 0:
				sim_tap = true
	if shot_on == "whack" and state == WHACK and frame > 30 and whacks_left <= 2:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(whack) frames=%d whacks_left=%d" % [frame, whacks_left])
		get_tree().quit()
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
