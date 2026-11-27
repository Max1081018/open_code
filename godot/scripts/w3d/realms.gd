class_name Realms
extends RefCounted
## The designed lands of the Starfall, layered over the procedural island:
##   The Great Jungle   (SW)  lush lowland round a sheer mesa crowned by the
##                            World Tree; three waterfalls fall from its rim
##                            into pools whose rivers run to the sea; a long
##                            root ramp climbs the mesa.
##   The Sunscar Sea    (W)   a vast desert of long crescent dune ridges with
##                            crossing ripples, two oases and great ruins.
##   The Crystal Coast  (SE)  sea cliffs broken by white beaches, crystal
##                            reefs, sea stacks and a fishing village.
##   Skybound Isle      (NW)  an archipelago of floating isles joined by
##                            bridges and wind currents, high over the land.
## All of these shape the terrain through `shape()` (pure, thread-safe: the
## chunk builders call it on worker threads) and pick their biome through
## `biome_override()`. The three starting locations are in STARTS.

const JUNGLE := Vector2(-1300.0, 1350.0)
const JUNGLE_R := 640.0
const MESA_R := 122.0
const MESA_H := 30.0
const RAMP_ANGLE := 0.75          ## the root ramp climbs from this side (radians)
const FALLS := [2.3, 3.6, 5.0]    ## waterfall angles round the mesa (main thread)
## The same as plain values for the chunk builders' threads: shared Arrays are
## not safe to iterate from several threads at once.
const FALL_0 := 2.3
const FALL_1 := 3.6
const FALL_2 := 5.0
const POOL_R := 150.0

const DESERT := Vector2(-1500.0, -250.0)
const DESERT_R := 800.0
const OASES := [[Vector2(-1350.0, -120.0), 34.0], [Vector2(-1820.0, -520.0), 26.0]]  ## main thread
const OASIS_A := Vector2(-1350.0, -120.0)
const OASIS_A_R := 34.0
const OASIS_B := Vector2(-1820.0, -520.0)
const OASIS_B_R := 26.0

const COAST := Vector2(1650.0, 1650.0)
const COAST_R := 560.0

const SKY := Vector2(-1250.0, -1650.0)
## [offset x, offset z, altitude above ground, radius, spire]
const SKY_ISLES := [
	[0.0, 0.0, 120.0, 62.0, true],
	[120.0, 40.0, 112.0, 24.0, false],
	[70.0, -110.0, 130.0, 22.0, false],
	[-115.0, -60.0, 138.0, 26.0, false],
	[-60.0, 125.0, 104.0, 20.0, false],
	[200.0, -40.0, 150.0, 18.0, false],
	[-190.0, 70.0, 158.0, 20.0, false],
]
## Bridges between isle indices.
const SKY_BRIDGES := [[0, 1], [0, 2], [0, 3], [0, 4], [1, 5]]

const START_ORDER := ["jungle", "sky", "coast"]
const STARTS := {
	"jungle": {"name": "The Great Jungle", "recommended": true, "difficulty": "Gentle", "level": 1,
		"desc": "Giant trees, roaring falls and the World Tree on its mesa. A green maze of ruins, caves and shrines, and the gentlest place to learn the blade.",
		"preview": "res://assets/ui/islands/jungle.jpg", "quest": "jungle_arrival"},
	"sky": {"name": "Skybound Isle", "recommended": false, "difficulty": "Moderate", "level": 2,
		"desc": "Floating isles strung with bridges over a long fall. Ride the wind currents, glide between ruins and find what the sky-folk left behind.",
		"preview": "res://assets/ui/islands/sky.jpg", "quest": "sky_arrival"},
	"coast": {"name": "The Crystal Coast", "recommended": false, "difficulty": "Moderate", "level": 2,
		"desc": "White sand, glass-clear water and reefs of living crystal. A fishing village keeps watch over the sea caves where the crystals sing.",
		"preview": "res://assets/ui/islands/coast.jpg", "quest": "coast_arrival"},
}


static func _warp(gen: TerrainGen, x: float, z: float, amount: float) -> float:
	return gen._hills.get_noise_2d(x * 0.25 + 500.0, z * 0.25) * amount


## 0..1 masks with noisy borders.
static func jungle(gen: TerrainGen, x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(JUNGLE)
	if d > JUNGLE_R + 160.0:
		return 0.0
	return 1.0 - smoothstep(JUNGLE_R - 120.0, JUNGLE_R + 40.0, d + _warp(gen, x, z, 120.0))


static func desert(gen: TerrainGen, x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(DESERT)
	if d > DESERT_R + 180.0:
		return 0.0
	return 1.0 - smoothstep(DESERT_R - 140.0, DESERT_R + 40.0, d + _warp(gen, x, z, 140.0))


static func coast(gen: TerrainGen, x: float, z: float) -> float:
	var d := Vector2(x, z).distance_to(COAST)
	if d > COAST_R + 160.0:
		return 0.0
	return 1.0 - smoothstep(COAST_R - 120.0, COAST_R + 40.0, d + _warp(gen, x, z, 110.0))


## The land's height reshaped by any realm here. `h` is the procedural height.
static func shape(gen: TerrainGen, x: float, z: float, h: float) -> float:
	var dm := desert(gen, x, z)
	if dm > 0.0:
		h = lerpf(h, dunes(gen, x, z), dm)
	var jm := jungle(gen, x, z)
	if jm > 0.0:
		h = lerpf(h, jungle_height(gen, x, z), jm)
	var cm := coast(gen, x, z)
	if cm > 0.0:
		# Sea cliffs: along stretches of the shore the land steps up sharply,
		# elsewhere it runs down to white beaches.
		var cliffs := smoothstep(0.0, 0.25, gen._forest.get_noise_2d(x * 0.4, z * 0.4))
		var step := smoothstep(3.0, 5.0, h) * 8.0 * cliffs
		# Sea stacks just off the cliffs.
		var stacks := maxf(0.0, gen._ridges.get_noise_2d(x * 3.0, z * 3.0) - 0.55) * 60.0 * smoothstep(-3.0, 0.5, h) * (1.0 - smoothstep(0.5, 3.0, h))
		h = lerpf(h, h + step + stacks, cm)
	return h


## Long crescent dunes across the wind, crossing ripples, broad swells and
## the oasis basins.
static func dunes(gen: TerrainGen, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var warp := gen._hills.get_noise_2d(x * 0.6, z * 0.6) * 46.0
	var u := (p.dot(Vector2(0.94, 0.34)) + warp) / 78.0
	var f := fposmod(u, 1.0)
	# Asymmetric profile: a long windward slope, a short steep slip face.
	var crest := f / 0.72 if f < 0.72 else (1.0 - f) / 0.28
	crest = crest * crest * (3.0 - 2.0 * crest)
	var size := 8.0 + 9.0 * (gen._continent.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5)
	var v := (p.dot(Vector2(-0.31, 0.95)) + warp * 0.4) / 24.0
	var ripple := pow(1.0 - absf(fposmod(v, 1.0) * 2.0 - 1.0), 2.0) * 1.4
	var swell := gen._continent.get_noise_2d(x * 0.45, z * 0.45) * 12.0
	# Wide flats between the dune fields: smooth, nearly level sand where the
	# dunes die away (about two fifths of the sea).
	var flat := smoothstep(0.05, 0.3, gen._forest.get_noise_2d(x * 0.22 + 300.0, z * 0.22))
	var h := 13.0 + swell * lerpf(1.0, 0.35, flat) + crest * size * (1.0 - flat * 0.9) + ripple * (1.0 - flat * 0.7)
	h = _oasis(h, p, OASIS_A, OASIS_A_R)
	h = _oasis(h, p, OASIS_B, OASIS_B_R)
	return h


static func _oasis(h: float, p: Vector2, c: Vector2, r: float) -> float:
	var d := p.distance_to(c)
	if d < r * 2.6:
		return lerpf(h, -1.4, 1.0 - smoothstep(r * 0.6, r * 2.6, d))
	return h


static func jungle_height(gen: TerrainGen, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := 7.0 + gen._hills.get_noise_2d(x, z) * 6.0 + gen._continent.get_noise_2d(x * 1.5, z * 1.5) * 4.0
	# The mesa: sheer walls, except the long root ramp on one side.
	var d := p.distance_to(JUNGLE) + gen._detail.get_noise_2d(x * 0.3, z * 0.3) * 6.0
	var a := atan2(z - JUNGLE.y, x - JUNGLE.x)
	var off := absf(wrapf(a - RAMP_ANGLE, -PI, PI))
	var ramp := 1.0 - smoothstep(0.1, 0.24, off)
	var wall := lerpf(14.0, 150.0, ramp)
	h += (1.0 - smoothstep(MESA_R, MESA_R + wall, d)) * MESA_H
	# Pools below each waterfall, and the rivers that run from them.
	var wob := gen._detail.get_noise_2d(x * 0.2, z * 0.2) * 10.0
	h = _fall_pool(h, p, FALL_0, wob)
	h = _fall_pool(h, p, FALL_1, wob)
	h = _fall_pool(h, p, FALL_2, wob)
	return h


static func _fall_pool(h: float, p: Vector2, fa: float, wob: float) -> float:
	var dir := Vector2(cos(fa), sin(fa))
	var pool := JUNGLE + dir * POOL_R
	var dp := p.distance_to(pool)
	h = lerpf(h, -1.6, 1.0 - smoothstep(14.0, 30.0, dp))
	var t := clampf((p - pool).dot(dir), 0.0, 620.0)
	var dr := p.distance_to(pool + dir * t) + wob
	return lerpf(h, minf(h, -1.2), 1.0 - smoothstep(5.0, 13.0, dr))


## The biome a realm imposes here, or -1.
static func biome_override(gen: TerrainGen, x: float, z: float, h: float) -> int:
	if desert(gen, x, z) > 0.5:
		return TerrainGen.Biome.DRY if h > TerrainGen.WATER + 0.6 else TerrainGen.Biome.BEACH
	if jungle(gen, x, z) > 0.5:
		return TerrainGen.Biome.JUNGLE if h > TerrainGen.WATER + 1.2 else TerrainGen.Biome.BEACH
	if coast(gen, x, z) > 0.5:
		return TerrainGen.Biome.CRYSTAL if h > TerrainGen.WATER + 1.6 else TerrainGen.Biome.BEACH
	return -1


## Positions of the floating isles of Skybound: [centre Vector3, radius, spire].
static func sky_isles(gen: TerrainGen) -> Array:
	var out := []
	for s in SKY_ISLES:
		var x: float = SKY.x + s[0]
		var z: float = SKY.y + s[1]
		var ground := maxf(gen.height(x, z), TerrainGen.WATER)
		out.append([Vector3(x, ground + s[2], z), float(s[3]), bool(s[4])])
	return out


## Where a start places the heroine: dry, gentle ground near the designed
## spot (on the main isle for Skybound).
static func spawn_point(gen: TerrainGen, id: String) -> Vector3:
	match id:
		"sky":
			var isle: Array = sky_isles(gen)[0]
			var c: Vector3 = isle[0]
			return c + Vector3(-18.0, 0.6, 22.0)
		"coast":
			return _dry_near(gen, COAST + Vector2(-260.0, -230.0))
		_:
			# On the jungle floor at the foot of the root ramp, the World
			# Tree's mesa ahead.
			var dir := Vector2(cos(RAMP_ANGLE), sin(RAMP_ANGLE))
			return _dry_near(gen, JUNGLE + dir * (MESA_R + 175.0))


static func _dry_near(gen: TerrainGen, at: Vector2) -> Vector3:
	for ring in 30:
		for k in 12:
			var a := TAU * k / 12.0
			var p := at + Vector2(cos(a), sin(a)) * ring * 6.0
			var h := gen.height(p.x, p.y)
			if h > TerrainGen.WATER + 1.2 and gen.normal(p.x, p.y).y > 0.9:
				return Vector3(p.x, h, p.y)
	return Vector3(at.x, gen.height(at.x, at.y), at.y)


## Which designed land a point lies in ("" when none), for titles and music.
static func realm_at(gen: TerrainGen, p: Vector3) -> String:
	for isle in sky_isles_cached(gen):
		var c: Vector3 = isle[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(isle[1]) + 20.0 and p.y > c.y - 30.0:
			return "sky"
	return ""


static var _sky_cache: Array = []


static func sky_isles_cached(gen: TerrainGen) -> Array:
	if _sky_cache.is_empty():
		_sky_cache = sky_isles(gen)
	return _sky_cache
