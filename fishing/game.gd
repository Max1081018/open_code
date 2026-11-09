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
const PLAYER_SPAWN := Vector3(0, 1.2, 7.0)        # out on the jetty
const FISHING_SPOT := Vector3(0, 0.72, 4.6)     # where you stand to cast
const EYE_HEIGHT := 1.62   # first-person camera height above the player's feet

# Wave settings shared with assets/water/stylized_water.gdshader. wave_height()
# below mirrors its waves() function so floating things ride the real surface.
const WAVE_HEIGHT := 0.38
const WAVE_LENGTH := 9.0
const WAVE_SPEED := 0.5
const WAVE_DIR := [Vector2(0.958, 0.287), Vector2(-0.447, 0.894), Vector2(0.6, -0.8), Vector2(-0.894, -0.447)]
const WAVE_LEN_MUL := [1.0, 0.71, 0.53, 0.37]
const WAVE_SHARE := [0.4, 0.27, 0.2, 0.13]
const WAVE_HALF_TURNS := [1.0, 2.0, 2.0, 3.0]

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
var sun_light: DirectionalLight3D
var world_env: Environment
var water_mat: ShaderMaterial
var shop_building: Node3D
var shop_counter: Node3D
var shopkeeper: Node3D
var near_shop := false
var fish_buyer: Node3D
var near_market := false
var market_ground := 0.0
var shop_floor_y := 0.0
var shop_door_z := 0.0
var held: Array = []              # catches you're carrying: {name, weight, value, set, node}
var held_view: Node3D             # the latest one, shown in your hand

# Boat
const BOAT_MOOR := Vector3(4.3, -0.55, 9.5)
const BOAT_YAW := PI                 # bow points out to sea (-Z)
const BOSS_WATERS := Vector3(-6.0, -0.55, -46.0)
const SAIL_TIME := 4.0
var boat: Node3D
var on_boat := false
var near_boat := false
var _sail_t := 0.0
var _sail_from := Vector3.ZERO
var _sail_to := Vector3.ZERO
var _sail_out := true
var island2_marker: Node3D
const WEAPON_LAYER := 4          # collision layer the crosshair ray looks for
var weapon_bodies := {}          # weapon id -> StaticBody3D
var weapon_outlines := {}        # weapon id -> Array[MeshInstance3D]
var looked_weapon := ""          # what the crosshair is on right now
var _greet_timer := 0.0

# Whacking the catch on the dock
var paddle: Node3D
var whacks_left := 0
var whack_anim := 0.0          # 0..1 swing progress
var catch_hop := 0.0           # bounce applied to the catch
var _catch_base_scale := Vector3.ONE
var pending_weight := 0.0
var pending_value := 0
var cam_pitch_target := -10.0  # degrees; eased each frame
const WHACK_SPOT := Vector3(0, 0.72, 3.55)  # on the deck, just in front of us
# Where fishing happens right now: the jetty by default, the boat at sea.
var fish_eye := EYE
var fish_tip := DOCK_TIP
var whack_spot := WHACK_SPOT

# Fish table: name, colour, weight range (kg). A few junk "catches" for laughs.
const CATCH_SETS := {
	"river": "res://assets/models/fishing/river-fish-set.glb",
	"rarity": "res://assets/models/fishing/rarity-fish-set.glb",
	"ocean": "res://assets/models/fishing/low-poly-ocean-fish-set.glb",
	"junk": "res://assets/models/fishing/junk-catches-set.glb",
	"mythic": "res://assets/models/fishing/mythic-fish-set.glb",
}

# Island 1's boss: only bites out at sea, from the boat, with the Boss Reel.
const BOSS := {"name": "the Baby Kraken", "set": "mythic", "node": "BabyKraken",
	"min": 18.0, "max": 26.0, "junk": false, "boss": true}
const BOSS_VALUE := 650

# Every catch is a real model pulled out of one of the sets above by node name.
var fish_table := [
	{"name": "Minnow", "set": "rarity", "node": "Fish_Minnow", "min": 0.05, "max": 0.30, "junk": false},
	{"name": "Perch", "set": "rarity", "node": "Fish_Perch", "min": 0.25, "max": 1.10, "junk": false},
	{"name": "Sunfish", "set": "river", "node": "Fish_Sunfish", "min": 0.30, "max": 1.40, "junk": false},
	{"name": "Trout", "set": "rarity", "node": "Fish_Trout", "min": 0.50, "max": 2.20, "junk": false},
	{"name": "Bass", "set": "river", "node": "Fish_Bass", "min": 0.80, "max": 3.20, "junk": false},
	{"name": "Carp", "set": "river", "node": "Fish_Carp", "min": 1.20, "max": 4.50, "junk": false},
	{"name": "Catfish", "set": "rarity", "node": "Fish_Catfish", "min": 1.80, "max": 6.00, "junk": false},
	{"name": "Pike", "set": "river", "node": "Fish_Pike", "min": 2.00, "max": 7.50, "junk": false},
	{"name": "Golden Koi", "set": "rarity", "node": "Fish_Golden", "min": 3.00, "max": 9.00, "junk": false, "prize": true},
	{"name": "an Old Boot", "set": "junk", "node": "Boot_Old", "min": 0.60, "max": 1.20, "junk": true},
	{"name": "a Rusty Tin", "set": "junk", "node": "TinCan_Rusty", "min": 0.20, "max": 0.50, "junk": true},
	{"name": "an Old Tyre", "set": "junk", "node": "Tyre_Seaweed", "min": 2.00, "max": 4.00, "junk": true},
	{"name": "a Message in a Bottle", "set": "junk", "node": "Bottle_Message", "min": 0.30, "max": 0.60, "junk": true},
	{"name": "a Sunken Chest", "set": "junk", "node": "Chest_Barnacle", "min": 2.50, "max": 5.00, "junk": true, "treasure": true},
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

# --- Weapons -------------------------------------------------------------------
# Island 1 (beginner) stock. `power` shaves whacks off landing a catch, so the
# gear you buy actually changes how the game plays.
const SHOP_STOCK := [
	{"id": "dagger_A", "name": "Gutting Knife", "rarity": "Common",
	 "desc": "A stubby blade for cleaning your catch.", "price": 40, "power": 1},
	{"id": "dagger_B", "name": "Fisherman's Dirk", "rarity": "Common",
	 "desc": "Holds an edge in salt air. Just about.", "price": 85, "power": 1},
	{"id": "fistweapon_A", "name": "Scaling Grips", "rarity": "Common",
	 "desc": "Knuckle guards for wrestling a slippery one.", "price": 130, "power": 2},
	{"id": "axe_A", "name": "Bait Hatchet", "rarity": "Uncommon",
	 "desc": "Chops bait. Chops most things, really.", "price": 210, "power": 2},
	{"id": "boss_reel", "name": "Boss Reel", "rarity": "Rare", "kind": "gear",
	 "desc": "Heavy carbon reel. Lets you take the boat out after something big.",
	 "price": 360, "power": 0,
	 "model": "res://assets/models/fishing/tiered-fishing-rods.glb", "node": "FishingRod_Carbon"},
]
var owned_weapons: Array = []
var equipped_weapon := ""
var has_boss_reel := false
var island2_unlocked := false


func weapon_by_id(id: String) -> Dictionary:
	for w in SHOP_STOCK:
		if w["id"] == id:
			return w
	return {}


## Whack bonus from the equipped weapon.
func weapon_power() -> int:
	if equipped_weapon == "":
		return 0
	var w := weapon_by_id(equipped_weapon)
	return int(w.get("power", 0))


func _buy_weapon(id: String) -> void:
	var w := weapon_by_id(id)
	if w.is_empty() or owned_weapons.has(id):
		return
	var price := int(w["price"])
	if coins < price:
		return
	coins -= price
	owned_weapons.append(id)
	if str(w.get("kind", "")) == "gear":
		has_boss_reel = true
		_play("caught")
		_save_game()
		_update_info()
		_flash("Boss Reel bought!  Take the boat out")
		return
	equipped_weapon = id        # equip what you just bought
	_play("caught")
	_save_game()
	_update_info()
	_flash("Bought %s!   -%d coins" % [w["name"], price])


func _equip_weapon(id: String) -> void:
	if id != "" and not owned_weapons.has(id):
		return
	if str(weapon_by_id(id).get("kind", "")) == "gear":
		_flash("Boss Reel ready - sail out in the boat")
		return
	equipped_weapon = "" if equipped_weapon == id else id
	_play("click")
	_save_game()
	var nm: String = weapon_by_id(id).get("name", "it")
	_flash("Equipped %s" % nm if equipped_weapon == id else "Put %s away" % nm)


func _refresh_weapon_shop() -> void:
	pass


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
		owned_weapons = cfg.get_value("save", "owned_weapons", [])
		equipped_weapon = str(cfg.get_value("save", "equipped_weapon", ""))
		held = cfg.get_value("save", "held", [])
		has_boss_reel = bool(cfg.get_value("save", "has_boss_reel", false))
		island2_unlocked = bool(cfg.get_value("save", "island2_unlocked", false))
		for key in upgrades:
			upgrades[key] = int(cfg.get_value("upgrades", key, 0))


func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "coins", coins)
	cfg.set_value("save", "catches", catches)
	cfg.set_value("save", "best_weight", best_weight)
	cfg.set_value("save", "best_name", best_name)
	cfg.set_value("save", "seen_help", seen_help)
	cfg.set_value("save", "owned_weapons", owned_weapons)
	cfg.set_value("save", "equipped_weapon", equipped_weapon)
	cfg.set_value("save", "held", held)
	cfg.set_value("save", "has_boss_reel", has_boss_reel)
	cfg.set_value("save", "island2_unlocked", island2_unlocked)
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
var test_yaw := PI
var test_walk := 450
var test_sprint := false
var _test_max_speed := 0.0
var _boss_logged := false
var _boss_sold := false
var _boss_sell_frame := -1


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
			"boss":
				coins = 500
				_start_play()
				_buy_weapon("boss_reel")
				player.position = Vector3(1.3, DECK_Y + 0.4, BOAT_MOOR.z)
				cam_yaw = -PI * 0.5
			"shopview":
				_start_play()
				player.position = Vector3(SHOP_POS.x, shop_floor_y + 0.3, shop_door_z - 0.4)
				cam_yaw = PI
				cam_pitch = -0.10
			"sell":
				_start_play()
				held = [
					{"name": "Bass", "weight": 2.1, "value": 29, "set": "river", "node": "Fish_Bass"},
					{"name": "Trout", "weight": 1.4, "value": 20, "set": "rarity", "node": "Fish_Trout"},
				]
				_refresh_held_view()
				player.position = Vector3(SELL_SPOT.x - 1.4, market_ground + 0.3, SELL_SPOT.z)
				cam_yaw = -PI * 0.5   # face +X, toward the buyer
				cam_pitch = -0.10
			"legs":
				_start_play()
				cam_pitch = -1.30
			"settings": _go_main_menu(); menu_ui.open_settings_for_test()
			"pause": _start_play(); _pause()
			"help": _go_main_menu(); menu_ui.open_help_for_test()
			"weaponshop":
				coins = 600
				_start_play()
				# Stand at the counter looking at the stock.
				var gy := _island_y(HOME, HOME_R, HOME_H, SHOP_POS.x, SHOP_POS.z)
				player.position = Vector3(SHOP_POS.x + 0.2, shop_floor_y + 0.3, SHOP_POS.z - 0.9)
				cam_yaw = 1.68            # toward the first display stand
				cam_pitch = -0.17
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
		elif a.begins_with("--yaw="): test_yaw = float(a.get_slice("=", 1))
		elif a.begins_with("--walk="): test_walk = int(a.get_slice("=", 1))
		elif a == "--sprint": test_sprint = true


# --- Wave height (mirror of the shader) --------------------------------------

func wave_height(x: float, z: float) -> float:
	# Mirrors waves() in stylized_water.gdshader.
	var t := float(Time.get_ticks_msec()) / 1000.0 * WAVE_SPEED
	var p := Vector2(x, z)
	var h := 0.0
	for i in 4:
		var k: float = TAU / (WAVE_LENGTH * float(WAVE_LEN_MUL[i]))
		var phase: float = k * (WAVE_DIR[i] as Vector2).dot(p) - PI * float(WAVE_HALF_TURNS[i]) * t
		h += WAVE_HEIGHT * float(WAVE_SHARE[i]) * sin(phase)
	return h


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
	sky_mat.sky_top_color = Color(0.13, 0.36, 0.78)
	sky_mat.sky_horizon_color = Color(0.74, 0.88, 0.97)
	sky_mat.ground_horizon_color = Color(0.74, 0.88, 0.97)
	sky_mat.ground_bottom_color = Color(0.32, 0.52, 0.66)
	sky_mat.sun_angle_max = 40.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.57, 0.70)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.82, 0.94)
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	world_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.02
	sun.light_color = Color(1.0, 0.93, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	sun_light = sun

	# Seabed, so the transparent water has something to tint against.
	var bed := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(300, 300)
	bm.material = _mat(Color(0.72, 0.64, 0.44), 1.0)
	bed.mesh = bm
	bed.position = Vector3(0, -7.0, -20)
	add_child(bed)

	# Water: a big subdivided plane running the stylized water shader.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	plane.subdivide_width = 150
	plane.subdivide_depth = 150
	var smat := ShaderMaterial.new()
	smat.shader = load("res://assets/water/stylized_water.gdshader")
	smat.set_shader_parameter("shallow_color", Color(0.30, 0.86, 0.82, 0.38))
	smat.set_shader_parameter("deep_color", Color(0.02, 0.22, 0.42, 0.96))
	smat.set_shader_parameter("depth_distance", 3.2)
	smat.set_shader_parameter("foam_color", Color(0.97, 0.99, 1.0, 1.0))
	smat.set_shader_parameter("foam_width", 0.16)
	smat.set_shader_parameter("wave_height", WAVE_HEIGHT)
	smat.set_shader_parameter("wave_length", WAVE_LENGTH)
	smat.set_shader_parameter("wave_speed", WAVE_SPEED)
	smat.set_shader_parameter("normal_scale", 0.35)
	smat.set_shader_parameter("normal_tile_size", 9.0)
	smat.set_shader_parameter("roughness", 0.07)
	smat.set_shader_parameter("normal_map_a", load("res://assets/water/water_normal_a.png"))
	smat.set_shader_parameter("normal_map_b", load("res://assets/water/water_normal_b.png"))
	plane.material = smat
	water_mat = smat
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
	"motorboat": "res://assets/models/fishing/fishing-motorboat.glb",
	"buoy": "res://assets/models/watercraft/buoy.glb",
	"buoy_flag": "res://assets/models/watercraft/buoy_flag.glb",
	# Shop
	"shop_building": "res://assets/models/fishing/lakeside-bait-shop.glb",
	"shop_counter": "res://assets/models/fishing/tackle-shop-counter.glb",
	"market": "res://assets/models/fishing/fish-market-stand.glb",
}

# Island 1 shop placement
const SHOP_POS := Vector3(-7.0, 0, 25.0)
const SHOP_SCALE := 0.34
const COUNTER_SCALE := 0.214
# Where the player stands to be served, and where the shopkeeper waits.
const SHOP_TALK_SPOT := Vector3(-7.0, 0, 25.4)
const WEAPON_DIR := "res://assets/models/weapons/"

# Fish market (where you sell what you carry)
const MARKET_POS := Vector3(7.0, 0, 19.5)
const MARKET_SCALE := 0.27
const SELL_SPOT := Vector3(5.2, 0, 19.5)    # in front of the counter
const MAX_CARRY := 5

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


## Height of an island at a world x/z. The profile is a smooth bump,
## H * (1 - (d/R)^2)^2, which meets the water tangentially, so every beach is
## a gentle walkable slope (max ~16 degrees) rather than a dome's vertical edge.
## Past the radius it keeps sloping down under the water so there's no lip.
func _island_y(center: Vector3, radius: float, vheight: float, x: float, z: float) -> float:
	var d := Vector2(x - center.x, z - center.z).length()
	if d >= radius:
		return center.y - 0.30 - (d - radius) * 0.22
	var u := 1.0 - (d * d) / (radius * radius)
	return center.y + vheight * u * u - 0.30


## Builds an island as one generated mesh: a polar grid on the bump profile,
## coloured by height (wet sand under water, dry sand on the beach, grass on
## top) with smooth normals. Walkable islands get matching trimesh collision.
func _make_island(center: Vector3, radius: float, height: float, grassy := true,
		walkable := false) -> void:
	var rings := 34
	var segs := 72
	var outer := radius * 1.22
	var grid: Array = []
	for i in rings + 1:
		var rr := outer * float(i) / float(rings)
		var row: Array = []
		for j in segs:
			var a := TAU * float(j) / float(segs)
			var x := center.x + cos(a) * rr
			var z := center.z + sin(a) * rr
			row.append(Vector3(x, _island_y(center, radius, height, x, z), z))
		grid.append(row)

	var wet := Color(0.60, 0.50, 0.33)
	var sand := Color(0.86, 0.73, 0.48)
	var grass := Color(0.32, 0.61, 0.26)
	var deep_grass := Color(0.24, 0.50, 0.21)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var add := func(v: Vector3) -> void:
		var h := v.y - center.y
		var c: Color
		if h < 0.05:
			c = wet.lerp(sand, clampf((h + 0.6) / 0.65, 0.0, 1.0))
		elif not grassy or h < 0.75:
			c = sand
		elif h < 1.25:
			c = sand.lerp(grass, (h - 0.75) / 0.5)
		else:
			c = grass.lerp(deep_grass, clampf((h - 1.25) / (height + 0.01), 0.0, 1.0))
		st.set_color(c)
		st.add_vertex(v)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			var p0: Vector3 = grid[i][j]
			var p1: Vector3 = grid[i][j2]
			var p2: Vector3 = grid[i + 1][j2]
			var p3: Vector3 = grid[i + 1][j]
			# Clockwise seen from above = front face in Godot.
			add.call(p0); add.call(p2); add.call(p1)
			add.call(p0); add.call(p3); add.call(p2)
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true      # colours above are picked in sRGB
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	add_child(mi)
	if walkable:
		mi.create_trimesh_collision()


const HOME := Vector3(0, 0, 36)
const HOME_R := 23.0
const HOME_H := 4.4


func _build_island() -> void:
	_make_island(HOME, HOME_R, HOME_H, true, true)

	# Wooden jetty out over the water (tile depth ~2.5).
	for i in 7:
		_spawn("dock", Vector3(0, -0.59, 19.0 - i * 2.5))

	# Dockside clutter.
	_spawn("barrel", Vector3(-1.62, DECK_Y, 16.2), 0.3, 0.70)
	_spawn("crate", Vector3(1.62, DECK_Y, 17.0), -0.4, 0.75)
	_spawn("barrel", Vector3(-1.66, DECK_Y, 15.2), -0.2, 0.60)

	# The motorboat, moored alongside the jetty. Buy the Boss Reel to take it out.
	boat = _spawn("motorboat", BOAT_MOOR, BOAT_YAW, 0.30)

	# Walkable surface for the jetty: one flat box rather than trimeshing every
	# plank, so the player glides along it.
	var dock_body := StaticBody3D.new()
	var dock_col := CollisionShape3D.new()
	var dock_box := BoxShape3D.new()
	dock_box.size = Vector3(2.3, 0.4, 18.6)
	dock_col.shape = dock_box
	dock_body.add_child(dock_col)
	dock_body.position = Vector3(0, DECK_Y - 0.2, 11.1)
	add_child(dock_body)


func _build_scenery() -> void:
	# Palms and rocks on the home island, standing on the dome surface.
	var home_props := [
		{"k": "palm", "x": -16.0, "z": 34.0, "s": 1.10, "r": 0.4},
		{"k": "palm_bend", "x": 13.0, "z": 31.0, "s": 1.00, "r": 2.1},
		{"k": "palm", "x": -4.0, "z": 41.0, "s": 1.20, "r": 1.2},
		{"k": "palm_bend", "x": 15.0, "z": 42.0, "s": 0.95, "r": 3.4},
		{"k": "palm", "x": -13.0, "z": 46.0, "s": 1.00, "r": 5.0},
		{"k": "palm", "x": 5.0, "z": 50.0, "s": 1.15, "r": 0.9},
		{"k": "palm_bend", "x": -18.0, "z": 23.0, "s": 0.90, "r": 2.6},
		{"k": "rocks_sand", "x": -17.0, "z": 40.0, "s": 0.75, "r": 1.0},
		{"k": "rocks", "x": 17.0, "z": 36.0, "s": 0.60, "r": 2.4},
		{"k": "rocks_sand", "x": 10.0, "z": 52.0, "s": 0.70, "r": 0.3},
		{"k": "grass", "x": 2.0, "z": 29.0, "s": 1.0, "r": 0.0},
		{"k": "grass", "x": -3.0, "z": 35.0, "s": 0.9, "r": 1.5},
		{"k": "grass", "x": 8.0, "z": 38.0, "s": 1.1, "r": 2.8},
		{"k": "grass", "x": -9.0, "z": 38.0, "s": 1.0, "r": 0.7},
	]
	for pr in home_props:
		var x: float = pr["x"]
		var z: float = pr["z"]
		var y := _island_y(HOME, HOME_R, HOME_H, x, z)
		_spawn(pr["k"], Vector3(x, y - 0.15, z), pr["r"], pr["s"])

	# A watchtower landmark set back on the island.
	var ty := _island_y(HOME, HOME_R, HOME_H, 3.0, 42.0)
	_spawn("tower", Vector3(3.0, ty - 0.2, 42.0), -0.5, 1.2)

	# Buoys bobbing on the open water (they float at their origin).
	for b in [
		{"k": "buoy", "p": Vector3(-6.5, 0, -7.0), "s": 0.85},
		{"k": "buoy_flag", "p": Vector3(10.0, 0, -17.0), "s": 0.9},
		{"k": "buoy", "p": Vector3(-15.0, 0, -24.0), "s": 0.8},
	]:
		var n := _spawn(b["k"], b["p"], randf() * TAU, b["s"])
		floaters.append(n)

	_build_shop()
	_build_market()
	if island2_unlocked:
		_show_island2_marker()

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
	camera.near = 0.08
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
	if play_mode == "sailing":
		_update_sail(delta)
		return

	if hud.consume_leave():
		_leave_fishing()
		return

	var action: bool = hud.action_down() or sim_action
	var tap: bool = hud.consume_tap() or sim_tap
	sim_tap = false

	match state:
		IDLE, CHARGING:
			if held.size() >= MAX_CARRY:
				hud.message = "Hands full!\nSell your catch at the fish market"
				power = 0.0
			elif action:
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
		var bob := wave_height(fish_eye.x, fish_eye.z) * 0.6 if on_boat else 0.0
		camera.position = fish_eye + Vector3(sin(elapsed * 0.8) * 0.05, sin(elapsed * 1.1) * 0.04 + bob, 0)
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
	cam_pitch = clampf(cam_pitch - look.y, -1.40, 0.45)

	player.move_input = touch.move
	player.sprint = touch.sprint
	player.cam_yaw = cam_yaw

	# Fell in the lake? Put them back on the jetty.
	if player.position.y < -3.0:
		player.velocity = Vector3.ZERO
		player.position = PLAYER_SPAWN

	# Sit the camera a little ahead of the chest so looking down shows your own
	# body and legs rather than the inside of your shoulders.
	var fwd := (Basis(Vector3.UP, cam_yaw) * Vector3(0, 0, -1)).normalized()
	camera.global_position = player.global_position + Vector3(0, EYE_HEIGHT, 0) + fwd * 0.26
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

	_update_look()

	near_fishing_spot = _hdist(player.global_position, FISHING_SPOT) < 3.0
	near_market = _hdist(player.global_position, SELL_SPOT) < 2.6
	near_boat = boat != null and _hdist(player.global_position, BOAT_MOOR) < 3.8
	var was_near := near_shop
	near_shop = _hdist(player.global_position, SHOP_TALK_SPOT) < 3.4
	if near_shop and not was_near:
		_greet_shopkeeper()
	if _greet_timer > 0.0:
		_greet_timer -= delta

	# What the crosshair is on decides the prompt.
	if looked_weapon != "":
		var w := weapon_by_id(looked_weapon)
		var price := int(w.get("price", 0))
		var owned: bool = owned_weapons.has(looked_weapon)
		touch.look_info = str(w.get("name", "?"))
		touch.look_stat = "+%d power" % int(w.get("power", 0))
		if str(w.get("kind", "")) == "gear":
			touch.look_stat = "unlocks the boat"
		if owned and str(w.get("kind", "")) == "gear":
			touch.look_cost = "OWNED"
			touch.prompt = ""
		elif owned:
			touch.look_cost = "EQUIPPED" if equipped_weapon == looked_weapon else "OWNED"
			touch.prompt = "UNEQUIP" if equipped_weapon == looked_weapon else "EQUIP"
		else:
			touch.look_cost = "%d" % price
			touch.prompt = "BUY" if coins >= price else "TOO DEAR"
	else:
		touch.look_info = ""
		touch.look_stat = ""
		touch.look_cost = ""
		if near_market and not held.is_empty():
			touch.prompt = "SELL %d" % held.size()
		elif near_boat:
			touch.prompt = "SAIL" if has_boss_reel else "LOCKED"
		elif near_fishing_spot:
			touch.prompt = "FISH"
		else:
			touch.prompt = ""


func _on_interact() -> void:
	if app_state != "playing":
		return
	if play_mode != "explore":
		return
	# Looking at stock takes priority: buy it or equip it right there.
	if looked_weapon != "":
		if owned_weapons.has(looked_weapon):
			_equip_weapon(looked_weapon)
		else:
			var w := weapon_by_id(looked_weapon)
			if coins < int(w.get("price", 0)):
				_flash("Not enough coins")
				_play("snap")
			else:
				_buy_weapon(looked_weapon)
		return
	if near_market and not held.is_empty():
		_sell_all()
		return
	if near_boat:
		if not has_boss_reel:
			_flash("You need the Boss Reel from Bait & Blade")
			_play("snap")
		elif held.size() >= MAX_CARRY:
			_flash("Hands full - sell your catch first")
		else:
			_start_sail(true)
		return
	if near_fishing_spot:
		_enter_fishing()


## Puts a weapon on display: the model, a white outline that lights up when you
## look at it, and a pick body on its own collision layer for the crosshair ray.
func _add_weapon_display(id: String, pos: Vector3, rot := Vector3.ZERO, scl := 0.42) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation = rot
	holder.scale = Vector3.ONE * scl
	add_child(holder)
	var info := weapon_by_id(id)
	var m: Node3D
	if info.has("model"):
		# Gear lives inside a multi-item pack: lift out just the one node.
		var root: Node3D = load(str(info["model"])).instantiate()
		var part := root.find_child(str(info.get("node", "")), true, false)
		if part:
			part.get_parent().remove_child(part)
			root.queue_free()
			m = Node3D.new()
			m.add_child(part)
			(part as Node3D).transform = Transform3D.IDENTITY
		else:
			m = root
		holder.add_child(m)
		var lb := _local_aabb(m)
		(part as Node3D).position -= Vector3(lb.position.x + lb.size.x * 0.5, 0, lb.position.z + lb.size.z * 0.5)
	else:
		var packed: PackedScene = load(WEAPON_DIR + id + ".gltf")
		m = packed.instantiate()
		holder.add_child(m)

	# Sit it on the surface: pos.y is the shelf, not the model origin.
	var pre := _node_aabb(m)
	holder.position.y += pos.y - pre.position.y

	# White "grown" shell, drawn only while highlighted.
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(1, 1, 1)
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.cull_mode = BaseMaterial3D.CULL_FRONT
	om.grow = true
	om.grow_amount = 0.05
	var outlines: Array = []
	for mi in m.find_children("*", "MeshInstance3D", true):
		if mi.mesh == null:
			continue
		var o := MeshInstance3D.new()
		o.mesh = mi.mesh
		o.material_override = om
		o.transform = mi.transform
		o.visible = false
		mi.get_parent().add_child(o)
		outlines.append(o)
	weapon_outlines[id] = outlines

	# Pick body sized to the model, parented to the world so scale stays simple.
	var box := _node_aabb(m)
	var body := StaticBody3D.new()
	body.collision_layer = WEAPON_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size + Vector3(0.14, 0.14, 0.14)
	col.shape = bs
	body.add_child(col)
	body.position = box.position + box.size * 0.5
	body.set_meta("weapon_id", id)
	add_child(body)
	weapon_bodies[id] = body


func _set_weapon_outline(id: String, on: bool) -> void:
	if id == "" or not weapon_outlines.has(id):
		return
	for o in weapon_outlines[id]:
		o.visible = on


## Casts a ray from the middle of the screen and highlights any stock it hits.
func _update_look() -> void:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_transform.basis.z * 3.8
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = WEAPON_LAYER
	var hit := space.intersect_ray(q)
	var id := ""
	if not hit.is_empty() and hit.has("collider"):
		var c = hit["collider"]
		if c and c.has_meta("weapon_id"):
			id = str(c.get_meta("weapon_id"))
	if id != looked_weapon:
		_set_weapon_outline(looked_weapon, false)
		_set_weapon_outline(id, true)
		looked_weapon = id


func _flash(text: String) -> void:
	if touch:
		touch.flash(text)


## The shopkeeper waves when you come in.
func _greet_shopkeeper() -> void:
	var ap = shopkeeper.get_meta("anim") if shopkeeper and shopkeeper.has_meta("anim") else null
	if ap and ap.has_animation("Cheer"):
		ap.play("Cheer")
		_greet_timer = 2.0


func _enter_fishing() -> void:
	play_mode = "fishing"
	_set_weapon_outline(looked_weapon, false)
	looked_weapon = ""
	if held_view:
		held_view.queue_free()
		held_view = null
	touch.look_info = ""
	touch.look_stat = ""
	touch.look_cost = ""
	player.frozen = true
	player.visible = false
	touch.visible = false
	touch.prompt = ""
	camera.position = fish_eye
	camera.rotation_degrees = Vector3(-10, 0, 0)
	cam_pitch_target = -10.0
	rod.visible = true
	hud.enabled = true
	hud.set_hud_visible(true)
	_enter_idle()


func _leave_fishing() -> void:
	if on_boat:
		_enter_idle()
		rod.visible = false
		paddle.visible = false
		bobber.visible = false
		line.visible = false
		hud.enabled = false
		hud.set_hud_visible(false)
		_start_sail(false)
		return
	play_mode = "explore"
	_enter_idle()
	player.frozen = false
	player.visible = true
	player.set_first_person(true)
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
	_refresh_held_view()


## World-space AABB of all meshes under a node.
func _node_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true):
		if n.mesh == null:
			continue
		var a: AABB = n.global_transform * n.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## AABB of a node's meshes in that node's own space. Walks local transforms by
## hand rather than using global_transform, so it also works on a subtree that
## has not been added to the scene yet.
func _local_aabb(root: Node3D) -> AABB:
	var acc: Array[AABB] = []
	for c in root.get_children():
		_collect_aabb(c, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return AABB()
	var out: AABB = acc[0]
	for i in range(1, acc.size()):
		out = out.merge(acc[i])
	return out


func _collect_aabb(node: Node, xform: Transform3D, acc: Array[AABB]) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		acc.append(t * (node as MeshInstance3D).mesh.get_aabb())
	for c in node.get_children():
		_collect_aabb(c, t, acc)


## Spawns a KayKit character scaled to human height, looping one animation.
func _spawn_character(path: String, pos: Vector3, yaw := 0.0, anim_name := "Idle") -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var m: Node3D = load(path).instantiate()
	root.add_child(m)
	var box := _local_aabb(m)
	if box.size.y > 0.001:
		var sc := 1.75 / box.size.y
		m.scale = Vector3.ONE * sc
		m.position.y = -box.position.y * sc
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation(anim_name):
		var a := ap.get_animation(anim_name)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		ap.play(anim_name)
		root.set_meta("anim", ap)
	return root


## Puts a weapon model in the world at a display size.
func _spawn_weapon(key: String, pos: Vector3, rot := Vector3.ZERO, scl := 0.45, parent: Node = null) -> Node3D:
	var packed: PackedScene = load(WEAPON_DIR + key + ".gltf")
	var n: Node3D = packed.instantiate()
	n.position = pos
	n.rotation = rot
	n.scale = Vector3.ONE * scl
	if parent == null:
		add_child(n)
	else:
		parent.add_child(n)
	return n


## Island 1's weapon shop: a bait shack you can actually walk into, standing on
## a flat foundation so it doesn't sink into the curved island.
## Levels a patch of the dome island and returns its height. The pad flares at
## the bottom so its edge is a ramp you can walk up, not a step.
func _flat_pad(x: float, z: float, top_r: float) -> float:
	var ground := _island_y(HOME, HOME_R, HOME_H, x, z)
	var pad := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = top_r
	pm.bottom_radius = top_r + 2.6
	pm.height = 1.8
	pm.radial_segments = 32
	pm.material = _mat(Color(0.78, 0.66, 0.43), 1.0)
	pad.mesh = pm
	pad.position = Vector3(x, ground - 0.9, z)
	add_child(pad)
	pad.create_trimesh_collision()
	return ground


## A painted sign: text in the world, facing -Z (toward the jetty) unless told.
func _sign(text: String, pos: Vector3, size := 72, yaw := PI, color := Color(0.16, 0.10, 0.05)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0055
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.rotation.y = yaw
	l.double_sided = false
	add_child(l)
	return l


## A wooden display stand with collision; returns the height of its top.
func _pedestal(pos: Vector3) -> float:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.52, 0.86, 0.52)
	bm.material = _mat(Color(0.40, 0.27, 0.17), 0.85)
	b.mesh = bm
	b.position = pos + Vector3(0, 0.43, 0)
	add_child(b)
	var cap := MeshInstance3D.new()
	var cpm := BoxMesh.new()
	cpm.size = Vector3(0.62, 0.06, 0.62)
	cpm.material = _mat(Color(0.64, 0.46, 0.30), 0.7)
	cap.mesh = cpm
	cap.position = pos + Vector3(0, 0.89, 0)
	add_child(cap)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.62, 0.92, 0.62)
	col.shape = bs
	body.add_child(col)
	body.position = pos + Vector3(0, 0.46, 0)
	add_child(body)
	return pos.y + 0.92


## Island 1's weapon shop: a bait shack you walk into. The interior is laid out
## from the shack's measured wall bounds, so nothing floats or sinks.
func _build_shop() -> void:
	var k := SHOP_SCALE / 0.27
	var ground := _flat_pad(SHOP_POS.x, SHOP_POS.z, 4.6 * k)

	# The shack, door facing back toward the jetty (-Z).
	shop_building = _spawn("shop_building", Vector3(SHOP_POS.x, ground, SHOP_POS.z), PI, SHOP_SCALE)
	var walls := AABB()
	for m in shop_building.find_children("*", "MeshInstance3D", true):
		var nm: String = m.name
		if nm.begins_with("Door"):
			m.visible = false
			continue
		if nm.begins_with("Shack_Walls"):
			walls = m.global_transform * m.mesh.get_aabb()
		if nm.begins_with("SignBoard"):
			var sb: AABB = m.global_transform * m.mesh.get_aabb()
			var c := sb.position + sb.size * 0.5
			_sign("BAIT & BLADE", Vector3(c.x, c.y, sb.position.z - 0.03), 76)
		if nm.begins_with("Shack_Walls") or nm.begins_with("Porch") or nm.begins_with("Shack_Roof"):
			m.create_trimesh_collision()

	# Inside faces of the room (door on the low-z wall).
	var floor_y := walls.position.y
	var x0 := walls.position.x + 0.30
	var x1 := walls.end.x - 0.30
	var z0 := walls.position.z + 0.30
	var z1 := walls.end.z - 0.30
	var cx := (x0 + x1) * 0.5
	shop_floor_y = floor_y
	shop_door_z = walls.position.z

	# Tackle counter as the back-wall display (rods, shelves, aquarium).
	shop_counter = _spawn("shop_counter", Vector3(cx, floor_y, z1 - 0.98), PI, COUNTER_SCALE)

	# Shopkeeper in the back corner beside his counter, facing the door.
	shopkeeper = _spawn_character("res://assets/models/characters/Barbarian.glb",
		Vector3(x1 - 0.42, floor_y, z1 - 0.50), PI - 0.25, "Idle")

	# Stock on its own stands, turned to face the middle of the room.
	var t1 := _pedestal(Vector3(x0 + 0.40, floor_y, z0 + 0.55))
	_add_weapon_display("dagger_A", Vector3(x0 + 0.40, t1, z0 + 0.55), Vector3(0, PI * 0.5, 0), 0.42)
	var t2 := _pedestal(Vector3(x0 + 0.40, floor_y, z0 + 1.55))
	_add_weapon_display("dagger_B", Vector3(x0 + 0.40, t2, z0 + 1.55), Vector3(0, PI * 0.5, 0), 0.42)
	var t3 := _pedestal(Vector3(x1 - 0.40, floor_y, z0 + 0.55))
	_add_weapon_display("fistweapon_A", Vector3(x1 - 0.40, t3, z0 + 0.55), Vector3(0, -PI * 0.5, 0), 0.55)
	# The best of the lot, mounted on the side wall above the stands.
	_add_weapon_display("axe_A", Vector3(x0 + 0.08, floor_y + 1.55, z0 + 1.05), Vector3(0, PI * 0.5, 0), 0.50)
	var t4 := _pedestal(Vector3(x1 - 0.40, floor_y, z0 + 1.55))
	_add_weapon_display("boss_reel", Vector3(x1 - 0.40, t4, z0 + 1.55), Vector3(0, 0, 0), 0.30)

	var ceil := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(walls.size.x, 0.12, walls.size.z)
	cm.material = _mat(Color(0.34, 0.24, 0.17), 1.0)
	ceil.mesh = cm
	ceil.position = Vector3(cx, floor_y + 3.25, (z0 + z1) * 0.5)
	add_child(ceil)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, floor_y + 2.7, (z0 + z1) * 0.5)
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 1.3
	lamp.omni_range = 7.5
	add_child(lamp)


## The fish market: a stall near the jetty where the buyer pays for your catch.
func _build_market() -> void:
	var g := _flat_pad(MARKET_POS.x, MARKET_POS.z, 3.4)
	# Front of the stall faces -X, toward the path up from the jetty.
	var stall := _spawn("market", Vector3(MARKET_POS.x, g, MARKET_POS.z), -PI * 0.5, MARKET_SCALE)
	for m in stall.find_children("*", "MeshInstance3D", true):
		if m.name.begins_with("Counter") or m.name.begins_with("Stand") or m.name.begins_with("Base"):
			m.create_trimesh_collision()
	# A solid box for the counter so you can't walk through the stall.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 1.2, 3.6)
	col.shape = bs
	body.add_child(col)
	body.position = Vector3(MARKET_POS.x, g + 0.6, MARKET_POS.z)
	add_child(body)
	market_ground = g

	var fm := _sign("FISH MARKET", Vector3(MARKET_POS.x - 0.2, g + 3.45, MARKET_POS.z), 92,
		-PI * 0.5, Color(1.0, 0.95, 0.85))
	fm.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # turns to face you
	fm.outline_size = 14
	fm.outline_modulate = Color(0.55, 0.18, 0.12)

	fish_buyer = _spawn_character("res://assets/models/characters/Knight.glb",
		Vector3(MARKET_POS.x + 1.15, g + 0.02, MARKET_POS.z), -PI * 0.5, "Idle")


## Sets off in the boat: out to the boss waters, or back to the jetty.
func _start_sail(out: bool) -> void:
	play_mode = "sailing"
	_sail_out = out
	_sail_t = 0.0
	_sail_from = boat.position
	_sail_to = BOSS_WATERS if out else BOAT_MOOR
	player.frozen = true
	player.visible = false
	touch.visible = false
	touch.prompt = ""
	if held_view:
		held_view.queue_free()
		held_view = null
	_flash("Sailing out..." if out else "Heading home...")
	_play("whoosh")


func _update_sail(delta: float) -> void:
	_sail_t = minf(_sail_t + delta / SAIL_TIME, 1.0)
	var k := _sail_t * _sail_t * (3.0 - 2.0 * _sail_t)   # ease in/out
	var pos := _sail_from.lerp(_sail_to, k)
	pos.y = BOAT_MOOR.y + wave_height(pos.x, pos.z)
	boat.position = pos
	# Point the bow along the trip, then settle back to facing out to sea.
	var dir := _sail_to - _sail_from
	var travel_yaw := atan2(-dir.x, -dir.z) + PI
	boat.rotation.y = lerp_angle(BOAT_YAW, travel_yaw, sin(k * PI))
	boat.rotation.z = sin(elapsed * 1.7) * 0.03
	# Ride in the boat, looking over the bow.
	var seat := boat.global_transform * Vector3(0, 5.6, -1.2)
	camera.global_position = seat
	camera.rotation = Vector3(-0.10, boat.rotation.y + PI, 0.0)
	if _sail_t >= 1.0:
		if _sail_out:
			_arrive_boss_waters()
		else:
			_arrive_home()


func _arrive_boss_waters() -> void:
	on_boat = true
	boat.rotation = Vector3(0, BOAT_YAW, 0)
	var b := boat.position
	fish_eye = Vector3(b.x, b.y + 2.55, b.z + 0.9)
	fish_tip = Vector3(b.x, 0.0, b.z - 3.3)
	whack_spot = Vector3(b.x, b.y + 0.95, b.z - 0.8)
	_enter_fishing()
	hud.message = "Something huge lives out here...\nCast and hold on tight!"


func _arrive_home() -> void:
	on_boat = false
	fish_eye = EYE
	fish_tip = DOCK_TIP
	whack_spot = WHACK_SPOT
	boat.position = BOAT_MOOR
	boat.rotation = Vector3(0, BOAT_YAW, 0)
	play_mode = "explore"
	player.frozen = false
	player.visible = true
	player.set_first_person(true)
	player.velocity = Vector3.ZERO
	player.position = Vector3(1.3, DECK_Y + 0.4, BOAT_MOOR.z)
	cam_yaw = PI
	cam_pitch = -0.12
	touch.visible = true
	_refresh_held_view()


## After the boss is sold: a lit buoy and sign marking the way to island 2.
func _show_island2_marker() -> void:
	if island2_marker:
		return
	island2_marker = Node3D.new()
	add_child(island2_marker)
	var spot := Vector3(-8.0, 0.0, -82.0)
	var flag := _spawn("buoy_flag", spot + Vector3(0, 0, 16.0), 0.0, 1.6, island2_marker)
	floaters.append(flag)
	var l := Label3D.new()
	l.text = "ISLAND 2\ncoming soon"
	l.font_size = 140
	l.pixel_size = 0.02
	l.outline_size = 22
	l.modulate = Color(1.0, 0.92, 0.55)
	l.outline_modulate = Color(0.25, 0.10, 0.05)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = spot + Vector3(0, 13.0, 0)
	island2_marker.add_child(l)


## Buoys ride the same waves the water shader draws.
func _update_floaters() -> void:
	if boat and play_mode != "sailing":
		boat.position.y = boat.position.y * 0.0 + BOAT_MOOR.y + wave_height(boat.position.x, boat.position.z)
		boat.rotation.z = sin(elapsed * 1.3) * 0.025
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
	player.visible = true
	player.set_first_person(true)
	player.frozen = false
	player.velocity = Vector3.ZERO
	player.position = PLAYER_SPAWN
	cam_yaw = 0.0
	cam_pitch = -0.12
	hud.enabled = false
	hud.set_hud_visible(false)
	touch.visible = true
	menu_ui.show_play()
	_refresh_held_view()
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
	var st: Dictionary = menu_ui.settings
	_camera_sway = st["camera_sway"]
	hud.left_handed = st["left_handed"]
	hud.recalc_layout()
	if touch:
		touch.crosshair = st.get("crosshair", true)
		touch.sens_scale = float(st.get("look_sens", 1.0))
		touch.hud_scale = float(st.get("hud_scale", 1.0))
		touch.hud_opacity = float(st.get("hud_opacity", 1.0))
		touch.fixed_joystick = bool(st.get("fixed_joystick", false))
		touch.apply_layout()
	if player:
		player.show_body = bool(st.get("show_body", true))
		player.set_first_person(player.first_person)
	_apply_graphics()


## Graphics preset: trades shadows, water detail, fog and anti-aliasing.
func _apply_graphics() -> void:
	if not menu_ui:
		return
	var q := str(menu_ui.settings.get("graphics", "High"))
	var want_shadows: bool = bool(menu_ui.settings.get("shadows", true)) and q != "Low"
	if sun_light:
		sun_light.shadow_enabled = want_shadows
	if world_env:
		world_env.fog_enabled = q != "Low"
	if water_mat:
		water_mat.set_shader_parameter("normal_scale", 0.12 if q == "Low" else (0.28 if q == "Medium" else 0.38))
		water_mat.set_shader_parameter("foam_width", 0.0 if q == "Low" else 0.16)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_DISABLED if q == "Low" else (Viewport.MSAA_2X if q == "Medium" else Viewport.MSAA_4X)


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
	cast_to = fish_tip + fwd * dist
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
	if on_boat:
		pending_fish = BOSS
		fish_strength = 2.4
		distance = 1.0
		tension = 0.30
		lunge_timer = randf_range(0.7, 1.4)
		state = FIGHT
		hud.mode = Hud.M_FIGHT
		hud.message = "IT'S THE BABY KRAKEN!"
		return
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
	_refresh_whack_tool()
	paddle.visible = true
	cam_pitch_target = -36.0

	pending_weight = lerpf(pending_fish["min"], pending_fish["max"], randf())
	catches += 1
	if pending_weight > best_weight:
		best_weight = pending_weight
		best_name = pending_fish["name"]

	# Coin value: by weight; crates/barrels are near-worthless, chests are not.
	if pending_fish.get("boss", false):
		pending_value = BOSS_VALUE
	elif pending_fish.get("treasure", false):
		pending_value = 70 + randi() % 110
	elif pending_fish.get("prize", false):
		pending_value = maxi(1, int(round(pending_weight * 32.0)))
	elif pending_fish.get("junk", false):
		pending_value = 1 + randi() % 3
	else:
		pending_value = maxi(1, int(round(pending_weight * 14.0)))

	# Heavier catches take more whacks.
	whacks_left = clampi(1 + int(round(pending_weight * 0.9)) - weapon_power(), 1, 5)
	if pending_fish.get("boss", false):
		whacks_left = 6 - weapon_power()
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
	held.append({
		"name": pending_fish["name"], "weight": pending_weight, "value": pending_value,
		"set": pending_fish.get("set", "river"), "node": pending_fish.get("node", ""),
		"boss": pending_fish.get("boss", false),
	})
	if pending_fish.get("boss", false):
		hud.message = "YOU LANDED THE BABY KRAKEN!\nSail back and sell it at the market"
		_play("caught")
		_save_game()
		_update_info()
		return
	_save_game()
	var line2 := "Hands full - sell at the market" if held.size() >= MAX_CARRY \
		else "Carrying %d of %d  -  keep fishing or go sell" % [held.size(), MAX_CARRY]
	hud.message = "Into the bag!  worth %d\n%s" % [pending_value, line2]
	_play("caught")
	_update_info()


## The thing in your hand when you whack: your equipped weapon, or the old
## paddle if you haven't bought one yet.
func _refresh_whack_tool() -> void:
	for c in paddle.get_children():
		c.queue_free()
	var m: Node3D
	if equipped_weapon != "" and ResourceLoader.exists(WEAPON_DIR + equipped_weapon + ".gltf"):
		m = load(WEAPON_DIR + equipped_weapon + ".gltf").instantiate()
		m.scale = Vector3.ONE * 0.62
		m.rotation_degrees = Vector3(0, 90, -40)
	else:
		m = load(MDL["paddle"]).instantiate()
		m.scale = Vector3.ONE * 0.40
		m.rotation_degrees = Vector3(0, 0, -38)
	paddle.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## What you're carrying, shown in your right hand while walking around.
func _refresh_held_view() -> void:
	if held_view:
		held_view.queue_free()
		held_view = null
	if touch:
		if held.is_empty():
			touch.carry_info = ""
		else:
			var total := 0
			for h in held:
				total += int(h["value"])
			touch.carry_info = "Carrying %d/%d  -  worth %d" % [held.size(), MAX_CARRY, total]
	if held.is_empty() or play_mode != "explore" or app_state != "playing":
		return
	var top: Dictionary = held[held.size() - 1]
	held_view = _make_fish(top, 4.5 if top.get("boss", false) else minf(float(top["weight"]), 2.5))
	held_view.scale *= 0.75
	held_view.position = Vector3(0.40, -0.46, -0.78)
	held_view.rotation = Vector3(0.25, 0.65, -0.15)
	camera.add_child(held_view)
	for mi in held_view.find_children("*", "MeshInstance3D", true):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sell_all() -> void:
	var total := 0
	var sold_boss := false
	for h in held:
		total += int(h["value"])
		if h.get("boss", false):
			sold_boss = true
	var n := held.size()
	coins += total
	held.clear()
	_save_game()
	_update_info()
	_refresh_held_view()
	_flash("Sold %d for %d coins!" % [n, total])
	_play("caught")
	if sold_boss and not island2_unlocked:
		island2_unlocked = true
		_save_game()
		_show_island2_marker()
		hud.message = ""
		_flash("The buyer hands you a map - ISLAND 2 unlocked!")
	var ap = fish_buyer.get_meta("anim") if fish_buyer and fish_buyer.has_meta("anim") else null
	if ap and ap.has_animation("Cheer"):
		ap.play("Cheer")


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
		caught_fish.position.y = whack_spot.y + hop * 0.28
		caught_fish.scale = _catch_base_scale * Vector3(1.0 + hop * 0.18, 1.0 - hop * 0.22, 1.0 + hop * 0.18)
		caught_fish.rotation.z = sin(elapsed * 14.0) * 0.07 * (0.3 + hop)


## Drops the catch onto the deck in front of the player, lying side-on so its
## face and tail both read, scaled by how heavy it is.
func _show_catch(info: Dictionary) -> void:
	if caught_fish:
		caught_fish.queue_free()
	caught_fish = _make_fish(info, pending_weight)
	_catch_base_scale = caught_fish.scale
	caught_fish.position = whack_spot
	caught_fish.rotation = Vector3.ZERO  # models lie along X: side-on to the camera
	add_child(caught_fish)


## Pulls one species (or one piece of junk) out of its set by node name and
## sizes it by weight, so every catch is a real model rather than a stand-in.
func _make_fish(info: Dictionary, weight: float) -> Node3D:
	var holder := Node3D.new()
	var set_key := str(info.get("set", "river"))
	var node_name := str(info.get("node", ""))
	var path := str(CATCH_SETS.get(set_key, CATCH_SETS["river"]))
	if node_name == "" or not ResourceLoader.exists(path):
		return holder

	var root: Node3D = load(path).instantiate()
	var target := root.find_child(node_name, true, false)
	if target == null:
		root.queue_free()
		return holder
	# Lift just this species out of the set and throw the rest away.
	target.get_parent().remove_child(target)
	holder.add_child(target)
	root.queue_free()
	if target is Node3D:
		(target as Node3D).transform = Transform3D.IDENTITY

	# Lay it flat: whichever axis is longest becomes the fish's length, pointing
	# along X so it lies across the deck rather than standing on its tail.
	var t := target as Node3D
	var box0 := _local_aabb(holder)
	if box0.size.y >= box0.size.x and box0.size.y >= box0.size.z:
		t.rotation = Vector3(0, 0, PI * 0.5)
	elif box0.size.z >= box0.size.x and box0.size.z >= box0.size.y:
		t.rotation = Vector3(0, PI * 0.5, 0)

	# Size by weight, then sit it on the deck, centred.
	var box := _local_aabb(holder)
	var longest: float = maxf(maxf(box.size.x, box.size.y), box.size.z)
	if longest > 0.0001:
		var want: float = clampf(0.38 + weight * 0.15, 0.38, 1.35)
		if info.get("boss", false):
			want = 1.7
		holder.scale = Vector3.ONE * (want / longest)
		t.position -= Vector3(box.position.x + box.size.x * 0.5,
			box.position.y, box.position.z + box.size.z * 0.5)
	return holder


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
			cam_yaw = test_yaw
		touch.sprint = test_sprint
		_test_max_speed = maxf(_test_max_speed, Vector2(player.velocity.x, player.velocity.z).length())
		if frame < 30:
			touch.move = Vector2.ZERO
		elif frame < 30 + test_walk:
			touch.move = Vector2(0, -1)
		else:
			touch.move = Vector2.ZERO
		if frame >= 30 + test_walk + 20:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST(explore) pos=%s on_floor=%s prompt='%s' anim=%s max_speed=%.2f" % [
				player.position.snapped(Vector3.ONE * 0.01), player.is_on_floor(),
				touch.prompt, player._cur, _test_max_speed])
			get_tree().quit()
		return

	# Full boss chain: sail -> fish -> land -> sail home -> walk -> sell.
	if start_screen == "boss":
		if frame == 20:
			print("AUTOTEST reel=%s coins=%d near_boat=%s prompt='%s'" % [has_boss_reel, coins, near_boat, touch.prompt])
			_on_interact()
		if play_mode == "fishing" and on_boat:
			match state:
				IDLE, CHARGING: sim_action = power < 0.75
				BITE: sim_tap = true
				FIGHT:
					sim_action = tension < 0.70
					distance = max(distance - 0.02, 0.0)
				WHACK:
					if frame % 14 == 0: sim_tap = true
				CAUGHT:
					if not _boss_logged:
						_boss_logged = true
						print("AUTOTEST landed: held=%s" % [held.map(func(h): return h["name"])])
						if autotest_shot != "":
							get_viewport().get_texture().get_image().save_png(autotest_shot.replace(".png", "_landed.png"))
					if frame % 30 == 0:
						_leave_fishing()
		if play_mode == "explore" and _boss_logged and not _boss_sold:
			player.position = Vector3(SELL_SPOT.x - 1.0, market_ground + 0.3, SELL_SPOT.z)
			_boss_sold = true
			_boss_sell_frame = frame + 15
		if _boss_sold and frame == _boss_sell_frame:
			_update_explore(0.016)
			_on_interact()
			print("AUTOTEST sold -> coins=%d island2=%s held=%d" % [coins, island2_unlocked, held.size()])
			cam_yaw = PI
			cam_pitch = 0.05
			player.position = Vector3(0, DECK_Y + 0.4, 4.0)
		if _boss_sold and frame == _boss_sell_frame + 20:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			get_tree().quit()
		if frame > autotest_frames:
			print("AUTOTEST boss TIMEOUT mode=%s state=%d on_boat=%s" % [play_mode, state, on_boat])
			get_tree().quit()
		return

	# Exercise a real purchase through the crosshair, not a menu.
	if start_screen == "weaponshop":
		if frame == 20:
			print("AUTOTEST looking at '%s'  prompt='%s'  info='%s'" % [looked_weapon, touch.prompt, touch.look_info])
		if frame == 26:
			_on_interact()
			print("AUTOTEST after buy -> coins=%d owned=%s equipped=%s" % [coins, owned_weapons, equipped_weapon])
		if frame == 32:
			_on_interact()
			print("AUTOTEST after 2nd press (equip toggle) -> equipped='%s'" % equipped_weapon)

	if start_screen == "sell":
		if frame == 25:
			print("AUTOTEST near_market=%s prompt='%s' carry='%s'" % [near_market, touch.prompt, touch.carry_info])
		if frame == 40 and autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		if frame == 42:
			_on_interact()
			print("AUTOTEST after sell -> coins=%d held=%d" % [coins, held.size()])
		if frame >= 50:
			get_tree().quit()
		return

	if start_screen in ["menu", "settings", "pause", "shop", "help", "weaponshop", "legs", "shopview"]:
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
