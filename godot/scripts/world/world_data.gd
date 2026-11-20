class_name WorldData
extends RefCounted
## The whole world as flat byte arrays, plus its generator.
##
## No nodes and no rendering: this is the model the World node draws, the
## save file stores, and the tests inspect. Coordinates are tile cells with
## y growing downward.

const WIDTH := 640
const HEIGHT := 360

# --- Tile materials (also the terrain atlas row + 1) -------------------------
const AIR := 0
const GRASS := 1
const SOIL := 2
const SAND := 3
const SNOW := 4
const ROCK := 5
const BRICK := 6
const CRYSTAL := 7
const BASALT := 8
const PLANKS := 9
const BEDROCK := 10

# --- Ores (overlay atlas column + 1) -----------------------------------------
const ORE_NONE := 0
const COAL := 1
const COPPER := 2
const IRON := 3
const SILVER := 4
const GOLD := 5
const GLOWSHARD := 6
const RUBY := 7
const EMERALD := 8

# --- Liquids -------------------------------------------------------------------
const DRY := 0
const WATER := 1
const LAVA := 2

enum Biome { MEADOW, DESERT, TUNDRA, CRYSTAL, DEPTHS }

## Mean surface row. The sky above it is open air.
const SURFACE_Y := 96
## Below this row the rock turns to basalt: the deep dark.
const DEEP_Y := 250

## Hardness of each material, indexed by material id. A tool must have at
## least this much power to break it.
const HARDNESS := [0, 1, 1, 1, 1, 2, 3, 3, 4, 1, 99]
## Hardness of each ore, indexed by ore id. Overrides the rock it sits in.
const ORE_HARDNESS := [0, 2, 2, 3, 4, 5, 4, 6, 6]

var width := WIDTH
var height := HEIGHT
var seed := 1

var tiles := PackedByteArray()
var walls := PackedByteArray()
var ores := PackedByteArray()
var liquids := PackedByteArray()
var surface := PackedInt32Array()
var biome_columns := PackedByteArray()
## First solid row of each column, kept current as tiles change: the
## lighting asks "how far down does sunlight reach" for every visible
## column several times a second, and scanning from the sky each time
## was the single most expensive thing it did.
var sky_depth := PackedInt32Array()

## cell index -> {"type": String, ...}. Trees, torches, chests, stations.
var objects := {}

var spawn := Vector2i.ZERO
var vault := Vector2i.ZERO


func _init(w: int = WIDTH, h: int = HEIGHT) -> void:
	width = w
	height = h
	tiles.resize(w * h)
	walls.resize(w * h)
	ores.resize(w * h)
	liquids.resize(w * h)
	surface.resize(w)
	biome_columns.resize(w)
	sky_depth.resize(w)


# =============================================================================
# Access
# =============================================================================

func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_tile(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return BEDROCK
	return tiles[y * width + x]


func set_tile(x: int, y: int, material: int) -> void:
	if in_bounds(x, y):
		tiles[y * width + x] = material
		if material == AIR:
			ores[y * width + x] = ORE_NONE
			if y == sky_depth[x]:
				_recompute_sky(x)
		elif y < sky_depth[x]:
			sky_depth[x] = y


func _recompute_sky(x: int) -> void:
	var y := 0
	while y < height and tiles[y * width + x] == AIR:
		y += 1
	sky_depth[x] = y


func recompute_all_sky() -> void:
	for x in width:
		_recompute_sky(x)


func is_solid(x: int, y: int) -> bool:
	return get_tile(x, y) != AIR


func get_wall(x: int, y: int) -> int:
	return walls[y * width + x] if in_bounds(x, y) else ROCK


func get_ore(x: int, y: int) -> int:
	return ores[y * width + x] if in_bounds(x, y) else ORE_NONE


func get_liquid(x: int, y: int) -> int:
	return liquids[y * width + x] if in_bounds(x, y) else DRY


func hardness(x: int, y: int) -> int:
	var ore := get_ore(x, y)
	if ore != ORE_NONE:
		return ORE_HARDNESS[ore]
	return HARDNESS[get_tile(x, y)]


func biome_at(x: int, y: int) -> int:
	if y > DEEP_Y:
		return Biome.DEPTHS
	if get_wall(x, y) == CRYSTAL:
		return Biome.CRYSTAL
	return biome_columns[clampi(x, 0, width - 1)]


## Which sides of (x, y) are open to air, as the autotile mask the terrain
## atlas is laid out by: up 1, down 2, left 4, right 8.
func mask(x: int, y: int) -> int:
	var m := 0
	if not is_solid(x, y - 1):
		m |= 1
	if not is_solid(x, y + 1):
		m |= 2
	if not is_solid(x - 1, y):
		m |= 4
	if not is_solid(x + 1, y):
		m |= 8
	return m


## Whether open sky is directly above (x, y): nothing solid and no wall
## between it and the top of the world.
func sees_sky(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return y <= surface[x] and not is_solid(x, y)


# =============================================================================
# Generation
# =============================================================================

var _terrain := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _caves := FastNoiseLite.new()
var _tunnels := FastNoiseLite.new()
var _hollows := FastNoiseLite.new()
var _ore_noise := []
var _rng := RandomNumberGenerator.new()


func _setup_noise() -> void:
	_rng.seed = seed

	_terrain.seed = seed
	_terrain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain.frequency = 0.008
	_terrain.fractal_octaves = 4

	_detail.seed = seed + 11
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 0.05

	# Blobby caverns.
	_caves.seed = seed + 23
	_caves.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_caves.frequency = 0.034
	_caves.fractal_octaves = 3

	# Long winding tunnels: the thin band where ridged noise crosses zero.
	_tunnels.seed = seed + 37
	_tunnels.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_tunnels.frequency = 0.018
	_tunnels.fractal_type = FastNoiseLite.FRACTAL_NONE

	_hollows.seed = seed + 41
	_hollows.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hollows.frequency = 0.012

	_ore_noise.clear()
	for i in 9:
		var n := FastNoiseLite.new()
		n.seed = seed + 100 + i * 17
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.11
		_ore_noise.append(n)


## Build a whole world. `progress` (optional Callable(float)) reports 0..1.
func generate(world_seed: int, progress := Callable()) -> void:
	seed = world_seed
	_setup_noise()
	objects.clear()

	_report(progress, 0.02)
	_shape_terrain()
	_report(progress, 0.20)
	_carve_caves()
	_report(progress, 0.40)
	_grow_crystal_hollows()
	_report(progress, 0.50)
	_place_ores()
	_report(progress, 0.65)
	_fill_pools()
	_report(progress, 0.72)
	_build_ruins()
	_build_cabin()
	_report(progress, 0.85)
	_plant_surface()
	_place_geode()
	_report(progress, 0.95)
	_seal_edges()
	recompute_all_sky()
	_report(progress, 1.0)


func _report(progress: Callable, value: float) -> void:
	if progress.is_valid():
		progress.call(value)


func _biome_for_column(x: int) -> int:
	# Tundra to the west, meadow in the middle, desert to the east, with
	# wobbling borders so the change is not a ruled line.
	var wobble := _detail.get_noise_1d(x * 0.3) * 18.0
	var t := (x + wobble) / float(width)
	if t < 0.30:
		return Biome.TUNDRA
	if t > 0.70:
		return Biome.DESERT
	return Biome.MEADOW


func _shape_terrain() -> void:
	for x in width:
		var biome := _biome_for_column(x)
		biome_columns[x] = biome

		var amplitude := 9.0
		match biome:
			Biome.TUNDRA:
				amplitude = 16.0  # craggy
			Biome.DESERT:
				amplitude = 6.0  # rolling dunes
		var h := SURFACE_Y + _terrain.get_noise_1d(x) * amplitude * 2.2
		h += _detail.get_noise_1d(x * 1.7) * 2.0
		surface[x] = int(h)

	# Flatten a pad around the spawn so the first few seconds are calm.
	var mid := width / 2
	var pad := surface[mid]
	for x in range(mid - 8, mid + 9):
		surface[x] = pad + int(round(abs(x - mid) / 7.0))
	spawn = Vector2i(mid, pad - 1)

	for x in width:
		var top := surface[x]
		var biome := biome_columns[x]
		var crust := 14 + int(_detail.get_noise_2d(x, 7.0) * 4.0)
		var deep := DEEP_Y + int(_terrain.get_noise_1d(x * 2.0 + 500.0) * 10.0)

		for y in range(top, height):
			var material := ROCK
			if y - top < crust:
				match biome:
					Biome.MEADOW:
						material = GRASS if y == top else SOIL
					Biome.TUNDRA:
						material = SNOW
					Biome.DESERT:
						material = SAND
			if y >= deep:
				material = BASALT
			if y >= height - 1:
				material = BEDROCK

			var i := idx(x, y)
			tiles[i] = material
			# Background walls start a little below the surface, so hills
			# keep a sky behind them.
			if y > top + 1:
				walls[i] = SOIL if material == GRASS else material


func _carve_caves() -> void:
	for x in width:
		var top := surface[x]
		for y in range(top + 6, height - 2):
			var depth := float(y - top)
			# Caverns grow more common with depth; tunnels run everywhere.
			var cavern := _caves.get_noise_2d(x, y * 1.4)
			var cavern_threshold := lerpf(0.52, 0.28, clampf(depth / 220.0, 0.0, 1.0))
			var tunnel: float = abs(_tunnels.get_noise_2d(x, y * 1.2))
			if cavern > cavern_threshold or (tunnel < 0.045 and depth > 10.0):
				tiles[idx(x, y)] = AIR

	# A few deliberate shafts from the surface, so caves are findable.
	for n in 7:
		var x := _rng.randi_range(40, width - 40)
		if abs(x - width / 2) < 20:
			continue
		var y := surface[x]
		var drift := 0.0
		for step in _rng.randi_range(24, 52):
			drift += _rng.randf_range(-0.6, 0.6)
			var cx := x + int(drift)
			for dx in range(-1, 2):
				if in_bounds(cx + dx, y + step) and tiles[idx(cx + dx, y + step)] != BEDROCK:
					tiles[idx(cx + dx, y + step)] = AIR


func _grow_crystal_hollows() -> void:
	# Large, glowing caverns in the middle depths. Their shells turn to
	# crystal stone and their walls to crystal, which is how biome_at()
	# recognises them later.
	for x in width:
		for y in range(SURFACE_Y + 50, mini(DEEP_Y - 6, height - 2)):
			var h := _hollows.get_noise_2d(x, y * 1.6)
			if h < 0.52:
				continue
			var i := idx(x, y)
			walls[i] = CRYSTAL
			# A thick shell: thin shells left almost no rock for glowshards
			# to grow in, which starved the lantern economy.
			if h > 0.66:
				tiles[i] = AIR
			elif tiles[i] != AIR:
				tiles[i] = CRYSTAL


## [ore, min depth below surface, max absolute row, threshold, host materials]
const ORE_RULES := [
	[COAL, 3, 260, 0.62, [SOIL, ROCK, SNOW, SAND]],
	[COPPER, 6, 230, 0.66, [ROCK, SOIL, SNOW, SAND]],
	[IRON, 30, 300, 0.68, [ROCK]],
	[SILVER, 75, 330, 0.72, [ROCK, BASALT]],
	[GOLD, 120, 358, 0.74, [ROCK, BASALT]],
	[GLOWSHARD, 50, 358, 0.32, [CRYSTAL]],
	[RUBY, 150, 358, 0.80, [BASALT]],
	[EMERALD, 150, 358, 0.80, [BASALT]],
]


func _place_ores() -> void:
	for rule in ORE_RULES:
		var ore: int = rule[0]
		var noise: FastNoiseLite = _ore_noise[ore]
		for x in width:
			var top := surface[x]
			for y in range(top + rule[1], min(rule[2], height - 1)):
				var i := idx(x, y)
				if ores[i] != ORE_NONE or not (tiles[i] in rule[4]):
					continue
				if noise.get_noise_2d(x, y) > rule[3]:
					ores[i] = ore


func _fill_pools() -> void:
	# Contained pools only: a run of air bounded by solid at both ends with
	# a floor beneath every cell. Static liquid that hangs in the air is
	# the obvious tell of a cheap generator.
	for y in range(height - 3, SURFACE_Y + 20, -1):
		var x := 1
		while x < width - 1:
			if is_solid(x, y) or get_liquid(x, y) != DRY:
				x += 1
				continue
			var start := x
			var floored := true
			while x < width - 1 and not is_solid(x, y):
				if not is_solid(x, y + 1) and get_liquid(x, y + 1) == DRY:
					floored = false
				x += 1
			var run := x - start
			if not floored or run < 3 or run > 16:
				continue
			if not is_solid(start - 1, y) or not is_solid(x, y):
				continue
			var below_has_liquid := get_liquid(start, y + 1) != DRY
			if not below_has_liquid and _detail.get_noise_2d(start * 3.0, y * 3.0) < 0.15:
				continue
			var kind := LAVA if y > DEEP_Y + 20 else WATER
			if below_has_liquid:
				kind = get_liquid(start, y + 1)
			for px in range(start, x):
				liquids[idx(px, y)] = kind


func _carve_room(rx: int, ry: int, w: int, h: int, wall_material: int) -> void:
	for x in range(rx, rx + w):
		for y in range(ry, ry + h):
			if not in_bounds(x, y) or get_tile(x, y) == BEDROCK:
				continue
			var i := idx(x, y)
			var edge := x == rx or y == ry or x == rx + w - 1 or y == ry + h - 1
			tiles[i] = wall_material if edge else AIR
			ores[i] = ORE_NONE
			liquids[i] = DRY
			walls[i] = wall_material


func _put_object(x: int, y: int, data: Dictionary) -> void:
	if in_bounds(x, y):
		objects[idx(x, y)] = data


func _build_ruins() -> void:
	# Abandoned brick halls: torches long gone dark, chests, and the robots
	# that still guard them. The deepest is the vault.
	var placed := 0
	var attempts := 0
	while placed < 6 and attempts < 60:
		attempts += 1
		var w := _rng.randi_range(14, 24)
		var h := _rng.randi_range(7, 10)
		var x := _rng.randi_range(30, width - 30 - w)
		var y := _rng.randi_range(SURFACE_Y + 45, DEEP_Y - 20)
		if abs(x + w / 2 - width / 2) < 30:
			continue
		_carve_room(x, y, w, h, BRICK)
		# A doorway on each side, so they connect to the caves.
		for dy in range(h - 4, h - 1):
			set_tile(x, y + dy, AIR)
			set_tile(x + w - 1, y + dy, AIR)
		var floor_y := y + h - 2
		_put_object(x + 2, floor_y, {"type": "chest", "loot": _ruin_loot(y)})
		_put_object(x + w / 2, y + 2, {"type": "torch", "lit": false})
		_put_object(x + w - 4, floor_y, {"type": "barrel"})
		_put_object(x + w / 2 + 2, floor_y, {"type": "spawner", "enemy": "robot"})
		placed += 1

	# The vault: deep, large, sealed, with the altar that wakes the Warden.
	var vw := 30
	var vh := 12
	var vx := width / 2 - vw / 2 + _rng.randi_range(-120, 120)
	var vy := DEEP_Y + 40
	_carve_room(vx, vy, vw, vh, BRICK)
	for dy in range(vh - 4, vh - 1):
		set_tile(vx, vy + dy, AIR)
	vault = Vector2i(vx + vw / 2, vy + vh - 2)
	_put_object(vault.x, vault.y, {"type": "altar"})
	_put_object(vx + 3, vy + 3, {"type": "torch", "lit": true})
	_put_object(vx + vw - 4, vy + 3, {"type": "torch", "lit": true})


func _ruin_loot(depth_y: int) -> Array:
	var loot := [{"id": "torch", "count": _rng.randi_range(4, 9)}]
	var pool := ["copper_ore", "iron_ore", "coal", "glowshard", "apple"]
	if depth_y > SURFACE_Y + 100:
		pool += ["silver_ore", "glow_flask", "heart_crystal"]
	for n in _rng.randi_range(2, 4):
		var id: String = pool[_rng.randi() % pool.size()]
		loot.append({"id": id, "count": 1 if id in ["heart_crystal", "glow_flask"] else _rng.randi_range(3, 10)})
	if _rng.randf() < 0.45:
		loot.append({"id": "vault_key", "count": 1})
	return loot


func _build_cabin() -> void:
	# A traveller's cabin just west of spawn: shelter for the first night,
	# a workbench, and a chest with the start of a kit. Its builder left a
	# note on the sign; the lantern is the only thing they took with them.
	var cx := spawn.x - 16
	var ground := surface[cx]
	for x in range(cx - 1, cx + 10):
		ground = max(ground, surface[x])
	var w := 9
	var h := 6
	var top := ground - h
	for x in range(cx, cx + w):
		for y in range(top, ground + 3):
			var i := idx(x, y)
			if y >= ground:
				tiles[i] = SOIL if y > ground else GRASS
				continue
			var edge := x == cx or x == cx + w - 1 or y == top
			# Dressed stone: planks stacked into walls read as a crate tower.
			tiles[i] = BRICK if edge else AIR
			walls[i] = BRICK
			ores[i] = ORE_NONE
		surface[x] = top
	# Doors in both side walls, as gaps the player can walk through.
	for y in range(ground - 3, ground):
		tiles[idx(cx, y)] = AIR
		tiles[idx(cx + w - 1, y)] = AIR
	_put_object(cx + 2, ground - 1, {"type": "workbench"})
	_put_object(cx + 6, ground - 1, {"type": "chest", "loot": [
		{"id": "wood", "count": 20}, {"id": "torch", "count": 10},
		{"id": "apple", "count": 3}, {"id": "glow_flask", "count": 1},
	]})
	_put_object(cx + 4, top + 2, {"type": "torch", "lit": true})
	_put_object(cx + w + 1, surface[cx + w + 1] - 1, {"type": "sign",
		"text": "Took the lantern down. The light goes further than you think, " +
			"but not forever. Plant wardstones as you go. — R."})


const TREES := {
	Biome.MEADOW: ["tree", "treeLong", "treeSmall_green1", "treeSmall_green2", "treeOrange"],
	Biome.TUNDRA: ["treePineSnow", "treeSnow", "treeFrozen", "treePineFrozen"],
	Biome.DESERT: ["treePalm", "cactus1", "cactus2", "cactus3"],
}
const SHRUBS := {
	Biome.MEADOW: ["bush1", "bush2", "bushAlt1", "bushAlt3", "mushroom_red", "mushroom_brown"],
	Biome.TUNDRA: ["bushAlt2", "rock"],
	Biome.DESERT: ["bushOrange1", "bushOrange3", "rock"],
}


func _plant_surface() -> void:
	var next_tree := 0
	for x in range(4, width - 4):
		var y := surface[x] - 1
		if not is_solid(x, y + 1) or is_solid(x, y) or objects.has(idx(x, y)):
			continue
		if abs(x - spawn.x) < 3:
			continue
		var biome := biome_columns[x]
		var roll := _rng.randf()
		if x >= next_tree and roll < 0.34:
			var kinds: Array = TREES[biome]
			_put_object(x, y, {"type": "tree", "art": kinds[_rng.randi() % kinds.size()],
				"health": 5})
			next_tree = x + _rng.randi_range(3, 7)
		elif roll < 0.62:
			var kinds: Array = SHRUBS[biome]
			_put_object(x, y, {"type": "shrub", "art": kinds[_rng.randi() % kinds.size()]})

	# Mushrooms and crystals decorate cave floors.
	for i in 4200:
		var x := _rng.randi_range(2, width - 3)
		var y := _rng.randi_range(SURFACE_Y + 20, height - 3)
		if is_solid(x, y) or not is_solid(x, y + 1) or get_liquid(x, y) != DRY:
			continue
		if objects.has(idx(x, y)):
			continue
		var biome := biome_at(x, y)
		var art := "mushroom_brown"
		if biome == Biome.CRYSTAL:
			art = ["gem_blue", "gem_blue", "grass_purple"][_rng.randi() % 3]
		elif biome == Biome.DEPTHS:
			art = ["rock", "mushroom_red"][_rng.randi() % 2]
		elif _rng.randf() < 0.5:
			art = "rock"
		_put_object(x, y, {"type": "shrub", "art": art})


## The heart of the largest hollow: a geode the Gloam sleeps beside.
func _place_geode() -> void:
	var best := Vector2i(-1, -1)
	var best_room := 0
	for attempt in 4000:
		var x := _rng.randi_range(20, width - 20)
		var y := _rng.randi_range(SURFACE_Y + 50, DEEP_Y - 8)
		if get_wall(x, y) != CRYSTAL or is_solid(x, y) or not is_solid(x, y + 1):
			continue
		if abs(x - spawn.x) < 60 or objects.has(idx(x, y)):
			continue
		var room := 0
		for dx in range(-6, 7):
			for dy in range(-5, 1):
				if not is_solid(x + dx, y + dy):
					room += 1
		if room > best_room:
			best_room = room
			best = Vector2i(x, y)
	if best.x >= 0:
		_put_object(best.x, best.y, {"type": "geode"})


func _seal_edges() -> void:
	for y in height:
		for x in [0, width - 1]:
			tiles[idx(x, y)] = BEDROCK
	for x in width:
		tiles[idx(x, height - 1)] = BEDROCK


# =============================================================================
# Saving
# =============================================================================

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"width": width,
		"height": height,
		"seed": seed,
		"tiles": tiles.compress(FileAccess.COMPRESSION_ZSTD),
		"tiles_len": tiles.size(),
		"walls": walls.compress(FileAccess.COMPRESSION_ZSTD),
		"ores": ores.compress(FileAccess.COMPRESSION_ZSTD),
		"liquids": liquids.compress(FileAccess.COMPRESSION_ZSTD),
		"surface": surface,
		"biomes": biome_columns,
		"objects": objects,
		"spawn": spawn,
		"vault": vault,
	}


static func from_dict(data: Dictionary) -> WorldData:
	var w := WorldData.new(int(data.width), int(data.height))
	var n: int = data.tiles_len
	w.seed = int(data.seed)
	w.tiles = (data.tiles as PackedByteArray).decompress(n, FileAccess.COMPRESSION_ZSTD)
	w.walls = (data.walls as PackedByteArray).decompress(n, FileAccess.COMPRESSION_ZSTD)
	w.ores = (data.ores as PackedByteArray).decompress(n, FileAccess.COMPRESSION_ZSTD)
	w.liquids = (data.liquids as PackedByteArray).decompress(n, FileAccess.COMPRESSION_ZSTD)
	w.surface = data.surface
	w.biome_columns = data.biomes
	w.objects = data.objects
	w.spawn = data.spawn
	w.vault = data.vault
	w.recompute_all_sky()
	return w
