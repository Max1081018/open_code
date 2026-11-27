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
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = tint.lerp(Color.WHITE, 0.35)
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	return m


## A star lance: a long crystal shard that drops from the sky onto `at`,
## then calls `landed` (the strike) and shatters into light.
static func lance(host: Node, at: Vector3, delay: float, landed: Callable, tint := VIOLET) -> void:
	var shard := MeshInstance3D.new()
	var prism := CylinderMesh.new()
	prism.top_radius = 0.0
	prism.bottom_radius = 0.16
	prism.height = 2.6
	prism.radial_segments = 4
	prism.rings = 1
	shard.mesh = prism
	shard.material_override = _glow_material(tint, 1.8)
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(shard)
	# Point first, tilted a little, from high above and to the side.
	shard.global_position = at + Vector3(randf_range(-3, 3), 22.0, randf_range(-3, 3))
	shard.look_at(at, Vector3.FORWARD if absf((at - shard.global_position).normalized().y) > 0.99 else Vector3.UP)
	shard.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	shard.visible = false
	var trail := CPUParticles3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.18, 0.18)
	trail.mesh = tq
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_texture = Play3D._spark_texture()
	tm.albedo_color = tint
	trail.material_override = tm
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.gravity = Vector3.ZERO
	trail.emitting = false
	shard.add_child(trail)
	var t := shard.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		shard.visible = true
		trail.emitting = true)
	t.tween_property(shard, "global_position", at + Vector3(0, 0.9, 0), 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func():
		landed.call(at)
		sparks(host, at + Vector3(0, 0.4, 0), tint, 16, 6.0, 0.1)
		flash(host, at + Vector3(0, 1.0, 0), tint, 1.5, 5.0, 0.25)
		trail.emitting = false
		shard.material_override = _glow_material(tint, 3.0))
	t.tween_property(shard, "scale", Vector3(1.6, 0.05, 1.6), 0.18)
	t.tween_callback(shard.queue_free)


## A homing arcane comet. Flies from where it is spawned along `heading`,
## turning toward `target` (an enemy, if any); bursts on contact, on
## striking the ground or after `life` seconds, calling `burst(at)`.
class Orb:
	extends Node3D
	var heading := Vector3.FORWARD
	var speed := 17.0
	var target: Node3D
	var life := 1.8
	var burst: Callable
	var ground: Callable   ## (x, z) -> ground height
	var tint := Arcana.VIOLET
	var _done := false

	func _ready() -> void:
		var core := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.22
		s.height = 0.44
		s.radial_segments = 16
		s.rings = 8
		core.mesh = s
		core.material_override = Arcana._glow_material(tint, 5.0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.34
		hs.height = 0.68
		hs.radial_segments = 16
		hs.rings = 8
		halo.mesh = hs
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hm.albedo_color = Color(tint, 0.16)
		hm.cull_mode = BaseMaterial3D.CULL_FRONT
		halo.material_override = hm
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
		var light := OmniLight3D.new()
		light.light_color = tint
		light.light_energy = 1.6
		light.omni_range = 4.0
		light.shadow_enabled = false
		add_child(light)
		var trail := CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.22)
		trail.mesh = q
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.albedo_texture = Play3D._spark_texture()
		tm.vertex_color_use_as_albedo = true
		trail.material_override = tm
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(Arcana.LILAC, 0.9), Color(tint, 0.0)])
		trail.color_ramp = ramp
		trail.amount = 48
		trail.lifetime = 0.45
		trail.local_coords = false
		trail.gravity = Vector3(0, 0.5, 0)
		trail.direction = Vector3.UP
		trail.spread = 180
		trail.initial_velocity_min = 0.2
		trail.initial_velocity_max = 0.8
		trail.scale_amount_min = 0.5
		trail.scale_amount_max = 1.2
		add_child(trail)

	func _physics_process(delta: float) -> void:
		if _done:
			return
		life -= delta
		if target != null and is_instance_valid(target):
			var want := (target.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
			heading = heading.slerp(want, clampf(delta * 6.0, 0.0, 1.0)).normalized()
			if global_position.distance_to(target.global_position + Vector3(0, 1.0, 0)) < 0.9:
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
