class_name MenuStage
extends Control
## The title screen's backdrop. A painted dusk vista of the Starfall (the
## World Tree on its mesa, the sea at sunset, the sky isles; Higgsfield key
## art) with a carved stone parapet in the foreground — and on that parapet,
## live in 3D, Lyra: the playable model, sitting with her legs swinging over
## the edge (SitPose), lit warm from the sunset behind her and cool from the
## sky. Around her: a star-lantern glowing at her side, fireflies, the
## painted lantern flickering, glints dancing on the sea.
## The 3D camera is fixed so she stays seated on the painted stone; the
## character screen turns her (`turn`) rather than moving the camera.

const BG := "res://assets/ui/front/menu_bg.jpg"
## Where her hips sit, in the 1920x1080 painting: on the parapet's top edge.
const SEAT_PX := Vector2(1330, 646)
const DEPTH := 6.0

var model: Node3D
var cam: Camera3D
var turn := 0.0            ## extra yaw for the character screen's drag
var orbit := 0.0           ## kept for callers; adds to `turn`
var _vp: SubViewport
var _t := 0.0
var _seat := Vector3.ZERO
var _lantern: Node3D
var _glow: TextureRect
var _sit: SitPose


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.texture = load(BG)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = Vector2(1920, 1080)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	add_child(_sea_glints())
	_glow = _soft_glow(Vector2(1824, 512), 90.0, Color(1.0, 0.78, 0.45, 0.55))
	add_child(_glow)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.size = Vector2(1920, 1080)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = true
	view.add_child(_vp)
	_environment()
	cam = Camera3D.new()
	cam.fov = 30.0
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3.UP)
	_seat = _project(SEAT_PX, DEPTH)
	model = CharacterKit.build(Account.character_kit() if Account.signed_in() else "player")
	_vp.add_child(model)
	# Hips on the stone, a hand's breadth back from the face; facing out.
	model.position = _seat - Vector3(0, 0.5, 0.3)
	model.rotation.y = 0.28
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap:
		var style: Dictionary = model.get_meta("style", {})
		var idle: String = String(style.get("clips", {}).get("Idle", "Idle"))
		if ap.has_animation(idle):
			ap.play(idle)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_sit = SitPose.new()
		(sks[0] as Skeleton3D).add_child(_sit)
	_build_vfx()
	add_child(_fireflies())


## A point `depth` metres in front of the camera under pixel `px` (camera at
## the origin looking down -Z; computed directly so it works before the
## viewport has drawn).
func _project(px: Vector2, depth: float) -> Vector3:
	var half_h := tan(deg_to_rad(cam.fov * 0.5)) * depth
	var half_w := half_h * 1920.0 / 1080.0
	return Vector3((px.x / 1920.0 * 2.0 - 1.0) * half_w, (1.0 - px.y / 1080.0 * 2.0) * half_h, -depth)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.48, 0.66)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 8.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# The sunset is behind her and to the right: a warm rim light.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.68, 0.45)
	sun.light_energy = 1.6
	sun.rotation = Vector3(-0.15, 2.6, 0)
	_vp.add_child(sun)
	# The dusk sky in front: a soft cool key.
	var sky := DirectionalLight3D.new()
	sky.light_color = Color(0.62, 0.66, 0.95)
	sky.light_energy = 0.75
	sky.rotation = Vector3(-0.5, -0.35, 0)
	_vp.add_child(sky)


func _build_vfx() -> void:
	# A small star-lantern on the stone at her side.
	_lantern = Node3D.new()
	_vp.add_child(_lantern)
	_lantern.position = _seat + Vector3(-0.55, 0.12, 0.0)
	# A wisp: a soft bright core with a halo (her own magic, at rest).
	var wisp := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	wisp.mesh = quad
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wm.albedo_texture = Play3D._spark_texture()
	wm.albedo_color = Color(0.9, 0.78, 1.0)
	wisp.material_override = wm
	_lantern.add_child(wisp)
	var light := OmniLight3D.new()
	light.light_color = Color(0.86, 0.7, 1.0)
	light.light_energy = 1.4
	light.omni_range = 2.5
	_lantern.add_child(light)
	var motes := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	motes.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = Color(0.85, 0.72, 1.0)
	motes.material_override = m
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.25
	motes.amount = 18
	motes.lifetime = 3.0
	motes.preprocess = 3.0
	motes.gravity = Vector3(0, 0.12, 0)
	motes.initial_velocity_min = 0.03
	motes.initial_velocity_max = 0.12
	motes.spread = 180.0
	_lantern.add_child(motes)


## Fireflies drifting across the front of the scene.
func _fireflies() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(1200, 760)
	p.amount = 34
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(760, 300)
	p.direction = Vector2(0.3, -1)
	p.spread = 60.0
	p.gravity = Vector2(4, -6)
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.5, 0.0), Color(1.0, 0.88, 0.55, 0.9), Color(1.0, 0.8, 0.5, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p


## Light dancing on the sea under the setting sun (the painting's right).
func _sea_glints() -> ColorRect:
	var r := ColorRect.new()
	r.position = Vector2(1180, 430)
	r.size = Vector2(740, 200)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """shader_type canvas_item;
render_mode blend_add;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = UV * vec2(420.0, 110.0);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float t = TIME * 1.1 + h(cell) * 20.0;
	// A short horizontal glint, soft at both ends, in a few cells at a time.
	float shape = (1.0 - smoothstep(0.0, 0.5, abs(f.x - 0.5))) * (1.0 - smoothstep(0.0, 0.18, abs(f.y - 0.5)));
	float s = step(0.9, h(cell + floor(t))) * sin(fract(t) * 3.14159) * shape;
	float column = exp(-pow((UV.x - 0.72) * 3.2, 2.0)) * smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.4, 1.0, UV.y));
	COLOR = vec4(vec3(1.0, 0.82, 0.6) * s * column * 0.75, 1.0);
}"""
	r.material = m
	return r


func _soft_glow(centre: Vector2, radius: float, col: Color) -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(col, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var t := TextureRect.new()
	t.texture = gt
	t.size = Vector2(radius, radius) * 2.0
	t.position = centre - Vector2(radius, radius)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	t.material = mat
	return t


## Kept for callers: the menu and the character screen share one framing.
func focus(_mode: String) -> void:
	pass


func _process(delta: float) -> void:
	_t += delta
	if model:
		var want := 0.28 + clampf(turn + orbit, -0.9, 0.9)
		model.rotation.y = lerpf(model.rotation.y, want, 1.0 - exp(-6.0 * delta))
	if _lantern:
		var c := _lantern.get_child(0) as Node3D
		c.rotation.y += delta * 0.8
		c.position.y = sin(_t * 1.6) * 0.03
	if _glow:
		# The painted lantern flickers like a flame.
		_glow.modulate.a = 0.65 + sin(_t * 7.0) * 0.12 + sin(_t * 13.0) * 0.08
