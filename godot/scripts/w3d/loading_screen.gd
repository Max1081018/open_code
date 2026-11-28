class_name LoadingScreen
extends Control
## The loading screen between every major scene: the night-violet key art
## drifting under a veil, motes of light rising, the Ethereal Tales emblem and
## title, a gold progress line with a glowing head and a rotating tip.
##
## Progress is real: the target scene and the heavy assets it will need
## (character models, nature models) are requested on loader threads and the
## bar shows their combined ResourceLoader progress. Loaded resources are
## held in `cache`, so the next scene's load() calls return at once.
##   LoadingScreen.go(tree, "res://scenes/main3d.tscn", ["res://assets/models/heroes/"])

const SCENE := "res://scenes/loading.tscn"
const GOLD := Color(0.96, 0.84, 0.56)
const PALE := Color(0.93, 0.92, 1.0)
const TIPS := [
	"Hold still for a few breaths and Lyra drifts up on her own magic.",
	"Strike the moment a foe's ground-mark fills: then dodge through the blow.",
	"Starstones remember you. Wake one and you can travel back to it from the map.",
	"Every region keeps its own weather. Sandstorms pass; shelter in the lee of a dune.",
	"The Moonblade's arts open as you grow: Crescent Wave, Arcane Comet, Violet Starfall.",
	"Crush ore and fell trees: the Haven's smith can turn them into better steel.",
	"Look for light where there should be none. Secrets glow.",
	"Sand slows the step. Ride the hard dune crests instead of the soft hollows.",
]

static var target := "res://scenes/menu3d.tscn"
static var warm_dirs: Array = ["res://assets/models/heroes/"]  ## first boot: the hero for the select screen
## Resources kept alive so the next scene finds them already loaded.
static var cache: Array = []

var _paths: Array[String] = []
var _done := false
var _shown := 0.0
var _time := 0.0
var _tip_time := 0.0
var _tip: Label
var _bar: Control
var _pct: Label
var _art: TextureRect
var _status: Label


static func go(tree: SceneTree, path: String, dirs: Array = []) -> void:
	target = path
	warm_dirs = dirs
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_paths = [target]
	for d in warm_dirs:
		_paths.append_array(_resources_in(String(d)))
	for p in _paths:
		if not ResourceLoader.has_cached(p):
			ResourceLoader.load_threaded_request(p, "", true)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


## Model files under `dir` (one level of subfolders), as loadable paths.
static func _resources_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap").trim_suffix(".import")
		if name.get_extension() in ["glb", "scn", "res"] and not out.has(dir + name):
			out.append(dir + name)
	for sub in d.get_directories():
		if sub != "anim":
			continue
		for f in DirAccess.get_files_at(dir + sub):
			var name := f.trim_suffix(".remap").trim_suffix(".import")
			if name.get_extension() in ["res", "glb"] and not out.has(dir + sub + "/" + name):
				out.append(dir + sub + "/" + name)
	return out


## Combined progress of every requested resource, 0..1.
func progress() -> float:
	if _paths.is_empty():
		return 1.0
	var total := 0.0
	for p in _paths:
		if ResourceLoader.has_cached(p):
			total += 1.0
			continue
		var pr := []
		var st := ResourceLoader.load_threaded_get_status(p, pr)
		match st:
			ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				total += 1.0
			_:
				total += float(pr[0]) if not pr.is_empty() else 0.0
	return total / _paths.size()


func _process(delta: float) -> void:
	_time += delta
	_art.scale = Vector2.ONE * (1.06 + sin(_time * 0.08) * 0.02)
	_art.position = Vector2(-50 + sin(_time * 0.05) * 30.0, -30 + cos(_time * 0.04) * 16.0)
	_tip_time += delta
	if _tip_time > 5.5:
		_tip_time = 0.0
		var t := create_tween()
		t.tween_property(_tip, "modulate:a", 0.0, 0.4)
		t.tween_callback(func(): _tip.text = TIPS.pick_random())
		t.tween_property(_tip, "modulate:a", 1.0, 0.5)
	var p := progress()
	# The bar eases toward the real value; it never runs ahead of it.
	_shown = minf(p, lerpf(_shown, p, 1.0 - exp(-6.0 * delta)) + delta * 0.05)
	_pct.text = "%d%%" % int(round(_shown * 100.0))
	_bar.queue_redraw()
	if p >= 1.0 and _shown > 0.995 and not _done:
		_done = true
		_finish()


func _finish() -> void:
	var packed: PackedScene = null
	for p in _paths:
		var res: Resource = null
		if ResourceLoader.load_threaded_get_status(p) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			res = ResourceLoader.load_threaded_get(p)
		if res == null:
			res = load(p)
		if res:
			cache.append(res)
		if p == target:
			packed = res as PackedScene
	_status.text = "Entering…"
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.45)
	t.tween_callback(func():
		if packed:
			get_tree().change_scene_to_packed(packed)
		else:
			get_tree().change_scene_to_file(target))


# ------------------------------------------------------------- visuals ---

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_art = TextureRect.new()
	_art.texture = load("res://assets/ui/front/menu_bg.jpg")
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.size = Vector2(2040, 1160)
	_art.pivot_offset = _art.size * 0.5
	_art.modulate = Color(0.5, 0.5, 0.58)
	add_child(_art)
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vm := ShaderMaterial.new()
	vm.shader = Shader.new()
	vm.shader.code = """shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.62);
	float v = smoothstep(0.25, 0.95, length(p * vec2(1.0, 1.6)));
	COLOR = vec4(0.03, 0.02, 0.09, 0.35 + v * 0.55);
}"""
	veil.material = vm
	add_child(veil)
	add_child(_motes())
	var logo := UiKit.logo(900)
	logo.position = Vector2(510, 400)
	add_child(logo)
	var sub := _label("Chronicles of the Starfall", 30, Color(0.86, 0.86, 0.92, 0.85), load("res://assets/fonts/Cormorant-Italic.ttf"))
	sub.position = Vector2(0, 560)
	sub.size = Vector2(1920, 50)
	add_child(sub)
	_bar = Control.new()
	_bar.position = Vector2(560, 860)
	_bar.size = Vector2(800, 24)
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_pct = _label("0%", 26, GOLD, load("res://assets/fonts/Cinzel.ttf"))
	_pct.position = Vector2(1370, 848)
	_pct.size = Vector2(120, 40)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_pct)
	_status = _label("Gathering starlight…", 26, PALE, load("res://assets/fonts/Cinzel.ttf"))
	_status.position = Vector2(0, 806)
	_status.size = Vector2(1920, 40)
	add_child(_status)
	_tip = _label(TIPS.pick_random(), 30, Color(0.86, 0.84, 0.98), load("res://assets/fonts/Cormorant-Italic.ttf"))
	_tip.position = Vector2(260, 930)
	_tip.size = Vector2(1400, 80)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_tip)


func _label(text: String, size: int, col: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _draw_bar() -> void:
	var w := _bar.size.x
	var y := _bar.size.y * 0.5
	_bar.draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.12), 1.0, true)
	var x := w * _shown
	_bar.draw_line(Vector2(0, y), Vector2(x, y), Color(0.9, 0.8, 0.58), 2.0, true)
	var pulse := 0.6 + sin(_time * 4.0) * 0.4
	for r in [10.0, 6.0]:
		_bar.draw_circle(Vector2(x, y), r, Color(1.0, 0.9, 0.7, 0.1 * pulse))
	_bar.draw_circle(Vector2(x, y), 3.5, Color(1, 0.97, 0.88))
	# Diamond caps.
	for cx in [-14.0, w + 14.0]:
		_bar.draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 6), Vector2(cx + 6, y), Vector2(cx, y + 6), Vector2(cx - 6, y)]), GOLD)


func _draw_emblem(e: Control) -> void:
	var c := e.size * 0.5
	var spin := _time * 0.3
	for k in 8:
		var a := spin + TAU * k / 8.0
		var len := 56.0 if k % 2 == 0 else 34.0
		var tip := c + Vector2(cos(a), sin(a)) * len
		var l := c + Vector2(cos(a + 0.22), sin(a + 0.22)) * 12.0
		var r := c + Vector2(cos(a - 0.22), sin(a - 0.22)) * 12.0
		e.draw_colored_polygon(PackedVector2Array([l, tip, r, c]), Color(GOLD, 0.9 if k % 2 == 0 else 0.6))
	e.draw_arc(c, 44.0, 0, TAU, 64, Color(GOLD, 0.5), 2.0, true)
	e.draw_circle(c, 9.0, Color(0.85, 0.7, 1.0))
	e.draw_circle(c, 5.0, Color(1, 1, 1))
	e.queue_redraw()


func _motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(960, 1120)
	p.amount = 70
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1000, 20)
	p.direction = Vector2(0, -1)
	p.spread = 15.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.85, 0.7, 1.0, 0.0), Color(0.95, 0.85, 1.0, 0.8), Color(1.0, 0.9, 0.7, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = ramp
	return p
