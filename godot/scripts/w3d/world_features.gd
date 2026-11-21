class_name WorldFeatures
extends Node3D
## Things to find and use in the open world:
##   updrafts — columns of rising wind (streaks of light swirling upward) that
##     lift a glider; one stands below every floating isle so its top can be
##     reached, more are scattered over the land;
##   Starshards — floating crystals hidden on peaks, isles and far corners;
##     each one found raises maximum stamina.

const SHARD_STAMINA := 6.0

var game: Node
var updrafts: Array = []    ## [Vector3 base, radius, height]
var shards: Array = []      ## Node3D, removed when collected
var found := 0
var total := 0
var _shard_mesh: Mesh
var _shard_mat: StandardMaterial3D


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	# Updrafts below each isle's rim, reaching above its crown.
	for top in game.islands.tops:
		var centre: Vector3 = top[0]
		var r: float = top[1]
		var at := centre + Vector3(r + 6.0, 0, 0).rotated(Vector3.UP, float(updrafts.size()) * 1.7)
		at.y = maxf(gen.height(at.x, at.z), TerrainGen.WATER)
		_updraft(at, 4.5, centre.y - at.y + 25.0)
	# A few more over open land and cliffs near home.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in 10:
		var a := rng.randf() * TAU
		var d := rng.randf_range(90.0, 600.0)
		var at := Vector3(cos(a) * d, 0, sin(a) * d)
		at.y = gen.height(at.x, at.z)
		if at.y > TerrainGen.WATER + 1.0:
			_updraft(at, 4.0, 45.0)
	# Starshards.
	var prism := PrismMesh.new()
	prism.size = Vector3(0.45, 0.7, 0.45)
	_shard_mesh = prism
	_shard_mat = StandardMaterial3D.new()
	_shard_mat.albedo_color = Color(0.75, 0.9, 1.0, 0.9)
	_shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shard_mat.emission_enabled = true
	_shard_mat.emission = Color(0.45, 0.85, 1.0)
	_shard_mat.emission_energy_multiplier = 2.2
	_shard_mat.rim_enabled = true
	for top in game.islands.tops:
		_shard((top[0] as Vector3) + Vector3(0, 3.0, 0))
	for k in 36:
		var a := rng.randf() * TAU
		var d := rng.randf_range(60.0, 900.0)
		var x := cos(a) * d
		var z := sin(a) * d
		var h := gen.height(x, z)
		if h < TerrainGen.WATER + 0.5:
			continue
		_shard(Vector3(x, h + rng.randf_range(1.5, 6.0), z))
	total = shards.size()


func _updraft(base: Vector3, radius: float, height: float) -> void:
	updrafts.append([base, radius, height])
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 1.4)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = Color(0.75, 0.95, 1.0, 0.55)
	p.material_override = m
	p.amount = 40
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.5
	p.emission_ring_height = 0.5
	p.direction = Vector3.UP
	p.spread = 5
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = height / 3.2
	p.initial_velocity_max = height / 2.6
	p.orbit_velocity_min = 0.15
	p.orbit_velocity_max = 0.3
	p.visibility_range_end = 260.0
	add_child(p)
	p.global_position = base


func _shard(at: Vector3) -> void:
	var holder := Node3D.new()
	var top := MeshInstance3D.new()
	top.mesh = _shard_mesh
	top.material_override = _shard_mat
	var bottom := MeshInstance3D.new()
	bottom.mesh = _shard_mesh
	bottom.material_override = _shard_mat
	bottom.rotation.x = PI
	bottom.position.y = -0.7
	top.add_child(bottom)
	holder.add_child(top)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.85, 1.0)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	holder.add_child(light)
	add_child(holder)
	holder.global_position = at
	shards.append(holder)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p: Player3D = game.player
	var t := Time.get_ticks_msec() / 1000.0
	# Updrafts lift whoever glides (or falls) inside them.
	var lift := 0.0
	for u in updrafts:
		var base: Vector3 = u[0]
		var flat := Vector2(p.global_position.x - base.x, p.global_position.z - base.z).length()
		if flat < u[1] * 1.4 and p.global_position.y < base.y + u[2]:
			lift = 9.0 if p.gliding else 3.0
	p.updraft = lift
	for i in range(shards.size() - 1, -1, -1):
		var s: Node3D = shards[i]
		s.get_child(0).rotation.y = t * 1.6
		s.get_child(0).position.y = sin(t * 2.0 + i) * 0.15
		if s.global_position.distance_to(p.global_position + Vector3(0, 0.9, 0)) < 1.3:
			shards.remove_at(i)
			found += 1
			p.max_stamina += SHARD_STAMINA
			p.stamina = p.max_stamina
			game.play.toast.emit("Starshard  %d / %d   ·  max stamina +%d" % [found, total, int(SHARD_STAMINA)])
			game.play.debris(s.global_position, Color(0.6, 0.9, 1.0), 20)
			Sfx.play("pickup")
			s.queue_free()
