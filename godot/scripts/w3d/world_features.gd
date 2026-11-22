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
var found_ids: Array = []   ## creation index of every Starshard collected
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


var _column_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _sparkle_mat: StandardMaterial3D


func _updraft(base: Vector3, radius: float, height: float) -> void:
	updrafts.append([base, radius, height])
	if _column_mat == null:
		_column_mat = ShaderMaterial.new()
		_column_mat.shader = load("res://scripts/shaders/updraft.gdshader")
		_ring_mat = ShaderMaterial.new()
		_ring_mat.shader = load("res://scripts/shaders/wind_ring.gdshader")
		_sparkle_mat = StandardMaterial3D.new()
		_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sparkle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_sparkle_mat.albedo_texture = Play3D._spark_texture()
		_sparkle_mat.albedo_color = Color(0.8, 0.97, 1.0, 0.9)
		_sparkle_mat.disable_fog = true
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = base
	# The column: two nested open cylinders turning at different speeds.
	for k in 2:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius * (1.15 if k == 0 else 0.7)
		cyl.bottom_radius = radius * (0.8 if k == 0 else 0.5)
		cyl.height = height
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 24
		cyl.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = _column_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = height * 0.5
		mi.rotation.y = k * 1.3
		mi.scale.x = -1.0 if k == 1 else 1.0  # mirror: the inner ribbons twist the other way
		mi.visibility_range_end = 420.0
		holder.add_child(mi)
	# The ring on the ground.
	var disc := PlaneMesh.new()
	disc.size = Vector2(radius * 2.6, radius * 2.6)
	var ring := MeshInstance3D.new()
	ring.mesh = disc
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.15
	ring.visibility_range_end = 160.0
	holder.add_child(ring)
	# Small sparkles spiralling up.
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	p.mesh = quad
	p.material_override = _sparkle_mat
	p.amount = 22
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.9
	p.emission_ring_inner_radius = radius * 0.3
	p.emission_ring_height = 0.5
	p.direction = Vector3.UP
	p.spread = 4
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = height / 4.5
	p.initial_velocity_max = height / 3.5
	p.orbit_velocity_min = 0.12
	p.orbit_velocity_max = 0.22
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.visibility_range_end = 200.0
	holder.add_child(p)


func _shard(at: Vector3) -> void:
	var holder := Node3D.new()
	var top := MeshInstance3D.new()
	top.mesh = _shard_mesh
	top.material_override = _shard_mat
	top.visibility_range_end = 260.0
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bottom := MeshInstance3D.new()
	bottom.mesh = _shard_mesh
	bottom.material_override = _shard_mat
	bottom.visibility_range_end = 260.0
	bottom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bottom.rotation.x = PI
	bottom.position.y = -0.7
	top.add_child(bottom)
	holder.add_child(top)
	add_child(holder)
	holder.global_position = at
	holder.set_meta("id", shards.size() + found_ids.size())
	shards.append(holder)


## Starshards found in a saved journey are gone again.
func restore_found(ids: Array) -> void:
	for i in range(shards.size() - 1, -1, -1):
		var s: Node3D = shards[i]
		if ids.has(s.get_meta("id", -1)):
			shards.remove_at(i)
			s.queue_free()
	found_ids = ids.duplicate()
	found = found_ids.size()


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
			found_ids.append(s.get_meta("id", -1))
			p.max_stamina += SHARD_STAMINA
			p.stamina = p.max_stamina
			game.play.toast.emit("Starshard  %d / %d   ·  max stamina +%d" % [found, total, int(SHARD_STAMINA)])
			game.play.debris(s.global_position, Color(0.6, 0.9, 1.0), 20)
			Sfx.play("pickup")
			s.queue_free()
