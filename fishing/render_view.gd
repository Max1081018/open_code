class_name RenderView
extends CanvasLayer
## Renders the 3D world at a chosen fraction of the screen resolution and
## scales it up behind the HUD, which stays sharp at full resolution. Phones
## have far more pixels than their GPUs can shade every frame, so this is the
## single biggest smoothness win. Optional FXAA smooths edges after the upscale
## (no MSAA: it caused edge-line artifacts on some phone GPUs).
##
## The root viewport's own 3D drawing is switched off; a camera inside the
## SubViewport copies the game camera every frame (after everything else has
## moved it) and renders the same World3D.

var scale_3d := 0.75
var fxaa := false

var view: SubViewport
var cam: Camera3D
var _rect: TextureRect
var _src: Camera3D
var _mat: ShaderMaterial

const FXAA_SHADER := """
shader_type canvas_item;
uniform bool enabled = false;
uniform vec2 texel = vec2(0.001);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (!enabled) {
		COLOR = c;
	} else {
		// Small FXAA-style edge blend: find the luma edge direction and
		// blur along it. Cheap enough for phones at upscaled resolution.
		vec3 W = vec3(0.299, 0.587, 0.114);
		float lM = dot(c.rgb, W);
		float lN = dot(texture(TEXTURE, UV + vec2(0.0, -texel.y)).rgb, W);
		float lS = dot(texture(TEXTURE, UV + vec2(0.0, texel.y)).rgb, W);
		float lE = dot(texture(TEXTURE, UV + vec2(texel.x, 0.0)).rgb, W);
		float lW = dot(texture(TEXTURE, UV + vec2(-texel.x, 0.0)).rgb, W);
		float lo = min(lM, min(min(lN, lS), min(lE, lW)));
		float hi = max(lM, max(max(lN, lS), max(lE, lW)));
		float range = hi - lo;
		if (range < max(0.04, hi * 0.12)) {
			COLOR = c;
		} else {
			vec2 dir = vec2(-((lN + lS) - (lE + lW) * 0.0) + (lN - lS) * 0.0, 0.0);
			dir = vec2(lS - lN, lE - lW);
			dir = normalize(dir + 1e-5) * texel * 1.2;
			vec3 a = 0.5 * (texture(TEXTURE, UV + dir * -0.33).rgb + texture(TEXTURE, UV + dir * 0.33).rgb);
			vec3 b = a * 0.5 + 0.25 * (texture(TEXTURE, UV + dir * -1.0).rgb + texture(TEXTURE, UV + dir).rgb);
			float lb = dot(b, W);
			COLOR = vec4((lb < lo || lb > hi) ? a : b, c.a);
		}
	}
}
"""


func _init() -> void:
	layer = -10              # behind every HUD layer


func setup(source_camera: Camera3D, world: World3D) -> void:
	_src = source_camera
	view = SubViewport.new()
	view.world_3d = world
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.handle_input_locally = false
	view.gui_disable_input = true
	add_child(view)
	cam = Camera3D.new()
	view.add_child(cam)
	cam.current = true
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_rect.texture = view.get_texture()
	var sh := Shader.new()
	sh.code = FXAA_SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	get_viewport().disable_3d = true
	get_viewport().size_changed.connect(_resize)
	_resize()


func set_quality(p_scale: float, p_fxaa: bool) -> void:
	scale_3d = clampf(p_scale, 0.3, 1.0)
	fxaa = p_fxaa
	_resize()


func _resize() -> void:
	if view == null:
		return
	var s := get_viewport().get_visible_rect().size
	# the root viewport may be stretched; use the real window pixels
	var win := Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else s
	if win.x < 2.0 or win.y < 2.0:
		win = s
	var px := Vector2i(maxi(int(win.x * scale_3d), 64), maxi(int(win.y * scale_3d), 64))
	view.size = px
	_mat.set_shader_parameter("enabled", fxaa)
	_mat.set_shader_parameter("texel", Vector2(1.0 / px.x, 1.0 / px.y))


## Runs after the game moved its camera this frame (high process priority).
func _process(_d: float) -> void:
	if _src == null or cam == null:
		return
	cam.global_transform = _src.global_transform
	cam.fov = _src.fov
	cam.near = _src.near
	cam.far = _src.far
	cam.environment = _src.environment
