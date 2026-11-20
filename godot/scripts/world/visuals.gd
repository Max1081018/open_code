class_name Visuals
extends RefCounted
## Shared shader materials, built once from the current settings.

## Per material (atlas row): [tint, saturation]. A natural, deeper palette
## in place of Kenney's toy-bright defaults: warm earth, cool grey rock,
## dusty sand, blue-shadowed snow, a red-violet deep.
const PALETTE := [
	[Color(0.90, 0.92, 0.84), 0.74],  # grass soil
	[Color(0.86, 0.78, 0.72), 0.72],  # soil
	[Color(0.94, 0.86, 0.74), 0.66],  # sand
	[Color(0.88, 0.92, 0.99), 0.80],  # snow
	[Color(0.78, 0.80, 0.86), 0.55],  # rock
	[Color(0.76, 0.74, 0.78), 0.55],  # brick
	[Color(0.86, 0.80, 1.00), 1.00],  # crystal
	[Color(0.90, 0.76, 0.80), 0.82],  # basalt
	[Color(0.84, 0.74, 0.64), 0.76],  # planks
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
	material.set_shader_parameter("detail", 0.20 if not wall else 0.28)
	material.set_shader_parameter("brightness", 0.92 if not wall else 1.0)
	material.set_shader_parameter("surface_px", WorldData.SURFACE_Y * 128.0)
	material.set_shader_parameter("deep_px", WorldData.DEEP_Y * 128.0)
	return material
