extends Node3D
## Deadzone - a first-person low-poly survival game.
##
## The whole game is built in code: there is no hand-made level, because the
## world is endless. Ground is generated from noise in chunks around you, the
## forest and rocks are scattered into those chunks as they appear, and the one
## fixed thing - the town you start in - is stamped into the middle of it.
##
## Everything a phone has to pay for every frame is kept on a short leash:
## chunks load and unload with you, grass and leaves are drawn as instanced
## batches rather than nodes, zombies far away think and animate on a slower
## clock, and the 3D view renders into a scaled-down buffer the HUD is drawn
## over at full size.

const Player := preload("res://player.gd")
const FPHands := preload("res://fp_hands.gd")
const Touch := preload("res://touch_controls.gd")
const StatusUI := preload("res://status_ui.gd")
const RenderView := preload("res://render_view.gd")
const WorldFX := preload("res://world_fx.gd")
const Sfx := preload("res://sfx.gd")
const Zombie := preload("res://zombie.gd")
const UITheme := preload("res://ui_theme.gd")
const IconBaker := preload("res://icon_baker.gd")
const MapUI := preload("res://map_ui.gd")

# --- world shape --------------------------------------------------------------
const CHUNK := 48.0               # metres across one patch of ground
const CHUNK_GRID := 24            # quads across that patch
const VIEW_CHUNKS := 2            # rings of chunks kept around you
const TOWN_R := 44.0              # the clearing the town sits in
const WORLD_R := 1150.0           # how far the land runs before the coast
const SEA_Y := -11.0              # water level past the shore
const SPAWN := Vector3(0, 0, 6)

const EYE := 1.62
const DAY_LENGTH := 420.0         # seconds for a full day/night turn

# --- items --------------------------------------------------------------------
# Everything you can carry. `use` is what tapping the action button does with
# it in hand, and `loot` is how often it turns up in containers.
const ITEMS := {
	"pistol": {"name": "Pistol", "kind": "gun", "dmg": 34.0, "rate": 0.26, "mag": 12,
		"ammo": "9mm", "model": "res://assets/models/guns/pistol_1911.fbx", "loot": 0.10},
	"revolver": {"name": "Revolver", "kind": "gun", "dmg": 52.0, "rate": 0.5, "mag": 6,
		"ammo": "9mm", "model": "res://assets/loot/Revolver_1.fbx", "loot": 0.06},
	"axe": {"name": "Fire Axe", "kind": "melee", "dmg": 46.0, "rate": 0.62,
		"model": "res://assets/loot/Axe.fbx", "loot": 0.09},
	"knife": {"name": "Knife", "kind": "melee", "dmg": 26.0, "rate": 0.38,
		"model": "res://assets/loot/Knife.fbx", "loot": 0.12},
	"9mm": {"name": "9mm Ammo", "kind": "ammo", "stack": 60, "loot": 0.34,
		"model": "res://assets/loot/Matchbox.fbx"},
	"bandage": {"name": "Bandage", "kind": "heal", "heal": 28.0, "stack": 6, "loot": 0.26,
		"model": "res://assets/loot/Bandages.fbx"},
	"medkit": {"name": "First Aid Kit", "kind": "heal", "heal": 70.0, "stack": 3, "loot": 0.09,
		"model": "res://assets/loot/FirstAidKit.fbx"},
	"can": {"name": "Canned Food", "kind": "food", "food": 42.0, "stack": 6, "loot": 0.30,
		"model": "res://assets/loot/Can_Closed.fbx"},
	"water": {"name": "Water Bottle", "kind": "drink", "water": 45.0, "stack": 6, "loot": 0.30,
		"model": "res://assets/loot/WaterBottle_1.fbx"},
	"battery": {"name": "Battery", "kind": "junk", "stack": 8, "loot": 0.16,
		"model": "res://assets/loot/Battery_Big.fbx"},
	"radio": {"name": "Radio", "kind": "junk", "loot": 0.05, "model": "res://assets/loot/Radio.fbx"},
}
const SLOTS := 6

# --- scenery ------------------------------------------------------------------
# Two packs' worth, mixed: Quaternius (fbx, nature/) and the CC0 starter pack
# (glb, nature2/). Each entry is [model, folder]. JUNGLE and DEAD are the
# other two biomes: the world is overgrown in the low wet ground and bare
# where the ruins are.
const JUNGLE := [["PalmTree_1", "nature"], ["PalmTree_2", "nature"], ["PalmTree_3", "nature"],
	["PalmTree_4", "nature"], ["Willow_1", "nature"], ["Willow_3", "nature"],
	["nature_tree_palm_01", "nature2"], ["nature_tree_deciduous_02", "nature2"]]
const JUNGLE_FLOOR := [["Plant_4", "nature"], ["Plant_5", "nature"], ["BushBerries_2", "nature"],
	["Bush_2", "nature"], ["nature_bush_02", "nature2"], ["nature_bush_04", "nature2"],
	["nature_bush_06", "nature2"]]
const DEAD := [["Willow_Dead_1", "nature"], ["Willow_Dead_3", "nature"], ["dead_tree", "apoc"],
	["CommonTree_Dead_1", "nature"], ["nature_tree_dead_01", "nature2"],
	["EA04_Env_Tree_Trunk_01a", "raft"], ["EA04_Env_Tree_Trunk_01c", "raft"],
	["EA04_Env_Tree_Beam_01a", "raft"], ["EA04_Env_Tree_Root_01a", "raft"]]
# Bleached wood, stone and dry scrub for the dead ground.
const DEAD_FLOOR := [["EA04_Env_Tree_Root_01c", "raft"], ["EA04_Env_Stone_Gray_01a", "raft"],
	["EA04_Env_Stone_Sand_01a", "raft"], ["EA04_Env_Plants_Grass_Dry_01a", "raft"],
	["EA04_Env_Plants_Grass_Dry_01c", "raft"], ["EA04_Env_Rocks_Sand_01c", "raft"]]
const RUINS := ["collapsed_house", "ruined_shop", "survivor_tent", "rubble_pile", "wrecked_car",
	"bunker_entrance", "guard_tower", "water_tank", "ruined_apartment", "burnt_bus"]
const TREES := [["CommonTree_1", "nature"], ["CommonTree_3", "nature"], ["CommonTree_5", "nature"],
	["PineTree_1", "nature"], ["PineTree_3", "nature"], ["PineTree_5", "nature"],
	["BirchTree_1", "nature"], ["BirchTree_3", "nature"],
	["nature_tree_pine_01", "nature2"], ["nature_tree_pine_02", "nature2"], ["nature_tree_pine_03", "nature2"],
	["nature_tree_deciduous_01", "nature2"], ["nature_tree_deciduous_02", "nature2"],
	["nature_tree_deciduous_03", "nature2"]]
const DEAD_TREES := [["CommonTree_Dead_1", "nature"], ["CommonTree_Dead_3", "nature"],
	["BirchTree_Dead_1", "nature"], ["nature_tree_dead_01", "nature2"], ["dead_tree", "apoc"]]
const ROCKS := [["Rock_1", "nature"], ["Rock_3", "nature"], ["Rock_5", "nature"], ["Rock_Moss_2", "nature"],
	["nature_rock_01", "nature2"], ["nature_rock_03", "nature2"], ["nature_rock_05", "nature2"],
	["nature_rock_07", "nature2"], ["EA04_Env_Rocks_Gray_01a", "raft"],
	["EA04_Env_Rocks_Gray_02a", "raft"], ["EA04_Env_Rocks_Sand_01a", "raft"]]
const BUSHES := [["Bush_1", "nature"], ["Bush_2", "nature"], ["BushBerries_1", "nature"],
	["Plant_1", "nature"], ["TreeStump", "nature"], ["nature_bush_01", "nature2"],
	["nature_bush_03", "nature2"], ["nature_bush_05", "nature2"], ["nature_stump_01", "nature2"],
	["nature_log_01", "nature2"]]
const GRASS := [["Grass", "nature"], ["Grass_2", "nature"], ["Wheat", "nature"], ["Flowers", "nature"],
	["nature_grass_01", "nature2"], ["nature_grass_03", "nature2"], ["nature_grass_05", "nature2"],
	["nature_flower_01", "nature2"], ["nature_flower_03", "nature2"]]

# --- graphics presets ---------------------------------------------------------
const Q_NAMES := ["Low", "Medium", "High", "Ultra"]
const Q_SCALE := [0.58, 0.74, 0.88, 1.0]
const Q_ROWS := [540, 720, 900, 100000]
const Q_GRASS := [0, 120, 260, 420]       # blades per chunk
const Q_SHADOW := [0, 1024, 2048, 3072]
const Q_DRAW := [70.0, 100.0, 140.0, 190.0]
const Q_ZOMBIES := [10, 16, 22, 28]

var quality := 1

# --- state --------------------------------------------------------------------
var player: CharacterBody3D
var camera: Camera3D
var hands: Node3D
var touch
var status
var icons
var map_ui
var render_view
var fx
var sun: DirectionalLight3D
var world_env: Environment
var sky_mat: ShaderMaterial
var _wind_mats := {}

var inv: Array = []               # [{id, n}] x SLOTS
var sel := 0
var ammo_loaded := 0              # rounds in the gun you are holding
var health := 100.0
var food := 100.0
var water := 100.0
var stamina := 1.0
var kills := 0
var day := 1
var clock := 0.30 * DAY_LENGTH    # morning
var dead := false

var cam_yaw := 0.0
var cam_pitch := -0.05
var _cam_ahead := 0.26
var elapsed := 0.0
var _fire_cd := 0.0
var _reload_t := 0.0
var _use_cd := 0.0
var _noise: FastNoiseLite
var _rough: FastNoiseLite
var _coast: FastNoiseLite
var _chunks := {}                 # Vector2i -> Node3D
var _models := {}                 # name -> PackedScene
var _zombies: Array = []
var _lootables: Array = []        # [{body, items, opened, label}]
var _looked_loot: Dictionary = {}
var _looked_pickup := -1
var _looked_zombie: Node = null
var _spawn_t := 0.0
var _rng := RandomNumberGenerator.new()
var _gun_mat: StandardMaterial3D
var _msg := ""
var _msg_t := 0.0
var _hurt_t := 0.0
var _step_d := 0.0
var players := {}

# --- autotest -----------------------------------------------------------------
var autotest := false
var autotest_frames := 600
var autotest_shot := ""
var autotest_hold := ""
var start_screen := "play"
var test_yaw := 999.0
var test_walk := 0
var frame := 0


func _ready() -> void:
	_parse_args()
	_rng.seed = 20261113
	_build_world()
	_build_player()
	_build_ui()
	_build_audio()
	_start_kit()
	_apply_quality()
	if autotest:
		_setup_test()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest": autotest = true
		elif a.begins_with("--frames="): autotest_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--shot="): autotest_shot = a.get_slice("=", 1)
		elif a.begins_with("--screen="): start_screen = a.get_slice("=", 1)
		elif a.begins_with("--hold="): autotest_hold = a.get_slice("=", 1)
		elif a.begins_with("--yaw="): test_yaw = float(a.get_slice("=", 1))
		elif a.begins_with("--walk="): test_walk = int(a.get_slice("=", 1))
		elif a.begins_with("--quality="): quality = clampi(Q_NAMES.find(a.get_slice("=", 1)), 0, 3)


# =====================================================================
# World
# =====================================================================

func _build_world() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = 1337
	_noise.frequency = 0.0032
	_noise.fractal_octaves = 4
	_rough = FastNoiseLite.new()
	_rough.seed = 99
	_rough.frequency = 0.021
	_coast = FastNoiseLite.new()
	_coast.seed = 2024
	_coast.frequency = 0.0022

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	# A washed-out, colourless sky: the pack's palette is for a world that
	# still has people in it.
	sky_mat.set_shader_parameter("day_top", Color(0.34, 0.40, 0.47))
	sky_mat.set_shader_parameter("day_horizon", Color(0.62, 0.64, 0.63))
	sky_mat.set_shader_parameter("dawn_top", Color(0.26, 0.29, 0.38))
	sky_mat.set_shader_parameter("dawn_horizon", Color(0.68, 0.56, 0.46))
	sky_mat.set_shader_parameter("dusk_top", Color(0.22, 0.23, 0.31))
	sky_mat.set_shader_parameter("dusk_horizon", Color(0.60, 0.44, 0.36))
	sky_mat.set_shader_parameter("cloud_day", Color(0.72, 0.73, 0.73))
	sky_mat.set_shader_parameter("cloud_night", Color(0.14, 0.15, 0.19))
	sky_mat.set_shader_parameter("sun_glow", 0.7)
	sky.sky_material = sky_mat
	env.sky = sky
	# The sky lights the world: ambient comes from it, so dawn is pink on the
	# walls and midnight is blue, without any of that being set by hand.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.50, 0.53, 0.55)
	env.fog_density = 0.013
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.5
	env.adjustment_enabled = true
	# Note: the compatibility renderer ignores these, which is why the drab
	# palette is baked into the shaders instead. Kept for desktop builds.
	env.adjustment_saturation = 0.72
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	world_env = env

	sun = DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 64.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 1.4
	add_child(sun)

	# The sea beyond the shore: one big plate at water level. It is what the
	# land falls into, and what stops the world looking like it was cut out.
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(WORLD_R * 4.0, WORLD_R * 4.0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.10, 0.26, 0.34)
	sm.roughness = 0.12
	sm.metallic = 0.35
	pm.material = sm
	sea.mesh = pm
	sea.position = Vector3(0, SEA_Y, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)

	fx = WorldFX.new()
	add_child(fx)

	_build_town()
	_build_loot_spots()
	_update_chunks(SPAWN, true)


## Ground height. Rolling hills from one noise field, with the land flattened
## off where the town stands so the streets are not on a slope.
func terrain_y(x: float, z: float) -> float:
	var h: float = _noise.get_noise_2d(x, z) * 17.0
	h += _rough.get_noise_2d(x, z) * 1.1
	var d := Vector2(x, z).length()
	# The land is finite: past the shore it falls away into the sea, with a
	# ragged coast rather than a circle. This is what gives the map a shape.
	var coast: float = WORLD_R + _coast.get_noise_2d(x * 0.6, z * 0.6) * 110.0
	if d > coast - 60.0:
		var t: float = clampf((d - (coast - 60.0)) / 60.0, 0.0, 1.0)
		h = lerpf(h, -14.0, t * t * (3.0 - 2.0 * t))
	if d < TOWN_R + 26.0:
		var flat: float = clampf((d - TOWN_R) / 26.0, 0.0, 1.0)
		h = lerpf(_town_level(), h, flat * flat * (3.0 - 2.0 * flat))
	return h


func _town_level() -> float:
	return _noise.get_noise_2d(0.0, 0.0) * 17.0


## Which biome a point is in: 0 pine forest, 1 jungle (low, wet), 2 dead
## ground (round ruins). Low ground goes to jungle; a second noise field
## carves the dead patches.
var _biome_noise: FastNoiseLite

func _biome(x: float, z: float) -> int:
	if _biome_noise == null:
		_biome_noise = FastNoiseLite.new()
		_biome_noise.seed = 555
		_biome_noise.frequency = 0.0045
	var dead: float = _biome_noise.get_noise_2d(x + 900.0, z - 400.0)
	if dead > 0.12:
		return 2
	var h := terrain_y(x, z)
	return 1 if h < -3.0 else 0


func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.6
	return Vector3(terrain_y(x - e, z) - terrain_y(x + e, z), 2.0 * e,
		terrain_y(x, z - e) - terrain_y(x, z + e)).normalized()


func _model(name: String, dir := "nature") -> PackedScene:
	if _models.has(name):
		return _models[name]
	var ext := ".fbx" if dir in ["nature", "loot"] else ".glb"
	if dir == "raft":
		pass
	var path := "res://assets/%s/%s%s" % [dir, name, ext]
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_models[name] = ps
	return ps


var _meshes := {}

## Folds a model's materials down into vertex colours on a single surface.
##
## The scenery pack paints each part of a tree with its own flat material -
## trunk, leaves, moss - which means several draw calls per tree and no way to
## put one shader on the whole thing. Since the colours are flat anyway, they
## are baked into the vertices here: a tree becomes one surface, every tree in
## a chunk becomes one instanced batch, and the wind shader can own all of it.
func _bake_colours(mesh: Mesh) -> ArrayMesh:
	if mesh == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		var base := Color(0.8, 0.8, 0.8)
		if mat is StandardMaterial3D:
			base = (mat as StandardMaterial3D).albedo_color
		elif mat is BaseMaterial3D:
			base = (mat as BaseMaterial3D).albedo_color
		var arr: Array = mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] else PackedColorArray()
		# Keep the texture coordinates. Dropping them was invisible for models
		# that carry only flat colours, but anything drawn on a shared atlas
		# then sampled the same corner pixel - which is how a field of rocks
		# came out solid black.
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array()
		var count: int = idx.size() if idx.size() > 0 else verts.size()
		for k in count:
			var vi: int = idx[k] if idx.size() > 0 else k
			var c := base
			if cols.size() > vi:
				c = Color(base.r * cols[vi].r, base.g * cols[vi].g, base.b * cols[vi].b, base.a)
			st.set_color(c)
			if norms.size() > vi:
				st.set_normal(norms[vi])
			if uvs.size() > vi:
				st.set_uv(uvs[vi])
			st.add_vertex(verts[vi])
	if st.get_aabb().size == Vector3.ZERO:
		return null
	return st.commit()


## One shared wind material per kind of plant. Grass whips, bushes bob, trees
## lean slowly: same shader, different numbers.
func _wind_mat(kind: String) -> ShaderMaterial:
	if _wind_mats.has(kind):
		return _wind_mats[kind]
	# Raft models share one atlas, so their batches need it on the material.
	var raft := kind.ends_with("_raft")
	kind = kind.replace("_raft", "")
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/toon_world.gdshader")
	# Everything green is knocked back toward olive and grey. A ruined world
	# does not have municipal lawns in it.
	m.set_shader_parameter("tint", Color(0.80, 0.80, 0.74))
	m.set_shader_parameter("desaturate", 0.52)
	m.set_shader_parameter("darken", 0.10)
	match kind:
		"grass":
			m.set_shader_parameter("sway_strength", 0.26)
			m.set_shader_parameter("sway_speed", 2.1)
			m.set_shader_parameter("height_scale", 0.6)
			m.set_shader_parameter("ao_strength", 0.45)
			m.set_shader_parameter("rim_strength", 0.5)
		"bush":
			m.set_shader_parameter("sway_strength", 0.10)
			m.set_shader_parameter("sway_speed", 1.4)
			m.set_shader_parameter("height_scale", 1.2)
			m.set_shader_parameter("ao_strength", 0.40)
		"tree":
			m.set_shader_parameter("sway_strength", 0.055)
			m.set_shader_parameter("sway_speed", 0.75)
			m.set_shader_parameter("height_scale", 7.0)
			m.set_shader_parameter("ao_strength", 0.22)
			m.set_shader_parameter("bands", 3)
			m.set_shader_parameter("shade_floor", 0.44)
		_:
			# rocks and stone: still, grey, and never bright - the pale ones
			# were rendering like marshmallows among the undergrowth
			m.set_shader_parameter("sway_strength", 0.0)
			m.set_shader_parameter("height_scale", 2.0)
			m.set_shader_parameter("ao_strength", 0.25)
			m.set_shader_parameter("bands", 4)
			m.set_shader_parameter("tint", Color(0.58, 0.58, 0.56))
			m.set_shader_parameter("desaturate", 0.4)
			m.set_shader_parameter("darken", 0.18)
	if kind == "tree":
		m.set_shader_parameter("tint", Color(0.78, 0.78, 0.72))
		m.set_shader_parameter("desaturate", 0.45)
	if raft:
		if _raft_tex == null:
			_raft_tex = load("res://assets/raft/texture.png")
		m.set_shader_parameter("use_texture", true)
		m.set_shader_parameter("albedo_texture", _raft_tex)
		m.set_shader_parameter("tint", Color(1, 1, 1))
	_wind_mats[kind + ("_raft" if raft else "")] = m
	return m


## How tall each kind of thing should end up, in metres. Packs disagree
## wildly about scale - one pack's boulder is five metres across, another's
## is knee high - so nothing is trusted to arrive at a sensible size. Every
## scattered model is measured and scaled to land near these.
const PLANT_HEIGHT := {"tree": 8.0, "bush": 1.4, "grass": 0.55, "rock": 1.3}

func _natural_height(name: String, dir: String) -> float:
	var pair := _mesh_of(name, dir)
	if pair[0] == null:
		return 1.0
	var box: AABB = (pair[1] as Transform3D) * (pair[0] as Mesh).get_aabb()
	# A fallen trunk is long, not tall: judging it by height alone blew a
	# half-metre log up into a nine-metre one. The long side has a say too.
	var long_side: float = maxf(box.size.x, box.size.z)
	return maxf(maxf(box.size.y, long_side * 0.45), 0.05)


func _plant_kind(name: String) -> String:
	if name.begins_with("EA04_Env_Plants_Grass"):
		return "grass"
	if name.begins_with("EA04_Env_Rocks") or name.begins_with("EA04_Env_Stone"):
		return "rock"
	if name.begins_with("EA04_Env_Tree") or name.begins_with("EA04_Env_Plants_Cactus"):
		return "bush"
	for g in GRASS:
		if g[0] == name:
			return "grass"
	for b in BUSHES:
		if b[0] == name:
			return "bush"
	for r in ROCKS:
		if r[0] == name:
			return "rock"
	return "tree"

## The mesh inside a model file, with whatever transform the pack baked into
## its node, so an instanced copy lands at the size and angle the artist drew
## it. Packs disagree wildly about units - some model in centimetres - and
## without this the forest comes out either microscopic or a hundred metres
## tall. Looked up once per model and kept.
func _mesh_of(name: String, dir := "nature") -> Array:
	if _meshes.has(name):
		return _meshes[name]
	var out: Array = [null, Transform3D()]
	var ps := _model(name, dir)
	if ps != null:
		var n: Node3D = ps.instantiate()
		var found: Array = n.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := found[0] as MeshInstance3D
			var xf := mi.transform
			var up: Node = mi.get_parent()
			while up != null and up != n:
				xf = (up as Node3D).transform * xf
				up = up.get_parent()
			out = [_bake_colours(mi.mesh), n.transform * xf]
		n.queue_free()
	_meshes[name] = out
	return out


# --- chunks -------------------------------------------------------------------

func _chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.z / CHUNK)))


func _update_chunks(around: Vector3, force := false) -> void:
	var c := _chunk_key(around)
	var want := {}
	for dx in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dz in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			want[k] = true
			if not _chunks.has(k):
				_chunks[k] = _build_chunk(k)
				if not force:
					return            # one chunk per frame keeps the hitch small
	for k in _chunks.keys():
		if not want.has(k):
			(_chunks[k] as Node3D).queue_free()
			_chunks.erase(k)


func _build_chunk(k: Vector2i) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	var step := CHUNK / float(CHUNK_GRID)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_col := Color(0.27, 0.29, 0.19)
	var dirt := Color(0.31, 0.28, 0.22)
	var rock := Color(0.38, 0.38, 0.37)
	var grid: Array = []
	for i in CHUNK_GRID + 1:
		var row: Array = []
		for j in CHUNK_GRID + 1:
			var x := x0 + step * i
			var z := z0 + step * j
			row.append(Vector3(x, terrain_y(x, z), z))
		grid.append(row)
	var add := func(v: Vector3) -> void:
		var n := _ground_normal(v.x, v.z)
		var slope := 1.0 - n.y
		var c: Color = grass_col.lerp(rock, clampf(slope * 3.4, 0.0, 1.0))
		match _biome(v.x, v.z):
			1: c = c.lerp(Color(0.21, 0.29, 0.18), 0.55)      # overgrown: dark, damp
			2: c = c.lerp(Color(0.33, 0.30, 0.24), 0.92)      # dead ground: ash and dust
		var d := Vector2(v.x, v.z).length()
		if d < TOWN_R * 0.8:
			c = c.lerp(dirt, clampf((TOWN_R * 0.8 - d) / 22.0, 0.0, 0.55))
		var n2: float = _rough.get_noise_2d(v.x * 2.0, v.z * 2.0)
		st.set_color(c.lightened(maxf(n2, 0.0) * 0.12).darkened(maxf(-n2, 0.0) * 0.14))
		st.set_normal(n)
		st.add_vertex(v)
	for i in CHUNK_GRID:
		for j in CHUNK_GRID:
			var p0: Vector3 = grid[i][j]
			var p1: Vector3 = grid[i][j + 1]
			var p2: Vector3 = grid[i + 1][j + 1]
			var p3: Vector3 = grid[i + 1][j]
			add.call(p0); add.call(p2); add.call(p1)
			add.call(p0); add.call(p3); add.call(p2)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ground_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.create_trimesh_collision()

	_scatter(root, k, x0, z0)
	_ruins(root, k, x0, z0)
	return root


## Trees, rocks and undergrowth for one chunk. Each kind of model is drawn as a
## single instanced batch, so a hundred pines cost one draw call, and only the
## trunks near enough to walk into get a collider.
func _scatter(root: Node3D, k: Vector2i, x0: float, z0: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) * 7919
	var batches := {}
	var place := func(name: String, dir: String, xf: Transform3D) -> void:
		if not batches.has(name):
			var pair := _mesh_of(name, dir)
			if pair[0] == null:
				return
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[0]
			batches[name] = [mm, [], pair[1], dir]
		(batches[name][1] as Array).append(xf * (batches[name][2] as Transform3D))

	# Trees come in stands rather than evenly spread: a few seed points per
	# chunk with a thick cluster round each, which reads as woodland instead
	# of an orchard.
	var groves: Array = []
	for i in rng.randi_range(2, 4):
		groves.append(Vector2(x0 + rng.randf() * CHUNK, z0 + rng.randf() * CHUNK))
	var density: int = 130
	for i in density:
		var x := x0 + rng.randf() * CHUNK
		var z := z0 + rng.randf() * CHUNK
		if rng.randf() < 0.55 and not groves.is_empty():
			var g: Vector2 = groves[rng.randi() % groves.size()]
			var ga := rng.randf() * TAU
			var gr := rng.randf() * rng.randf() * 13.0
			x = g.x + cos(ga) * gr
			z = g.y + sin(ga) * gr
		var d := Vector2(x, z).length()
		if d < TOWN_R * 0.92:
			continue                                   # the town is a clearing
		var y := terrain_y(x, z)
		if y < SEA_Y + 1.5:
			continue                                   # under water
		var n := _ground_normal(x, z)
		if n.y < 0.80:
			continue                                   # too steep to root in
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.85, 1.3)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z))
		var pick: Array
		var biome := _biome(x, z)
		if biome == 1:
			# jungle: palms and willows close together, thick undergrowth
			if roll < 0.45:
				pick = JUNGLE[rng.randi() % JUNGLE.size()]
				_trunk(root, Vector3(x, y, z), 0.3, 6.0)
			elif roll < 0.85:
				pick = JUNGLE_FLOOR[rng.randi() % JUNGLE_FLOOR.size()]
			else:
				pick = ROCKS[rng.randi() % ROCKS.size()]
		elif biome == 2:
			# dead ground: bare trees, rubble, the odd ruin
			if roll < 0.46:
				pick = DEAD[rng.randi() % DEAD.size()]
				_trunk(root, Vector3(x, y, z), 0.3, 4.0)
			elif roll < 0.56:
				pick = ROCKS[rng.randi() % ROCKS.size()]
			elif roll < 0.80:
				pick = DEAD_FLOOR[rng.randi() % DEAD_FLOOR.size()]
			else:
				pick = [["rubble_pile", "apoc"], ["bone_pile", "apoc"], ["tire_stack", "apoc"],
					["toxic_barrel", "apoc"]][rng.randi() % 4]
		elif roll < 0.38:
			# Trunks are solid wherever they are. They used to be solid only
			# near the middle of the map, so anywhere else you walked through
			# the forest as if it were painted on.
			pick = TREES[rng.randi() % TREES.size()]
			_trunk(root, Vector3(x, y, z), 0.34, 5.0)
		elif roll < 0.58:
			pick = DEAD_TREES[rng.randi() % DEAD_TREES.size()]
			_trunk(root, Vector3(x, y, z), 0.3, 4.0)
		elif roll < 0.64:
			pick = DEAD_FLOOR[rng.randi() % DEAD_FLOOR.size()]
		elif roll < 0.72:
			pick = ROCKS[rng.randi() % ROCKS.size()]
			_trunk(root, Vector3(x, y, z), 0.55, 1.0)
		else:
			pick = BUSHES[rng.randi() % BUSHES.size()]
		# Scale it to the height its kind should be, give or take.
		var kind0 := _plant_kind(str(pick[0]))
		var want_h: float = float(PLANT_HEIGHT.get(kind0, 1.5)) * rng.randf_range(0.75, 1.3)
		var fit: float = clampf(want_h / _natural_height(str(pick[0]), str(pick[1])), 0.2, 4.0)
		xf = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * fit), xf.origin)
		place.call(str(pick[0]), str(pick[1]), xf)

	# Ground cover: cheap, dense, and gone in the distance.
	var blades: int = Q_GRASS[quality]
	if blades > 0:
		for i in blades:
			var x := x0 + rng.randf() * CHUNK
			var z := z0 + rng.randf() * CHUNK
			if Vector2(x, z).length() < TOWN_R * 0.8:
				continue
			var y := terrain_y(x, z)
			if _ground_normal(x, z).y < 0.82:
				continue
			var g: Array = GRASS[rng.randi() % GRASS.size()]
			var gh: float = 0.55 * rng.randf_range(0.7, 1.4) / _natural_height(str(g[0]), str(g[1]))
			place.call(str(g[0]), str(g[1]),
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(gh, gh, gh)),
					Vector3(x, y, z)))
		# And the proper grass: tufted clumps with the EmacEArt wind shader,
		# thick near you and gone a short way off.
		_grass_carpet(root, rng, x0, z0, blades * 6)

	for name in batches:
		var mm: MultiMesh = batches[name][0]
		var list: Array = batches[name][1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var kind := _plant_kind(str(name))
		var dir2 := str(batches[name][3])
		mmi.material_override = _wind_mat(kind + ("_raft" if dir2 == "raft" else ""))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind == "tree" \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == "grass":
			mmi.visibility_range_end = 38.0
			mmi.visibility_range_end_margin = 6.0
		else:
			mmi.visibility_range_end = Q_DRAW[quality]
			mmi.visibility_range_end_margin = 14.0
		root.add_child(mmi)


var _ground_shader: ShaderMaterial

## One material for every chunk of ground: the terrain shader, which does the
## blotching, grain, dirt and haze that a flat vertex colour cannot.
func _ground_mat() -> ShaderMaterial:
	if _ground_shader == null:
		_ground_shader = ShaderMaterial.new()
		_ground_shader.shader = load("res://assets/shaders/terrain.gdshader")
	return _ground_shader


var _grass_mat: ShaderMaterial
var _grass_mesh: Mesh

## A carpet of grass clumps over a chunk, drawn as one instanced batch with
## the EmacEArt wind shader (textured, alpha-cut, gusting). It is what makes
## the ground read as ground instead of a green sheet.
func _grass_carpet(root: Node3D, rng: RandomNumberGenerator, x0: float, z0: float, count: int) -> void:
	if count <= 0:
		return
	if _grass_mesh == null:
		_grass_mesh = load("res://assets/grass/EA_Grass_Clump.mesh")
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = load("res://assets/grass/EA_GrassWind.gdshader")
		_grass_mat.set_shader_parameter("albedo_texture", load("res://assets/grass/GRASS_DIFF.tga"))
		_grass_mat.set_shader_parameter("normal_texture", load("res://assets/grass/GRASS_NMAP.tga"))
		_grass_mat.set_shader_parameter("base_color", Color(0.38, 0.37, 0.24))
		_grass_mat.set_shader_parameter("alpha_cutoff", 0.55)
		_grass_mat.set_shader_parameter("normal_strength", 0.5)
		_grass_mat.set_shader_parameter("wind_strength", 0.28)
		_grass_mat.set_shader_parameter("wind_speed", 1.1)
		_grass_mat.set_shader_parameter("wind_frequency", 0.7)
		_grass_mat.set_shader_parameter("gust_strength", 0.5)
		_grass_mat.set_shader_parameter("anchor_height", 1.0)
	if _grass_mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_mesh
	var xfs: Array = []
	for i in count:
		var x := x0 + rng.randf() * CHUNK
		var z := z0 + rng.randf() * CHUNK
		if Vector2(x, z).length() < TOWN_R * 0.75:
			continue
		if _ground_normal(x, z).y < 0.84:
			continue
		# Dead ground is bare: no grass grows round the ruins.
		if _biome(x, z) == 2:
			continue
		var sc := rng.randf_range(0.45, 0.85)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc)),
			Vector3(x, terrain_y(x, z) - 0.03, z)))
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 44.0
	mmi.visibility_range_end_margin = 10.0
	root.add_child(mmi)


func _trunk(root: Node3D, at: Vector3, r: float, h: float) -> void:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = r
	cy.height = h
	c.shape = cy
	b.add_child(c)
	b.position = at + Vector3(0, h * 0.5, 0)
	root.add_child(b)


# --- the town -----------------------------------------------------------------

# What each prop should measure in the world, in metres of height. The kit
# models at roughly quarter scale: next to a 1.75 m player its "barrel" was a
# bucket and its tent would not have slept a dog.
const PROP_HEIGHT := {
	"barrel": 0.95, "barrel-open": 0.95, "box": 0.55, "box-open": 0.58, "box-large": 0.55,
	"chest": 0.6, "tent": 1.7, "campfire-pit": 0.28, "bedroll": 0.35, "workbench": 0.95,
	"signpost": 2.1, "fence": 1.1, "bucket": 0.4, "resource-planks": 0.4,
}

## Drops a model from one of the packs into the world, at the size that thing
## really is rather than the size the pack happened to save it.
func _prop(parent: Node3D, name: String, at: Vector3, yaw: float, scale := 1.0, dir := "props") -> Node3D:
	var ps := _model(name, dir)
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = at
	n.rotation.y = yaw
	if PROP_HEIGHT.has(name):
		var h := _node_box(n).size.y
		if h > 0.001:
			scale *= float(PROP_HEIGHT[name]) / h
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if dir == "apoc" \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_toonify(m3, dir)
	return n


var _toon_cache := {}
var _raft_tex: Texture2D

## Re-dresses a model in the cel shader: its own colour and texture, lit in
## bands with a rim, so a crate out of one pack and a ruin out of another sit
## in the same world. Materials are shared by colour, so a street of props
## costs a handful of them.
func _toonify(m3: MeshInstance3D, dir: String) -> void:
	if m3.mesh == null:
		return
	if _raft_tex == null and dir == "raft":
		_raft_tex = load("res://assets/raft/texture.png")
	for si in m3.mesh.get_surface_count():
		var src := m3.mesh.surface_get_material(si) as BaseMaterial3D
		var col := src.albedo_color if src else Color.WHITE
		var tex: Texture2D = src.albedo_texture if src else null
		# The Raft models are drawn on one shared atlas that does not travel
		# inside the file, so it is put back on here.
		if tex == null and dir == "raft":
			tex = _raft_tex
		var key := "%s|%s" % [col, tex.resource_path if tex else "-"]
		if not _toon_cache.has(key):
			var tm := ShaderMaterial.new()
			tm.shader = load("res://assets/shaders/toon_world.gdshader")
			tm.set_shader_parameter("tint", col)
			tm.set_shader_parameter("sway_strength", 0.0)
			tm.set_shader_parameter("ao_strength", 0.12)
			tm.set_shader_parameter("bands", 4)
			tm.set_shader_parameter("rim_strength", 0.30)
			tm.set_shader_parameter("desaturate", 0.34)
			tm.set_shader_parameter("darken", 0.06)
			if tex:
				tm.set_shader_parameter("use_texture", true)
				tm.set_shader_parameter("albedo_texture", tex)
			_toon_cache[key] = tm
		m3.set_surface_override_material(si, _toon_cache[key])


func _flat_mat(c: Color, rough := 0.95, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


## A collider cut to the model: its own triangles for things with gaps you
## should be able to walk into (buildings, fences, barricades), its convex hull
## for solid lumps (vehicles, barrels, rocks). Nothing here is a box.
func _solid_shape(n: Node3D, exact := true) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_transform = n.global_transform
	var inv := body.global_transform.affine_inverse()
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = inv * mi.global_transform
		var col := CollisionShape3D.new()
		if exact:
			var faces: PackedVector3Array = mi.mesh.get_faces()
			if faces.size() < 3:
				continue
			for i in faces.size():
				faces[i] = xf * faces[i]
			var tri := ConcavePolygonShape3D.new()
			tri.backface_collision = true
			tri.set_faces(faces)
			col.shape = tri
		else:
			var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			if hull == null or hull.points.size() < 4:
				continue
			var pts: PackedVector3Array = hull.points
			for i in pts.size():
				pts[i] = xf * pts[i]
			var cv := ConvexPolygonShape3D.new()
			cv.points = pts
			col.shape = cv
		body.add_child(col)


## A box collider around a prop so you cannot walk through it.
func _solidify(n: Node3D, at: Vector3, r: float, h: float) -> void:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r * 2.0, h, r * 2.0)
	c.shape = bs
	b.add_child(c)
	b.position = at + Vector3(0, h * 0.5, 0)
	add_child(b)


# Every piece of the Apocalypse pack that is big enough to walk round or climb
# on, with how its collider is cut: true = its own triangles, false = hull.
const APOC_SOLID := {
	"ruined_apartment": true, "ruined_shop": true, "collapsed_house": true, "ruined_tower": true,
	"guard_tower": true, "bunker_entrance": true, "water_tank": false, "radio_antenna": false,
	"burnt_bus": false, "overturned_truck": false, "wrecked_car": false, "tipped_motorbike": false,
	"concrete_barrier": false, "sandbag_wall": false, "wooden_barricade": true, "barbed_fence": true,
	"rubble_pile": false, "tire_stack": false, "toxic_barrel": false, "burning_barrel": false,
	"supply_crate": false, "survivor_tent": false, "abandoned_shopping_cart": false,
	"broken_streetlight": false, "gas_mask_post": false, "dead_tree": false, "bone_pile": false,
	"traffic_light_fallen": false,
}

## The ruined town you start in: a cracked road through the middle, blocks of
## wrecked buildings either side, vehicles where they stopped, barricades
## where someone made a stand, and the things they left behind to search.
func _build_town() -> void:
	var y := _town_level()
	var town := Node3D.new()
	add_child(town)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var put := func(name: String, x: float, z: float, yaw: float, lootable := false) -> Node3D:
		var n := _prop(town, name, Vector3(x, y + 0.01, z), yaw, 1.0, "apoc")
		if n == null:
			return null
		if APOC_SOLID.has(name):
			_solid_shape(n, bool(APOC_SOLID[name]))
		if lootable:
			_make_lootable(n, Vector3(x, y + 0.45, z), 1.0, rng)
		return n

	# Road: slabs end to end along both axes, and the kerb-side wreckage.
	# Two slabs abreast: one row was a three-metre path pretending to be a
	# street. Six metres reads as a road a bus once used.
	for i in range(-14, 15):
		for lane in [-1.5, 1.5]:
			put.call("cracked_road_slab", float(i) * 3.0, lane, 0.0)
			put.call("cracked_road_slab", lane, float(i) * 3.0, PI * 0.5)
	# Buildings, set back from the road and facing it.
	var blocks := [
		["ruined_apartment", -14.0, -12.0, 0.0], ["ruined_shop", 12.0, -10.0, PI],
		["collapsed_house", -12.0, 11.0, PI * 0.5], ["ruined_apartment", 15.0, 12.0, -PI * 0.5],
		["ruined_shop", -24.0, -2.0, PI * 0.5], ["ruined_tower", 24.0, -24.0, 0.0],
		["guard_tower", -26.0, 22.0, 0.0], ["bunker_entrance", 8.0, 26.0, PI],
		["water_tank", 26.0, 4.0, 0.0], ["radio_antenna", -22.0, -24.0, 0.0],
		["collapsed_house", 22.0, 24.0, PI * 0.25], ["survivor_tent", -10.0, 24.0, 0.4],
		["survivor_tent", -6.0, 26.0, -0.5],
	]
	for b in blocks:
		put.call(str(b[0]), float(b[1]), float(b[2]), float(b[3]))
	# Vehicles on and beside the road.
	for v in [["burnt_bus", 6.0, -5.0, 0.3], ["wrecked_car", -8.0, 4.0, 1.3],
			["overturned_truck", 5.0, 16.0, PI * 0.5 + 0.2], ["wrecked_car", -5.0, -16.0, -0.4],
			["tipped_motorbike", 10.0, 6.0, 2.0], ["abandoned_shopping_cart", 14.0, -3.0, 1.0]]:
		put.call(str(v[0]), float(v[1]), float(v[2]), float(v[3]))
	# Someone's last stand across the north road, and street furniture.
	for k in [["sandbag_wall", -3.0, -20.0, 0.0], ["sandbag_wall", 3.0, -20.0, 0.0],
			["concrete_barrier", 0.0, -22.0, 0.0], ["wooden_barricade", -3.0, 20.0, 0.0],
			["barbed_fence", 3.0, 20.0, 0.0], ["broken_streetlight", -4.5, -8.0, 0.0],
			["broken_streetlight", 4.5, 8.0, PI], ["traffic_light_fallen", 5.0, -12.0, 0.8],
			["gas_mask_post", -4.5, 12.0, 0.0], ["bone_pile", 9.0, -14.0, 1.1],
			["rubble_pile", -16.0, -6.0, 0.5], ["rubble_pile", 17.0, 15.0, 2.2],
			["tire_stack", 13.0, 1.0, 0.0], ["dead_tree", -18.0, 16.0, 0.0], ["dead_tree", 19.0, -16.0, 1.5]]:
		put.call(str(k[0]), float(k[1]), float(k[2]), float(k[3]))
	# Things worth searching, spread between the buildings.
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(6.0, 30.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if absf(x) < 2.0 or absf(z) < 2.0:
			continue
		var kind: String = ["supply_crate", "toxic_barrel", "burning_barrel", "supply_crate"][rng.randi() % 4]
		put.call(kind, x, z, rng.randf() * TAU, true)
	_map_marks.append({"pos": Vector3.ZERO, "kind": "town"})
	print("TOWN: %d lootable containers" % _lootables.size())


## Crates, barrels and a tent or two dropped around the start area. This is
## the stand-in for buildings and their contents until there are models for
## them: somewhere to walk to, something to search, and a reason to be out in
## the open where the zombies are.
## Ruins out in the world: a wrecked house or two, a camp, a bunker, every
## few hundred metres, each with something to search. Placed by a hash of
## the chunk so they are always in the same place.
func _ruins(root: Node3D, k: Vector2i, x0: float, z0: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) * 31 + 7
	if rng.randf() > 0.46:
		return
	var x := x0 + rng.randf_range(8.0, CHUNK - 8.0)
	var z := z0 + rng.randf_range(8.0, CHUNK - 8.0)
	if Vector2(x, z).length() < TOWN_R + 20.0 or _ground_normal(x, z).y < 0.9:
		return
	var y := terrain_y(x, z)
	var yaw := rng.randf() * TAU
	var main: String = RUINS[rng.randi() % RUINS.size()]
	var n := _prop(root, main, Vector3(x, y, z), yaw, 1.0, "apoc")
	if n and APOC_SOLID.has(main):
		_solid_shape(n, bool(APOC_SOLID[main]))
	_map_marks.append({"pos": Vector3(x, y, z), "kind": "ruin"})
	for i in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 9.0)
		var px := x + cos(a) * r
		var pz := z + sin(a) * r
		var kind: String = ["supply_crate", "toxic_barrel", "burning_barrel", "survivor_tent",
			"wooden_barricade", "sandbag_wall", "abandoned_shopping_cart"][rng.randi() % 7]
		var p := _prop(root, kind, Vector3(px, terrain_y(px, pz), pz), rng.randf() * TAU, 1.0, "apoc")
		if p == null:
			continue
		if APOC_SOLID.has(kind):
			_solid_shape(p, bool(APOC_SOLID[kind]))
		if kind in ["supply_crate", "toxic_barrel"]:
			_make_lootable(p, Vector3(px, terrain_y(px, pz) + 0.45, pz), 1.0, rng)


func _build_loot_spots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var holder := Node3D.new()
	add_child(holder)
	for i in 18:
		var a := rng.randf() * TAU
		var r := rng.randf_range(48.0, 110.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if _ground_normal(x, z).y < 0.88:
			continue
		var at := Vector3(x, terrain_y(x, z), z)
		var kind: String = ["barrel", "box", "box-large", "chest", "barrel-open", "box-open",
			"tent", "campfire-pit", "bedroll", "workbench", "signpost"][rng.randi() % 11]
		var n := _prop(holder, kind, at, rng.randf() * TAU, 1.0)
		if n == null:
			continue
		if kind in ["barrel", "box", "box-large", "chest", "barrel-open", "box-open"]:
			_make_lootable(n, at + Vector3(0, 0.45, 0), 0.9, rng)
			_solidify(n, at, 0.45, 0.9)
	print("WORLD: %d lootable containers" % _lootables.size())


## Containers you can search. The pick body is a box you can put the crosshair
## on; what is inside is rolled when the world is made, not when you open it,
## so two people in a co-op game would find the same thing.
func _make_lootable(node: Node3D, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 0
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r, 1.0, r)
	c.shape = bs
	b.add_child(c)
	b.position = at
	add_child(b)
	var items: Array = []
	# The further from the start, the better the finds: the reason to walk
	# out past the treeline instead of looping the same six crates.
	var far_bonus: float = clampf(at.length() / 420.0, 0.0, 1.0)
	var tries: int = rng.randi_range(2, 4)
	if rng.randf() < far_bonus * 0.8:
		items.append([{"id": "revolver", "n": 1}, {"id": "medkit", "n": 1},
			{"id": "axe", "n": 1}, {"id": "9mm", "n": rng.randi_range(14, 26)}][rng.randi() % 4])
	for i in tries:
		for id in ITEMS:
			var chance: float = float(ITEMS[id].get("loot", 0.0))
			if chance > 0.0 and rng.randf() < chance * 0.42:
				var n := 1
				if id == "9mm":
					n = rng.randi_range(6, 18)
				elif int(ITEMS[id].get("stack", 1)) > 1:
					n = rng.randi_range(1, 2)
				items.append({"id": id, "n": n})
				break
	var entry := {"body": b, "items": items, "opened": false, "node": node}
	b.set_meta("loot", _lootables.size())
	_lootables.append(entry)


# =====================================================================
# Player, view and HUD
# =====================================================================

func _build_player() -> void:
	player = Player.new()
	player.collision_layer = 1
	player.collision_mask = 1 | 2
	player.position = Vector3(SPAWN.x, terrain_y(SPAWN.x, SPAWN.z) + 1.0, SPAWN.z)
	add_child(player)
	camera = Camera3D.new()
	camera.fov = 71.0
	camera.near = 0.05
	camera.far = 420.0
	add_child(camera)
	hands = FPHands.new()
	camera.add_child(hands)

	render_view = RenderView.new()
	add_child(render_view)
	render_view.setup(camera, get_world_3d())


func _build_ui() -> void:
	touch = Touch.new()
	add_child(touch)
	touch.interact_pressed.connect(_on_action)
	touch.secondary_pressed.connect(_on_secondary)
	touch.slot_pressed.connect(_select_slot)
	touch.jump_pressed.connect(func() -> void:
		if player:
			player.jump())
	status = StatusUI.new()
	add_child(status)
	# Hotbar pictures are rendered from the items' own models, one at a time
	# in a tiny off-screen viewport, so a slot shows the thing you are holding.
	icons = IconBaker.new()
	add_child(icons)
	icons.baked.connect(func(_k: String) -> void: _sync_hotbar())
	# The map is painted from the same functions that built the ground, so it
	# cannot disagree with the world.
	map_ui = MapUI.new()
	map_ui.world_r = WORLD_R
	map_ui.sea_y = SEA_Y
	map_ui.height_at = func(x: float, z: float) -> float: return terrain_y(x, z)
	map_ui.biome_at = func(x: float, z: float) -> int: return _biome(x, z)
	add_child(map_ui)
	map_ui.bake()
	map_ui.marks = _map_marks
	status.respawn_pressed.connect(_respawn)


var _voices: Array = []           # 3D mouths, borrowed in turn
var _voice_next := 0

## A sound from a place: moans, blows and bodies come from where they happen,
## not from inside your head. A small pool of 3D players is reused in turn.
func _play_at(key: String, at: Vector3, pitch := 1.0, vol_db := 0.0) -> void:
	if _voices.is_empty():
		for i in 6:
			var v := AudioStreamPlayer3D.new()
			v.max_distance = 46.0
			v.unit_size = 7.0
			v.attenuation_filter_cutoff_hz = 4500.0
			add_child(v)
			_voices.append(v)
	var p: AudioStreamPlayer3D = _voices[_voice_next]
	_voice_next = (_voice_next + 1) % _voices.size()
	if not players.has(key):
		return
	p.stream = (players[key] as AudioStreamPlayer).stream
	p.global_position = at
	p.pitch_scale = pitch
	p.volume_db = vol_db
	p.play()


func _build_audio() -> void:
	var streams := {
		"shot": Sfx.gunshot(), "reload": Sfx.gun_reload(), "hit": Sfx.bonk(),
		"hurt": Sfx.hurt(), "pickup": Sfx.pickup(), "click": Sfx.click(),
		"step": Sfx.step_soft(), "wood": Sfx.step_wood(), "swing": Sfx.whoosh(),
		"snap": Sfx.snap(), "moan": Sfx.moan(), "moan_near": Sfx.moan(),
	}
	for key in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		add_child(p)
		players[key] = p
	# The world is never silent: wind, all the time, louder at night.
	var amb := AudioStreamPlayer.new()
	amb.stream = Sfx.wind_loop()
	amb.volume_db = -22.0
	amb.autoplay = true
	add_child(amb)
	amb.play()
	players["wind"] = amb
	players["moan"].volume_db = -14.0
	players["moan_near"].volume_db = -7.0
	players["step"].volume_db = -12.0


func _start_kit() -> void:
	inv.clear()
	for i in SLOTS:
		inv.append({})
	inv[0] = {"id": "pistol", "n": 1}
	inv[1] = {"id": "knife", "n": 1}
	inv[2] = {"id": "9mm", "n": 24}
	inv[3] = {"id": "bandage", "n": 2}
	sel = 0
	ammo_loaded = int(ITEMS["pistol"]["mag"])
	_apply_held()
	_sync_hotbar()


func _apply_quality() -> void:
	var q := clampi(quality, 0, 3)
	if render_view:
		render_view.set_quality(Q_SCALE[q], true, Q_ROWS[q])
	if sun:
		sun.shadow_enabled = Q_SHADOW[q] > 0
		if Q_SHADOW[q] > 0:
			sun.set("directional_shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED


# =====================================================================
# Loop
# =====================================================================

func _process(delta: float) -> void:
	frame += 1
	elapsed += delta
	if autotest:
		_drive_test()
	if dead:
		_update_hud()
		return
	clock += delta
	if clock > DAY_LENGTH:
		clock -= DAY_LENGTH
		day += 1
	_update_sky()
	_update_player(delta)
	_update_chunks(player.global_position)
	_update_zombies(delta)
	_update_pickups(delta)
	_update_survival(delta)
	_update_look()
	_update_hud()


func _update_player(delta: float) -> void:
	var look: Vector2 = touch.consume_look()
	cam_yaw -= look.x
	cam_pitch = clampf(cam_pitch - look.y, -1.40, 1.25)
	player.move_input = touch.move
	player.cam_yaw = cam_yaw
	player.cam_pitch = cam_pitch
	var want_sprint: bool = touch.sprint and stamina > 0.05 and touch.move.length() > 0.4
	player.sprint = want_sprint
	stamina = clampf(stamina + (-0.26 if want_sprint else 0.16) * delta, 0.0, 1.0)
	player.carry_slow = 1.0 if food > 15.0 and water > 15.0 else 0.72

	var head := player.global_position + Vector3(0, EYE, 0)
	var fwd := (Basis(Vector3.UP, cam_yaw) * Vector3(0, 0, -1)).normalized()
	var ahead := 0.26
	var wq := PhysicsRayQueryParameters3D.create(head, head + fwd * 0.5)
	wq.collision_mask = 1
	wq.exclude = [player.get_rid()]
	var wh := get_world_3d().direct_space_state.intersect_ray(wq)
	if not wh.is_empty():
		ahead = clampf(head.distance_to(wh["position"]) - 0.24, -0.05, 0.26)
	_cam_ahead = lerpf(_cam_ahead, ahead, clampf(delta * 14.0, 0.0, 1.0)) if ahead > _cam_ahead else ahead
	camera.global_position = head + fwd * _cam_ahead
	_shake = maxf(_shake - delta * 2.4, 0.0)
	var jolt := Vector3.ZERO
	if _shake > 0.001:
		var k := _shake * _shake
		jolt = Vector3(sin(elapsed * 51.0) * 0.022, sin(elapsed * 47.0 + 1.7) * 0.018,
			sin(elapsed * 43.0 + 0.6) * 0.03) * k
	camera.rotation = Vector3(cam_pitch + _recoil() + jolt.x, cam_yaw + jolt.y, jolt.z)

	# Footsteps, paced by distance covered rather than a timer.
	var sp := Vector2(player.velocity.x, player.velocity.z).length()
	_step_d += sp * delta
	if _step_d > (2.3 if want_sprint else 1.7) and player.is_on_floor():
		_step_d = 0.0
		players["step"].pitch_scale = randf_range(0.85, 1.15)
		players["step"].play()

	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_use_cd = maxf(_use_cd - delta, 0.0)
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			_finish_reload()
	hands.move_speed = sp
	hands.sprint = want_sprint
	hands.mode = _hands_mode()


var _recoil_amt := 0.0

func _recoil() -> float:
	_recoil_amt = lerpf(_recoil_amt, 0.0, 0.12)
	return _recoil_amt


func _hands_mode() -> String:
	var it := held()
	if it.is_empty():
		return "bare"
	var kind := str(ITEMS[str(it["id"])].get("kind", "junk"))
	if kind == "gun":
		return "gun"
	return "melee" if kind == "melee" else "bare"


func held() -> Dictionary:
	if sel < 0 or sel >= SLOTS or inv[sel].is_empty():
		return {}
	return inv[sel]


func held_id() -> String:
	var it := held()
	return str(it.get("id", "")) if not it.is_empty() else ""


func _update_survival(delta: float) -> void:
	food = maxf(food - delta * 0.42, 0.0)
	water = maxf(water - delta * 0.55, 0.0)
	if food <= 0.0 or water <= 0.0:
		_damage(delta * 1.6, "starved")
	elif health < 100.0:
		health = minf(health + delta * 0.6, 100.0)
	_hurt_t = maxf(_hurt_t - delta, 0.0)


## The sun is moved by the clock and the sky shader is told the hour; the two
## stay in step because the shader draws its sun at the light's own direction.
func _update_sky() -> void:
	var t := clock / DAY_LENGTH            # 0 midnight .. 0.5 noon
	var hour := t * 24.0
	var ang := (t - 0.25) * TAU
	# A tilted arc, so the light sweeps across the town instead of straight
	# over it, and shadows stretch out morning and evening.
	var up: float = clampf(sin(ang) * 1.5, -1.0, 1.0)
	var light: float = clampf(up * 0.5 + 0.5, 0.0, 1.0)
	var low: float = clampf(1.0 - absf(up) * 2.2, 0.0, 1.0)      # near the horizon
	if up > 0.0:
		sun.rotation = Vector3(-ang, 0.55 + sin(ang) * 0.25, 0.0)
		# Weak and colourless: the sun is behind cloud most of the time.
		sun.light_energy = lerpf(0.0, 0.85, clampf(up * 2.2, 0.0, 1.0))
		sun.light_color = Color(0.92, 0.91, 0.86).lerp(Color(0.86, 0.58, 0.40), low)
	else:
		# After dark the one light is the moon, opposite the sun, cold and
		# faint - enough to make out shapes, not enough to see colour.
		sun.rotation = Vector3(-ang + PI, 0.55, 0.0)
		sun.light_energy = 0.16 * clampf(-up * 2.5, 0.0, 1.0)
		sun.light_color = Color(0.62, 0.70, 0.95)
	sun.light_angular_distance = lerpf(0.6, 3.0, low)
	world_env.ambient_light_energy = lerpf(0.30, 0.70, light)
	var fog_day := Color(0.52, 0.55, 0.56)
	var fog_night := Color(0.09, 0.11, 0.18)
	var fog_dusk := Color(0.44, 0.31, 0.26)
	world_env.fog_light_color = fog_night.lerp(fog_day, light).lerp(fog_dusk, low * 0.7)
	world_env.fog_density = lerpf(0.030, 0.0105, light)
	if players.has("wind"):
		players["wind"].volume_db = lerpf(-16.0, -23.0, light)
	if sky_mat:
		sky_mat.set_shader_parameter("hour", hour)
		# Heavy cover most of the time: the sun rarely gets through.
		sky_mat.set_shader_parameter("cloud_cover", 0.66 + 0.16 * sin(elapsed * 0.012))


func is_night() -> bool:
	var t := clock / DAY_LENGTH
	return t < 0.22 or t > 0.80


# =====================================================================
# Zombies
# =====================================================================

func _update_zombies(delta: float) -> void:
	_spawn_t -= delta
	for i in range(_zombies.size() - 1, -1, -1):
		var z = _zombies[i]
		if not is_instance_valid(z):
			_zombies.remove_at(i)
			continue
		if z.global_position.distance_to(player.global_position) > 140.0:
			z.queue_free()
			_zombies.remove_at(i)
	var cap: int = Q_ZOMBIES[quality]
	if is_night():
		cap = int(cap * 1.4)
	if _spawn_t <= 0.0 and _zombies.size() < cap:
		_spawn_t = 1.2
		_spawn_zombie()


func _spawn_zombie() -> void:
	# Somewhere out of sight: behind you, or far enough that you won't see it
	# appear. Never inside a wall and never on a cliff.
	for attempt in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(34.0, 68.0)
		var p := player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		var to := (p - player.global_position).normalized()
		var fwd := (Basis(Vector3.UP, cam_yaw) * Vector3(0, 0, -1)).normalized()
		if to.dot(fwd) > 0.3 and r < 55.0:
			continue
		if _ground_normal(p.x, p.z).y < 0.85:
			continue
		p.y = terrain_y(p.x, p.z) + 0.1
		var z = Zombie.new()
		add_child(z)
		z.setup(self, p, _rng.randi(), _rng.randf() < 0.18)
		_zombies.append(z)
		return


func zombie_hit_player(amount: float, _z: Node) -> void:
	_damage(amount, "mauled")
	_shake = maxf(_shake, 0.65)
	if status:
		status.hit(clampf(amount / 30.0, 0.2, 1.0))
	players["hurt"].play()


func zombie_moan(at: Vector3, near: bool) -> void:
	_play_at("moan", at, randf_range(0.75, 1.05), 0.0 if near else -7.0)


func zombie_hurt(z: Node, where: String, amount: float) -> void:
	if fx:
		fx.blood(z.global_position + Vector3(0, 1.2 if where == "head" else 0.9, 0), where == "head")
	_play_at("hit", z.global_position + Vector3(0, 1.1, 0),
		randf_range(0.9, 1.2) * (1.3 if where == "head" else 1.0))
	if where == "head" and amount > 40.0:
		_flash_msg("Headshot!")


func zombie_died(z: Node) -> void:
	kills += 1
	_flash_msg("Zombie down  (%d)" % kills)
	# What it was carrying. Most have nothing; ammunition is the commonest
	# find, and the rare ones make a kill feel like a win.
	var roll := randf()
	var at: Vector3 = (z as Node3D).global_position
	if roll < 0.30:
		_drop_item("9mm", randi_range(3, 8), at)
	elif roll < 0.42:
		_drop_item(["bandage", "can", "water"][randi() % 3], 1, at)
	elif roll < 0.455:
		_drop_item(["medkit", "revolver"][randi() % 2], 1, at)


# =====================================================================
# Looking, shooting, looting
# =====================================================================

func _update_look() -> void:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = camera.global_position
	var to := from - camera.global_transform.basis.z * 3.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 4                       # loot pick bodies
	var hit := space.intersect_ray(q)
	_looked_loot = {}
	_looked_pickup = -1
	if not hit.is_empty() and hit.has("collider"):
		var c = hit["collider"]
		if c and c.has_meta("loot"):
			var idx := int(c.get_meta("loot"))
			if idx < _lootables.size():
				_looked_loot = _lootables[idx]
		elif c and c.has_meta("pickup"):
			_looked_pickup = int(c.get_meta("pickup"))
	# And whatever zombie is under the crosshair, for the name tag.
	_looked_zombie = null
	var q2 := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * 40.0)
	q2.collision_mask = 2
	q2.exclude = [player.get_rid()]
	var h2 := space.intersect_ray(q2)
	if not h2.is_empty() and h2.has("collider"):
		var c2 = h2["collider"]
		if c2 and c2.has_method("take_damage"):
			_looked_zombie = c2


func _on_action() -> void:
	if dead:
		return
	var p: String = touch.shown_prompt()
	match p:
		"LOOT":
			_loot(_looked_loot)
		"TAKE":
			_take_pickup(_looked_pickup)
		"SHOOT":
			_shoot()
		"RELOAD":
			_start_reload()
		"SWING":
			_melee()
		"EAT", "DRINK", "USE":
			_use_item()
		_:
			_melee()


func _on_secondary() -> void:
	if dead:
		return
	if held_id() != "" and str(ITEMS[held_id()].get("kind", "")) == "gun":
		_start_reload()


func _shoot() -> void:
	if dead:
		return
	var id := held_id()
	if id == "" or str(ITEMS[id].get("kind", "")) != "gun":
		return
	if _fire_cd > 0.0 or _reload_t > 0.0:
		return
	if ammo_loaded <= 0:
		_start_reload()
		return
	ammo_loaded -= 1
	_fire_cd = float(ITEMS[id]["rate"])
	_recoil_amt += 0.034
	players["shot"].pitch_scale = randf_range(0.96, 1.05)
	players["shot"].play()
	if hands:
		hands.play_fire()
		hands.muzzle_flash()
	# Everything within earshot comes to look.
	for z in _zombies:
		if is_instance_valid(z):
			z.hear(player.global_position, 1.0)

	var from: Vector3 = camera.global_position
	var aim := -camera.global_basis.z
	var spread := 0.004 + (0.014 if player.velocity.length() > 2.5 else 0.0)
	aim = (aim + camera.global_basis.x * randf_range(-spread, spread)
		+ camera.global_basis.y * randf_range(-spread, spread)).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + aim * 120.0)
	q.collision_mask = 1 | 2
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var at: Vector3 = hit["position"]
	var body = hit.get("collider")
	if body and body.has_method("take_damage"):
		var rel: float = at.y - body.global_position.y
		var where := "body"
		if rel > 1.35:
			where = "head"
		elif rel < 0.75:
			where = "leg"
		body.take_damage(float(ITEMS[id]["dmg"]), where, from)
	elif fx:
		fx.dust(at, 0.6)


func _start_reload() -> void:
	if dead:
		return
	var id := held_id()
	if id == "" or str(ITEMS[id].get("kind", "")) != "gun" or _reload_t > 0.0:
		return
	var mag := int(ITEMS[id]["mag"])
	if ammo_loaded >= mag or _count(str(ITEMS[id]["ammo"])) <= 0:
		return
	_reload_t = 1.35
	players["reload"].play()
	if hands:
		hands.play_reload(1.35)


func _finish_reload() -> void:
	var id := held_id()
	if id == "" or str(ITEMS[id].get("kind", "")) != "gun":
		return
	var kind := str(ITEMS[id]["ammo"])
	var mag := int(ITEMS[id]["mag"])
	var need := mag - ammo_loaded
	var have := _count(kind)
	var take := mini(need, have)
	ammo_loaded += take
	_take(kind, take)
	_sync_hotbar()


func _melee() -> void:
	if dead or _use_cd > 0.0:
		return
	var id := held_id()
	var dmg := 14.0
	var rate := 0.5
	if id != "" and str(ITEMS[id].get("kind", "")) == "melee":
		dmg = float(ITEMS[id]["dmg"])
		rate = float(ITEMS[id]["rate"])
	_use_cd = rate
	players["swing"].pitch_scale = randf_range(1.2, 1.5)
	players["swing"].play()
	if hands:
		if id != "" and str(ITEMS[id].get("kind", "")) == "melee":
			hands.play_swing()
		else:
			hands.play_punch()
	var from: Vector3 = camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 2.3)
	q.collision_mask = 2
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.has("collider"):
		var b = hit["collider"]
		if b and b.has_method("take_damage"):
			var rel: float = float(hit["position"].y) - b.global_position.y
			b.take_damage(dmg, "head" if rel > 1.35 else "body", from)


func _loot(entry: Dictionary) -> void:
	if entry.is_empty() or bool(entry.get("opened", false)):
		return
	entry["opened"] = true
	var got: Array = []
	for it in entry["items"]:
		if _give(str(it["id"]), int(it["n"])):
			got.append("%s%s" % [str(ITEMS[str(it["id"])]["name"]),
				(" x%d" % int(it["n"])) if int(it["n"]) > 1 else ""])
	players["pickup"].play()
	_flash_msg("Found: " + ", ".join(got) if not got.is_empty() else "Empty")
	var n = entry.get("node")
	if n and is_instance_valid(n):
		# Swap a closed container for its open version where the pack has one.
		for mi in (n as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.45, 0.42, 0.38)
			mat.roughness = 1.0
			m.material_overlay = mat
	_sync_hotbar()


func _use_item() -> void:
	var it := held()
	if dead or it.is_empty() or _use_cd > 0.0:
		return
	var id := str(it["id"])
	var info: Dictionary = ITEMS[id]
	var kind := str(info.get("kind", ""))
	_use_cd = 0.8
	match kind:
		"heal":
			if health >= 100.0:
				_flash_msg("You're not hurt")
				return
			health = minf(health + float(info["heal"]), 100.0)
			_flash_msg("Patched up")
		"food":
			food = minf(food + float(info["food"]), 100.0)
			_flash_msg("Ate the " + str(info["name"]).to_lower())
		"drink":
			water = minf(water + float(info["water"]), 100.0)
			_flash_msg("Drank the water")
		_:
			return
	players["pickup"].play()
	_take(id, 1)
	_sync_hotbar()
	_apply_held()


# --- inventory ----------------------------------------------------------------

func _count(id: String) -> int:
	var n := 0
	for it in inv:
		if not it.is_empty() and str(it["id"]) == id:
			n += int(it["n"])
	return n


func _take(id: String, n: int) -> void:
	var left := n
	for i in SLOTS:
		if left <= 0:
			break
		if inv[i].is_empty() or str(inv[i]["id"]) != id:
			continue
		var have := int(inv[i]["n"])
		var used := mini(have, left)
		left -= used
		if have - used <= 0:
			inv[i] = {}
		else:
			inv[i]["n"] = have - used


func _give(id: String, n: int) -> bool:
	if not ITEMS.has(id):
		return false
	var stack := int(ITEMS[id].get("stack", 1))
	if stack > 1:
		for i in SLOTS:
			if not inv[i].is_empty() and str(inv[i]["id"]) == id and int(inv[i]["n"]) < stack:
				inv[i]["n"] = mini(int(inv[i]["n"]) + n, stack)
				return true
	for i in SLOTS:
		if inv[i].is_empty():
			inv[i] = {"id": id, "n": n}
			return true
	return false


func _select_slot(i: int) -> void:
	if i < 0 or i >= SLOTS or dead:
		return
	sel = i
	_reload_t = 0.0
	var id := held_id()
	if id != "" and str(ITEMS[id].get("kind", "")) == "gun":
		ammo_loaded = mini(int(ITEMS[id]["mag"]), _count(str(ITEMS[id]["ammo"])) + ammo_loaded)
	players["click"].play()
	_apply_held()
	_sync_hotbar()


## Puts the right thing in your hands: the model goes on the right hand's bone
## attachment, so it follows the animation instead of being pinned to the view.
func _apply_held() -> void:
	if hands == null:
		return
	var id := held_id()
	if id == "" or not ITEMS.has(id):
		hands.mount(null)
		return
	var info: Dictionary = ITEMS[id]
	var path := str(info.get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		hands.mount(null)
		return
	var m: Node3D = (load(path) as PackedScene).instantiate()
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if id == "pistol":
		var tex := "res://assets/models/guns/1911.png"
		if ResourceLoader.exists(tex):
			if _gun_mat == null:
				_gun_mat = StandardMaterial3D.new()
				_gun_mat.albedo_texture = load(tex)
				_gun_mat.metallic = 0.5
				_gun_mat.roughness = 0.45
			for mi in m.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = _gun_mat
		for extra in ["Mag", "45 ACP", "45 ACP Blank"]:
			var e := m.find_child(extra, true, false)
			if e:
				e.get_parent().remove_child(e)
				e.queue_free()
	# Normalise the model's own convention first: grip on the origin, barrel
	# down -Z. The arm rig then points the whole thing where you are looking.
	var holder := Node3D.new()
	holder.add_child(m)
	m.transform = _grip_of(id)
	# Size what is in the fist by measuring it. The loot pack saves its knife
	# one centimetre long and its axe at a third of size; trusted raw, the
	# knife in your hand was literally invisible.
	if id != "pistol":
		var box := _node_box(m)
		var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var want: float = {"knife": 0.34, "axe": 0.82, "revolver": 0.28}.get(id, 0.4)
		if longest > 0.0005:
			m.scale *= want / longest
	hands.mount(holder)
	hands.aim_offset(Vector3(0.0, 0.015, -0.03))


## How each item sits in the fist. Every pack models at its own size and
## facing, so these are measured per item rather than guessed at.
func _grip_of(id: String) -> Transform3D:
	match id:
		"pistol":
			# the pack models it barrel-forward with the grip off the origin
			return Transform3D(Basis(Vector3.UP, PI), Basis(Vector3.UP, PI) * -Vector3(-0.0124, 0.062, -0.034))
		"revolver":
			return Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO)
		"axe", "knife":
			return Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3.ZERO)
	return Transform3D()


func _damage(amount: float, cause: String) -> void:
	if dead:
		return
	health -= amount
	_hurt_t = 0.6
	if health <= 0.0:
		health = 0.0
		dead = true
		player.frozen = true
		# Everything you were carrying stays where you fell. Getting back to
		# your own corpse with a knife is the oldest loop in the genre, and
		# it is what makes dying matter without ending the run.
		var spill := 0.0
		for i in SLOTS:
			if inv[i].is_empty():
				continue
			var off := Vector3(cos(spill) * 0.8, 0, sin(spill) * 0.8)
			_drop_item(str(inv[i]["id"]), int(inv[i]["n"]), player.global_position + off)
			spill += 1.3
			inv[i] = {}
		status.show_death("YOU DIED", "%s on day %d  ·  %d zombies killed  ·  your gear is where you fell" % [
			cause.capitalize(), day, kills])


func _respawn() -> void:
	dead = false
	health = 100.0
	food = 70.0
	water = 70.0
	# You come back with a knife and a dressing, nothing more.
	for i in SLOTS:
		inv[i] = {}
	inv[0] = {"id": "knife", "n": 1}
	inv[1] = {"id": "bandage", "n": 1}
	sel = 0
	ammo_loaded = 0
	_apply_held()
	_sync_hotbar()
	player.frozen = false
	player.global_position = Vector3(SPAWN.x, terrain_y(SPAWN.x, SPAWN.z) + 1.2, SPAWN.z)
	player.velocity = Vector3.ZERO
	status.hide_death()
	for z in _zombies:
		if is_instance_valid(z):
			z.queue_free()
	_zombies.clear()


func _flash_msg(text: String) -> void:
	_msg = text
	_msg_t = 2.6


# --- HUD ----------------------------------------------------------------------

func _sync_hotbar() -> void:
	if touch == null:
		return
	var arr: Array = []
	for it in inv:
		if it.is_empty():
			arr.append({})
		else:
			var id := str(it["id"])
			if icons and not icons.has_icon(id):
				var m := _item_model(id)
				if m:
					icons.request(id, m)
			var entry := {"icon": _icon_for(id), "count": int(it["n"]), "tint": Color(1, 1, 1, 0.95)}
			if icons and icons.has_icon(id):
				entry["tex"] = icons.get_icon(id)
			arr.append(entry)
	touch.slots = arr
	touch.selected = sel


## A fresh copy of an item's model, for its hotbar picture.
func _item_model(id: String) -> Node3D:
	var path := str(ITEMS[id].get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var m: Node3D = (load(path) as PackedScene).instantiate()
	if id == "pistol":
		for extra in ["Mag", "45 ACP", "45 ACP Blank"]:
			var e := m.find_child(extra, true, false)
			if e:
				e.get_parent().remove_child(e)
				e.queue_free()
	return m


func _icon_for(id: String) -> String:
	match str(ITEMS[id].get("kind", "")):
		"gun": return "gun"
		"melee": return "dagger"
		"ammo": return "whack"
		"heal": return "clam"
		"food": return "fish"
		"drink": return "bubble"
	return "whack"


var _map_marks: Array = []
var _pickups: Array = []          # things lying on the ground you can take
var _shake := 0.0                 # camera flinch, decaying

## Drops an item into the world as something you can walk up to and take.
## This is where half the game's objects come from: zombie drops, and your
## own gear after you die.
func _drop_item(id: String, n: int, at: Vector3) -> void:
	if not ITEMS.has(id):
		return
	var m := _item_model(id)
	if m == null:
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(at.x, terrain_y(at.x, at.z) + 0.25, at.z)
	var box := _node_box(m)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.001:
		m.scale = Vector3.ONE * (0.45 / longest)
	root.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 0
	var c := CollisionShape3D.new()
	var bs := SphereShape3D.new()
	bs.radius = 0.55
	c.shape = bs
	b.add_child(c)
	root.add_child(b)
	b.set_meta("pickup", _pickups.size())
	_pickups.append({"root": root, "body": b, "id": id, "n": n, "ph": randf() * TAU})


func _node_box(n: Node3D) -> AABB:
	var acc := AABB()
	var got := false
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.transform * m.mesh.get_aabb()
		acc = a if not got else acc.merge(a)
		got = true
	return acc if got else AABB(Vector3.ZERO, Vector3.ONE)


## Dropped things bob and turn so they catch the eye, but only the ones near
## enough to be seen.
func _update_pickups(delta: float) -> void:
	for p in _pickups:
		var root = p["root"]
		if not is_instance_valid(root):
			continue
		if root.global_position.distance_squared_to(player.global_position) > 1600.0:
			continue
		p["ph"] = float(p["ph"]) + delta * 2.2
		root.rotation.y = float(p["ph"]) * 0.6
		(root.get_child(0) as Node3D).position.y = 0.12 + sin(float(p["ph"])) * 0.05


func _take_pickup(idx: int) -> void:
	if idx < 0 or idx >= _pickups.size():
		return
	var p: Dictionary = _pickups[idx]
	if not is_instance_valid(p["root"]):
		return
	if not _give(str(p["id"]), int(p["n"])):
		_flash_msg("No room")
		return
	players["pickup"].play()
	_flash_msg("Took %s%s" % [str(ITEMS[str(p["id"])]["name"]),
		(" x%d" % int(p["n"])) if int(p["n"]) > 1 else ""])
	(p["root"] as Node) .queue_free()
	_sync_hotbar()

func _update_hud() -> void:
	if map_ui:
		map_ui.player_pos = player.global_position
		map_ui.player_yaw = cam_yaw
	status.health = health
	status.breath = stamina
	status.show_breath = stamina < 0.995
	_msg_t = maxf(_msg_t - get_process_delta_time(), 0.0)
	touch.look_info = ""
	touch.look_stat = ""
	touch.look_cost = ""
	touch.secondary = ""
	touch.act_progress = -1.0
	touch.act_dim = false
	var p := ""
	var id := held_id()
	var kind := str(ITEMS[id].get("kind", "")) if id != "" else ""
	if _looked_pickup >= 0 and _looked_pickup < _pickups.size() \
			and is_instance_valid(_pickups[_looked_pickup]["root"]):
		var pk: Dictionary = _pickups[_looked_pickup]
		touch.look_info = str(ITEMS[str(pk["id"])]["name"])
		touch.look_stat = ("x%d" % int(pk["n"])) if int(pk["n"]) > 1 else ""
		p = "TAKE"
	elif not _looked_loot.is_empty():
		touch.look_info = "Container"
		touch.look_stat = "searched" if bool(_looked_loot.get("opened", false)) else "not searched"
		p = "LOOT"
	elif _reload_t > 0.0:
		p = "RELOAD"
		touch.act_dim = true
		touch.act_progress = 1.0 - _reload_t / 1.35
	elif kind == "gun":
		p = "SHOOT"
		touch.secondary = "RELOAD"
	elif kind == "melee":
		p = "SWING"
	elif kind == "heal":
		p = "USE"
	elif kind == "food":
		p = "EAT"
	elif kind == "drink":
		p = "DRINK"
	else:
		p = "SWING"
	if _looked_zombie and is_instance_valid(_looked_zombie):
		touch.look_info = "Zombie"
		touch.look_stat = "%d%%" % int(_looked_zombie.health / _looked_zombie.max_health * 100.0)
	touch.prompt = p
	if frame < 4 or frame == 60:
		touch._process(0.016)
		print("HUDDBG f=%d p=%s vis=%s proc=%s sig_after_manual=%d bump=%s" % [frame, p, touch.visible, touch.is_processing(), touch._sig.length(), touch._bump])
	var line := "Day %d  ·  %s" % [day, "night" if is_night() else "day"]
	if kind == "gun":
		line += "   ·   %d / %d" % [ammo_loaded, _count(str(ITEMS[id]["ammo"]))]
	line += "   ·   food %d%%  water %d%%" % [int(food), int(water)]
	if _msg_t > 0.0:
		line = _msg
	touch.carry_info = line


# =====================================================================
# Autotest
# =====================================================================

var _basics := 0

## Each stage drives the game through the controls a player would use, and
## prints what came of it, so a run either reports the whole loop working or
## names the step that stopped.
func _basics_step() -> void:
	match _basics:
		0:
			# walk to the nearest container
			if _lootables.is_empty():
				print("AUTOTEST basics FAIL no containers")
				_basics = 99
				return
			var best: Dictionary = {}
			var bd := 1e9
			for l in _lootables:
				var d: float = (l["body"] as Node3D).global_position.distance_to(player.global_position)
				if d < bd:
					bd = d
					best = l
			_test_target = (best["body"] as Node3D).global_position
			print("AUTOTEST basics: walking %.1fm to a container" % bd)
			_basics = 1
		1:
			var to := _test_target - player.global_position
			to.y = 0.0
			cam_yaw = atan2(-to.x, -to.z)
			touch.move = Vector2(0, -1)
			if to.length() < 1.9:
				touch.move = Vector2.ZERO
				_basics = 2
			elif frame > 900:
				print("AUTOTEST basics FAIL could not reach the container")
				_basics = 99
		2:
			cam_pitch = -0.35
			if not _looked_loot.is_empty():
				var before := inv.duplicate(true)
				_on_action()
				print("AUTOTEST basics: looted -> %s" % [inv])
				_basics = 3
			elif frame > 1000:
				print("AUTOTEST basics FAIL crosshair never found the container")
				_basics = 99
		3:
			# shoot the nearest zombie until it drops
			cam_pitch = 0.0
			var z: Node3D = _nearest_zombie() as Node3D
			if z == null:
				return
			# Keep a magazine in it: running dry is a different test.
			if _count("9mm") < 12:
				_give("9mm", 30)
			var to2: Vector3 = z.global_position - player.global_position
			cam_yaw = atan2(-to2.x, -to2.z)
			cam_pitch = clampf(atan2(z.global_position.y + 1.1 - camera.global_position.y,
				Vector2(to2.x, to2.z).length()), -1.0, 1.0)
			# This stage is testing that shots land and kill, not whether you
			# can survive a mob, so damage is topped back up.
			health = 100.0
			if frame % 18 == 0:
				_shoot()
			if kills > 0:
				print("AUTOTEST basics: zombie killed, ammo=%d" % ammo_loaded)
				_basics = 4
			elif frame > 1800:
				print("AUTOTEST basics FAIL nothing died (hp left %.0f)" % z.health)
				_basics = 99
		4:
			# stand still and let one reach you; if none is about, send one
			touch.move = Vector2.ZERO
			var near: Node3D = _nearest_zombie() as Node3D
			var far_off: bool = near == null \
				or near.global_position.distance_to(player.global_position) > 20.0
			if frame % 180 == 0 and far_off:
				var ang := randf() * TAU
				var at := player.global_position + Vector3(cos(ang), 0, sin(ang)) * 6.0
				at.y = terrain_y(at.x, at.z)
				var zz = Zombie.new()
				add_child(zz)
				zz.setup(self, at, 77, false)
				_zombies.append(zz)
			if frame % 120 == 0:
				print("AUTOTEST stage4 f=%d zombies=%d near=%s state=%s vel=%.2f you=%s" % [
					frame, _zombies.size(),
					"%.1fm" % near.global_position.distance_to(player.global_position) if near else "none",
					near.state if near else "-",
					Vector2(near.velocity.x, near.velocity.z).length() if near else 0.0,
					player.global_position.snapped(Vector3.ONE * 0.1)])
			if health < 100.0:
				print("AUTOTEST basics: took a hit, hp=%.0f" % health)
				_basics = 5
			elif frame > 2600:
				print("AUTOTEST basics FAIL no zombie ever reached the player")
				_basics = 99
		5:
			print("AUTOTEST basics: pickups on the ground before dying: %d" % _live_pickups())
			_damage(200.0, "testing")
			_basics = 6
		6:
			if dead:
				print("AUTOTEST basics: died and the death screen is up")
				_respawn()
				_basics = 7
		7:
			print("AUTOTEST basics: respawned hp=%.0f, carrying %d things, %d lying where I fell" % [
				health, _inv_count(), _live_pickups()])
			if _inv_count() > 2:
				print("AUTOTEST basics FAIL still carrying everything after death")
				_basics = 99
				return
			_basics = 8
		8:
			# The corpse run: walk back to your things and pick one up.
			var best := Vector3.ZERO
			var bd := 1e9
			for pk in _pickups:
				if not is_instance_valid(pk["root"]):
					continue
				var d2: float = (pk["root"] as Node3D).global_position.distance_to(player.global_position)
				if d2 < bd:
					bd = d2
					best = (pk["root"] as Node3D).global_position
			if bd > 900.0:
				print("AUTOTEST basics FAIL no gear to walk back to")
				_basics = 99
				return
			var to3 := best - player.global_position
			cam_yaw = atan2(-to3.x, -to3.z)
			cam_pitch = clampf(atan2(to3.y - 1.2, Vector2(to3.x, to3.z).length()), -1.2, 0.3)
			touch.move = Vector2(0, -1) if to3.length() > 1.6 else Vector2.ZERO
			if _looked_pickup >= 0:
				var before := _inv_count()
				_on_action()
				touch.move = Vector2.ZERO
				print("AUTOTEST basics: took my gear back (%d -> %d things)" % [before, _inv_count()])
				_basics = 98
			elif frame > 5200:
				print("AUTOTEST basics FAIL could not reach my own gear")
				_basics = 99
		98:
			print("AUTOTEST basics ALL OK")
			get_tree().quit()


var _test_target := Vector3.ZERO

func _live_pickups() -> int:
	var n := 0
	for pk in _pickups:
		if is_instance_valid(pk["root"]):
			n += 1
	return n


func _inv_count() -> int:
	var n := 0
	for it in inv:
		if not it.is_empty():
			n += 1
	return n


func _nearest_zombie() -> Node:
	var best: Node = null
	var bd := 1e9
	for z in _zombies:
		if not is_instance_valid(z) or not z.alive:
			continue
		var d: float = z.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = z
	return best


func _setup_test() -> void:
	if autotest_hold != "":
		_give(autotest_hold, 1)
		for i in SLOTS:
			if not inv[i].is_empty() and str(inv[i]["id"]) == autotest_hold:
				_select_slot(i)
				break
	match start_screen:
		"basics", "zombies":
			for i in (2 if start_screen == "basics" else 6):
				var a := float(i) / 6.0 * TAU
				var p := player.global_position + Vector3(cos(a), 0, sin(a)) * 7.0
				p.y = terrain_y(p.x, p.z)
				var z = Zombie.new()
				add_child(z)
				z.setup(self, p, 100 + i, i == 5)
				_zombies.append(z)
		"fight":
			# One of them, at a distance you can actually watch it from.
			var at := player.global_position + Vector3(0, 0, -4.5)
			at.y = terrain_y(at.x, at.z)
			var z = Zombie.new()
			add_child(z)
			z.setup(self, at, 7, false)
			_zombies.append(z)
			cam_yaw = 0.0
		"night":
			clock = DAY_LENGTH * 0.92
		"loot":
			pass
	if test_yaw < 900.0:
		cam_yaw = test_yaw


func _drive_test() -> void:
	if test_walk > 0 and frame < test_walk:
		touch.move = Vector2(0, -1)
	else:
		touch.move = Vector2.ZERO
	if frame % 60 == 0:
		print("AUTOTEST f=%d pos=%s vel=%.2f floor=%s hp=%.0f zombies=%d loot=%d chunks=%d fps=%.0f" % [
			frame, player.global_position.snapped(Vector3.ONE * 0.1),
			Vector2(player.velocity.x, player.velocity.z).length(), player.is_on_floor(), health,
			_zombies.size(), _lootables.size(), _chunks.size(),
			Engine.get_frames_per_second()])
	if start_screen == "fight":
		# Stand still and watch it come: walk, then the swing.
		touch.move = Vector2.ZERO
		var zz: Node3D = _nearest_zombie() as Node3D
		if zz and autotest_shot != "":
			var idx := [60, 110, 150, 190].find(frame)
			if idx >= 0:
				get_viewport().get_texture().get_image().save_png(
					autotest_shot.replace(".png", "_%d.png" % idx))
				print("AUTOTEST fight%d: %.1fm state=%s clip=%s hp=%.0f yours=%.0f" % [
					idx, zz.global_position.distance_to(player.global_position), zz.state,
					zz.body._pb.get_current_node() if zz.body._pb else "?", zz.health, health])
		if frame > 210:
			print("AUTOTEST fight done")
			get_tree().quit()
		return

	if start_screen == "zombies" and autotest_shot != "":
		var at := [120, 220, 300].find(frame)
		if at >= 0:
			get_viewport().get_texture().get_image().save_png(
				autotest_shot.replace(".png", "_%d.png" % at))
			var z0: Node3D = _nearest_zombie() as Node3D
			if z0:
				print("AUTOTEST shot%d: nearest %.1fm state=%s clip=%s hp=%.0f" % [
					at, z0.global_position.distance_to(player.global_position),
					z0.state, z0.body._pb.get_current_node() if z0.body._pb else "?", z0.health])
	if start_screen == "zombies" and frame == 90:
		var z = _zombies[0]
		z.take_damage(40.0, "body", player.global_position)
		print("AUTOTEST hit zombie -> hp=%.0f state=%s" % [z.health, z.state])
	if start_screen == "zombies" and frame == 150:
		_shoot()
		print("AUTOTEST shot fired, ammo=%d" % ammo_loaded)
	# Walks the whole loop a player goes through: find a container, search it,
	# shoot a zombie dead, get hit, die, come back.
	if start_screen == "basics":
		_basics_step()
		if frame > autotest_frames:
			print("AUTOTEST basics done kills=%d hp=%.0f items=%s" % [kills, health, inv])
			get_tree().quit()
		return

	# A look at the world from a chosen spot, in each direction. Walking there
	# is no good for pictures: you end up nose-first against a bus.
	if start_screen == "scenic":
		if frame == 2:
			var a0: float = test_yaw if test_yaw < 900.0 else 1.0
			var r0: float = float(test_walk) if test_walk > 0 else 150.0
			var at := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			player.global_position = Vector3(at.x, terrain_y(at.x, at.z) + 1.2, at.z)
			cam_yaw = a0 + PI
			cam_pitch = -0.06
		if frame > 40 and (frame - 40) % 30 == 0 and autotest_shot != "":
			var i := (frame - 40) / 30 - 1
			if i >= 0 and i < 4:
				get_viewport().get_texture().get_image().save_png(
					autotest_shot.replace(".png", "_%d.png" % i))
				cam_yaw += PI * 0.5
			if i >= 4:
				print("AUTOTEST scenic done at %s biome=%d" % [
					player.global_position.snapped(Vector3.ONE), _biome(player.global_position.x, player.global_position.z)])
				get_tree().quit()
		return

	# The map, open, with the island on it.
	if start_screen == "map":
		if frame == 20:
			map_ui.open = true
		if frame > 40 and autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
			print("AUTOTEST map marks=%d open=%s" % [map_ui.marks.size(), map_ui.open])
			get_tree().quit()
		return

	# A short tour: look around from where you stand, then walk on.
	if start_screen == "tour":
		var shots := [50, 110, 170, 230, 290]
		var idx := shots.find(frame)
		if idx >= 0 and autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(
				autotest_shot.replace(".png", "_%d.png" % idx))
			cam_yaw += 1.25
			if idx == 2:
				clock = DAY_LENGTH * 0.95        # and once after dark
			if idx == 3:
				cam_pitch = 0.35
		if frame > 320:
			print("AUTOTEST tour done")
			get_tree().quit()
		return
	if frame >= autotest_frames:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		var alive := 0
		for z in _zombies:
			if is_instance_valid(z) and z.alive:
				alive += 1
		print("AUTOTEST done frames=%d zombies=%d alive=%d kills=%d hp=%.0f items=%s" % [
			frame, _zombies.size(), alive, kills, health, inv])
		get_tree().quit()
