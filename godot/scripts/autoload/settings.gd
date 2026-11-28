extends Node
## Player preferences, persisted to user://settings.cfg.
##
## Graphics has four presets, each of which sets six separate controls.
## Every control switches a real system: nothing here is decorative.
##
##   lighting     light-map rate and lantern detail        (0 low .. 3 ultra)
##   particles    particle budgets and ambient particles   (0 .. 3)
##   shader_fx    terrain relief, water, heat, underwater   (0 .. 3)
##   background   parallax depth layers, mist, light shafts (0 .. 3)
##   shadows      soft shadows under creatures and objects  (on/off)
##   bloom        additive glow around lights               (on/off)
##   weather      rain, snow and falling leaves              (on/off)

signal changed

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const PRESET_NAMES := ["Low", "Medium", "High", "Ultra"]
## preset -> [lighting, particles, shader_fx, background, shadows, bloom, weather]
const PRESETS := [
	[0, 0, 0, 0, false, false, false],
	[1, 1, 1, 1, true, true, true],
	[2, 2, 2, 2, true, true, true],
	[3, 3, 3, 3, true, true, true],
]

var quality: int = Quality.HIGH
var lighting := 2
var particles := 2
var shader_fx := 2
var background := 2
var shadows := true
var bloom := true
var weather := true
## Rigged 3D characters (on) or the flat cut-out rig (off, for weak phones).
var characters_3d := true
## The player is the 3D hooded hero (false: the hand-drawn cut-out hero).
var player_3d := true

var master_volume := 1.0
var music_volume := 0.7
var ambient_volume := 0.8
var sfx_volume := 0.9
var voice_volume := 1.0
var control_scale := 1.0  ## 0.7 .. 1.4, multiplies every on-screen control
var control_opacity := 0.85
## Camera turn speed, touch drag and mouse alike (0.4 .. 2.0).
var look_sensitivity := 1.0
var left_handed := false  ## swap the stick and the action buttons
var camera_zoom := 1.0  ## 0.8 .. 1.25 on top of the screen-fitted zoom
var screen_shake := true
var show_fps := false
## Frames per second cap: 30 saves battery and heat on phones, 0 = none.
var fps_cap := 60
## Adaptive resolution: when frames run long for a few seconds the 3D view
## renders a little smaller (down to half), and grows back with headroom.
var adaptive_res := true
## 3D resolution scale (0.5 .. 1.0): the world renders smaller and is
## stretched to the screen; the UI stays sharp.
var render_scale := 1.0
## Screen-space ambient occlusion from the depth buffer (contact shadows).
var ao := true
## Crepuscular rays from the sun past trees and cliffs.
var sun_shafts := true
## Streamed land around her: 0 near .. 3 farthest (rings of terrain chunks).
var view_distance := 2
## Anti-aliasing: 0 off, 1 FXAA, 2 MSAA 2x, 3 MSAA 4x.
var antialiasing := 3
const PRESET_AO := [false, false, true, true]
const PRESET_SHAFTS := [false, false, true, true]
const PRESET_VIEW := [0, 1, 2, 3]
const PRESET_AA := [1, 1, 3, 3]
const PRESET_SCALE := [0.6, 0.75, 0.9, 1.0]
## Per preset: how far scenery, flora and props draw (a multiplier on each
## object's own range; landmarks keep their long ranges), the sun's shadow
## reach / cascades / map size / softness, and how eagerly meshes step down
## a level of detail (pixels of error allowed).
const PRESET_DRAW := [0.65, 0.85, 1.0, 1.3]
const PRESET_SHADOW_DIST := [0.0, 50.0, 90.0, 140.0]
const PRESET_SHADOW_SPLITS := [1, 1, 2, 2]
const PRESET_SHADOW_MAP := [1024, 1024, 2048, 4096]
const PRESET_SHADOW_SOFT := [0, 0, 1, 2]
const PRESET_LOD := [4.0, 2.5, 1.5, 1.0]


## Draw distance for something whose full-detail range is `metres`.
func draw(metres: float) -> float:
	return metres * PRESET_DRAW[clampi(quality, 0, 3)]


## The sun's shadows for the current preset (shadows off: Low, or the toggle).
func apply_sun(sun: DirectionalLight3D) -> void:
	var q := clampi(quality, 0, 3)
	sun.shadow_enabled = shadows and PRESET_SHADOW_DIST[q] > 0.0
	sun.directional_shadow_max_distance = maxf(PRESET_SHADOW_DIST[q], 40.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if PRESET_SHADOW_SPLITS[q] == 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_split_1 = 0.18
	RenderingServer.directional_shadow_atlas_set_size(PRESET_SHADOW_MAP[q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([
		RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW][PRESET_SHADOW_SOFT[q]])
var debug_collision := false
## Per-control offsets set in the layout editor: name -> Vector2 (fraction of screen).
var control_offsets := {}


func _ready() -> void:
	_migrate_user_dir()
	load_settings()
	_apply_audio()


## The game was renamed (Lanternbound -> Ethereal Tales). On Android the
## save folder belongs to the package id, which did not change. On desktop
## the folder is named after the game, so the old one's settings, accounts
## and journeys are copied over once (never overwriting newer files).
static func _migrate_user_dir() -> void:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return
	var now := OS.get_user_data_dir()
	var old := now.get_base_dir().path_join("Lanternbound")
	if old == now or not DirAccess.dir_exists_absolute(old) or FileAccess.file_exists(now.path_join(".migrated")):
		return
	_copy_tree(old, now)
	var f := FileAccess.open(now.path_join(".migrated"), FileAccess.WRITE)
	if f:
		f.store_string("from " + old)


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for file in DirAccess.get_files_at(from):
		if not FileAccess.file_exists(to.path_join(file)):
			DirAccess.copy_absolute(from.path_join(file), to.path_join(file))
	for sub in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(sub), to.path_join(sub))


## Apply a preset to every graphics control.
func apply_preset(preset: int) -> void:
	quality = clampi(preset, 0, 3)
	var p: Array = PRESETS[quality]
	lighting = p[0]
	particles = p[1]
	shader_fx = p[2]
	background = p[3]
	shadows = p[4]
	bloom = p[5]
	weather = p[6]
	render_scale = PRESET_SCALE[quality]
	ao = PRESET_AO[quality]
	sun_shafts = PRESET_SHAFTS[quality]
	view_distance = PRESET_VIEW[quality]
	antialiasing = PRESET_AA[quality]
	# Low: a steady 30 beats a ragged 60 on a phone that cannot hold it.
	fps_cap = 30 if quality == Quality.LOW else 60


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		_detect_quality()
		return
	# Older saves stored only a 0..2 quality; that still names a preset.
	apply_preset(config.get_value("graphics", "quality", quality))
	lighting = config.get_value("graphics", "lighting", lighting)
	particles = config.get_value("graphics", "particles", particles)
	shader_fx = config.get_value("graphics", "shader_fx", shader_fx)
	background = config.get_value("graphics", "background", background)
	shadows = config.get_value("graphics", "shadows", shadows)
	bloom = config.get_value("graphics", "bloom", bloom)
	weather = config.get_value("graphics", "weather", weather)
	camera_zoom = config.get_value("graphics", "camera_zoom", camera_zoom)
	screen_shake = config.get_value("graphics", "screen_shake", screen_shake)
	show_fps = config.get_value("graphics", "show_fps", show_fps)
	fps_cap = config.get_value("graphics", "fps_cap", fps_cap)
	adaptive_res = config.get_value("graphics", "adaptive_res", adaptive_res)
	render_scale = config.get_value("graphics", "render_scale", render_scale)
	ao = config.get_value("graphics", "ao", ao)
	sun_shafts = config.get_value("graphics", "sun_shafts", sun_shafts)
	view_distance = config.get_value("graphics", "view_distance", view_distance)
	antialiasing = config.get_value("graphics", "antialiasing", antialiasing)
	debug_collision = config.get_value("graphics", "debug_collision", debug_collision)
	music_volume = config.get_value("audio", "music", music_volume)
	master_volume = config.get_value("audio", "master", master_volume)
	ambient_volume = config.get_value("audio", "ambient", ambient_volume)
	sfx_volume = config.get_value("audio", "sfx", sfx_volume)
	voice_volume = config.get_value("audio", "voice", voice_volume)
	control_scale = config.get_value("controls", "scale", control_scale)
	control_opacity = config.get_value("controls", "opacity", control_opacity)
	look_sensitivity = config.get_value("controls", "look_sensitivity", look_sensitivity)
	left_handed = config.get_value("controls", "left_handed", left_handed)
	control_offsets = config.get_value("controls", "offsets", control_offsets)


## Frame cap and 3D resolution onto a viewport (the game's own).
func apply_display(vp: Viewport) -> void:
	Engine.max_fps = fps_cap
	vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(antialiasing, 0, 3)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if antialiasing == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	# A mesh steps down a level of detail when the change would move it by
	# less than this many pixels: 2 is invisible on a phone's dense screen.
	var lod: float = PRESET_LOD[clampi(quality, 0, 3)]
	vp.mesh_lod_threshold = maxf(lod, 2.0) if OS.has_feature("mobile") and quality < 3 else lod


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "lighting", lighting)
	config.set_value("graphics", "particles", particles)
	config.set_value("graphics", "shader_fx", shader_fx)
	config.set_value("graphics", "background", background)
	config.set_value("graphics", "shadows", shadows)
	config.set_value("graphics", "bloom", bloom)
	config.set_value("graphics", "weather", weather)
	config.set_value("graphics", "camera_zoom", camera_zoom)
	config.set_value("graphics", "screen_shake", screen_shake)
	config.set_value("graphics", "show_fps", show_fps)
	config.set_value("graphics", "fps_cap", fps_cap)
	config.set_value("graphics", "adaptive_res", adaptive_res)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "ao", ao)
	config.set_value("graphics", "sun_shafts", sun_shafts)
	config.set_value("graphics", "view_distance", view_distance)
	config.set_value("graphics", "antialiasing", antialiasing)
	config.set_value("graphics", "debug_collision", debug_collision)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "ambient", ambient_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("audio", "voice", voice_volume)
	config.set_value("controls", "scale", control_scale)
	config.set_value("controls", "opacity", control_opacity)
	config.set_value("controls", "look_sensitivity", look_sensitivity)
	config.set_value("controls", "left_handed", left_handed)
	config.set_value("controls", "offsets", control_offsets)
	config.save(PATH)
	_apply_audio()
	changed.emit()


func _detect_quality() -> void:
	# First launch: guess from the device. Phones with few cores get the
	# light settings until the player says otherwise.
	var cores := OS.get_processor_count()
	if OS.has_feature("mobile"):
		# The full look on phones that can carry it (character and grass
		# LODs, cheaper shafts and one bloom made High affordable).
		apply_preset(Quality.HIGH if cores >= 8 else (Quality.MEDIUM if cores >= 6 else Quality.LOW))
	else:
		apply_preset(Quality.HIGH)


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	var amb := AudioServer.get_bus_index("Ambient")
	if amb >= 0:
		AudioServer.set_bus_volume_db(amb, linear_to_db(maxf(ambient_volume, 0.0001)))
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))
	var voice := AudioServer.get_bus_index("Voice")
	if voice >= 0:
		AudioServer.set_bus_volume_db(voice, linear_to_db(maxf(voice_volume, 0.0001)))


## How many light-map updates per second the lighting level affords.
func light_rate() -> float:
	return [6.0, 12.0, 20.0, 30.0][lighting]


## Particle budget multiplier.
func particle_scale() -> float:
	return [0.3, 0.6, 1.0, 1.4][particles]


## How many creatures may roam at once.
func enemy_cap() -> int:
	return [4, 6, 8, 9][quality]
