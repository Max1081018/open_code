class_name WorldFX
extends Node3D
## Small effects, pooled so that nothing is allocated while you are playing:
## impact bursts where a shot lands, puffs of dust and dirt, and expanding
## ground rings. Each kind keeps a handful of emitters and reuses them in turn,
## which matters on a phone where allocating a particle system mid-fight is a
## visible stutter.

const POOL := 5

var _bursts: Array[CPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_t: Array[float] = []
var _ring_size: Array[float] = []
var _next := 0
var _hits: Array[CPUParticles3D] = []
var _hit_next := 0
var _dusts: Array[CPUParticles3D] = []
var _dust_next := 0

var _t := 0.0



func _ready() -> void:
	_build_hits()
	_build_dust()
	_build_splashes()


# --- Splashes ----------------------------------------------------------------------

func _build_splashes() -> void:
	var drop := SphereMesh.new()
	drop.radius = 0.045
	drop.height = 0.09
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.92, 0.97, 1.0)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 3
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(1, 1, 1, 0.6)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 18
		p.lifetime = 0.7
		p.explosiveness = 0.95
		p.mesh = drop
		p.direction = Vector3.UP
		p.spread = 32.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.0
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_bursts.append(p)
		var r := MeshInstance3D.new()
		r.mesh = ring
		r.material_override = rm.duplicate()
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		add_child(r)
		_rings.append(r)
		_ring_t.append(0.0)
		_ring_size.append(1.0)


## A splash at `pos` (on the water surface). `size` ~1 for a bobber, 2-3 for
## a fish going back in.
func splash(pos: Vector3, size := 1.0) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	var p := _bursts[i]
	p.global_position = pos
	p.amount = int(clampf(10.0 * size, 8, 32))
	p.initial_velocity_min = 1.6 * sqrt(size)
	p.initial_velocity_max = 3.4 * sqrt(size)
	p.restart()
	p.emitting = true
	var r := _rings[i]
	r.global_position = pos + Vector3(0, 0.03, 0)
	r.visible = true
	_ring_t[i] = 0.0
	_ring_size[i] = size


func _update_rings(delta: float) -> void:
	for i in POOL:
		var r := _rings[i]
		if not r.visible:
			continue
		_ring_t[i] += delta / 1.1
		var k: float = _ring_t[i]
		if k >= 1.0:
			r.visible = false
			continue
		var sc := (0.25 + k * 1.4) * _ring_size[i]
		r.scale = Vector3(sc, 0.4, sc)
		var m := r.material_override as StandardMaterial3D
		m.albedo_color.a = 0.6 * (1.0 - k)


# --- Hit bursts ---------------------------------------------------------------------

func _build_hits() -> void:
	var star := PrismMesh.new()
	star.size = Vector3(0.07, 0.07, 0.02)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	star.material = sm
	for i in 3:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.5
		p.explosiveness = 1.0
		p.mesh = star
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 1.6
		p.initial_velocity_max = 3.2
		p.gravity = Vector3(0, -4.0, 0)
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.4
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_hits.append(p)


## Soft puffs of sand or dust kicked up by boots and flopping fish.
func _build_dust() -> void:
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	puff.radial_segments = 6
	puff.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.93, 0.86, 0.70, 0.5)
	m.vertex_color_use_as_albedo = false
	puff.material = m
	for i in 2:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 10
		p.lifetime = 0.7
		p.explosiveness = 0.9
		p.mesh = puff
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.4
		p.gravity = Vector3(0, -1.2, 0)
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.5
		p.scale_amount_curve = _fade_curve()
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_dusts.append(p)


## Particles start small, swell, then shrink away.
func _fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


## A puff of sand where something lands.
func dust(pos: Vector3, size := 1.0) -> void:
	var p := _dusts[_dust_next]
	_dust_next = (_dust_next + 1) % _dusts.size()
	p.global_position = pos
	p.amount = int(clampf(8.0 * size, 5, 20))
	p.initial_velocity_max = 1.2 * size
	p.restart()
	p.emitting = true


## A burst of little stars where a blow lands; gold and bigger for a knockout.
func hit_burst(pos: Vector3, ko := false) -> void:
	var p := _hits[_hit_next]
	_hit_next = (_hit_next + 1) % _hits.size()
	p.global_position = pos
	p.color = Color(1.0, 0.85, 0.25) if ko else Color(1, 1, 1)
	p.amount = 22 if ko else 12
	p.initial_velocity_max = 4.2 if ko else 3.0
	p.restart()
	p.emitting = true


func _process(delta: float) -> void:
	_t += delta
	_update_rings(delta)
