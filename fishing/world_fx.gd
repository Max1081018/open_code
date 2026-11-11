class_name WorldFX
extends Node3D
## Little bits of life around the island, all cheap enough for a phone:
## - water splashes (a droplet burst plus an expanding ripple ring), pooled so
##   nothing is allocated while playing;
## - seagulls gliding in lazy circles, drawn as one MultiMesh (one draw call)
##   with the wing flap done in the vertex shader.

const POOL := 5
const GULLS := 6
## A gull spotted a catch lying about and is coming down for it.
signal steal_started(pos: Vector3)
## It has it: the game should stop treating this body as its own.
signal stole(body: Node3D)

var _bursts: Array[CPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_t: Array[float] = []
var _ring_size: Array[float] = []
var _next := 0
var _hits: Array[CPUParticles3D] = []
var _hit_next := 0
var _dusts: Array[CPUParticles3D] = []
var _dust_next := 0

var _gull_mm: MultiMesh
var _gulls: Array = []        # [centre, radius, height, speed, angle, bob phase]
# Thieving: one gull at a time can break off, dive on a catch and carry it away.
var _thief := -1              # which gull, -1 for none
var _thief_state := ""        # "dive", "rise"
var _thief_pos := Vector3.ZERO
var _thief_target: Node3D
var _thief_t := 0.0
var _t := 0.0
var gull_centre := Vector3(0, 0, 30)

# Fish shadows swimming under the surface in front of the jetty.
const SHADOWS := 9
var _shadow_mm: MultiMesh
var _shadows: Array = []      # [pos (Vector2 xz), heading, speed, depth, scale, flee]
var shadow_area := Rect2(-16, -22, 32, 22)   # x/z region they keep to
var wave_fn: Callable                       # (x, z) -> surface height


func _ready() -> void:
	_build_hits()
	_build_dust()
	_build_splashes()
	_build_gulls()
	_build_shadows()


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
	# Anything swimming close by darts away.
	for f in _shadows:
		var fp: Vector2 = f[0]
		if fp.distance_to(Vector2(pos.x, pos.z)) < 3.5 * size + 1.0:
			f[5] = 1.0
			f[1] = atan2(fp.y - pos.z, fp.x - pos.x)


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


# --- Seagulls -------------------------------------------------------------------------

func _gull_mesh() -> ArrayMesh:
	# Body, head, tail and two wings. UV.x carries "how far out along a wing"
	# (0 on the body) so the shader can flap it.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(0.97, 0.97, 0.95)
	var grey := Color(0.62, 0.66, 0.72)
	var beak := Color(1.0, 0.72, 0.2)
	var tris := [
		# body (a stretched diamond)
		[Vector3(0, 0, -0.32), Vector3(0.08, 0, 0), Vector3(0, 0.07, 0), white],
		[Vector3(0, 0, -0.32), Vector3(0, 0.07, 0), Vector3(-0.08, 0, 0), white],
		[Vector3(0, 0, -0.32), Vector3(-0.08, 0, 0), Vector3(0, -0.06, 0), white],
		[Vector3(0, 0, -0.32), Vector3(0, -0.06, 0), Vector3(0.08, 0, 0), white],
		[Vector3(0, 0, 0.30), Vector3(0, 0.07, 0), Vector3(0.08, 0, 0), white],
		[Vector3(0, 0, 0.30), Vector3(-0.08, 0, 0), Vector3(0, 0.07, 0), white],
		[Vector3(0, 0, 0.30), Vector3(0, -0.06, 0), Vector3(-0.08, 0, 0), white],
		[Vector3(0, 0, 0.30), Vector3(0.08, 0, 0), Vector3(0, -0.06, 0), white],
		# beak
		[Vector3(0, 0, -0.42), Vector3(0.02, 0.01, -0.31), Vector3(-0.02, 0.01, -0.31), beak],
		# tail
		[Vector3(0, 0.01, 0.26), Vector3(0.09, 0.01, 0.42), Vector3(-0.09, 0.01, 0.42), white],
	]
	for t in tris:
		for k in 3:
			st.set_color(t[3])
			st.set_uv(Vector2(0, 0))
			st.add_vertex(t[k])
	# wings: inner panel + grey-tipped outer panel, both sides
	for side in [-1.0, 1.0]:
		var a := Vector3(0.06 * side, 0.02, -0.10)
		var b := Vector3(0.06 * side, 0.02, 0.10)
		var c := Vector3(0.42 * side, 0.03, -0.04)
		var d := Vector3(0.40 * side, 0.03, 0.12)
		var e := Vector3(0.78 * side, 0.0, 0.12)
		var quads := [[a, c, b, d, white], [c, e, d, e, grey]]
		for q in quads:
			var pts := [q[0], q[1], q[2], q[2], q[1], q[3]]
			for v in pts:
				st.set_color(q[4])
				st.set_uv(Vector2(absf(v.x) / 0.78, 0))
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _build_gulls() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
varying float phase;
void vertex() {
	phase = INSTANCE_CUSTOM.r;
	float out_w = UV.x;
	float glide = INSTANCE_CUSTOM.g;          // 0 = flapping, 1 = gliding
	float flap = sin(TIME * 7.0 + phase * 6.28) * (1.0 - glide) + 0.18 * glide;
	VERTEX.y += flap * out_w * out_w * 0.42 + out_w * 0.06;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	EMISSION = COLOR.rgb * 0.18;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_gull_mm = MultiMesh.new()
	_gull_mm.transform_format = MultiMesh.TRANSFORM_3D
	_gull_mm.use_colors = true          # COLOR reads black without instance colours
	_gull_mm.use_custom_data = true
	_gull_mm.mesh = _gull_mesh()
	_gull_mm.instance_count = GULLS
	for i in GULLS:
		_gull_mm.set_instance_color(i, Color.WHITE)
		_gulls.append([
			Vector2(randf_range(-10, 10), randf_range(-10, 10)),   # circle centre offset
			randf_range(9.0, 22.0),                                 # radius
			randf_range(11.0, 19.0),                                # height
			randf_range(0.18, 0.32) * (1.0 if randf() < 0.5 else -1.0),  # angular speed
			randf() * TAU,                                          # angle
			randf(),                                                # flap phase
		])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _gull_mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-80, -10, -80), Vector3(160, 60, 160))
	add_child(mmi)


func _update_gulls(delta: float) -> void:
	for i in GULLS:
		var g: Array = _gulls[i]
		var pos := Vector3.ZERO
		var dir := Vector3.FORWARD
		var flapping := true
		if i == _thief:
			pos = _update_thief(delta)
			dir = _thief_dir
		else:
			g[4] = float(g[4]) + float(g[3]) * delta
			var a: float = g[4]
			var c: Vector2 = g[0]
			var r: float = g[1]
			pos = gull_centre + Vector3(c.x + cos(a) * r, float(g[2]) + sin(_t * 0.4 + i) * 1.2, c.y + sin(a) * r)
			dir = Vector3(-sin(a), 0, cos(a)) * signf(float(g[3]))
			flapping = false
		var basis := Basis.looking_at(dir, Vector3.UP)
		if i != _thief:
			basis = basis * Basis(Vector3(0, 0, 1), -0.35 * signf(float(g[3])))
		_gull_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * 1.25), pos))
		# Flap for a few seconds, glide for a few — but a thief always flaps.
		var glide := 0.0 if flapping else clampf(sin(_t * 0.35 + float(g[5]) * 9.0) * 2.0, 0.0, 1.0)
		_gull_mm.set_instance_custom_data(i, Color(float(g[5]), glide, 0, 0))


## True if a gull is free to go after something.
func can_steal() -> bool:
	return _thief == -1


## Sends a gull down after a catch lying on the ground. It takes a couple of
## seconds to arrive, so you can beat it to the fish by picking it up.
func try_steal(body: Node3D) -> bool:
	if _thief != -1 or body == null or not is_instance_valid(body):
		return false
	_thief = randi() % GULLS
	_thief_state = "dive"
	_thief_target = body
	_thief_t = 0.0
	var g: Array = _gulls[_thief]
	var a: float = g[4]
	var c: Vector2 = g[0]
	var r: float = g[1]
	_thief_pos = gull_centre + Vector3(c.x + cos(a) * r, float(g[2]), c.y + sin(a) * r)
	steal_started.emit(body.global_position)
	return true


## Where the diving gull is right now, or ZERO if none is on its way down.
## The game uses this to offer you the chance to drive it off.
func thief_dive_pos() -> Vector3:
	return _thief_pos if _thief_state == "dive" else Vector3.ZERO


## Scare the diving gull off empty-clawed. Returns where it was, so the game
## can put a puff of feathers there.
func scare_thief() -> Vector3:
	if _thief_state != "dive":
		return Vector3.ZERO
	var at := _thief_pos
	_thief_target = null
	_thief_state = "rise"
	_thief_t = 0.0
	return at


var _thief_dir := Vector3.FORWARD

func _update_thief(delta: float) -> Vector3:
	_thief_t += delta
	var want := _thief_pos
	if _thief_state == "dive":
		if _thief_target == null or not is_instance_valid(_thief_target):
			_thief_state = "rise"
		else:
			want = _thief_target.global_position + Vector3(0, 0.35, 0)
			if _thief_pos.distance_to(want) < 0.45:
				# got it: the catch is the gull's now
				stole.emit(_thief_target)
				_thief_state = "rise"
				_thief_t = 0.0
	if _thief_state == "rise":
		want = _thief_pos + (_thief_pos - gull_centre).normalized() * 30.0 + Vector3(0, 22.0, 0)
		if _thief_t > 4.5:
			# A gull that was driven off has no catch to make away with.
			if _thief_target and is_instance_valid(_thief_target):
				_thief_target.queue_free()
			_thief_target = null
			_thief = -1
			_thief_state = ""
	var speed := 11.0 if _thief_state == "dive" else 9.0
	var step := (want - _thief_pos)
	if step.length() > 0.001:
		_thief_dir = step.normalized()
		_thief_pos += _thief_dir * minf(speed * delta, step.length())
	# carry the catch slung under the bird
	if _thief_state == "rise" and _thief_target and is_instance_valid(_thief_target):
		(_thief_target as Node3D).global_position = _thief_pos - Vector3(0, 0.3, 0)
	return _thief_pos


## Position of the gull nearest to `p` (for the occasional squawk).
func nearest_gull(p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for i in GULLS:
		var q := _gull_mm.get_instance_transform(i).origin
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = q
	return best


# --- Fish shadows ------------------------------------------------------------------

func _build_shadows() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A flat fish silhouette in the XZ plane, nose toward +X.
	var body: Array = []
	for i in 14:
		var a := TAU * float(i) / 14.0
		body.append(Vector3(cos(a) * 0.30, 0, sin(a) * 0.095))
	for i in 14:
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(body[(i + 1) % 14])
		st.add_vertex(body[i])
	for v in [Vector3(-0.24, 0, 0), Vector3(-0.46, 0, 0.12), Vector3(-0.46, 0, -0.12)]:
		st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.01, 0.07, 0.12, 0.6)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 1          # after the water, so it reads through it
	_shadow_mm = MultiMesh.new()
	_shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_shadow_mm.mesh = st.commit()
	_shadow_mm.instance_count = SHADOWS
	for i in SHADOWS:
		_shadows.append([
			Vector2(randf_range(shadow_area.position.x, shadow_area.end.x),
				randf_range(shadow_area.position.y, shadow_area.end.y)),
			randf() * TAU, randf_range(0.5, 1.1), randf_range(0.25, 0.55),
			randf_range(1.2, 2.3), 0.0])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _shadow_mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(shadow_area.position.x - 2, -3, shadow_area.position.y - 2),
		Vector3(shadow_area.size.x + 4, 4, shadow_area.size.y + 4))
	add_child(mmi)


func _update_shadows(delta: float) -> void:
	for i in SHADOWS:
		var f: Array = _shadows[i]
		var p: Vector2 = f[0]
		var h: float = f[1]
		var flee: float = f[5]
		# Lazy wandering, turning back when they reach the edge of their patch.
		h += sin(_t * 0.6 + i * 1.7) * 0.6 * delta
		if not shadow_area.has_point(p):
			var c := shadow_area.get_center()
			h = lerp_angle(h, atan2(c.y - p.y, c.x - p.x), clampf(delta * 2.0, 0, 1))
		var sp: float = float(f[2]) * (1.0 + flee * 3.5)
		p += Vector2(cos(h), sin(h)) * sp * delta
		flee = maxf(flee - delta * 0.8, 0.0)
		f[0] = p
		f[1] = h
		f[5] = flee
		var y := -float(f[3])
		if wave_fn.is_valid():
			y += float(wave_fn.call(p.x, p.y)) * 0.7
		var wiggle := sin(_t * (5.0 + flee * 8.0) + i) * 0.18
		var b := Basis(Vector3.UP, -h + wiggle).scaled(Vector3.ONE * float(f[4]))
		_shadow_mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, y, p.y)))


func _process(delta: float) -> void:
	_t += delta
	_update_rings(delta)
	_update_gulls(delta)
	_update_shadows(delta)
