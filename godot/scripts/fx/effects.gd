class_name Effects
extends RefCounted
## Particle effects. CPUParticles2D throughout: GPU particles depend on
## transform feedback, which the low end of Android does not reliably have.

static var _textures := {}
static var _add: CanvasItemMaterial


static func tex(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load("res://assets/fx/%s.png" % name)
	return _textures[name]


static func additive() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add


static func _fade(from: Color, to: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	return gradient


static func _budget(amount: int) -> int:
	return max(1, int(round(amount * Settings.particle_scale())))


## Flames licking up from a campfire.
static func fire(offset: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = offset
	p.texture = tex("flame_04")
	p.material = additive()
	p.z_as_relative = false
	p.z_index = 61
	p.amount = _budget(16)
	p.lifetime = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(18, 4)
	p.direction = Vector2.UP
	p.spread = 12.0
	p.gravity = Vector2(0, -160)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.10
	p.scale_amount_max = 0.18
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	p.color_ramp = _fade(Color(1.0, 0.75, 0.35, 0.9), Color(1.0, 0.25, 0.08, 0.0))
	return p


## A few sparks drifting up from a torch.
static func embers(offset: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = offset
	p.texture = tex("circle_05")
	p.material = additive()
	p.z_as_relative = false
	p.z_index = 61
	p.amount = _budget(6)
	p.lifetime = 1.6
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -40)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 50.0
	p.scale_amount_min = 0.015
	p.scale_amount_max = 0.03
	p.color_ramp = _fade(Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.4, 0.1, 0.0))
	return p


## Slow glowing motes hanging around a magical light.
static func motes(offset: Vector2, color: Color, radius_tiles: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = offset
	p.texture = tex("circle_05")
	p.material = additive()
	p.z_as_relative = false
	p.z_index = 61
	p.amount = _budget(10)
	p.lifetime = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius_tiles * 128.0 * 0.5
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 18.0
	p.spread = 180.0
	p.scale_amount_min = 0.012
	p.scale_amount_max = 0.03
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, 1.0), Color(color, 0.0)])
	p.color_ramp = gradient
	return p


## One-shot burst at a world position, freed when it finishes.
static func burst(parent: Node, position: Vector2, kind: String, color := Color.WHITE) -> void:
	var p := CPUParticles2D.new()
	p.position = position
	p.one_shot = true
	p.explosiveness = 0.95
	p.z_as_relative = false
	p.z_index = 40
	match kind:
		"dig":
			p.texture = tex("dirt_01")
			p.amount = _budget(9)
			p.lifetime = 0.55
			p.spread = 180.0
			p.initial_velocity_min = 140.0
			p.initial_velocity_max = 320.0
			p.gravity = Vector2(0, 900)
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.11
			p.color = color
			p.color_ramp = _fade(Color.WHITE, Color(1, 1, 1, 0))
		"break":
			p.texture = tex("dirt_02")
			p.amount = _budget(16)
			p.lifetime = 0.8
			p.spread = 180.0
			p.initial_velocity_min = 200.0
			p.initial_velocity_max = 460.0
			p.gravity = Vector2(0, 1100)
			p.angular_velocity_min = -360
			p.angular_velocity_max = 360
			p.scale_amount_min = 0.07
			p.scale_amount_max = 0.16
			p.color = color
			p.color_ramp = _fade(Color.WHITE, Color(1, 1, 1, 0))
		"hit":
			p.texture = tex("star_04")
			p.material = additive()
			p.z_index = 62
			p.amount = _budget(10)
			p.lifetime = 0.35
			p.spread = 180.0
			p.initial_velocity_min = 240.0
			p.initial_velocity_max = 520.0
			p.scale_amount_min = 0.08
			p.scale_amount_max = 0.16
			p.color_ramp = _fade(Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.2, 0))
		"heal", "glow":
			p.texture = tex("circle_05")
			p.material = additive()
			p.z_index = 62
			p.amount = _budget(18)
			p.lifetime = 0.9
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 60.0
			p.direction = Vector2.UP
			p.spread = 30.0
			p.gravity = Vector2(0, -220)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 140.0
			p.scale_amount_min = 0.03
			p.scale_amount_max = 0.06
			p.color_ramp = _fade(color, Color(color, 0.0))
		"smoke":
			p.texture = tex("smoke_04")
			p.amount = _budget(8)
			p.lifetime = 1.0
			p.spread = 180.0
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 180.0
			p.gravity = Vector2(0, -80)
			p.scale_amount_min = 0.2
			p.scale_amount_max = 0.4
			p.color_ramp = _fade(Color(color, 0.7), Color(color, 0.0))
		"splash":
			p.texture = tex("circle_05")
			p.amount = _budget(5)
			p.lifetime = 0.35
			p.direction = Vector2.UP
			p.spread = 60.0
			p.initial_velocity_min = 80.0
			p.initial_velocity_max = 200.0
			p.gravity = Vector2(0, 1400)
			p.scale_amount_min = 0.012
			p.scale_amount_max = 0.022
			p.color = Color(0.75, 0.88, 1.0, 0.9)
		"slash":
			p.texture = tex("slash_03")
			p.material = additive()
			p.z_index = 62
			p.amount = 1
			p.lifetime = 0.22
			p.spread = 0.0
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.0
			p.scale_amount_min = 0.55
			p.scale_amount_max = 0.55
			p.color_ramp = _fade(Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## A number or word that pops up and floats away: damage, pickups.
static func float_text(parent: Node, position: Vector2, text: String, color := Color.WHITE,
		size := 52) -> void:
	var label := Label.new()
	label.text = text
	label.z_as_relative = false
	label.z_index = 80
	label.add_theme_font_override("font", UITheme.title_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
	label.add_theme_constant_override("outline_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = position - Vector2(100, 40)
	label.size = Vector2(200, 80)
	label.pivot_offset = Vector2(100, 40)
	label.scale = Vector2(0.4, 0.4)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position:y", label.position.y - 110, 0.9) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.25)
	tween.tween_callback(label.queue_free)
