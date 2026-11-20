extends Node
## Player preferences, persisted to user://settings.cfg.

signal changed

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH }

var quality: int = Quality.HIGH
var music_volume := 0.7
var sfx_volume := 0.9
var control_scale := 1.0  ## 0.7 .. 1.4, multiplies every on-screen control
var control_opacity := 0.85
var left_handed := false  ## swap the stick and the action buttons
var camera_zoom := 1.0  ## 0.8 .. 1.25 on top of the screen-fitted zoom
var screen_shake := true
var show_fps := false
## Per-control offsets set in the layout editor: name -> Vector2 (fraction of screen).
var control_offsets := {}


func _ready() -> void:
	load_settings()
	_apply_audio()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		_detect_quality()
		return
	quality = config.get_value("graphics", "quality", quality)
	camera_zoom = config.get_value("graphics", "camera_zoom", camera_zoom)
	screen_shake = config.get_value("graphics", "screen_shake", screen_shake)
	show_fps = config.get_value("graphics", "show_fps", show_fps)
	music_volume = config.get_value("audio", "music", music_volume)
	sfx_volume = config.get_value("audio", "sfx", sfx_volume)
	control_scale = config.get_value("controls", "scale", control_scale)
	control_opacity = config.get_value("controls", "opacity", control_opacity)
	left_handed = config.get_value("controls", "left_handed", left_handed)
	control_offsets = config.get_value("controls", "offsets", control_offsets)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "quality", quality)
	config.set_value("graphics", "camera_zoom", camera_zoom)
	config.set_value("graphics", "screen_shake", screen_shake)
	config.set_value("graphics", "show_fps", show_fps)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("controls", "scale", control_scale)
	config.set_value("controls", "opacity", control_opacity)
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
		quality = Quality.MEDIUM if cores >= 8 else Quality.LOW
	else:
		quality = Quality.HIGH


func _apply_audio() -> void:
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if music >= 0:
		AudioServer.set_bus_volume_db(music, linear_to_db(maxf(music_volume, 0.0001)))
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(sfx_volume, 0.0001)))


## How many light-map updates per second the quality level affords.
func light_rate() -> float:
	return [6.0, 12.0, 20.0][quality]


## Particle budget multiplier.
func particle_scale() -> float:
	return [0.35, 0.7, 1.0][quality]
