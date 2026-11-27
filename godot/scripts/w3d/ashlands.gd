class_name Ashlands
extends Node3D
## The Ashlands' set dressing: a lava pool in each crater with a column of
## smoke rising from it and embers spiralling up, glowing on the clouds of
## its own smoke; a red light over the great crater.

var game: Node


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	var lava := ShaderMaterial.new()
	lava.shader = load("res://scripts/shaders/lava.gdshader")
	for i in gen.volcanoes.size():
		var v: Array = gen.volcanoes[i]
		var c: Vector2 = v[0]
		var r: float = v[1]
		var floor_y := gen.height(c.x, c.y)
		var pool := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = r * 0.2
		disc.bottom_radius = r * 0.18
		disc.height = 1.0
		disc.radial_segments = 32
		pool.mesh = disc
		pool.material_override = lava
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pool)
		pool.global_position = Vector3(c.x, floor_y + r * 0.035, c.y)
		_smoke(pool.global_position, r, i == 0)
		if i == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.45, 0.15)
			l.light_energy = 6.0
			l.omni_range = r * 0.9
			l.shadow_enabled = false
			add_child(l)
			l.global_position = pool.global_position + Vector3(0, 12, 0)


func _smoke(at: Vector3, r: float, great: bool) -> void:
	var smoke := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	smoke.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.vertex_color_use_as_albedo = true
	# Thin out as the camera comes near (never a white wall over the view).
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 25.0
	m.distance_fade_max_distance = 110.0
	smoke.material_override = m
	smoke.amount = 60 if great else 26
	smoke.lifetime = 14.0
	smoke.preprocess = 14.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = r * 0.12
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 5.0
	smoke.initial_velocity_max = 8.0
	smoke.gravity = Vector3(1.2, 0.5, 0.4)
	smoke.damping_min = 0.2
	smoke.damping_max = 0.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, r * 0.12))
	grow.add_point(Vector2(1, r * 0.38))
	smoke.scale_amount_curve = grow
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 1.0
	var col := Gradient.new()
	col.offsets = PackedFloat32Array([0.0, 0.05, 0.3, 1.0])
	col.colors = PackedColorArray([Color(0.85, 0.4, 0.18, 0.0), Color(0.45, 0.3, 0.26, 0.55), Color(0.26, 0.24, 0.26, 0.5), Color(0.48, 0.47, 0.5, 0.0)])
	smoke.color_ramp = col
	smoke.visibility_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 400, 400))
	add_child(smoke)
	smoke.global_position = at
	var embers := CPUParticles3D.new()
	var eq := QuadMesh.new()
	eq.size = Vector2(0.6, 0.6)
	embers.mesh = eq
	var em := m.duplicate() as StandardMaterial3D
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	embers.material_override = em
	embers.amount = 50 if great else 20
	embers.lifetime = 5.0
	embers.preprocess = 5.0
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = r * 0.15
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 6.0
	embers.initial_velocity_max = 14.0
	embers.gravity = Vector3(0, -1.5, 0)
	var ec := Gradient.new()
	ec.colors = PackedColorArray([Color(1.0, 0.8, 0.3, 1.0), Color(1.0, 0.3, 0.05, 0.0)])
	embers.color_ramp = ec
	embers.visibility_aabb = AABB(Vector3(-100, -10, -100), Vector3(200, 200, 200))
	add_child(embers)
	embers.global_position = at
