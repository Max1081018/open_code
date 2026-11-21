class_name TerrainGen
extends RefCounted
## The shape of the world: one deterministic function of (x, z) that every
## system asks (terrain meshes, colliders, foliage, spawns, the map), so they
## always agree. An island about 2 km across: ridged mountain ranges, rolling
## hills, rivers carved where a winding noise field crosses zero, lakes and
## the sea below WATER, and biomes from temperature and moisture. The village
## plateau at the centre is flattened by hand.
##
## Pure functions of the seed: safe to call from worker threads.

const WATER := 0.0
const HALF := 1536.0          ## the island's half-extent in metres (a 3 km island)
const VILLAGE := Vector2(0, 0)
const VILLAGE_RADIUS := 70.0
const VILLAGE_HEIGHT := 9.0

enum Biome { FOREST, DARK_FOREST, SNOW, DRY, VOLCANIC, CORRUPTED, BEACH }
const BIOME_NAMES := ["Greenwood", "The Gloomwood", "The Frostpeaks", "The Sunscar", "The Ashlands", "The Blight", "The Shore"]

var seed_value: int
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _mountain_mask := FastNoiseLite.new()
var _river := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(the_seed := 1337) -> void:
	seed_value = the_seed
	_setup(_continent, 1, 0.0011, 4)
	_setup(_hills, 2, 0.006, 3)
	_setup(_ridges, 3, 0.0042, 5)
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_mountain_mask, 4, 0.0014, 2)
	_setup(_river, 5, 0.0016, 2)
	_setup(_temperature, 6, 0.0009, 2)
	_setup(_moisture, 7, 0.0011, 2)
	_setup(_detail, 8, 0.05, 2)
	_setup(_forest, 9, 0.0045, 3)


func _setup(noise: FastNoiseLite, offset: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value * 31 + offset
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = octaves


## Ground height in metres.
func height(x: float, z: float) -> float:
	# The island: land falls to the sea toward the edge.
	var edge := maxf(absf(x), absf(z)) / HALF
	var island := 1.0 - smoothstep(0.72, 1.0, edge)
	var base := 6.0 + _continent.get_noise_2d(x, z) * 18.0 + _hills.get_noise_2d(x, z) * 7.0
	# Mountain ranges where the mask is high.
	var mask := smoothstep(0.05, 0.45, _mountain_mask.get_noise_2d(x, z))
	# Ranges stand back from the village: a wide valley around home.
	mask *= smoothstep(160.0, 420.0, Vector2(x, z).distance_to(VILLAGE))
	var ridge := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
	var mountains := pow(ridge, 2.2) * 150.0 * mask
	var h := base + mountains
	# Rivers: channels where the river field is near zero, outside mountains.
	var r := absf(_river.get_noise_2d(x, z))
	var channel := 1.0 - smoothstep(0.015, 0.06, r)
	channel *= 1.0 - mask * 0.85
	h = lerpf(h, minf(h, WATER - 2.5), channel)
	h = lerpf(-18.0, h, island)
	h += _detail.get_noise_2d(x, z) * 0.35
	# The village plateau, blended into the land around it.
	var d := Vector2(x, z).distance_to(VILLAGE)
	var flat := 1.0 - smoothstep(VILLAGE_RADIUS, VILLAGE_RADIUS * 2.2, d)
	h = lerpf(h, VILLAGE_HEIGHT + _detail.get_noise_2d(x, z) * 0.15, flat)
	return h


## Surface normal from neighbouring heights.
func normal(x: float, z: float, step := 1.5) -> Vector3:
	var hx := height(x + step, z) - height(x - step, z)
	var hz := height(x, z + step) - height(x, z - step)
	return Vector3(-hx, step * 2.0, -hz).normalized()


## How wooded the land is here, 0..1: groves and open meadows alternate.
func forest(x: float, z: float) -> float:
	return smoothstep(-0.15, 0.35, _forest.get_noise_2d(x, z))


func biome(x: float, z: float) -> int:
	var h := height(x, z)
	if h < WATER + 1.6:
		return Biome.BEACH
	var t := _temperature.get_noise_2d(x, z) - h * 0.004
	var m := _moisture.get_noise_2d(x, z)
	if h > 85.0 or t < -0.32:
		return Biome.SNOW
	if Vector2(x, z).distance_to(VILLAGE) < VILLAGE_RADIUS * 2.5:
		return Biome.FOREST
	if t > 0.3 and m < -0.05:
		return Biome.VOLCANIC if _continent.get_noise_2d(z, x) > 0.1 else Biome.DRY
	if t > 0.18 and m < 0.1:
		return Biome.DRY
	if m > 0.28:
		return Biome.CORRUPTED if t > 0.1 else Biome.DARK_FOREST
	return Biome.FOREST


## Splat weights for the terrain material: [grass, rock, snow, sand], soil
## takes the rest. Slope makes rock, height and cold make snow, water and
## dry lands make sand; volcanic and corrupted ground darken the soil.
func splat(x: float, z: float, h: float, n: Vector3, b: int) -> Color:
	var slope := 1.0 - n.y
	var rock := smoothstep(0.18, 0.4, slope)
	var snow := 0.0
	if b == Biome.SNOW:
		snow = clampf((h - 40.0) / 30.0, 0.35, 1.0) * (1.0 - rock * 0.6)
	var sand := 0.0
	if h < WATER + 2.2:
		sand = 1.0 - smoothstep(WATER + 0.8, WATER + 2.2, h)
	if b == Biome.DRY:
		sand = maxf(sand, 0.75)
	var grass := 1.0 - rock
	match b:
		Biome.DRY, Biome.VOLCANIC:
			grass *= 0.12
		Biome.SNOW:
			grass *= 0.3
		Biome.CORRUPTED:
			grass *= 0.45
	grass *= 1.0 - sand
	return Color(clampf(grass, 0, 1), rock, snow, sand)


## A per-biome tint and darkening carried to the shader (r,g,b tint, a ash).
func tint(b: int) -> Color:
	match b:
		Biome.DARK_FOREST:
			return Color(0.72, 0.8, 0.74, 0.0)
		Biome.CORRUPTED:
			return Color(0.82, 0.68, 0.9, 0.25)
		Biome.VOLCANIC:
			return Color(0.6, 0.55, 0.52, 0.8)
		Biome.DRY:
			return Color(1.08, 0.98, 0.82, 0.0)
		Biome.SNOW:
			return Color(0.95, 0.98, 1.05, 0.0)
	return Color(1, 1, 1, 0)


func biome_name(b: int) -> String:
	return BIOME_NAMES[b]
