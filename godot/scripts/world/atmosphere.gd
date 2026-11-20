class_name Atmosphere
extends Node
## Everything that gives the world depth and air.
##
##   sky gradient, sun and moon, stars          (screen space, furthest back)
##   four depth layers of hills and forest     (each fogged by distance)
##   drifting mist between them
##   light shafts and floating motes           (over the world, additive)
##   dark foreground foliage framing the view
##   a final grade: vignette, tint, fringing
##
## Atmospheric perspective — distant layers fading toward the fog colour —
## is most of why a painted forest reads as deep. Each layer here is the
## same Kenney art at a different scale, fog amount and scroll speed.

const TILE := 128.0

## Per biome: layer textures and the fog colour by day.
const BIOMES := {
	WorldData.Biome.MEADOW: {
		"far": "fade_trees", "near": "color_hills",
		"trees": ["tree", "treeLong", "treePine", "tree", "treeSmall_green1"],
		"fog": Color(0.40, 0.56, 0.54), "sky_top": Color(0.30, 0.50, 0.70),
		"sky_low": Color(0.62, 0.74, 0.72),
	},
	WorldData.Biome.TUNDRA: {
		"far": "fade_hills", "near": "color_hills",
		"trees": ["treePineSnow", "treeSnow", "treePineFrozen", "treeFrozen"],
		"fog": Color(0.62, 0.70, 0.80), "sky_top": Color(0.30, 0.42, 0.62),
		"sky_low": Color(0.76, 0.82, 0.90),
	},
	WorldData.Biome.DESERT: {
		"far": "fade_desert", "near": "color_desert",
		"trees": ["treePalm", "cactus1", "cactus2", "treePalm"],
		"fog": Color(0.80, 0.66, 0.50), "sky_top": Color(0.34, 0.50, 0.70),
		"sky_low": Color(0.92, 0.78, 0.60),
	},
}

## [scroll factor, fog amount, tree scale, vertical follow, texture kind]
const LAYERS := [
	[0.04, 0.78, 0.0, 0.10, "far"],
	[0.10, 0.62, 0.55, 0.22, "trees"],
	[0.22, 0.42, 0.85, 0.38, "trees"],
	[0.38, 0.18, 0.0, 0.55, "near"],
]

var world: World
var camera: Camera2D

var _sky: ColorRect
var _sky_material: ShaderMaterial
var _sun: Sprite2D
var _moon: Sprite2D
var _stars: TextureRect
var _layer_root: CanvasLayer
var _sets := {}  ## biome -> Array of layer Node2D
var _mists: Array[Sprite2D] = []
var _rays: Array[ColorRect] = []
var _ray_layer: CanvasLayer
var _motes: CPUParticles2D
var _fireflies: CPUParticles2D
var _foreground: Node2D
var _grade: ShaderMaterial
var _strip_width := 4096.0


func setup(the_world: World, the_camera: Camera2D) -> void:
	world = the_world
	camera = the_camera
	_build_sky()
	_build_layers()
	_build_air()
	_build_foreground()
	_build_grade()


# =============================================================================
# Construction
# =============================================================================

func _build_sky() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -30
	add_child(layer)

	_sky = ColorRect.new()
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load("res://scripts/shaders/sky.gdshader")
	_sky.material = _sky_material
	layer.add_child(_sky)

	var star_image := Image.create(512, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 260:
		var p := Vector2i(rng.randi() % 512, rng.randi() % 256)
		var v := rng.randf_range(0.4, 1.0)
		star_image.set_pixelv(p, Color(v, v, v * 1.05, v))
	_stars = TextureRect.new()
	_stars.texture = ImageTexture.create_from_image(star_image)
	_stars.stretch_mode = TextureRect.STRETCH_TILE
	_stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(_stars)

	_sun = Sprite2D.new()
	_sun.texture = load("res://assets/scenery/sun.png")
	_sun.scale = Vector2(0.9, 0.9)
	layer.add_child(_sun)
	_sun.add_child(Glow.make(Color(1.0, 0.92, 0.7), 3.2, false))
	_sun.get_child(0).position = Vector2.ZERO
	_moon = Sprite2D.new()
	_moon.texture = load("res://assets/scenery/moonFull.png")
	_moon.scale = Vector2(0.6, 0.6)
	layer.add_child(_moon)


func _build_layers() -> void:
	_layer_root = CanvasLayer.new()
	_layer_root.layer = -25
	add_child(_layer_root)
	var smoke: Texture2D = load("res://assets/fx/smoke_07.png")

	for biome in BIOMES:
		var spec: Dictionary = BIOMES[biome]
		var set := []
		for i in LAYERS.size():
			var layer_spec: Array = LAYERS[i]
			var layer := Node2D.new()
			var fog_material := ShaderMaterial.new()
			fog_material.shader = load("res://scripts/shaders/fog_layer.gdshader")
			fog_material.set_shader_parameter("amount", layer_spec[1])
			# Nearer layers keep a little more colour than distant ones.
			fog_material.set_shader_parameter("saturation", lerpf(0.45, 0.7, float(i) / 3.0))
			layer.material = fog_material
			layer.set_meta("fog", fog_material)
			_layer_root.add_child(layer)
			match layer_spec[4]:
				"far", "near":
					var tex: Texture2D = load("res://assets/scenery/parallax/%s.png" % spec[layer_spec[4]])
					var scale := 1.6 if layer_spec[4] == "far" else 2.2
					var w := tex.get_width() * scale
					var count := int(ceil(_strip_width / w)) + 1
					for n in count:
						var s := Sprite2D.new()
						s.texture = tex
						s.centered = false
						s.scale = Vector2(scale, scale)
						# Place by the crest, not the bottom edge: the lower
						# half of each backdrop is solid fill, and anchoring by
						# the bottom stood a flat green wall across the screen.
						s.position = Vector2(n * w, -tex.get_height() * scale * 0.56)
						s.use_parent_material = true
						layer.add_child(s)
					layer.set_meta("repeat", count * w - w)
				"trees":
					_fill_tree_line(layer, spec.trees, layer_spec[2], i)
					layer.set_meta("repeat", _strip_width)
			set.append(layer)

			# Mist settles in front of each distant layer.
			if i < 3:
				var mist := Sprite2D.new()
				mist.texture = smoke
				mist.scale = Vector2(14.0, 1.4)
				mist.modulate = Color(1, 1, 1, 0.0)
				layer.add_child(mist)
				mist.position = Vector2(_strip_width * 0.5, -60)
				mist.set_meta("speed", 8.0 + i * 6.0)
				_mists.append(mist)
		_sets[biome] = set


func _fill_tree_line(layer: Node2D, kinds: Array, scale: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + seed_value
	var x := 0.0
	while x < _strip_width:
		var tex: Texture2D = load("res://assets/scenery/%s.png" % kinds[rng.randi() % kinds.size()])
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var k := scale * rng.randf_range(0.8, 1.35)
		s.scale = Vector2(k, k)
		s.flip_h = rng.randf() < 0.5
		s.position = Vector2(x, -tex.get_height() * k + rng.randf_range(0, 24))
		s.use_parent_material = true
		layer.add_child(s)
		x += tex.get_width() * k * rng.randf_range(0.45, 0.85)
	# A ground band under the trees so they do not float above the horizon.
	var ground := ColorRect.new()
	ground.size = Vector2(_strip_width + 400, 1400)
	ground.position = Vector2(-200, -4)
	ground.color = Color(0.16, 0.30, 0.22)
	ground.use_parent_material = true
	layer.add_child(ground)


func _build_air() -> void:
	_ray_layer = CanvasLayer.new()
	_ray_layer.layer = 1
	add_child(_ray_layer)

	var ray_shader: Shader = load("res://scripts/shaders/light_ray.gdshader")
	for i in 5:
		var ray := ColorRect.new()
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ray.size = Vector2(randf_range(140, 300), 2200)
		ray.pivot_offset = Vector2(ray.size.x * 0.5, 0)
		ray.rotation = deg_to_rad(-24)
		var material := ShaderMaterial.new()
		material.shader = ray_shader
		material.set_shader_parameter("phase", i * 1.7)
		ray.material = material
		ray.set_meta("x", 0.12 + i * 0.19 + randf_range(-0.04, 0.04))
		_ray_layer.add_child(ray)
		_rays.append(ray)

	_motes = _air_particles(Color(1.0, 0.95, 0.78), 26, 0.010, 0.022, 9.0)
	_fireflies = _air_particles(Color(0.70, 1.0, 0.45), 22, 0.016, 0.034, 5.0)


func _air_particles(color: Color, amount: int, small: float, big: float, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = load("res://assets/fx/circle_05.png")
	p.material = Effects.additive()
	p.amount = max(4, int(amount * Settings.particle_scale()))
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1200, 700)
	p.position = Vector2(960, 540)
	p.gravity = Vector2(6, -6)
	p.spread = 180.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = small
	p.scale_amount_max = big
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.9),
		Color(color, 0.35), Color(color, 0.95), Color(color, 0.0)])
	p.color_ramp = gradient
	_ray_layer.add_child(p)
	return p


func _build_foreground() -> void:
	# Dark leaves at the bottom edge, passing faster than the world: the
	# cheapest possible way to put the camera *inside* a forest.
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_foreground = Node2D.new()
	layer.add_child(_foreground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var x := 0.0
	var kinds := ["bush1", "bush2", "bushAlt1", "bushAlt3", "bush4"]
	while x < _strip_width:
		var tex: Texture2D = load("res://assets/scenery/%s.png" % kinds[rng.randi() % kinds.size()])
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var k := rng.randf_range(1.5, 2.6)
		s.scale = Vector2(k, k)
		s.flip_h = rng.randf() < 0.5
		s.position = Vector2(x, -tex.get_height() * k * rng.randf_range(0.35, 0.6))
		s.modulate = Color(0.05, 0.10, 0.08, 0.96)
		_foreground.add_child(s)
		x += tex.get_width() * k * rng.randf_range(1.6, 3.4)


func _build_grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade = ShaderMaterial.new()
	_grade.shader = load("res://scripts/shaders/grade.gdshader")
	rect.material = _grade
	layer.add_child(rect)
	rect.visible = Settings.shader_fx >= 1


# =============================================================================
# Frame
# =============================================================================

func _process(delta: float) -> void:
	if world == null or camera == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var centre := camera.get_screen_center_position()
	var data := world.data
	var column := clampi(int(centre.x / TILE), 0, data.width - 1)
	var surface_world := data.surface[column] * TILE
	var horizon := (surface_world - centre.y) * camera.zoom.y + screen.y * 0.5

	# How far underground the view is: 0 outdoors, 1 well below.
	var depth := clampf((centre.y - surface_world) / (TILE * 14.0), 0.0, 1.0)
	var t := world.time_of_day
	var daylight := clampf(sin((t - 0.25) * TAU) * 1.6 + 0.35, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(sin((t - 0.25) * TAU)) * 3.0, 0.0, 1.0) * daylight

	# Biome weights blend over ~24 tiles so the backdrop never pops.
	var weights := _biome_weights(centre.x / TILE)
	var fog := Color.BLACK
	var sky_top := Color.BLACK
	var sky_low := Color.BLACK
	for biome in weights:
		fog += BIOMES[biome].fog * weights[biome]
		sky_top += BIOMES[biome].sky_top * weights[biome]
		sky_low += BIOMES[biome].sky_low * weights[biome]
	var night_fog := Color(0.10, 0.14, 0.26)
	fog = night_fog.lerp(fog.lerp(Color(1.0, 0.62, 0.45), dusk * 0.55), daylight)
	sky_top = Color(0.03, 0.04, 0.10).lerp(sky_top.lerp(Color(0.42, 0.36, 0.62), dusk * 0.6), daylight)
	sky_low = Color(0.10, 0.12, 0.24).lerp(sky_low.lerp(Color(1.0, 0.58, 0.40), dusk), daylight)
	var overcast: float = Game.level.life.overcast() if Game.level and Game.level.life else 0.0
	fog = fog.lerp(Color(0.46, 0.50, 0.55) * daylight, overcast)
	sky_top = sky_top.lerp(Color(0.32, 0.36, 0.42) * maxf(daylight, 0.2), overcast)
	sky_low = sky_low.lerp(Color(0.55, 0.58, 0.62) * maxf(daylight, 0.2), overcast)
	var cave := Color(0.035, 0.03, 0.06)
	_sky_material.set_shader_parameter("top", sky_top.lerp(cave, depth))
	_sky_material.set_shader_parameter("bottom", sky_low.lerp(cave, depth))
	_sky_material.set_shader_parameter("horizon", clampf(horizon / screen.y, -0.5, 1.5))
	_stars.modulate = Color(1, 1, 1, (1.0 - daylight) * (1.0 - depth) * 0.9)

	var arc := (t - 0.25) * TAU
	_sun.position = Vector2(screen.x * (0.5 + cos(arc - PI * 0.5) * -0.42),
		horizon - sin(arc) * screen.y * 0.62)
	_sun.visible = daylight > 0.0 and depth < 1.0
	_moon.position = Vector2(screen.x * (0.5 + cos(arc + PI * 0.5) * -0.42),
		horizon + sin(arc) * screen.y * 0.62)
	_moon.visible = daylight < 0.8 and depth < 1.0

	for biome in _sets:
		var weight: float = weights.get(biome, 0.0)
		var layers: Array = _sets[biome]
		for i in layers.size():
			var layer: Node2D = layers[i]
			layer.visible = weight > 0.01 and depth < 0.98
			if not layer.visible:
				continue
			var spec: Array = LAYERS[i]
			var fog_material: ShaderMaterial = layer.get_meta("fog")
			fog_material.set_shader_parameter("fog", fog)
			fog_material.set_shader_parameter("light", lerpf(0.42, 1.0, daylight))
			layer.modulate = Color(1, 1, 1, weight)
			var repeat: float = layer.get_meta("repeat", _strip_width)
			layer.position.x = -fposmod(centre.x * spec[0], repeat)
			# Distant layers settle toward a fixed band above the ground the
			# player walks on; nearer ones follow the real terrain more.
			layer.position.y = lerpf(screen.y * 0.50, horizon, spec[3]) + 30.0

	for mist in _mists:
		mist.position.x = fposmod(mist.position.x + mist.get_meta("speed") * delta, _strip_width)
		mist.modulate = Color(fog.lightened(0.25), 0.22 * (1.0 - depth))

	var outdoors := 1.0 - depth
	for ray in _rays:
		ray.position = Vector2(screen.x * ray.get_meta("x") - ray.size.x * 0.5, -200)
		ray.modulate = Color(1.0, 0.95, 0.8, outdoors * daylight * (1.0 - dusk * 0.5) * 0.85 * (1.0 - overcast * 2.0))
		ray.visible = Settings.background >= 2
	_motes.emitting = outdoors > 0.2 and daylight > 0.3
	_motes.position = screen * 0.5
	_motes.emission_rect_extents = screen * 0.55
	_fireflies.emitting = outdoors > 0.2 and daylight < 0.5 \
		and weights.get(WorldData.Biome.MEADOW, 0.0) > 0.3
	_fireflies.position = screen * 0.5
	_fireflies.emission_rect_extents = screen * 0.55

	_foreground.position.x = -fposmod(centre.x * 1.35, _strip_width - 600)
	_foreground.position.y = horizon + screen.y * 0.40
	_foreground.visible = depth < 0.6
	_foreground.modulate = Color(1, 1, 1, 1.0 - depth / 0.6)

	if _grade:
		_grade.set_shader_parameter("tint", Color.WHITE.lerp(fog, 0.10).lerp(Color(0.75, 0.80, 1.0), depth * 0.25))


func grade_material() -> ShaderMaterial:
	return _grade


func _biome_weights(tile_x: float) -> Dictionary:
	var data := world.data
	var weights := {}
	var total := 0.0
	for offset in range(-12, 13, 4):
		var x := clampi(int(tile_x) + offset, 0, data.width - 1)
		var biome: int = data.biome_columns[x]
		weights[biome] = weights.get(biome, 0.0) + 1.0
		total += 1.0
	for biome in weights:
		weights[biome] /= total
	return weights
