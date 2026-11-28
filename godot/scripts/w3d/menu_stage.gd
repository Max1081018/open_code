class_name MenuStage
extends Control
## The title screen's backdrop: the painted dusk vista of the Starfall (the
## World Tree on its mesa, the sea at sunset, the sky isles; Higgsfield key
## art), alive: a violet wisp drifting over the parapet, fireflies, the
## painted lantern flickering, glints dancing on the sea. On the character
## screen Lyra — the playable model — stands on the terrace (`show_hero`).

const BG := "res://assets/ui/front/menu_bg.jpg"
## Where her hips sit, in the 1920x1080 painting: on the parapet's top edge.
const SEAT_PX := Vector2(1330, 640)
## Where her hip joint goes on screen: a little above the stone's edge.
const HIPS_PX := Vector2(1330, 616)
const DEPTH := 7.0
## The hero screen: she stands on the terrace floor, feet here.
const FEET_PX := Vector2(1420, 1000)

var model: Node3D
var cam: Camera3D
var turn := 0.0            ## extra yaw for the character screen's drag
var orbit := 0.0           ## kept for callers; adds to `turn`
var _vp: SubViewport
var _t := 0.0
var _seat := Vector3.ZERO
var _glow: TextureRect
var _sit: SitPose
var _skel: Skeleton3D
var _shadow: TextureRect
## The painting and everything placed on it, in the painting's own 1920x1080
## pixels; scaled to cover any screen (a 20:9 phone crops a little of the
## sky rather than showing a black strip).
var _canvas: Control
## The painting and its 2D life render once into this layer at a fixed size
## (1920x1080, less on low settings) and are scaled to the screen: a phone's
## 3200x1440 panel never runs the vista shader at native resolution.
var _paint: SubViewport
var _paint_root: Control
var _view: SubViewportContainer
var _wisp: Node2D
## How the crop sits on a screen wider than 16:9: 0 keeps the top, 1 the
## bottom. The title keeps the World Tree and the isles (crops the terrace
## floor); the hero screen keeps her feet on the terrace.
const FOCUS_TITLE := 0.15
const FOCUS_HERO := 0.85
var _focus_y := FOCUS_TITLE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	# The painted layer.
	var res: Vector2i = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1920, 1080)][clampi(Settings.quality, 0, 3)]
	_paint = SubViewport.new()
	_paint.size = res
	_paint.disable_3d = true
	_paint.transparent_bg = false
	_paint.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_paint)
	_paint_root = Control.new()
	_paint_root.size = Vector2(1920, 1080)
	_paint_root.scale = Vector2(res) / Vector2(1920, 1080)
	_paint.add_child(_paint_root)
	var shown := TextureRect.new()
	shown.texture = _paint.get_texture()
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.size = Vector2(1920, 1080)
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(shown)
	var art := TextureRect.new()
	art.texture = load(BG)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = Vector2(1920, 1080)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The painting moves: isles bob, the tree stirs, falls run, mist drifts.
	var vista := ShaderMaterial.new()
	vista.shader = load("res://scripts/shaders/menu_vista.gdshader")
	vista.set_shader_parameter("noise_tex", _noise_texture())
	art.material = vista
	_put(art)
	_put(_sea_glints())
	_glow = _soft_glow(Vector2(1824, 512), 90.0, Color(1.0, 0.78, 0.45, 0.55))
	_put(_glow)
	_wisp = _build_wisp(Vector2(1272, 566))
	_put(_wisp)
	_put(_fireflies())
	# Her contact shadow on the terrace (shown with her on the hero screen).
	_shadow = _soft_glow(FEET_PX, 110.0, Color(0, 0, 0, 0.5))
	_shadow.material = null
	_shadow.scale = Vector2(1.0, 0.18)
	_shadow.pivot_offset = Vector2(110, 110)
	_shadow.visible = false
	_canvas.add_child(_shadow)
	# The 3D view: only the character screen draws anything in it, so it
	# renders only while she is shown.
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size = Vector2(1920, 1080)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.visible = false
	_canvas.add_child(_view)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.msaa_3d = Viewport.MSAA_2X if OS.has_feature("mobile") or Settings.quality < 2 else Viewport.MSAA_4X
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_view.add_child(_vp)
	_environment()
	cam = Camera3D.new()
	cam.fov = 30.0
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 0), Vector3(0, 0, -1), Vector3.UP)
	_seat = _project(SEAT_PX, DEPTH)
	_fit()
	get_viewport().size_changed.connect(_fit)


## Smooth value noise in a small tiling texture: the vista shader samples it
## instead of evaluating sine hashes per pixel (far cheaper on a phone GPU).
static func _noise_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		for x in n:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## Her magic at rest on the parapet: a soft violet wisp with motes rising.
func _build_wisp(at: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = at
	var halo := _soft_glow(Vector2.ZERO, 30.0, Color(0.78, 0.6, 1.0, 0.4))
	root.add_child(halo)
	var core := _soft_glow(Vector2.ZERO, 8.0, Color(1.0, 0.94, 1.0, 0.85))
	root.add_child(core)
	var motes := CPUParticles2D.new()
	motes.amount = 14
	motes.lifetime = 3.0
	motes.preprocess = 3.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 18.0
	motes.direction = Vector2(0, -1)
	motes.spread = 40.0
	motes.gravity = Vector2(0, -8)
	motes.initial_velocity_min = 3.0
	motes.initial_velocity_max = 12.0
	motes.scale_amount_min = 1.5
	motes.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.85, 0.72, 1.0, 0.0), Color(0.9, 0.8, 1.0, 0.9), Color(0.85, 0.72, 1.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	motes.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	motes.material = mat
	root.add_child(motes)
	return root


## Everything the stage builds goes onto the painting's canvas.
func _put(node: Node) -> void:
	_paint_root.add_child(node)


## Cover the screen with the painting, whatever its shape, plus a very slow
## push-in and drift (a breath every minute) so the view itself is alive.
func _fit() -> void:
	var view := get_viewport_rect().size
	var breath := 0.5 - 0.5 * cos(_t * TAU / 60.0)
	var k := maxf(view.x / 1920.0, view.y / 1080.0) * (1.0 + 0.025 * breath)
	_canvas.scale = Vector2(k, k)
	var spare := view - Vector2(1920, 1080) * k
	_canvas.position = Vector2(spare.x * (0.5 + 0.2 * (breath - 0.5)), spare.y * _focus_y)


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


## Show (or hide) Lyra standing on the terrace in her idle: the character
## screen's preview. The title screen itself shows only the vista.
func show_hero(on: bool) -> void:
	_view.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on and model == null:
		model = CharacterKit.build(Account.character_kit() if Account.signed_in() else "player")
		_vp.add_child(model)
		model.position = _project(FEET_PX, 6.0)
		model.rotation.y = 0.35
		var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
		if ap:
			var style: Dictionary = model.get_meta("style", {})
			var idle: String = String(style.get("clips", {}).get("Idle", "Idle"))
			if ap.has_animation(idle):
				ap.play(idle)
	if model:
		model.visible = on
	if _shadow:
		_shadow.visible = on


func _process(delta: float) -> void:
	_t += delta
	var focus_want := FOCUS_HERO if model and model.visible else FOCUS_TITLE
	_focus_y = lerpf(_focus_y, focus_want, 1.0 - exp(-3.0 * delta))
	_fit()
	if model:
		var want := 0.35 + clampf(turn + orbit, -1.2, 1.2)
		model.rotation.y = lerpf(model.rotation.y, want, 1.0 - exp(-6.0 * delta))
	if _wisp:
		_wisp.position.y = 566.0 + sin(_t * 1.6) * 6.0
		_wisp.modulate.a = 0.85 + sin(_t * 2.3) * 0.15
	if _glow:
		# The painted lantern flickers like a flame.
		_glow.modulate.a = 0.65 + sin(_t * 7.0) * 0.12 + sin(_t * 13.0) * 0.08
