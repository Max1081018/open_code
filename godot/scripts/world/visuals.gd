class_name Visuals
extends RefCounted
## Shared shader materials, built once from the current settings.

## Per material (atlas row): [tint, saturation]. A natural, deeper palette
## in place of Kenney's toy-bright defaults: warm earth, cool grey rock,
## dusty sand, blue-shadowed snow, a red-violet deep.
## Per-material tint and saturation. Muted and earthy (moss, peat, weathered
## stone) to sit with the mature cast: candy colours made the world a toy.
const PALETTE := [
	[Color(0.80, 0.86, 0.72), 0.52],  # grass soil: moss, not lawn
	[Color(0.80, 0.72, 0.66), 0.50],  # soil: peat
	[Color(0.92, 0.85, 0.74), 0.50],  # sand
	[Color(0.88, 0.92, 0.99), 0.70],  # snow
	[Color(0.80, 0.82, 0.86), 0.40],  # rock: weathered grey
	[Color(0.78, 0.76, 0.80), 0.40],  # brick: old stone
	[Color(0.86, 0.80, 1.00), 0.95],  # crystal
	[Color(0.90, 0.76, 0.80), 0.70],  # basalt
	[Color(0.84, 0.76, 0.66), 0.58],  # planks
]

static var _noise: Texture2D


static func noise() -> Texture2D:
	if _noise == null:
		var generator := FastNoiseLite.new()
		generator.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		generator.frequency = 0.03
		generator.fractal_octaves = 4
		var red := generator.get_seamless_image(256, 256)
		generator.seed = 77
		generator.frequency = 0.08
		var green := generator.get_seamless_image(256, 256)
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				image.set_pixel(x, y, Color(red.get_pixel(x, y).r, green.get_pixel(x, y).r, 0.5))
		image.generate_mipmaps()
		_noise = ImageTexture.create_from_image(image)
	return _noise


## The terrain material. `wall` gives the flatter, darker look for the
## background walls, so they read as depth rather than as more ground.
static func terrain(wall := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/terrain.gdshader")
	var tints := PackedColorArray()
	var saturations := PackedFloat32Array()
	for entry in PALETTE:
		tints.append(entry[0])
		saturations.append(entry[1] * (0.7 if wall else 1.0))
	material.set_shader_parameter("row_tint", tints)
	material.set_shader_parameter("row_saturation", saturations)
	material.set_shader_parameter("detail_noise", noise())
	material.set_shader_parameter("quality", mini(Settings.shader_fx, 2) if not wall else mini(Settings.shader_fx, 1))
	material.set_shader_parameter("relief", 0.55 if not wall else 0.0)
	material.set_shader_parameter("bevel", 1.0 if not wall else 0.0)
	material.set_shader_parameter("detail", 0.20 if not wall else 0.28)
	material.set_shader_parameter("brightness", 0.92 if not wall else 1.0)
	material.set_shader_parameter("surface_px", WorldData.SURFACE_Y * 128.0)
	material.set_shader_parameter("deep_px", WorldData.DEEP_Y * 128.0)
	return material


static func liquid() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/liquid.gdshader")
	material.set_shader_parameter("noise_tex", noise())
	material.set_shader_parameter("quality", mini(Settings.shader_fx, 2))
	return material


static var _sway: ShaderMaterial


## One shared wind material for all ground cover.
static func sway() -> ShaderMaterial:
	if _sway == null:
		_sway = ShaderMaterial.new()
		_sway.shader = load("res://scripts/shaders/sway.gdshader")
	return _sway


## Foliage species: how each kind of plant moves in the wind.
##   [bend, flutter, shimmer, speed, canopy_start, cluster_scale, leaf_detail, pad]
const SPECIES := {
	"broadleaf": [12.0, 7.0, 1.6, 1.0, 0.30, 2.2, 0.16, 26.0],
	"poplar": [16.0, 4.0, 1.2, 1.2, 0.22, 3.0, 0.14, 26.0],
	"conifer": [8.0, 2.5, 0.6, 0.8, 0.18, 3.6, 0.10, 18.0],
	"palm": [18.0, 11.0, 1.0, 0.7, 0.68, 1.6, 0.10, 34.0],
	"sapling": [6.0, 3.0, 1.2, 1.4, 0.30, 2.0, 0.12, 12.0],
	"dead": [4.0, 0.0, 0.0, 0.6, 0.40, 1.0, 0.0, 8.0],
	"cactus": [0.0, 0.0, 0.0, 1.0, 1.10, 1.0, 0.0, 2.0],
	"bush": [6.0, 4.0, 1.2, 1.3, 0.0, 2.6, 0.14, 14.0],
}

static var _foliage := {}


## The species a piece of tree or bush art belongs to.
static func species_of(art: String) -> String:
	if art.begins_with("bush"):
		return "bush"
	if art.begins_with("cactus"):
		return "cactus"
	if art.begins_with("treePine"):
		return "conifer"
	if art.begins_with("treeLong"):
		return "poplar"
	if art.begins_with("treePalm"):
		return "palm"
	if art.begins_with("treeSmall"):
		return "sapling"
	if art.begins_with("treeDead"):
		return "dead"
	return "broadleaf"


## One shared material per species.
static func foliage(species: String) -> ShaderMaterial:
	if not _foliage.has(species):
		var spec: Array = SPECIES.get(species, SPECIES.broadleaf)
		var material := ShaderMaterial.new()
		material.shader = load("res://scripts/shaders/foliage.gdshader")
		material.set_shader_parameter("noise_tex", noise())
		material.set_shader_parameter("quality", mini(Settings.shader_fx, 2))
		var names := ["bend", "flutter", "shimmer", "speed", "canopy_start", "cluster_scale",
			"leaf_detail", "pad"]
		for i in names.size():
			material.set_shader_parameter(names[i], spec[i])
		_foliage[species] = material
	return _foliage[species]


## Sun and wind for every plant at once: a handful of uniform writes a
## frame, however many trees are on screen.
static func set_environment(sun_dir: Vector2, sun_strength: float, wind: float,
		player_position: Vector2) -> void:
	for material in _foliage.values():
		material.set_shader_parameter("sun_dir", sun_dir)
		material.set_shader_parameter("sun_strength", sun_strength)
		material.set_shader_parameter("wind", wind)
	var cover := sway()
	cover.set_shader_parameter("wind", wind)
	cover.set_shader_parameter("player_position", player_position)


## Graphics settings changed: rebuild on next use.
static func reset() -> void:
	_foliage.clear()
	_sway = null
