class_name WorldFX
extends Node3D
## Little bits of life around the island, all cheap enough for a phone:
## - water splashes (a droplet burst plus an expanding ripple ring), pooled so
##   nothing is allocated while playing;
## - seagulls gliding in lazy circles, drawn as one MultiMesh (one draw call)
##   with the wing flap done in the vertex shader.

const POOL := 5
const GULLS := 6

var _bursts: Array[CPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_t: Array[float] = []
var _ring_size: Array[float] = []
var _next := 0

var _gull_mm: MultiMesh
var _gulls: Array = []        # [centre, radius, height, speed, angle, bob phase]
var _t := 0.0
var gull_centre := Vector3(0, 0, 30)

# Fish shadows swimming under the surface in front of the jetty.
const SHADOWS := 9
var _shadow_mm: MultiMesh
var _shadows: Array = []      # [pos (Vector2 xz), heading, speed, depth, scale, flee]
var shadow_area := Rect2(-16, -22, 32, 22)   # x/z region they keep to
var wave_fn: Callable                       # (x, z) -> surface height


func _ready() -> void:
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
		g[4] = float(g[4]) + float(g[3]) * delta
		var a: float = g[4]
		var c: Vector2 = g[0]
		var r: float = g[1]
		var pos := gull_centre + Vector3(c.x + cos(a) * r, float(g[2]) + sin(_t * 0.4 + i) * 1.2, c.y + sin(a) * r)
		# Face along the circle and bank into the turn.
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(float(g[3]))
		var basis := Basis.looking_at(dir, Vector3.UP)
		basis = basis * Basis(Vector3(0, 0, 1), -0.35 * signf(float(g[3])))
		_gull_mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * 1.25), pos))
		# Flap for a few seconds, glide for a few.
		var glide := clampf(sin(_t * 0.35 + float(g[5]) * 9.0) * 2.0, 0.0, 1.0)
		_gull_mm.set_instance_custom_data(i, Color(float(g[5]), glide, 0, 0))


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
