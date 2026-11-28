class_name Arcana
extends RefCounted
## The heroine's violet arcana: the pieces her magic is drawn with.
##   circle()  a rune circle opening on the ground and fading
##   pillar()  a column of light rising through it
##   flash()   a brief coloured light
##   sparks()  a burst of glowing motes
##   Orb       a homing arcane comet that bursts on contact
##   lance()   a star lance falling from the sky onto a point
## Everything is additive and unshaded, so it reads against any ground and
## glows under the bloom; lights are short-lived and shadowless (phones).

const VIOLET := Color(0.72, 0.45, 1.0)
const LILAC := Color(0.9, 0.72, 1.0)

static var _circle_shader: Shader
static var _pillar_shader: Shader
static var _glow_tex: Texture2D


## A soft round glow (bright centre, long falloff) for camera-facing halos.
static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.12, Color(1, 1, 1, 0.62))
		g.add_point(0.4, Color(1, 1, 1, 0.14))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


## A rune circle of `radius` metres at `at` (ground point), drawn in over
## 0.3 s, held for `life` seconds, then faded.
static func circle(host: Node, at: Vector3, radius: float, tint := VIOLET, life := 0.8, spin := 0.35) -> MeshInstance3D:
	if _circle_shader == null:
		_circle_shader = load("res://scripts/shaders/magic_circle.gdshader")
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = _circle_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("grow", 0.0)
	mat.set_shader_parameter("spin", spin)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = at + Vector3(0, 0.08, 0)
	var t := mi.create_tween()
	t.tween_method(func(v: float): mat.set_shader_parameter("grow", v), 0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_interval(life)
	t.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.45)
	t.tween_callback(mi.queue_free)
	return mi


## A column of light `height` tall rising from `at`.
static func pillar(host: Node, at: Vector3, radius: float, height: float, tint := VIOLET, life := 0.9) -> void:
	if _pillar_shader == null:
		_pillar_shader = load("res://scripts/shaders/arcane_pillar.gdshader")
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.7
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 32
	mi.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = _pillar_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("height", height)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	mi.global_position = at + Vector3(0, height * 0.5, 0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var t := mi.create_tween()
	t.tween_property(mi, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_interval(life)
	t.tween_method(func(v: float): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
	t.tween_callback(mi.queue_free)


## A short burst of coloured light.
static func flash(host: Node, at: Vector3, tint := VIOLET, energy := 4.0, reach := 8.0, life := 0.4) -> void:
	var l := OmniLight3D.new()
	l.light_color = tint
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	host.add_child(l)
	l.global_position = at
	var t := l.create_tween()
	t.tween_property(l, "light_energy", 0.0, life).set_ease(Tween.EASE_IN)
	t.tween_callback(l.queue_free)


## A burst of glowing motes flung out from `at`.
static func sparks(host: Node, at: Vector3, tint := VIOLET, amount := 40, speed := 6.0, size := 0.12, gravity := -2.0) -> void:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(tint, 0.9), Color(tint, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	p.color_ramp = ramp
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.8
	p.damping_max = speed * 1.4
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	host.get_tree().create_timer(1.4).timeout.connect(p.queue_free)


static func _glow_material(tint: Color, energy: float) -> StandardMaterial3D:
	# Additive light (no depth written, so the depth AO never greys it).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = tint * clampf(energy * 0.45, 0.6, 1.4)
	return m


## A star lance: a long crystal shard that drops from the sky onto `at`,
## then calls `landed` (the strike) and shatters into light.
static func lance(host: Node, at: Vector3, delay: float, landed: Callable, tint := VIOLET) -> void:
	var shard := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.17
	prism.height = 3.8
	prism.radial_segments = 6
	prism.rings = 1
	shard.mesh = prism
	# A crystal of light: a glowing rim (energy shader) round a bright core.
	var rim := ShaderMaterial.new()
	rim.shader = load("res://scripts/shaders/magic_energy.gdshader")
	rim.set_shader_parameter("energy", 1.8)
	rim.set_shader_parameter("fill", 0.55)
	rim.set_shader_parameter("edge", tint)
	rim.set_shader_parameter("core", tint.lerp(Color.WHITE, 0.3))
	shard.material_override = rim
	var core := MeshInstance3D.new()
	var cp := CylinderMesh.new()
	cp.top_radius = 0.0
	cp.bottom_radius = 0.06
	cp.height = 3.3
	cp.radial_segments = 4
	cp.rings = 1
	core.mesh = cp
	core.material_override = _glow_material(tint.lerp(Color.WHITE, 0.5), 2.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shard.add_child(core)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(shard)
	# Point first, tilted a little, from high above and to the side.
	# Straight down onto its mark (a slanting fall could cross the lens).
	shard.global_position = at + Vector3(randf_range(-0.6, 0.6), 22.0, randf_range(-0.6, 0.6))
	shard.look_at(at, Vector3.FORWARD if absf((at - shard.global_position).normalized().y) > 0.99 else Vector3.UP)
	shard.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	shard.visible = false
	var trail := CPUParticles3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.4, 0.4)
	trail.mesh = tq
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_texture = Play3D._spark_texture()
	tm.albedo_color = tint
	trail.material_override = tm
	trail.amount = 40
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.emitting = false
	shard.add_child(trail)
	var t := shard.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		shard.visible = true
		trail.emitting = true
		ribbon(shard, tint, 0.07, 0.07))
	t.tween_property(shard, "global_position", at + Vector3(0, 0.9, 0), 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func():
		landed.call(at)
		sparks(host, at + Vector3(0, 0.4, 0), tint, 22, 7.0, 0.12)
		flash(host, at + Vector3(0, 1.0, 0), tint, 1.5, 5.0, 0.25)
		# Each lance leaves its own small ring where it struck.
		circle(host, at, 1.3, tint, 0.15, 3.0)
		trail.emitting = false)
	# It shatters into that light: the crystal stays where it struck while
	# its glow drains away and its core shrinks (no squashing: a flattened
	# cone read as a white panel).
	t.tween_method(func(v: float): rim.set_shader_parameter("energy", v), 1.8, 0.0, 0.3)
	t.parallel().tween_property(core, "scale", Vector3(0.2, 1.0, 0.2), 0.3)
	t.tween_callback(shard.queue_free)


## A homing arcane comet. Flies from where it is spawned along `heading`,
## turning toward `target` (an enemy, if any); bursts on contact, on
## striking the ground or after `life` seconds, calling `burst(at)`.
class Orb:
	extends Node3D
	var heading := Vector3.FORWARD
	var speed := 17.0
	## Seconds it gathers before it flies (it grows in place).
	var charge := 0.0
	var target: Node3D
	## Bursts on contact with this node without steering toward it (a foe's bolt).
	var hit_target: Node3D
	var life := 1.8
	var burst: Callable
	var ground: Callable   ## (x, z) -> ground height
	var tint := Arcana.VIOLET
	## 1 for her comet; a foe's bolt is smaller (0.7).
	var size := 1.0
	var _done := false

	func _ready() -> void:
		# Drawn as light, not geometry: a white-hot core and a wide glow of
		# its colour, both camera-facing sprites. (A sphere read as a bubble
		# up close, and an opaque one was shaded grey by the depth AO.)
		add_child(_sprite(1.5 * size, Color(tint, 0.9)))
		add_child(_sprite(0.62 * size, Color(tint.lerp(Color.WHITE, 0.75), 1.0)))
		add_child(_sprite(0.3 * size, Color(1, 1, 1, 1)))
		var light := OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 1.6
		light.omni_range = 4.0 * size
		light.shadow_enabled = false
		add_child(light)
		# The streak is a ribbon; a few motes sparkle off it.
		Arcana.ribbon(self, tint, 0.3 * size, 0.2)
		var trail := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.22) * size
		trail.mesh = q
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.albedo_texture = Arcana.glow_texture()
		tm.vertex_color_use_as_albedo = true
		tm.disable_fog = true
		trail.material_override = tm
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(tint.lerp(Color.WHITE, 0.5), 0.85), Color(tint, 0.5), Color(tint, 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		trail.color_ramp = ramp
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 1.0))
		shrink.add_point(Vector2(1.0, 0.15))
		trail.scale_amount_curve = shrink
		trail.amount = 36
		trail.lifetime = 0.5
		trail.local_coords = false
		trail.gravity = Vector3.ZERO
		trail.direction = Vector3.UP
		trail.spread = 180
		trail.initial_velocity_min = 0.3
		trail.initial_velocity_max = 1.1
		trail.scale_amount_min = 0.8
		trail.scale_amount_max = 1.1
		add_child(trail)

	func _sprite(width: float, colour: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(width, width)
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = Arcana.glow_texture()
		m.albedo_color = colour
		m.disable_fog = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	func _physics_process(delta: float) -> void:
		if _done:
			return
		if charge > 0.0:
			charge -= delta
			scale = Vector3.ONE * clampf(1.0 - charge * 4.0, 0.15, 1.0)
			return
		scale = Vector3.ONE
		life -= delta
		if target != null and is_instance_valid(target):
			var want := (target.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
			heading = heading.slerp(want, clampf(delta * 6.0, 0.0, 1.0)).normalized()
			if global_position.distance_to(target.global_position + Vector3(0, 1.0, 0)) < 0.9:
				_pop()
				return
		if hit_target != null and is_instance_valid(hit_target) \
				and global_position.distance_to(hit_target.global_position + Vector3(0, 1.0, 0)) < 0.8:
			_pop()
			return
		global_position += heading * speed * delta
		var floor_y: float = ground.call(global_position.x, global_position.z) if ground.is_valid() else -INF
		if life <= 0.0 or global_position.y < floor_y + 0.2:
			_pop()

	func _pop() -> void:
		_done = true
		if burst.is_valid():
			burst.call(global_position)
		queue_free()


## A glowing ribbon left behind a moving node: a camera-facing strip through
## its last positions, white-hot and widest at the head, tapering and fading
## to the tail. Particles emitted once a frame leave beads behind anything
## fast; this stays one smooth streak at any speed. It outlives what it
## follows just long enough to fade out.
class Ribbon:
	extends MeshInstance3D
	var follow: Node3D
	var width := 0.3
	var span := 0.22         ## seconds of history it keeps
	var tint := Arcana.VIOLET
	var follow_for := INF    ## seconds to follow before letting go
	var _pts: Array = []     ## [position, age], oldest first
	var _im := ImmediateMesh.new()
	static var _tex: Texture2D

	## A soft band: clear at both edges, solid in the middle (across UV.y).
	static func _band() -> Texture2D:
		if _tex == null:
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 0))
			g.set_color(1, Color(1, 1, 1, 0))
			g.add_point(0.5, Color(1, 1, 1, 1))
			g.add_point(0.34, Color(1, 1, 1, 0.22))
			g.add_point(0.66, Color(1, 1, 1, 0.22))
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill_from = Vector2(0, 0)
			t.fill_to = Vector2(0, 1)
			t.width = 4
			t.height = 32
			_tex = t
		return _tex

	func _ready() -> void:
		top_level = true
		global_transform = Transform3D.IDENTITY
		mesh = _im
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _band()
		m.disable_fog = true
		material_override = m
		extra_cull_margin = 16384.0   # its AABB is rebuilt every frame

	func _process(delta: float) -> void:
		follow_for -= delta
		if follow_for <= 0.0:
			follow = null
		for p in _pts:
			p[1] += delta
		while not _pts.is_empty() and _pts[0][1] > span:
			_pts.pop_front()
		if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
			if follow.is_visible_in_tree():
				var at := follow.global_position
				if _pts.is_empty() or (_pts.back()[0] as Vector3).distance_to(at) > 0.01:
					_pts.append([at, 0.0])
		else:
			follow = null
			if _pts.is_empty():
				queue_free()
				return
		_build()

	func _build() -> void:
		_im.clear_surfaces()
		var cam := get_viewport().get_camera_3d()
		if _pts.size() < 2 or cam == null:
			return
		var eye := cam.global_position
		var n := _pts.size()
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n:
			var p: Vector3 = _pts[i][0]
			var a: Vector3 = _pts[maxi(i - 1, 0)][0]
			var b: Vector3 = _pts[mini(i + 1, n - 1)][0]
			var side := (b - a).cross(eye - p)
			if side.length_squared() < 1e-8:
				side = Vector3.UP
			# 1 at the head (newest), 0 at the tail.
			var f := clampf(1.0 - float(_pts[i][1]) / span, 0.0, 1.0)
			side = side.normalized() * width * (0.25 + 0.75 * f)
			var c := Color(tint.lerp(Color.WHITE, 0.35 * f * f), f * f * 0.85)
			_im.surface_set_color(c)
			_im.surface_set_uv(Vector2(f, 0.0))
			_im.surface_add_vertex(p + side)
			_im.surface_set_color(c)
			_im.surface_set_uv(Vector2(f, 1.0))
			_im.surface_add_vertex(p - side)
		_im.surface_end()


## Start a ribbon behind `node` (added beside it, so it survives the node).
static func ribbon(node: Node3D, tint: Color, width := 0.3, span := 0.22, follow_for := INF) -> void:
	var r := Ribbon.new()
	r.follow = node
	r.follow_for = follow_for
	r.tint = tint
	r.width = width
	r.span = span
	node.get_parent().add_child.call_deferred(r)
