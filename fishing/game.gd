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
const StatusUI := preload("res://status_ui.gd")

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

# Health / breath
const MAX_HEALTH := 100.0
const BREATH_SECONDS := 6.0
var health := MAX_HEALTH
var breath := 1.0
var _since_hit := 99.0
var status
var _death_t := 0.0
var _death_roll_dir := 1.0
var reel_click_t := 0.0
var floaters: Array[Node3D] = []  # buoys etc. that ride the waves
var sun_light: DirectionalLight3D
var grass_mm: MultiMeshInstance3D
var flower_mm: MultiMeshInstance3D
var clouds: Array = []
var rain: CPUParticles3D
var _weather_t := 60.0
var _raining := false
var _rain_amt := 0.0
var weather_enabled := true
var world_env: Environment
var sky_mat: ProceduralSkyMaterial
var _sky_rain := -1.0
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
var held: Array = []              # legacy save data only (migrated to loose fish)
var held_view: Node3D             # unused; kept so old references stay valid

# Physical catches: every landed fish is a RigidBody3D you can grab and carry.
const FISH_LAYER := 8
var loose_fish: Array = []        # RigidBody3D, each with meta "fish" (its data)
var holding: RigidBody3D = null   # the fish in your hands
var shop_lamp: OmniLight3D
var _static_props: Array = []    # multi-part models to batch into few draws
var _shop_box := AABB()
var hands: FPHands                # first-person hands (camera child)
var _reach := 0.0
var _hands_enabled := true
var fx: WorldFX
var _surf: AudioStreamPlayer
var _step_dist := 0.0
var _gull_t := 8.0
var looked_fish: RigidBody3D = null
var _pending_loose: Array = []    # from the save, spawned once the world exists
var boat_deck: AnimatableBody3D
var _cargo: Array = []            # [body, local offset] riding the boat
var _hold_far_t := 0.0

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
var _flop_timer := 0.0
var _windup := 0.0
var _leap_t := 0.0
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
const NEW_SPECIES_BONUS := 15
const BOSS := {"name": "the Baby Kraken", "set": "mythic", "node": "BabyKraken",
	"min": 18.0, "max": 26.0, "junk": false, "boss": true,
	"rarity": "Legendary", "atk": 30, "spd": 1.6, "tier": 0}
const BOSS_VALUE := 650

# Every catch is a real model pulled out of one of the sets above by node name.
# price = coins per kg, atk = damage when it leaps at you, spd = how hard it
# fights and how often it flops, tier = reel level needed before it can bite.
var fish_table := [
	{"name": "Minnow", "set": "rarity", "node": "Fish_Minnow", "min": 0.05, "max": 0.30,
	 "rarity": "Common", "price": 30, "atk": 3, "spd": 0.8, "tier": 0},
	{"name": "Perch", "set": "rarity", "node": "Fish_Perch", "min": 0.25, "max": 1.10,
	 "rarity": "Common", "price": 14, "atk": 5, "spd": 0.9, "tier": 0},
	{"name": "Sunfish", "set": "river", "node": "Fish_Sunfish", "min": 0.30, "max": 1.40,
	 "rarity": "Common", "price": 13, "atk": 5, "spd": 0.85, "tier": 0},
	{"name": "Trout", "set": "rarity", "node": "Fish_Trout", "min": 0.50, "max": 2.20,
	 "rarity": "Uncommon", "price": 17, "atk": 8, "spd": 1.1, "tier": 0},
	{"name": "Bass", "set": "river", "node": "Fish_Bass", "min": 0.80, "max": 3.20,
	 "rarity": "Uncommon", "price": 16, "atk": 10, "spd": 1.15, "tier": 0},
	{"name": "Carp", "set": "river", "node": "Fish_Carp", "min": 1.20, "max": 4.50,
	 "rarity": "Rare", "price": 19, "atk": 13, "spd": 1.2, "tier": 1},
	{"name": "Catfish", "set": "rarity", "node": "Fish_Catfish", "min": 1.80, "max": 6.00,
	 "rarity": "Rare", "price": 18, "atk": 15, "spd": 1.3, "tier": 1},
	{"name": "Pike", "set": "river", "node": "Fish_Pike", "min": 2.00, "max": 7.50,
	 "rarity": "Epic", "price": 26, "atk": 21, "spd": 1.55, "tier": 2},
	{"name": "Golden Koi", "set": "rarity", "node": "Fish_Golden", "min": 3.00, "max": 9.00,
	 "rarity": "Legendary", "price": 62, "atk": 28, "spd": 1.8, "tier": 3},
	{"name": "an Old Boot", "set": "junk", "node": "Boot_Old", "min": 0.60, "max": 1.20,
	 "rarity": "Common", "junk": true, "flat": 3, "atk": 0, "spd": 0.5, "tier": 0},
	{"name": "a Rusty Tin", "set": "junk", "node": "TinCan_Rusty", "min": 0.20, "max": 0.50,
	 "rarity": "Common", "junk": true, "flat": 2, "atk": 0, "spd": 0.4, "tier": 0},
	{"name": "an Old Tyre", "set": "junk", "node": "Tyre_Seaweed", "min": 2.00, "max": 4.00,
	 "rarity": "Common", "junk": true, "flat": 5, "atk": 0, "spd": 0.9, "tier": 0},
	{"name": "a Message in a Bottle", "set": "junk", "node": "Bottle_Message", "min": 0.30, "max": 0.60,
	 "rarity": "Uncommon", "junk": true, "flat": 25, "atk": 0, "spd": 0.4, "tier": 0},
	{"name": "a Sunken Chest", "set": "junk", "node": "Chest_Barnacle", "min": 2.50, "max": 5.00,
	 "rarity": "Rare", "junk": true, "treasure": true, "flat": 120, "atk": 0, "spd": 1.0, "tier": 1},
]
const RARITY_WEIGHT := {"Common": 58.0, "Uncommon": 27.0, "Rare": 10.0, "Epic": 4.0, "Legendary": 1.0}
# Each reel level makes the rarer bands bite more often.
const RARITY_REEL_BOOST := {"Common": 1.0, "Uncommon": 1.12, "Rare": 1.32, "Epic": 1.55, "Legendary": 1.8}

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
	"rod":  {"name": "Reel", "desc": "Rarer fish bite, longer casts", "levels": 5, "cost": 60},
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
var journal := {}              # species name -> [times caught, best kg]
var _new_species := false
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
		_pending_loose = cfg.get_value("save", "loose", [])
		has_boss_reel = bool(cfg.get_value("save", "has_boss_reel", false))
		island2_unlocked = bool(cfg.get_value("save", "island2_unlocked", false))
		journal = cfg.get_value("save", "journal", {})
		if journal.is_empty() and catches > 0:
			# Older save: start the journal from what we know you've caught.
			if best_name != "":
				journal[best_name] = [1, best_weight]
			for d in _pending_loose:
				var nm := str(d.get("name", ""))
				if nm != "":
					var e: Array = journal.get(nm, [0, 0.0])
					journal[nm] = [int(e[0]) + 1, maxf(float(e[1]), float(d.get("weight", 0.0)))]
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
	cfg.set_value("save", "held", [])
	var loose_out: Array = []
	for b in loose_fish:
		if is_instance_valid(b):
			var d: Dictionary = (b.get_meta("fish") as Dictionary).duplicate()
			d["pos"] = [b.global_position.x, b.global_position.y, b.global_position.z]
			loose_out.append(d)
	cfg.set_value("save", "loose", loose_out)
	cfg.set_value("save", "has_boss_reel", has_boss_reel)
	cfg.set_value("save", "island2_unlocked", island2_unlocked)
	cfg.set_value("save", "journal", journal)
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
var test_rain := false
var _test_whack_f := 0
var _test_max_speed := 0.0
var _boss_logged := false
var _flop_seen := false
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

	status = StatusUI.new()
	add_child(status)
	status.respawn_pressed.connect(_respawn)

	touch = TouchControls.new()
	add_child(touch)
	touch.interact_pressed.connect(_on_interact)
	touch.secondary_pressed.connect(_on_secondary)
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
				player.position = Vector3(SELL_SPOT.x - 1.4, market_ground + 0.3, SELL_SPOT.z)
				cam_yaw = -PI * 0.5   # face +X, toward the buyer
				cam_pitch = -0.10
				var tb := _spawn_loose_fish({"name": "Bass", "weight": 2.1, "value": 34,
					"rarity": "Uncommon", "set": "river", "node": "Fish_Bass"},
					player.position + Vector3(0.6, 1.2, 0.0), 0.0)
				_grab(tb)
				# and one tossed straight onto the counter
				_spawn_loose_fish({"name": "Trout", "weight": 1.4, "value": 24,
					"rarity": "Uncommon", "set": "rarity", "node": "Fish_Trout"},
					Vector3(MARKET_POS.x, market_ground + 1.5, MARKET_POS.z + 0.6), 0.0)
			"flop":
				_start_play()
				_enter_fishing()
				pending_fish = fish_table[6]   # Catfish: Rare, atk 15
				_land_fish()
			"drown":
				_start_play()
				player.position = Vector3(0, -5.0, -4.0)
				cam_yaw = PI
				cam_pitch = 0.0
			"legs":
				_start_play()
				cam_pitch = -1.30
			"settings": _go_main_menu(); menu_ui.open_settings_for_test()
			"pause": _start_play(); _pause()
			"help": _go_main_menu(); menu_ui.open_help_for_test()
			"journal":
				_go_main_menu()
				_update_info()
				menu_ui.open_journal_for_test()
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
		elif a == "--rain": test_rain = true


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
	sky_mat = ProceduralSkyMaterial.new()
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
	# Distance haze: clear up close, the far islands fade into a soft grey-blue.
	env.fog_enabled = true
	env.fog_light_color = Color(0.52, 0.61, 0.70)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0085
	env.fog_sky_affect = 0.55
	env.fog_height = -1.5
	env.fog_height_density = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	world_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.02
	sun.light_color = Color(1.0, 0.93, 0.78)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
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
	var bed_body := StaticBody3D.new()
	var bed_col := CollisionShape3D.new()
	bed_col.shape = WorldBoundaryShape3D.new()
	bed_body.add_child(bed_col)
	bed_body.position = Vector3(0, -7.0, 0)
	add_child(bed_body)

	# Water: a big subdivided plane running the stylized water shader.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	plane.subdivide_width = 110       # ~2.7 m quads: plenty for 9 m waves
	plane.subdivide_depth = 110
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
	_optimize_world()
	fx = WorldFX.new()
	fx.gull_centre = HOME
	add_child(fx)


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
	var outer := radius * 1.6
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
	var noise := FastNoiseLite.new()
	noise.seed = int(center.x * 13.0 + center.z * 7.0)
	noise.frequency = 0.09
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
		# patchy variation so the ground isn't one flat colour
		var n := noise.get_noise_2d(v.x, v.z)
		c = c.lightened(maxf(n, 0.0) * 0.16).darkened(maxf(-n, 0.0) * 0.18)
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
	# A deck to stand catches on; moved with the boat.
	boat_deck = AnimatableBody3D.new()
	boat_deck.sync_to_physics = false   # we place it directly every frame
	var dcol := CollisionShape3D.new()
	var dbox := BoxShape3D.new()
	dbox.size = Vector3(2.0, 0.4, 5.0)
	dcol.shape = dbox
	boat_deck.add_child(dcol)
	add_child(boat_deck)
	_sync_deck()

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
	_static_props.append(_spawn("tower", Vector3(3.0, ty - 0.2, 42.0), -0.5, 1.2))

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
	_build_grass()
	_build_clouds()
	_build_weather()
	if island2_unlocked:
		_show_island2_marker()
	for d in _pending_loose:
		var pp: Array = d.get("pos", [0, 1.5, 15])
		var pos := Vector3(float(pp[0]), float(pp[1]) + 0.2, float(pp[2]))
		if _hdist(pos, HOME) > 34.0:      # was out at sea when saved
			pos = Vector3(randf_range(-0.6, 0.6), DECK_Y + 0.5, randf_range(14.0, 17.0))
		_spawn_loose_fish(d, pos, randf() * TAU)
	for d in held:
		_spawn_loose_fish(d, Vector3(randf_range(-0.6, 0.6), DECK_Y + 0.5, randf_range(14.0, 17.0)), randf() * TAU)
	held = []
	_pending_loose = []

	# A wrecked ship on the horizon for silhouette.
	_static_props.append(_spawn("wreck", Vector3(-38, -1.0, -60), 0.7, 1.3))

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
	rod.position = Vector3(0.40, -0.36, -0.70)
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
	gm.top_radius = 0.03
	gm.bottom_radius = 0.034
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

	# First-person hands, with a reel on the rod for the left hand to crank.
	hands = FPHands.new()
	camera.add_child(hands)
	hands.attach_reel(rod)
	hands.paddle = paddle

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
		"bonk": Sfx.bonk(), "hurt": Sfx.hurt(), "coins": Sfx.coins(),
		"step_soft": Sfx.step_soft(), "step_wood": Sfx.step_wood(), "gull": Sfx.gull(),
	}
	for key in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		add_child(p)
		players[key] = p
	players["step_soft"].volume_db = -9.0
	players["step_wood"].volume_db = -6.0
	players["gull"].volume_db = -10.0
	# The sea, always there in the background.
	_surf = AudioStreamPlayer.new()
	_surf.stream = Sfx.surf_loop()
	_surf.volume_db = -16.0
	_surf.autoplay = true
	add_child(_surf)


func _play(key: String) -> void:
	if players.has(key):
		players[key].play()


# --- State helpers ------------------------------------------------------------

func _enter_idle() -> void:
	state = IDLE
	_windup = 0.0
	_leap_t = 0.0
	if hud:
		hud.clear_card()
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
		var landed_boss := island2_unlocked
		for b in loose_fish:
			if is_instance_valid(b) and (b.get_meta("fish") as Dictionary).get("boss", false):
				landed_boss = true
		menu_ui.set_menu_stats({
			"Coins": coins,
			"Catches": catches,
			"Best catch": "%s %.1f kg" % [_short_name(best_name), best_weight] if best_name != "" else "-",
			"Boss": "Landed!" if landed_boss else ("Hunting" if has_boss_reel else "Need Boss Reel"),
			"Next island": "Unlocked" if island2_unlocked else "Locked",
			"Where": "Island 1  -  Bait Bay",
		})
		var entries: Array = []
		for f in fish_table + [BOSS]:
			var nm := str(f["name"])
			var e: Array = journal.get(nm, [0, 0.0])
			entries.append({"name": nm.substr(0, 1).to_upper() + nm.substr(1),
				"rarity": str(f.get("rarity", "Common")), "count": int(e[0]), "best": float(e[1]),
				"junk": f.get("junk", false), "price": int(f.get("price", f.get("flat", 0)))})
		menu_ui.set_journal(entries)


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	if autotest:
		_autotest(delta)

	# Pause from the in-game button.
	if app_state == "playing" and menu_ui and menu_ui.consume_pause():
		_pause()

	_update_floaters()
	_update_health(delta)
	_update_weather(delta)
	_update_hands(delta)

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
	if play_mode == "dead":
		_update_death(delta)
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
			_update_flop(delta)
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

	# Water: wade slower, and with your head under you run out of air.
	var surface := wave_height(player.global_position.x, player.global_position.z)
	var depth := surface - player.global_position.y
	player.wading = depth > 0.55
	var eye_y := player.global_position.y + EYE_HEIGHT
	var under := eye_y < surface - 0.05
	status.underwater = under
	if under:
		breath = maxf(breath - delta / BREATH_SECONDS, 0.0)
		if breath <= 0.0:
			_take_damage(18.0 * delta, "drowned", false)
	else:
		breath = minf(breath + delta * 0.7, 1.0)
	status.show_breath = breath < 0.995
	if player.position.y < -14.0:
		player.velocity = Vector3.ZERO
		player.position = PLAYER_SPAWN

	# Sit the camera a little ahead of the chest so looking down shows your own
	# body and legs rather than the inside of your shoulders.
	var fwd := (Basis(Vector3.UP, cam_yaw) * Vector3(0, 0, -1)).normalized()
	camera.global_position = player.global_position + Vector3(0, EYE_HEIGHT, 0) + fwd * 0.26
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

	_update_look()
	_update_fish_look()
	_refresh_held_view()
	_update_ambience(delta, surface, depth)

	near_fishing_spot = _hdist(player.global_position, FISHING_SPOT) < 3.0
	near_market = _hdist(player.global_position, SELL_SPOT) < 2.6
	near_boat = boat != null and _hdist(player.global_position, BOAT_MOOR) < 3.8
	var was_near := near_shop
	near_shop = _hdist(player.global_position, SHOP_TALK_SPOT) < 3.4
	if shop_lamp:
		shop_lamp.visible = _hdist(player.global_position, SHOP_POS) < 11.0
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
		touch.secondary = ""
		if holding:
			var hd: Dictionary = holding.get_meta("fish")
			if near_market:
				touch.prompt = "SELL"
				touch.secondary = "DROP"
			else:
				touch.prompt = "DROP"
				touch.secondary = "THROW"
		elif looked_fish and is_instance_valid(looked_fish):
			var fd: Dictionary = looked_fish.get_meta("fish")
			var rar := str(fd.get("rarity", "Common"))
			touch.look_info = str(fd.get("name", "")).capitalize() if str(fd.get("name", "")).begins_with("a") else str(fd.get("name", ""))
			touch.look_stat = "%s  ·  %.1f kg" % [rar, float(fd.get("weight", 0))]
			touch.look_cost = "%d" % int(fd.get("value", 0))
			touch.prompt = "GRAB"
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
	if holding:
		if near_market:
			if hands:
				hands.play_throw()
			_sell_body(holding)
		else:
			_drop_holding()
		return
	if looked_fish:
		_grab(looked_fish)
		return
	if near_boat:
		if not has_boss_reel:
			_flash("You need the Boss Reel from Bait & Blade")
			_play("snap")
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


func _on_secondary() -> void:
	if app_state != "playing" or play_mode != "explore" or holding == null:
		return
	_drop_holding(touch.secondary == "THROW")


## Crosshair on a loose catch (when not already on shop stock).
func _update_fish_look() -> void:
	var found: RigidBody3D = null
	if looked_weapon == "" and holding == null:
		var space := get_world_3d().direct_space_state
		var from: Vector3 = camera.global_position
		var to: Vector3 = from - camera.global_transform.basis.z * 3.2
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = FISH_LAYER
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] is RigidBody3D and hit["collider"].has_meta("fish"):
			found = hit["collider"]
	if found != looked_fish:
		_set_fish_outline(looked_fish, false)
		_set_fish_outline(found, true)
		looked_fish = found


## The shopkeeper waves when you come in.
func _greet_shopkeeper() -> void:
	var ap = shopkeeper.get_meta("anim") if shopkeeper and shopkeeper.has_meta("anim") else null
	if ap and ap.has_animation("Cheer"):
		ap.play("Cheer")
		_greet_timer = 2.0


func _enter_fishing() -> void:
	_drop_holding()
	_set_fish_outline(looked_fish, false)
	looked_fish = null
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
	shop_lamp = lamp
	_shop_box = walls.grow(0.2)


## The fish market: a stall near the jetty where the buyer pays for your catch.
func _build_market() -> void:
	var g := _flat_pad(MARKET_POS.x, MARKET_POS.z, 3.4)
	# Front of the stall faces -X, toward the path up from the jetty.
	var stall := _spawn("market", Vector3(MARKET_POS.x, g, MARKET_POS.z), -PI * 0.5, MARKET_SCALE)
	_static_props.append(stall)
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

	var fm := _sign("FISH MARKET", Vector3(MARKET_POS.x - 0.2, g + 3.45, MARKET_POS.z), 58,
		-PI * 0.5, Color(1.0, 0.95, 0.85))
	fm.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # turns to face you
	fm.outline_size = 14
	fm.outline_modulate = Color(0.55, 0.18, 0.12)

	fish_buyer = _spawn_character("res://assets/models/characters/Knight.glb",
		Vector3(MARKET_POS.x + 1.15, g + 0.02, MARKET_POS.z), -PI * 0.5, "Idle")


func _sync_deck() -> void:
	if boat and boat_deck:
		boat_deck.global_position = boat.global_position + Vector3(0, 0.74, 0)
		boat_deck.rotation = boat.rotation


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
	_drop_holding()
	# Anything lying on the boat comes along for the ride.
	_cargo.clear()
	for b in loose_fish:
		if is_instance_valid(b) and _hdist(b.global_position, boat.global_position) < 4.0 \
				and b.global_position.y > -0.3:
			b.freeze = true
			_cargo.append([b, boat.to_local(b.global_position)])
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
	_sync_deck()
	for c in _cargo:
		if is_instance_valid(c[0]):
			(c[0] as RigidBody3D).global_position = boat.to_global(c[1])
	# Ride in the boat, looking over the bow.
	var seat := boat.global_transform * Vector3(0, 5.6, -1.2)
	camera.global_position = seat
	camera.rotation = Vector3(-0.10, boat.rotation.y + PI, 0.0)
	if _sail_t >= 1.0:
		if _sail_out:
			_arrive_boss_waters()
		else:
			_arrive_home()


func _release_cargo() -> void:
	_sync_deck()
	for c in _cargo:
		if is_instance_valid(c[0]):
			var b: RigidBody3D = c[0]
			b.global_position = boat.to_global(c[1]) + Vector3(0, 0.15, 0)
			b.freeze = false
	_cargo.clear()


func _arrive_boss_waters() -> void:
	on_boat = true
	boat.rotation = Vector3(0, BOAT_YAW, 0)
	_release_cargo()
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
	_release_cargo()
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


## Health ticks back up once you've been out of trouble for a few seconds.
func _update_health(delta: float) -> void:
	if status == null:
		return
	status.visible_bars = app_state == "playing" and play_mode != "dead"
	if app_state != "playing":
		status.underwater = false
		return
	_since_hit += delta
	if _since_hit > 4.0 and play_mode != "dead" and not status.underwater:
		health = minf(health + 3.0 * delta, MAX_HEALTH)
	status.health = health
	status.breath = breath


func _take_damage(amount: float, cause: String, flash := true) -> void:
	if play_mode == "dead" or app_state != "playing":
		return
	health = maxf(health - amount, 0.0)
	_since_hit = 0.0
	if hands:
		hands.play_hit()
	if flash:
		status.hit(amount)
		_play("hurt")
	if health <= 0.0:
		_die(cause)


## You've had it: drop what you're holding, lose a little money, fall over.
func _die(cause: String) -> void:
	var was_fishing := play_mode == "fishing"
	play_mode = "dead"
	_death_t = 0.0
	_death_roll_dir = 1.0 if randf() < 0.5 else -1.0
	player.frozen = true
	touch.visible = false
	touch.prompt = ""
	hud.enabled = false
	hud.set_hud_visible(false)
	if was_fishing:
		state = IDLE
		if caught_fish:
			caught_fish.queue_free()
			caught_fish = null
		rod.visible = false
		paddle.visible = false
		bobber.visible = false
		line.visible = false
	_drop_holding()
	var lost := int(coins * 0.10)
	coins -= lost
	_save_game()
	_update_info()
	var title := "YOU DROWNED" if cause == "drowned" else "KNOCKED OUT"
	var sub := "Lost %d coins" % lost
	if cause != "drowned":
		sub = "%s.   Lost %d coins" % [cause.capitalize(), lost]
	status.show_death(title, sub)
	_play("snap")


func _update_death(delta: float) -> void:
	_death_t += delta
	var k := clampf(_death_t / 1.1, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	camera.rotation.z = lerpf(camera.rotation.z, _death_roll_dir * 1.35, e * 0.25)
	camera.rotation.x = lerpf(camera.rotation.x, -0.15, e * 0.15)
	camera.position.y -= delta * 0.9 * (1.0 - k)


func _respawn() -> void:
	health = MAX_HEALTH
	breath = 1.0
	_since_hit = 99.0
	status.underwater = false
	if on_boat:
		on_boat = false
		fish_eye = EYE
		fish_tip = DOCK_TIP
		whack_spot = WHACK_SPOT
		boat.position = BOAT_MOOR
		boat.rotation = Vector3(0, BOAT_YAW, 0)
	_enter_idle()
	play_mode = "explore"
	player.frozen = false
	player.visible = true
	player.set_first_person(true)
	player.velocity = Vector3.ZERO
	player.position = PLAYER_SPAWN
	cam_yaw = PI
	cam_pitch = -0.12
	camera.rotation = Vector3.ZERO
	touch.visible = true
	_refresh_held_view()


## Grass tufts and wildflowers scattered over the green part of the home
## island, drawn as two MultiMeshes with a wind shader. Kept off the shop and
## market pads and the path up from the jetty.
func _tuft_mesh(blades: int, height: float, base_col: Color, tip_col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a := TAU * float(i) / float(blades) + randf() * 0.6
		var lean := Vector3(cos(a), 0, sin(a)) * randf_range(0.04, 0.10)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.035
		var h := height * randf_range(0.7, 1.15)
		var root := Vector3(cos(a), 0, sin(a)) * 0.03
		var tip := root + lean + Vector3(0, h, 0)
		var verts := [root - side, root + side, tip]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)]
		var cols := [base_col, base_col, tip_col]
		for k in 3:
			st.set_color(cols[k])
			st.set_uv(uvs[k])
			st.set_normal(Vector3.UP)
			st.add_vertex(verts[k])
	return st.commit()


func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.30, 0.56, 0.24)
	var h := 0.26
	# stem
	for v in [[Vector3(-0.012, 0, 0), 0.0], [Vector3(0.012, 0, 0), 0.0], [Vector3(0, h, 0), 1.0]]:
		st.set_color(stem)
		st.set_uv(Vector2(0, v[1]))
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])
	# petals: a small flat star facing up (white so the instance tint colours it)
	var c := Vector3(0, h, 0)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := a0 + TAU / 10.0
		var a2 := a0 + TAU / 5.0
		# petals tilt up into a shallow cup so they read from standing height
		var tip_a := c + Vector3(cos(a0) * 0.11, 0.06, sin(a0) * 0.11)
		var mid := c + Vector3(cos(a1) * 0.045, 0.02, sin(a1) * 0.045)
		var tip_b := c + Vector3(cos(a2) * 0.11, 0.06, sin(a2) * 0.11)
		var pts := [c, tip_a, mid]
		var pts2 := [c, mid, tip_b]
		for tri in [pts, pts2]:
			for q in tri:
				st.set_color(Color(1, 1, 1))
				st.set_uv(Vector2(0, 1))
				st.set_normal(Vector3.UP)
				st.add_vertex(q)
	return st.commit()


func _scatter_ok(x: float, z: float) -> bool:
	var g := _island_y(HOME, HOME_R, HOME_H, x, z)
	if g - HOME.y < 1.35:                      # only on the green part
		return false
	if _hdist(Vector3(x, 0, z), SHOP_POS) < 6.6:
		return false
	if _hdist(Vector3(x, 0, z), MARKET_POS) < 5.2:
		return false
	if absf(x) < 1.6 and z < 20.0:             # top of the jetty path
		return false
	return true


func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/grass.gdshader")

	# Root matches the ground's grass colour so tufts blend in; tips catch the light.
	var tuft := _tuft_mesh(7, 0.34, Color(0.28, 0.56, 0.23), Color(0.62, 0.86, 0.38))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true      # instance colour multiplies COLOR; left off it reads as black
	mm.mesh = tuft
	var spots: Array = []
	var tries := 0
	while spots.size() < 3600 and tries < 16000:
		tries += 1
		var a := randf() * TAU
		var r := sqrt(randf()) * HOME_R
		var x := HOME.x + cos(a) * r
		var z := HOME.z + sin(a) * r
		if _scatter_ok(x, z):
			spots.append(Vector2(x, z))
	mm.instance_count = spots.size()
	for i in spots.size():
		var p: Vector2 = spots[i]
		var y := _island_y(HOME, HOME_R, HOME_H, p.x, p.y) - 0.02
		var sc := randf_range(0.7, 1.35)
		var t := Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(sc, sc * randf_range(0.8, 1.2), sc)),
			Vector3(p.x, y, p.y))
		mm.set_instance_transform(i, t)
		var tint := Color(1, 1, 1).lerp(Color(1.05, 1.0, 0.72), randf() * 0.5)
		mm.set_instance_custom_data(i, tint)
		mm.set_instance_color(i, Color.WHITE)
	grass_mm = MultiMeshInstance3D.new()
	grass_mm.multimesh = mm
	grass_mm.material_override = mat
	grass_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grass_mm)

	# Wildflowers in small clumps.
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.use_custom_data = true
	fm.use_colors = true
	fm.mesh = _flower_mesh()
	var palette := [Color(1.0, 0.92, 0.35), Color(1.0, 1.0, 1.0), Color(1.0, 0.55, 0.65),
		Color(0.70, 0.60, 1.0), Color(1.0, 0.65, 0.30)]
	var fl: Array = []
	tries = 0
	while fl.size() < 360 and tries < 6000:
		tries += 1
		var a := randf() * TAU
		var r := sqrt(randf()) * HOME_R
		var cx := HOME.x + cos(a) * r
		var cz := HOME.z + sin(a) * r
		if not _scatter_ok(cx, cz):
			continue
		var col: Color = palette[randi() % palette.size()]
		for k in 6:
			var x := cx + randf_range(-0.7, 0.7)
			var z := cz + randf_range(-0.7, 0.7)
			if _scatter_ok(x, z):
				fl.append([Vector3(x, _island_y(HOME, HOME_R, HOME_H, x, z) - 0.02, z), col])
	fm.instance_count = fl.size()
	for i in fl.size():
		var sc := randf_range(0.8, 1.3)
		fm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * sc), fl[i][0]))
		fm.set_instance_custom_data(i, fl[i][1])
		fm.set_instance_color(i, Color.WHITE)
	flower_mm = MultiMeshInstance3D.new()
	flower_mm.multimesh = fm
	flower_mm.material_override = mat
	flower_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flower_mm)


## Low-poly clouds: clusters of flattened spheres drifting slowly overhead.
func _build_clouds() -> void:
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1, 1, 1)
	cm.roughness = 1.0
	cm.emission_enabled = true
	cm.emission = Color(0.85, 0.88, 0.95)
	cm.emission_energy_multiplier = 0.35
	cm.disable_receive_shadows = true
	for i in 12:
		var cloud := Node3D.new()
		var a := randf() * TAU
		var r := randf_range(70.0, 150.0)
		cloud.position = Vector3(cos(a) * r, randf_range(34.0, 52.0), sin(a) * r + 10.0)
		# All the puffs of one cloud baked into a single mesh: one draw call.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in randi_range(4, 7):
			var sm := SphereMesh.new()
			sm.radius = randf_range(3.0, 6.0)
			sm.height = sm.radius * 2.0
			sm.radial_segments = 10
			sm.rings = 6
			var xf := Transform3D(Basis().scaled(Vector3(1.3, randf_range(0.5, 0.7), 1.0)),
				Vector3(randf_range(-9, 9), randf_range(-1.5, 1.5), randf_range(-4, 4)))
			st.append_from(sm, 0, xf)
		var puff := MeshInstance3D.new()
		puff.mesh = st.commit()
		puff.material_override = cm
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.add_child(puff)
		add_child(cloud)
		clouds.append(cloud)


## Static batching: bakes every visible mesh under `root` into one mesh per
## material (the originals are hidden, so collision bodies under them keep
## working). A 50-piece market stall becomes a handful of draw calls.
func _merge_static(root: Node3D) -> void:
	if root == null:
		return
	var inv := root.global_transform.affine_inverse()
	var by_mat := {}
	var mats := {}
	var shadows := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or m.skin != null \
				or m.get_node_or_null(m.skeleton) is Skeleton3D:
			continue
		var xf := inv * m.global_transform
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			var key := mat.get_instance_id() if mat else 0
			if not by_mat.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[key] = st
				mats[key] = mat
				shadows[key] = false
			(by_mat[key] as SurfaceTool).append_from(m.mesh, si, xf)
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadows[key] = true
		m.visible = false
	for key in by_mat:
		var out := MeshInstance3D.new()
		out.mesh = (by_mat[key] as SurfaceTool).commit()
		out.material_override = mats[key]
		out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows[key] \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(out)


## One pass over the built world to cut draw calls on phones:
## - only things big enough to matter cast shadows (not water, terrain or
##   small props), so the shadow passes stay short;
## - the shop's interior (shelves, stock, stands, the keeper) only draws when
##   you're close enough to see inside.
func _optimize_world() -> void:
	var t0 := Time.get_ticks_usec()
	for n in _static_props + [shop_building, shop_counter, boat]:
		if n and is_instance_valid(n):
			_merge_static(n)
	if autotest:
		print("PERF merge_ms=%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	for gi in find_children("*", "GeometryInstance3D", true, false):
		if camera and camera.is_ancestor_of(gi):
			continue
		var g := gi as GeometryInstance3D
		var box := AABB()
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			box = g.global_transform * (g as MeshInstance3D).mesh.get_aabb()
		var big := box.size.x > 0.9 or box.size.y > 0.9 or box.size.z > 0.9
		if g is MeshInstance3D and ((g as MeshInstance3D).mesh is PlaneMesh or box.size.x > 40.0):
			big = false                       # water, seabed, islands
		if not big:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _shop_box.has_volume() and box.has_volume() and _shop_box.encloses(box) \
				and not shop_building.is_ancestor_of(g):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.visibility_range_end = 26.0
			g.visibility_range_end_margin = 2.0


## Light weather: mostly clear, now and then a short drizzle that dims the sun
## and thickens the haze a touch. Rain is a particle box that follows the camera.
func _build_weather() -> void:
	rain = CPUParticles3D.new()
	rain.amount = 400
	rain.lifetime = 0.9
	rain.local_coords = false
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(16, 0.5, 16)
	rain.direction = Vector3(0.12, -1, 0.05)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -6, 0)
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 19.0
	rain.particle_flag_align_y = true
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.42, 0.012)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
	drop.material = rm
	rain.mesh = drop
	rain.emitting = false
	add_child(rain)
	_weather_t = randf_range(40.0, 90.0)


func _update_weather(delta: float) -> void:
	if rain == null:
		return
	# clouds drift and wrap around
	for c in clouds:
		c.position.x += delta * 1.2
		if c.position.x > 160.0:
			c.position.x = -160.0
	_weather_t -= delta
	if test_rain:
		_raining = true
		_rain_amt = 1.0
		_weather_t = 99.0
	if _weather_t <= 0.0:
		_raining = not _raining and weather_enabled
		_weather_t = randf_range(25.0, 40.0) if _raining else randf_range(90.0, 160.0)
	var want := 1.0 if (_raining and weather_enabled) else 0.0
	_rain_amt = move_toward(_rain_amt, want, delta * 0.25)
	rain.emitting = _rain_amt > 0.15
	rain.global_position = camera.global_position + Vector3(0, 11, 0)
	if sun_light:
		sun_light.light_energy = lerpf(1.02, 0.66, _rain_amt)
	if world_env:
		world_env.fog_density = lerpf(0.0085, 0.016, _rain_amt)
		world_env.ambient_light_energy = lerpf(0.42, 0.36, _rain_amt)
	# Grey the sky a little in a shower (only when it changes: sky updates cost).
	if sky_mat and absf(_rain_amt - _sky_rain) > 0.02:
		_sky_rain = _rain_amt
		sky_mat.sky_top_color = Color(0.13, 0.36, 0.78).lerp(Color(0.36, 0.44, 0.55), _rain_amt)
		sky_mat.sky_horizon_color = Color(0.74, 0.88, 0.97).lerp(Color(0.66, 0.72, 0.78), _rain_amt)


## Buoys ride the same waves the water shader draws.
func _update_floaters() -> void:
	if boat and play_mode != "sailing":
		boat.position.y = boat.position.y * 0.0 + BOAT_MOOR.y + wave_height(boat.position.x, boat.position.z)
		boat.rotation.z = sin(elapsed * 1.3) * 0.025
		_sync_deck()
	for f in floaters:
		var h := wave_height(f.position.x, f.position.z)
		f.position.y = h
		f.rotation.x = sin(elapsed * 1.3 + f.position.x) * 0.10
		f.rotation.z = cos(elapsed * 1.1 + f.position.z) * 0.10


func _menu_camera(delta: float) -> void:
	# Slow orbit around the home island, framed to the right of the menu.
	_menu_cam_t += delta * 0.045
	var a := -0.55 + sin(_menu_cam_t) * 0.55
	var centre := Vector3(0.0, 2.5, 24.0)
	camera.position = centre + Vector3(sin(a) * 34.0, 10.0 + sin(_menu_cam_t * 0.7) * 1.2, -cos(a) * 34.0)
	camera.look_at(centre)
	camera.rotate_object_local(Vector3.UP, 0.34)


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
	hud.hud_scale = float(st.get("hud_scale", 1.0))
	hud.hud_opacity = float(st.get("hud_opacity", 1.0))
	hud.recalc_layout()
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
		world_env.fog_enabled = true
	if water_mat:
		water_mat.set_shader_parameter("normal_scale", 0.12 if q == "Low" else (0.28 if q == "Medium" else 0.38))
		water_mat.set_shader_parameter("foam_width", 0.0 if q == "Low" else 0.16)
	if grass_mm:
		var n := grass_mm.multimesh.instance_count
		grass_mm.multimesh.visible_instance_count = int(n * (0.35 if q == "Low" else (0.7 if q == "Medium" else 1.0)))
	weather_enabled = bool(menu_ui.settings.get("weather", true))
	_hands_enabled = bool(menu_ui.settings.get("show_hands", true))
	if status:
		status.show_fps = bool(menu_ui.settings.get("show_fps", false))
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_DISABLED if q == "Low" else (Viewport.MSAA_2X if q == "Medium" else Viewport.MSAA_4X)
	if camera:
		camera.far = 170.0 if q == "Low" else 260.0
	if shop_lamp and q == "Low":
		shop_lamp.omni_range = 5.0


var _idle_delay := 0.0
func await_then_idle(t: float) -> void:
	_idle_delay = t
	state = -1 as int  # transient; handled below
	set_process(true)


func _physics_process(_d: float) -> void:
	_update_holding()
	_update_loose_fish()
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
	if hands:
		hands.play_cast()
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
		if fx:
			fx.splash(Vector3(bobber.position.x, wave_height(bobber.position.x, bobber.position.z), bobber.position.z), 1.0)
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
	if fx:
		fx.splash(bobber.position, 0.7)
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
	var pick := _roll_catch()
	pending_fish = pick
	fish_strength = float(pick.get("spd", 1.0)) * randf_range(0.85, 1.15) * (1.0 + float(pick["max"]) * 0.05)
	distance = 1.0
	tension = 0.35
	lunge_timer = randf_range(0.8, 1.8)
	state = FIGHT
	hud.mode = Hud.M_FIGHT
	hud.message = ""


## Reel level (the "Reel" upgrade) decides which fish can bite at all and makes
## the rare bands more likely; Luck nudges it further.
func reel_tier() -> int:
	return int(upgrades.get("rod", 0))


func _roll_catch() -> Dictionary:
	var tier := reel_tier()
	var luck := int(upgrades.get("luck", 0))
	var pool: Array = []
	var weights: Array = []
	var total := 0.0
	for f in fish_table:
		if int(f.get("tier", 0)) > tier:
			continue
		var rar := str(f.get("rarity", "Common"))
		var w: float = RARITY_WEIGHT.get(rar, 10.0)
		w *= pow(float(RARITY_REEL_BOOST.get(rar, 1.0)), tier + luck * 0.5)
		if f.get("junk", false):
			w *= 0.45
		pool.append(f)
		weights.append(w)
		total += w
	var r := randf() * total
	for i in pool.size():
		r -= float(weights[i])
		if r <= 0.0:
			return pool[i]
	return pool[0]


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
	# Journal: count it, and a little bonus the first time you land a species.
	var jn := str(pending_fish["name"])
	_new_species = not journal.has(jn)
	var je: Array = journal.get(jn, [0, 0.0])
	journal[jn] = [int(je[0]) + 1, maxf(float(je[1]), pending_weight)]
	if pending_weight > best_weight:
		best_weight = pending_weight
		best_name = pending_fish["name"]

	# Coin value: price per kg x weight; junk has a flat (mostly tiny) value.
	if pending_fish.get("boss", false):
		pending_value = BOSS_VALUE
	elif pending_fish.has("flat"):
		pending_value = int(pending_fish["flat"]) + randi() % maxi(1, int(pending_fish["flat"]) / 2 + 1)
	else:
		pending_value = maxi(2, int(round(pending_weight * float(pending_fish.get("price", 14)))))
	if _new_species:
		pending_value += NEW_SPECIES_BONUS
		_flash("New species for your journal!  +%d coins" % NEW_SPECIES_BONUS)

	# Heavier catches take more whacks.
	whacks_left = clampi(1 + int(round(pending_weight * 0.9)) - weapon_power(), 1, 5)
	if pending_fish.get("boss", false):
		whacks_left = 6 - weapon_power()
	whack_anim = 0.0
	catch_hop = 0.0
	_flop_timer = randf_range(1.6, 2.6) / float(pending_fish.get("spd", 1.0))
	_windup = 0.0
	hud.message = ""
	_play("caught")
	_show_catch(pending_fish)
	_whack_message()


func _whack_message() -> void:
	var rar := str(pending_fish.get("rarity", "Common"))
	hud.card_title = str(pending_fish["name"]).capitalize() if pending_fish.get("junk", false) else str(pending_fish["name"])
	hud.card_color = UITheme.RARITY.get(rar, Color.WHITE)
	hud.card_sub = "%s%s   ·   %.2f kg   ·   %d coins" % ["NEW!  " if _new_species else "", rar, pending_weight, pending_value]
	if _windup > 0.0:
		hud.card_hint = "It's going to jump - WHACK IT!"
	else:
		hud.card_hint = "Tap to whack   ·   %d left" % whacks_left


## One tap = one whack. Swings the paddle, bounces the catch, and when the
## catch is done, pays out and moves to the result screen.
func _do_whack() -> void:
	whacks_left -= 1
	whack_anim = 1.0
	catch_hop = 1.0
	_play("bonk")
	if _windup > 0.0:
		# Caught it mid wind-up: knocked flat, no jump this time.
		_windup = 0.0
		hud.windup = 0.0
		_flop_timer = randf_range(1.4, 2.4) / float(pending_fish.get("spd", 1.0))
	if whacks_left > 0:
		_whack_message()
	else:
		_finish_catch()


func _finish_catch() -> void:
	state = CAUGHT
	hud.mode = Hud.M_CAUGHT
	hud.clear_card()
	var data := {
		"name": pending_fish["name"], "weight": pending_weight, "value": pending_value,
		"rarity": pending_fish.get("rarity", "Common"),
		"set": pending_fish.get("set", "river"), "node": pending_fish.get("node", ""),
		"boss": pending_fish.get("boss", false),
	}
	# The whacked catch flops off to one side of the deck as a real object.
	var spot := caught_fish.global_position if caught_fish else whack_spot
	if caught_fish:
		caught_fish.queue_free()
		caught_fish = null
	var off := Vector3(randf_range(-0.55, 0.55), 0.35, randf_range(0.9, 1.9))
	if on_boat:
		off = Vector3(randf_range(-0.35, 0.35), 0.35, randf_range(0.2, 0.9))
	var body := _spawn_loose_fish(data, spot + off, randf() * TAU)
	body.linear_velocity = Vector3(randf_range(-0.4, 0.4), 1.6, 0.5 if not on_boat else 0.0)
	_save_game()
	_update_info()
	_play("caught")
	if data["boss"]:
		hud.message = "YOU LANDED THE BABY KRAKEN!\nSail back and drag it to the market"
	else:
		hud.message = "Landed %s  -  worth %d\nIt's on the deck: carry it to the market" % [data["name"], data["value"]]


## Spawns a catch as a physics object: its real model, a box collider sized to
## it, a white outline shell for when you look at it, and its data as meta.
func _spawn_loose_fish(data: Dictionary, pos: Vector3, yaw := 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = FISH_LAYER
	body.collision_mask = 1 | FISH_LAYER
	body.mass = clampf(float(data.get("weight", 1.0)), 0.3, 30.0)
	body.linear_damp = 0.4
	body.angular_damp = 1.2
	body.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.18
	body.physics_material_override = pm
	body.set_meta("fish", data)

	var w := 4.5 if data.get("boss", false) else float(data.get("weight", 1.0))
	var model := _make_fish(data, w)
	body.add_child(model)
	var box := _local_aabb(model)
	var size := box.size * model.scale
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(size.x, 0.12), maxf(size.y, 0.10), maxf(size.z, 0.12))
	col.shape = bs
	col.position = Vector3(0, bs.size.y * 0.5, 0)
	body.add_child(col)

	# Outline shell, shown while the crosshair is on it.
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(1, 1, 1)
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.cull_mode = BaseMaterial3D.CULL_FRONT
	om.grow = true
	om.grow_amount = 0.04 / maxf(model.scale.x, 0.01)
	var outlines: Array = []
	for mi in model.find_children("*", "MeshInstance3D", true):
		if mi.mesh == null:
			continue
		var o := MeshInstance3D.new()
		o.mesh = mi.mesh
		o.material_override = om
		o.transform = mi.transform
		o.visible = false
		mi.get_parent().add_child(o)
		outlines.append(o)
	body.set_meta("outlines", outlines)

	body.position = pos
	body.rotation.y = yaw
	add_child(body)
	loose_fish.append(body)
	return body


func _set_fish_outline(b: RigidBody3D, on: bool) -> void:
	if b == null or not is_instance_valid(b) or not b.has_meta("outlines"):
		return
	for o in b.get_meta("outlines"):
		if is_instance_valid(o):
			o.visible = on


func _grab(b: RigidBody3D) -> void:
	if b == null or not is_instance_valid(b):
		return
	_drop_holding()
	holding = b
	_hold_far_t = 0.0
	_set_fish_outline(b, false)
	b.gravity_scale = 0.0
	b.angular_damp = 4.0
	b.add_collision_exception_with(player)
	if hands:
		hands.play_grab()
	var d: Dictionary = b.get_meta("fish")
	player.carry_slow = 0.6 if d.get("boss", false) else 0.9
	_play("whoosh")


func _drop_holding(throw := false) -> void:
	if holding == null or not is_instance_valid(holding):
		holding = null
		if player:
			player.carry_slow = 1.0
		return
	holding.gravity_scale = 1.0
	holding.angular_damp = 1.2
	if throw:
		if hands:
			hands.play_throw()
		var fwd := -camera.global_transform.basis.z
		holding.linear_velocity = fwd * 6.0 + Vector3(0, 2.5, 0)
	holding = null
	player.carry_slow = 1.0


## Held fish hang from a point in front of you and swing as you move.
func _update_holding() -> void:
	if holding == null:
		return
	if not is_instance_valid(holding):
		holding = null
		return
	var fwd := -camera.global_transform.basis.z
	var half := _held_half()
	var target := camera.global_position + fwd * (0.42 + half * 0.9) + Vector3(0, -0.24 - half * 0.2, 0)
	var to := target - holding.global_position
	# Only let go if it's been snagged far away for a moment (walls etc).
	if to.length() > 3.2:
		_hold_far_t += get_physics_process_delta_time()
		if _hold_far_t > 0.6:
			_drop_holding()
			return
	else:
		_hold_far_t = 0.0
	holding.linear_velocity = (to * 13.0).limit_length(14.0)
	# Held side-on across your view, nose dipping, like carrying it by the gills.
	holding.angular_velocity = Vector3.ZERO
	var sway := sin(elapsed * 3.0) * 0.06
	holding.global_rotation = Vector3(0.0, cam_yaw, -0.32 + sway)


## Half the length of the held fish (its collider is sized to the model).
func _held_half() -> float:
	if holding == null or not is_instance_valid(holding):
		return 0.2
	for c in holding.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var sz: Vector3 = (c.shape as BoxShape3D).size
			return clampf(maxf(sz.x, sz.z) * 0.5, 0.08, 0.9)
	return 0.2


## Footsteps (wood on the jetty and boat, soft on sand and grass, sloshing in
## the shallows), the odd gull squawk, and the sea louder near the shore.
func _update_ambience(delta: float, surface: float, depth: float) -> void:
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and v > 0.6:
		_step_dist += v * delta
		var stride := 1.05 if v > 4.0 else 0.78
		if _step_dist >= stride:
			_step_dist = 0.0
			var pp := player.global_position
			if depth > 0.15:
				players["splash"].pitch_scale = randf_range(1.3, 1.6)
				_play("splash")
			elif pp.y > DECK_Y - 0.25 and (absf(pp.x) < 2.2 and pp.z < 20.0 or near_boat):
				players["step_wood"].pitch_scale = randf_range(0.9, 1.12)
				_play("step_wood")
			else:
				players["step_soft"].pitch_scale = randf_range(0.85, 1.15)
				_play("step_soft")
	else:
		_step_dist = 0.6
	players["splash"].pitch_scale = 1.0 if depth <= 0.15 else players["splash"].pitch_scale
	_gull_t -= delta
	if _gull_t <= 0.0 and fx:
		_gull_t = randf_range(9.0, 22.0)
		if fx.nearest_gull(player.global_position).distance_to(player.global_position) < 30.0:
			players["gull"].pitch_scale = randf_range(0.9, 1.15)
			_play("gull")
	if _surf:
		var shore := clampf((_hdist(player.global_position, HOME) - 10.0) / 14.0, 0.0, 1.0)
		_surf.volume_db = lerpf(-20.0, -11.0, shore)


## "the Baby Kraken" -> "Baby Kraken", "an Old Boot" -> "Old Boot".
func _short_name(n: String) -> String:
	for a in ["the ", "an ", "a "]:
		if n.begins_with(a):
			return n.substr(a.length())
	return n


## Render/physics counters for the perf checks (draw calls etc. carry over to
## phones even though headless frame times don't).
func _print_perf() -> void:
	print("PERF draw_calls=%d objects=%d primitives=%d nodes=%d physics_active=%d mem_static=%.1fMB vmem=%.1fMB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	if OS.get_environment("PERF_DETAIL") == "":
		return
	var groups := {}
	for mi in find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var top: Node = mi
		while top.get_parent() != self:
			top = top.get_parent()
		var key: String = Array(str(top.name).split("@", false))[0].rstrip("0123456789")
		if key == "Node3D" and top.get_child_count() > 0:
			key = "Node3D/" + Array(str(top.get_child(0).name).split("@", false))[0].rstrip("0123456789")
		var tris := 0
		var g: Array = groups.get(key, [0, 0, 0, 0])
		g[0] += 1
		g[1] += mi.mesh.get_surface_count()
		g[2] += tris
		g[3] += 1 if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
		groups[key] = g
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	for k in keys.slice(0, 25):
		print("  %-28s meshes=%4d surfaces=%4d tris=%7d shadow=%4d" % [k, groups[k][0], groups[k][1], groups[k][2], groups[k][3]])


## Drives the first-person hands from whatever you're doing right now.
func _update_hands(delta: float) -> void:
	if hands == null:
		return
	var m := "hidden"
	if app_state == "playing" or app_state == "paused":
		match play_mode:
			"explore":
				if holding and is_instance_valid(holding):
					m = "carry"
					var half := _held_half()
					hands.carry_half = minf(half, 0.32)
					hands.carry_heavy = (holding.get_meta("fish") as Dictionary).get("boss", false)
					# hold near the middle of the fish (its origin sits on its belly)
					hands.carry_point = camera.to_local(holding.global_position + Vector3(0, 0.05, 0))
				else:
					m = "explore"
					var want := 1.0 if (looked_fish != null or looked_weapon != "") else 0.0
					_reach = move_toward(_reach, want, delta * 4.0)
					hands.reach = _reach
					hands.move_speed = Vector2(player.velocity.x, player.velocity.z).length()
					hands.sprint = player.sprint and hands.move_speed > 3.5
			"sailing":
				m = "sail"
			"fishing":
				if paddle.visible:
					m = "whack"
				elif rod.visible:
					m = "rod"
	hands.mode = m if _hands_enabled else "hidden"
	hands.reeling = play_mode == "fishing" and state == FIGHT and (hud.action_down() or sim_action)
	hands.charge = power if (play_mode == "fishing" and state == CHARGING) else 0.0
	hands.tension = hud.tension if (play_mode == "fishing" and state == FIGHT) else 0.0
	hands.windup = hud.windup if state == WHACK else 0.0


## Fish left in the sea slip away; fish dropped on the market counter sell.
func _update_loose_fish() -> void:
	for b in loose_fish.duplicate():
		if not is_instance_valid(b):
			loose_fish.erase(b)
			continue
		if b == holding:
			continue
		var p: Vector3 = b.global_position
		if p.y < wave_height(p.x, p.z) - 0.35 and _cargo.find(b) == -1:
			var d: Dictionary = b.get_meta("fish")
			_flash("%s slipped back into the water!" % str(d.get("name", "It")).capitalize())
			if b == looked_fish:
				looked_fish = null
			if fx:
				fx.splash(Vector3(p.x, wave_height(p.x, p.z), p.z), 2.2)
			_play("splash")
			loose_fish.erase(b)
			b.queue_free()
			continue
		# Resting on the market counter: the buyer takes it.
		var rel := p - Vector3(MARKET_POS.x, market_ground, MARKET_POS.z)
		if absf(rel.x) < 0.75 and absf(rel.z) < 1.8 and rel.y > 0.8 and rel.y < 1.6 \
				and b.linear_velocity.length() < 0.6:
			_sell_body(b)


func _sell_body(b: RigidBody3D) -> void:
	var d: Dictionary = b.get_meta("fish")
	var value := int(d.get("value", 0))
	coins += value
	if b == holding:
		holding = null
		player.carry_slow = 1.0
	if b == looked_fish:
		looked_fish = null
	loose_fish.erase(b)
	b.queue_free()
	_play("coins")
	_flash("Sold %s for %d coins" % [str(d.get("name", "it")), value])
	var ap = fish_buyer.get_meta("anim") if fish_buyer and fish_buyer.has_meta("anim") else null
	if ap and ap.has_animation("Cheer"):
		ap.play("Cheer")
	if d.get("boss", false) and not island2_unlocked:
		island2_unlocked = true
		_show_island2_marker()
		hud.message = ""
		_flash("The buyer hands you a map - ISLAND 2 unlocked!")
	_save_game()
	_update_info()


## The thing in your hand when you whack: your equipped weapon, or the old
## paddle if you haven't bought one yet.
func _refresh_whack_tool() -> void:
	for c in paddle.get_children():
		c.queue_free()
	# The tool node sits in the right fist (FPHands moves it): its origin is the
	# grip and +Y runs up the blade.
	var m: Node3D
	var style := "chop"
	if equipped_weapon != "" and ResourceLoader.exists(WEAPON_DIR + equipped_weapon + ".gltf"):
		m = load(WEAPON_DIR + equipped_weapon + ".gltf").instantiate()
		if equipped_weapon.begins_with("fistweapon"):
			style = "punch"
			m.scale = Vector3.ONE * 0.55
			m.rotation_degrees = Vector3(0, 90, 0)
		else:
			m.scale = Vector3.ONE * 0.42
	else:
		m = load(MDL["paddle"]).instantiate()
		m.scale = Vector3.ONE * 0.21
		m.rotation_degrees = Vector3(0, 90, 180)      # blade up and facing you, handle in the fist
		m.position = Vector3(0, 2.15 * 0.21, 0)
	paddle.add_child(m)
	if hands:
		hands.whack_style = style
	for mi in m.find_children("*", "MeshInstance3D", true):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Kept for older call sites: the carry pill now describes what's in your hands.
func _refresh_held_view() -> void:
	if touch == null:
		return
	if holding and is_instance_valid(holding):
		var d: Dictionary = holding.get_meta("fish")
		touch.carry_info = "Holding %s  -  %d coins" % [str(d.get("name", "")), int(d.get("value", 0))]
	else:
		touch.carry_info = ""


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Fish fight back: every so often a live catch winds up (shakes, warning
## shown) and then leaps at you for its attack damage. Whack it during the
## wind-up to stop the jump. Junk never attacks.
func _update_flop(delta: float) -> void:
	var atk := float(pending_fish.get("atk", 0))
	if atk <= 0.0 or state != WHACK or caught_fish == null:
		return
	if _windup > 0.0:
		_windup -= delta
		hud.windup = clampf(_windup / 0.7, 0.0, 1.0)
		caught_fish.rotation.z = sin(elapsed * 46.0) * 0.22
		caught_fish.rotation.x = sin(elapsed * 39.0) * 0.12
		if _windup <= 0.0:
			_fish_leap(atk)
		return
	_flop_timer -= delta
	if _flop_timer <= 0.0:
		_windup = 0.7
		hud.windup = 1.0
		_play("bite")
		_whack_message()


func _fish_leap(atk: float) -> void:
	_windup = 0.0
	hud.windup = 0.0
	catch_hop = 1.0
	_leap_t = 0.35
	_flop_timer = randf_range(1.6, 2.8) / float(pending_fish.get("spd", 1.0))
	_play("snap")
	_take_damage(atk * randf_range(0.85, 1.15), "%s got you" % str(pending_fish["name"]))
	if state == WHACK:
		_whack_message()


## Animates the paddle swing and the catch bouncing on the deck.
func _update_whack(delta: float) -> void:
	if whack_anim > 0.0:
		whack_anim = maxf(whack_anim - delta * 4.5, 0.0)
	if catch_hop > 0.0:
		catch_hop = maxf(catch_hop - delta * 3.0, 0.0)
	# Paddle rests raised, snaps down on a whack.
	if hands:
		hands.swing = sin(whack_anim * PI)
	if _leap_t > 0.0:
		_leap_t = maxf(_leap_t - delta, 0.0)
	if caught_fish:
		var hop: float = sin(catch_hop * PI)
		var leap: float = sin((1.0 - _leap_t / 0.35) * PI) if _leap_t > 0.0 else 0.0
		caught_fish.position = whack_spot.lerp(camera.global_position + Vector3(0, -0.35, 0), leap * 0.55)
		caught_fish.position.y = whack_spot.y + hop * 0.28 + leap * 0.9
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
			_print_perf()
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
						print("AUTOTEST landed: loose=%s health=%.0f" % [loose_fish.map(func(b): return b.get_meta("fish")["name"]), health])
						if autotest_shot != "":
							get_viewport().get_texture().get_image().save_png(autotest_shot.replace(".png", "_landed.png"))
					if frame % 30 == 0:
						_leave_fishing()
		if play_mode == "explore" and _boss_logged and not _boss_sold:
			for b in loose_fish:
				if is_instance_valid(b) and b.get_meta("fish").get("boss", false):
					print("AUTOTEST kraken home at %s" % [b.global_position.snapped(Vector3.ONE * 0.1)])
					player.position = Vector3(SELL_SPOT.x - 1.0, market_ground + 0.3, SELL_SPOT.z)
					_grab(b)
					b.global_position = player.global_position + Vector3(0.8, 1.2, 0)
			_boss_sold = true
			_boss_sell_frame = frame + 25
		if _boss_sold and frame == _boss_sell_frame:
			_update_explore(0.016)
			_on_interact()
			print("AUTOTEST sold -> coins=%d island2=%s loose=%d" % [coins, island2_unlocked, loose_fish.size()])
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
			print("AUTOTEST near_market=%s prompt='%s' secondary='%s' holding=%s" % [
				near_market, touch.prompt, touch.secondary, holding != null])
		if frame == 40 and autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		if frame == 42:
			_on_interact()
			print("AUTOTEST after hand sell -> coins=%d holding=%s loose=%d" % [coins, holding != null, loose_fish.size()])
		if frame >= 160:
			print("AUTOTEST after counter drop -> coins=%d loose=%d" % [coins, loose_fish.size()])
			for b in loose_fish:
				if is_instance_valid(b):
					var rel: Vector3 = b.global_position - Vector3(MARKET_POS.x, market_ground, MARKET_POS.z)
					print("AUTOTEST   loose %s rel=%s v=%.2f" % [b.get_meta("fish").get("name", "?"), rel, b.linear_velocity.length()])
			get_tree().quit()
		return

	if start_screen == "flop":
		if frame == 2:
			_flop_timer = 0.3
		if hud.windup > 0.0 and not _flop_seen:
			_flop_seen = true
			print("AUTOTEST windup hint='%s'" % hud.card_hint)
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
		if frame == 120:
			print("AUTOTEST after leap: health=%.0f card='%s / %s'" % [health, hud.card_title, hud.card_sub])
			get_tree().quit()
		return

	if start_screen == "drown":
		if frame % 120 == 0:
			print("AUTOTEST drown f=%d health=%.0f breath=%.2f under=%s mode=%s" % [
				frame, health, breath, status.underwater, play_mode])
		if play_mode == "dead" and _death_t > 1.8:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST died at f=%d coins=%d" % [frame, coins])
			get_tree().quit()
		if frame > 1200:
			print("AUTOTEST drown TIMEOUT")
			get_tree().quit()
		return

	if start_screen in ["menu", "settings", "pause", "shop", "help", "weaponshop", "legs", "shopview"]:
		if frame > 40:
			if autotest_shot != "":
				get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST(%s) frame=%d" % [start_screen, frame])
			_print_perf()
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
	_test_whack_f = _test_whack_f + 1 if state == WHACK else 0
	if shot_on == "whack" and state == WHACK and frame > 30 and _test_whack_f == 24:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(whack) frames=%d whacks_left=%d hands=%s paddle=%s rod=%s" % [frame, whacks_left,
			hands.mode, paddle.visible, rod.visible])
		get_tree().quit()
	if (shot_on == "fight" and state == FIGHT and sim_action and distance < 0.6) \
			or (shot_on == "charge" and state == CHARGING and power > 0.7):
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(%s) frames=%d" % [shot_on, frame])
		get_tree().quit()
	if shot_on == "caught" and state == CAUGHT and frame > 30:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(caught) frames=%d catches=%d best=%.2f" % [frame, catches, best_weight])
		get_tree().quit()
	if frame >= autotest_frames:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST frames=%d catches=%d best=%.2f state=%d health=%.0f loose=%d mode=%s" % [
			frame, catches, best_weight, state, health, loose_fish.size(), play_mode])
		get_tree().quit()
