class_name WorldLife
extends Node
## The small motion that makes a world feel inhabited:
##
##   weather      rain, or snow in Rimefrost, that darkens the sky
##   leaves       drifting across the forest
##   drips        water falling from cave ceilings, with a splash
##   underwater   a tint and wobble while the player's head is submerged
##   heat         shimmer while lava is close
##
## Everything is gated by the graphics settings and switches off where it
## would never be seen (rain underground, drips on the surface).

const TILE := 128.0

enum Weather { CLEAR, RAIN, SNOW }

var level: Level
var sky := Weather.CLEAR
var intensity := 0.0  ## 0..1, eased toward the target
var _target := 0.0
var _weather_timer := 90.0

var _layer: CanvasLayer
var _rain: CPUParticles2D
var _snow: CPUParticles2D
var _leaves: CPUParticles2D
var _drips: Array[Dictionary] = []
var _drip_timer := 0.0
var _drip_texture: Texture2D
var _underwater := 0.0
var _heat := 0.0


func setup(the_level: Level) -> void:
	level = the_level
	_layer = CanvasLayer.new()
	_layer.layer = 1
	add_child(_layer)
	_rain = _make_rain()
	_snow = _make_snow()
	_leaves = _make_leaves()
	_drip_texture = load("res://assets/fx/circle_05.png")


func _make_rain() -> CPUParticles2D:
	var streak := Image.create(4, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		var a := sin(y / 47.0 * PI) * 0.8
		for x in 4:
			streak.set_pixel(x, y, Color(0.8, 0.88, 1.0, a * (1.0 - absf(x - 1.5) / 2.0)))
	var p := CPUParticles2D.new()
	p.texture = ImageTexture.create_from_image(streak)
	p.amount = max(30, int(160 * Settings.particle_scale()))
	p.lifetime = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.18, 1.0)
	p.spread = 3.0
	p.gravity = Vector2(0, 1800)
	p.initial_velocity_min = 1300.0
	p.initial_velocity_max = 1600.0
	p.particle_flag_align_y = true
	p.emitting = false
	_layer.add_child(p)
	return p


func _make_snow() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = load("res://assets/fx/circle_05.png")
	p.amount = max(30, int(140 * Settings.particle_scale()))
	p.lifetime = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.3, 1.0)
	p.spread = 25.0
	p.gravity = Vector2(20, 40)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 130.0
	p.scale_amount_min = 0.012
	p.scale_amount_max = 0.03
	p.color = Color(0.95, 0.97, 1.0, 0.85)
	p.emitting = false
	_layer.add_child(p)
	return p


func _make_leaves() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = load("res://assets/fx/leaf.png")
	p.amount = max(4, int(14 * Settings.particle_scale()))
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(1.0, 0.35)
	p.spread = 30.0
	p.gravity = Vector2(10, 35)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.6
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.1, 0.9, 1.0])
	gradient.colors = PackedColorArray([Color(0.42, 0.62, 0.30, 0.0), Color(0.42, 0.62, 0.30, 0.9),
		Color(0.80, 0.50, 0.18, 0.9), Color(0.80, 0.50, 0.18, 0.0)])
	p.color_ramp = gradient
	p.emitting = false
	_layer.add_child(p)
	return p


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var data := level.data
	var player := level.player
	var cell := World.cell_of(player.global_position - Vector2(0, 100))
	var column := clampi(cell.x, 0, data.width - 1)
	var outdoors := clampf(1.0 - float(cell.y - data.surface[column]) / 10.0, 0.0, 1.0)
	var biome: int = data.biome_columns[column]

	_advance_weather(delta, biome)
	var shown := intensity * outdoors if Settings.weather else 0.0

	for p in [_rain, _snow, _leaves]:
		p.position = Vector2(screen.x * 0.5, -40)
		p.emission_rect_extents = Vector2(screen.x * 0.65, 20)
	_leaves.position = Vector2(-60, screen.y * 0.45)
	_leaves.emission_rect_extents = Vector2(20, screen.y * 0.45)
	_rain.emitting = shown > 0.15 and sky == Weather.RAIN
	_snow.emitting = shown > 0.15 and sky == Weather.SNOW
	_rain.modulate.a = shown
	_snow.modulate.a = shown
	_leaves.emitting = Settings.particles > 0 and outdoors > 0.5 and biome == WorldData.Biome.MEADOW \
		and sky != Weather.SNOW

	_update_drips(delta, outdoors)
	_update_grade(cell)
	_update_plants(delta)


## How hard the wind blows: a breeze that rises and falls, much stronger
## in a storm.
func wind() -> float:
	var breeze := 0.8 + 0.25 * sin(Time.get_ticks_msec() / 9000.0)
	return breeze + intensity * 1.1 if Settings.weather else breeze


## The sun's direction across the sky (screen space, pointing toward it),
## and how strong it is: it rises on the left and sets on the right; at
## night the moon takes over, faintly.
func sun() -> Array:
	var t: float = level.world.time_of_day
	var day := clampf(sin((t - 0.25) * TAU) * 1.6 + 0.35, 0.0, 1.0)
	var arc := (t - 0.25) * TAU if day > 0.0 else (t - 0.75) * TAU
	var direction := Vector2(-cos(arc), -maxf(absf(sin(arc)), 0.3)).normalized()
	var strength := lerpf(0.25, 1.0, day) * (1.0 - overcast())
	return [direction, strength]


func _update_plants(delta: float) -> void:
	var lighting := sun()
	Visuals.set_environment(lighting[0], lighting[1], wind(), level.player.global_position)
	_update_falling_leaves(delta)


## A few leaves let go of the trees on screen and flutter down. A small
## pool of sprites moved here, not a particle system per tree.
var _falling: Array[Dictionary] = []
var _leaf_timer := 0.0


func _update_falling_leaves(delta: float) -> void:
	_leaf_timer -= delta
	if _leaf_timer <= 0.0 and Settings.particles > 0 and _falling.size() < int(10 * Settings.particle_scale()):
		_leaf_timer = randf_range(0.4, 1.2) / maxf(wind(), 0.5)
		var tree := level.world.random_visible_tree()
		if not tree.is_empty():
			var leaf := Sprite2D.new()
			leaf.texture = load("res://assets/fx/leaf.png")
			leaf.scale = Vector2.ONE * randf_range(0.35, 0.55)
			leaf.modulate = [Color(0.55, 0.72, 0.36), Color(0.78, 0.62, 0.25), Color(0.62, 0.70, 0.30)][randi() % 3]
			leaf.z_index = 12
			leaf.position = tree.position + Vector2(randf_range(-110, 110), -randf_range(260, 520))
			level.fx_layer.add_child(leaf)
			_falling.append({"node": leaf, "life": randf_range(5.0, 8.0), "phase": randf() * TAU})
	var w := wind()
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		var node: Sprite2D = f.node
		f.life -= delta
		f.phase += delta * 2.4
		# Side-to-side flutter, drifting downwind, slowing as it tips.
		node.position += Vector2(cos(f.phase) * 70.0 + 40.0 * w, 60.0 + sin(f.phase * 2.0) * 25.0) * delta
		node.rotation = sin(f.phase) * 0.9
		var cell := World.cell_of(node.position)
		if f.life <= 0.0 or level.data.is_solid(cell.x, cell.y):
			node.modulate.a -= delta * 2.0
			if node.modulate.a <= 0.0:
				node.queue_free()
				_falling.remove_at(i)


func _advance_weather(delta: float, biome: int) -> void:
	_weather_timer -= delta
	if _weather_timer <= 0.0:
		if sky == Weather.CLEAR and randf() < (0.25 if biome == WorldData.Biome.DESERT else 0.6):
			sky = Weather.SNOW if biome == WorldData.Biome.TUNDRA else Weather.RAIN
			_target = randf_range(0.6, 1.0)
			_weather_timer = randf_range(45.0, 100.0)
		else:
			_target = 0.0
			_weather_timer = randf_range(70.0, 160.0)
	intensity = move_toward(intensity, _target, delta / 6.0)
	if intensity <= 0.0 and _target <= 0.0:
		sky = Weather.CLEAR


## Force weather, for captures and tests.
func set_weather(kind: int, amount: float) -> void:
	sky = kind
	_target = amount
	intensity = amount
	_weather_timer = 120.0


## How much the weather dims sunlight, 0..1.
func overcast() -> float:
	return intensity * 0.42 if Settings.weather else 0.0


func _update_drips(delta: float, outdoors: float) -> void:
	var world := level.world
	var data := level.data
	_drip_timer -= delta
	if _drip_timer <= 0.0 and outdoors < 0.2 and Settings.particles > 0:
		_drip_timer = randf_range(0.25, 0.7) / Settings.particle_scale()
		var view := world.visible_cells()
		for attempt in 10:
			var x := randi_range(view.position.x, view.end.x)
			var y := randi_range(view.position.y, view.end.y)
			if data.is_solid(x, y) and not data.is_solid(x, y + 1) and data.get_liquid(x, y + 1) == WorldData.DRY:
				var drop := Sprite2D.new()
				drop.texture = _drip_texture
				drop.scale = Vector2(0.025, 0.045)
				drop.modulate = Color(0.7, 0.85, 1.0, 0.9)
				drop.z_index = 6
				drop.position = Vector2((x + randf_range(0.2, 0.8)) * TILE, (y + 1) * TILE + 4)
				level.fx_layer.add_child(drop)
				_drips.append({"node": drop, "speed": 0.0, "hang": randf_range(0.2, 0.9)})
				break
	for i in range(_drips.size() - 1, -1, -1):
		var drip: Dictionary = _drips[i]
		var node: Sprite2D = drip.node
		if drip.hang > 0.0:
			# A drop gathers on the ceiling before it lets go.
			drip.hang -= delta
			node.scale.y = 0.045 + (0.9 - drip.hang) * 0.02
			continue
		drip.speed += 2400.0 * delta
		node.position.y += drip.speed * delta
		var below := World.cell_of(node.position)
		if data.is_solid(below.x, below.y) or data.get_liquid(below.x, below.y) != WorldData.DRY \
				or drip.speed > 4000.0:
			if drip.speed < 4000.0:
				Effects.burst(level.fx_layer, Vector2(node.position.x, below.y * TILE), "splash")
			node.queue_free()
			_drips.remove_at(i)


func _update_grade(cell: Vector2i) -> void:
	var grade: ShaderMaterial = level.atmosphere.grade_material()
	if grade == null:
		return
	var data := level.data
	var head := World.cell_of(level.player.global_position - Vector2(0, 170))
	var under := 1.0 if data.get_liquid(head.x, head.y) == WorldData.WATER else 0.0
	var heat := 0.0
	if Settings.shader_fx >= 2:
		for dy in range(-3, 5):
			for dx in range(-6, 7):
				if data.get_liquid(cell.x + dx, cell.y + dy) == WorldData.LAVA:
					heat = 1.0
	_underwater = move_toward(_underwater, under, 0.08)
	_heat = move_toward(_heat, heat, 0.03)
	grade.set_shader_parameter("underwater", _underwater)
	grade.set_shader_parameter("heat", _heat)
	grade.set_shader_parameter("rain", intensity if sky == Weather.RAIN else 0.0)
