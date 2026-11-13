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

# --- world shape --------------------------------------------------------------
const CHUNK := 48.0               # metres across one patch of ground
const CHUNK_GRID := 24            # quads across that patch
const VIEW_CHUNKS := 2            # rings of chunks kept around you
const TOWN_R := 46.0              # the clearing the town sits in
const SPAWN := Vector3(6, 0, 18)

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
	"9mm": {"name": "9mm Ammo", "kind": "ammo", "stack": 60, "loot": 0.34},
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
const TREES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5",
	"PineTree_1", "PineTree_2", "PineTree_3", "PineTree_4", "PineTree_5",
	"BirchTree_1", "BirchTree_2", "BirchTree_3"]
const DEAD_TREES := ["CommonTree_Dead_1", "CommonTree_Dead_2", "CommonTree_Dead_3", "BirchTree_Dead_1"]
const ROCKS := ["Rock_1", "Rock_2", "Rock_3", "Rock_4", "Rock_5",
	"Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3"]
const BUSHES := ["Bush_1", "Bush_2", "BushBerries_1", "Plant_1", "Plant_2", "Plant_3", "TreeStump"]
const GRASS := ["Grass", "Grass_2", "Grass_Short", "Wheat", "Flowers"]

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
var _chunks := {}                 # Vector2i -> Node3D
var _models := {}                 # name -> PackedScene
var _zombies: Array = []
var _lootables: Array = []        # [{body, items, opened, label}]
var _looked_loot: Dictionary = {}
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

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	# The sky lights the world: ambient comes from it, so dawn is pink on the
	# walls and midnight is blue, without any of that being set by hand.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.60, 0.66, 0.70)
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.10
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

	fx = WorldFX.new()
	add_child(fx)

	_build_loot_spots()
	_update_chunks(SPAWN, true)


## Ground height. Rolling hills from one noise field, with the land flattened
## off where the town stands so the streets are not on a slope.
func terrain_y(x: float, z: float) -> float:
	var h: float = _noise.get_noise_2d(x, z) * 17.0
	h += _rough.get_noise_2d(x, z) * 1.1
	var d := Vector2(x, z).length()
	if d < TOWN_R + 26.0:
		var flat: float = clampf((d - TOWN_R) / 26.0, 0.0, 1.0)
		h = lerpf(_town_level(), h, flat * flat * (3.0 - 2.0 * flat))
	return h


func _town_level() -> float:
	return _noise.get_noise_2d(0.0, 0.0) * 17.0


func _ground_normal(x: float, z: float) -> Vector3:
	var e := 0.6
	return Vector3(terrain_y(x - e, z) - terrain_y(x + e, z), 2.0 * e,
		terrain_y(x, z - e) - terrain_y(x, z + e)).normalized()


func _model(name: String, dir := "nature") -> PackedScene:
	if _models.has(name):
		return _models[name]
	var ext := ".fbx" if dir != "props" else ".glb"
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
			st.add_vertex(verts[vi])
	if st.get_aabb().size == Vector3.ZERO:
		return null
	return st.commit()


## One shared wind material per kind of plant. Grass whips, bushes bob, trees
## lean slowly: same shader, different numbers.
func _wind_mat(kind: String) -> ShaderMaterial:
	if _wind_mats.has(kind):
		return _wind_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/wind.gdshader")
	match kind:
		"grass":
			m.set_shader_parameter("sway_strength", 0.26)
			m.set_shader_parameter("sway_speed", 2.1)
			m.set_shader_parameter("height_scale", 0.6)
			m.set_shader_parameter("ao_strength", 0.45)
		"bush":
			m.set_shader_parameter("sway_strength", 0.10)
			m.set_shader_parameter("sway_speed", 1.4)
			m.set_shader_parameter("height_scale", 1.2)
			m.set_shader_parameter("ao_strength", 0.40)
		"tree":
			m.set_shader_parameter("sway_strength", 0.055)
			m.set_shader_parameter("sway_speed", 0.75)
			m.set_shader_parameter("height_scale", 7.0)
			m.set_shader_parameter("ao_strength", 0.28)
		_:
			m.set_shader_parameter("sway_strength", 0.0)
			m.set_shader_parameter("height_scale", 2.0)
			m.set_shader_parameter("ao_strength", 0.25)
	_wind_mats[kind] = m
	return m


func _plant_kind(name: String) -> String:
	if name in GRASS:
		return "grass"
	if name in BUSHES:
		return "bush"
	if name in ROCKS:
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
	var grass_col := Color(0.33, 0.42, 0.24)
	var dirt := Color(0.40, 0.35, 0.26)
	var rock := Color(0.42, 0.42, 0.44)
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
		var d := Vector2(v.x, v.z).length()
		if d < TOWN_R:
			c = c.lerp(dirt, clampf((TOWN_R - d) / 16.0, 0.0, 0.75))
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
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.roughness = 1.0
	gm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = gm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.create_trimesh_collision()

	_scatter(root, k, x0, z0)
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
			batches[name] = [mm, [], pair[1]]
		(batches[name][1] as Array).append(xf * (batches[name][2] as Transform3D))

	var density: int = 44
	for i in density:
		var x := x0 + rng.randf() * CHUNK
		var z := z0 + rng.randf() * CHUNK
		var d := Vector2(x, z).length()
		if d < TOWN_R * 0.92:
			continue                                   # the town is a clearing
		var y := terrain_y(x, z)
		var n := _ground_normal(x, z)
		if n.y < 0.80:
			continue                                   # too steep to root in
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.85, 1.3)
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z))
		if roll < 0.52:
			var t: String = TREES[rng.randi() % TREES.size()]
			place.call(t, "nature", xf)
			if d < 170.0:
				_trunk(root, Vector3(x, y, z), 0.34 * s, 5.0 * s)
		elif roll < 0.62:
			place.call(DEAD_TREES[rng.randi() % DEAD_TREES.size()], "nature", xf)
			if d < 170.0:
				_trunk(root, Vector3(x, y, z), 0.3 * s, 4.0 * s)
		elif roll < 0.76:
			place.call(ROCKS[rng.randi() % ROCKS.size()], "nature", xf)
		else:
			place.call(BUSHES[rng.randi() % BUSHES.size()], "nature", xf)

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
			var s := rng.randf_range(0.7, 1.4)
			place.call(GRASS[rng.randi() % GRASS.size()], "nature",
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
					Vector3(x, y, z)))

	for name in batches:
		var mm: MultiMesh = batches[name][0]
		var list: Array = batches[name][1]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var kind := _plant_kind(str(name))
		mmi.material_override = _wind_mat(kind)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind == "tree" \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if str(name) in GRASS:
			mmi.visibility_range_end = 38.0
			mmi.visibility_range_end_margin = 6.0
		else:
			mmi.visibility_range_end = Q_DRAW[quality]
			mmi.visibility_range_end_margin = 14.0
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

## Drops a model from one of the packs into the world.
func _prop(parent: Node3D, name: String, at: Vector3, yaw: float, scale := 1.0) -> Node3D:
	var ps := _model(name, "props")
	if ps == null:
		return null
	var n: Node3D = ps.instantiate()
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	parent.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


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


## Crates, barrels and a tent or two dropped around the start area. This is
## the stand-in for buildings and their contents until there are models for
## them: somewhere to walk to, something to search, and a reason to be out in
## the open where the zombies are.
func _build_loot_spots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var holder := Node3D.new()
	add_child(holder)
	for i in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, 90.0)
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
	var tries: int = rng.randi_range(2, 4)
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
	camera.fov = 76.0
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
	status.respawn_pressed.connect(_respawn)


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
	camera.rotation = Vector3(cam_pitch + _recoil(), cam_yaw, 0.0)

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
	sun.rotation = Vector3(-ang, 0.55 + sin(ang) * 0.25, 0.0)
	var up: float = clampf(sin(ang) * 1.5, -1.0, 1.0)
	var light: float = clampf(up * 0.5 + 0.5, 0.0, 1.0)
	var low: float = clampf(1.0 - absf(up) * 2.2, 0.0, 1.0)      # near the horizon
	sun.light_energy = lerpf(0.0, 1.15, clampf(up * 2.2, 0.0, 1.0))
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.56, 0.30), low)
	sun.light_angular_distance = lerpf(0.6, 3.0, low)
	world_env.ambient_light_energy = lerpf(0.22, 0.85, light)
	var fog_day := Color(0.62, 0.70, 0.76)
	var fog_night := Color(0.06, 0.08, 0.14)
	var fog_dusk := Color(0.55, 0.34, 0.26)
	world_env.fog_light_color = fog_night.lerp(fog_day, light).lerp(fog_dusk, low * 0.7)
	world_env.fog_density = lerpf(0.026, 0.0062, light)
	if sky_mat:
		sky_mat.set_shader_parameter("hour", hour)
		sky_mat.set_shader_parameter("cloud_cover", 0.38 + 0.2 * sin(elapsed * 0.012))


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
	if status:
		status.hit(clampf(amount / 30.0, 0.2, 1.0))
	players["hurt"].play()


func zombie_moan(at: Vector3, near: bool) -> void:
	var d := at.distance_to(player.global_position)
	var p: AudioStreamPlayer = players["moan_near"] if near else players["moan"]
	p.pitch_scale = randf_range(0.75, 1.05)
	p.volume_db = lerpf(-6.0, -24.0, clampf(d / 34.0, 0.0, 1.0))
	if not p.playing:
		p.play()


func zombie_hurt(z: Node, where: String, amount: float) -> void:
	if fx:
		fx.hit_burst(z.global_position + Vector3(0, 1.1, 0), where == "head")
	players["hit"].pitch_scale = randf_range(0.9, 1.2) * (1.3 if where == "head" else 1.0)
	players["hit"].play()
	if where == "head" and amount > 40.0:
		_flash_msg("Headshot!")


func zombie_died(_z: Node) -> void:
	kills += 1
	_flash_msg("Zombie down  (%d)" % kills)


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
	if not hit.is_empty() and hit.has("collider"):
		var c = hit["collider"]
		if c and c.has_meta("loot"):
			var idx := int(c.get_meta("loot"))
			if idx < _lootables.size():
				_looked_loot = _lootables[idx]
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
	hands.mount(holder)
	hands.aim_offset(Vector3(0.075, 0.105, -0.06))


## How each item sits in the fist. Every pack models at its own size and
## facing, so these are measured per item rather than guessed at.
func _grip_of(id: String) -> Transform3D:
	match id:
		"pistol":
			# the pack models it barrel-forward with the grip off the origin
			return Transform3D(Basis(Vector3.UP, PI), Basis(Vector3.UP, PI) * -Vector3(-0.0124, 0.062, -0.034))
		"revolver":
			return Transform3D(Basis.from_euler(Vector3(0, PI, 0)).scaled(Vector3.ONE * 0.011), Vector3.ZERO)
		"axe", "knife":
			return Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)).scaled(Vector3.ONE * 0.011), Vector3.ZERO)
	return Transform3D(Basis().scaled(Vector3.ONE * 0.01), Vector3.ZERO)


func _damage(amount: float, cause: String) -> void:
	if dead:
		return
	health -= amount
	_hurt_t = 0.6
	if health <= 0.0:
		health = 0.0
		dead = true
		player.frozen = true
		status.show_death("YOU DIED", "%s on day %d  ·  %d zombies killed" % [cause.capitalize(), day, kills])


func _respawn() -> void:
	dead = false
	health = 100.0
	food = 70.0
	water = 70.0
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
			arr.append({"icon": _icon_for(id), "count": int(it["n"]),
				"tint": Color(1, 1, 1, 0.95)})
	touch.slots = arr
	touch.selected = sel


func _icon_for(id: String) -> String:
	match str(ITEMS[id].get("kind", "")):
		"gun": return "gun"
		"melee": return "dagger"
		"ammo": return "whack"
		"heal": return "clam"
		"food": return "fish"
		"drink": return "bubble"
	return "whack"


func _update_hud() -> void:
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
	if not _looked_loot.is_empty():
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
			# stand still and let one reach you
			touch.move = Vector2.ZERO
			if health < 100.0:
				print("AUTOTEST basics: took a hit, hp=%.0f" % health)
				_basics = 5
			elif frame > 2600:
				print("AUTOTEST basics FAIL no zombie ever reached the player")
				_basics = 99
		5:
			_damage(200.0, "testing")
			_basics = 6
		6:
			if dead:
				print("AUTOTEST basics: died and the death screen is up")
				_respawn()
				_basics = 7
		7:
			print("AUTOTEST basics: respawned hp=%.0f at %s" % [health, player.global_position.snapped(Vector3.ONE)])
			_basics = 98
		98:
			print("AUTOTEST basics ALL OK")
			get_tree().quit()


var _test_target := Vector3.ZERO

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
