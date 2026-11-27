class_name Weather3D
extends Node3D
## Regional weather. Each region draws spells of weather from its own table
## (Greenwood: clear, showers, the odd thunderstorm; Gloomwood: mist and
## drizzle; Frostpeaks: snow and blizzards; Sunscar: sandstorms; Ashlands:
## falling ash and embers; the Blight: violet motes rising and void storms).
## A spell lasts a few minutes, then a new one is drawn; crossing into
## another region draws at once. Everything eases in and out.
##   kind / amount       current weather and how strong (0..1)
##   fog_extra, fog_tint (rgb + weight), sun_mul, cloud_cover   read by Main3D
##   force(kind)         pin a weather (capture harness, tests)

enum Kind { CLEAR, RAIN, STORM, MIST, SNOW, BLIZZARD, SANDSTORM, ASHFALL, VOIDMOTES }

const NAMES := ["Clear", "Rain", "Thunderstorm", "Mist", "Snow", "Blizzard", "Sandstorm", "Ashfall", "Void motes"]

## Region -> [[kind, weight], ...]
const TABLE := {
	TerrainGen.Biome.FOREST: [[Kind.CLEAR, 6], [Kind.RAIN, 2], [Kind.STORM, 1]],
	TerrainGen.Biome.BEACH: [[Kind.CLEAR, 5], [Kind.RAIN, 1]],
	TerrainGen.Biome.DARK_FOREST: [[Kind.MIST, 4], [Kind.RAIN, 3], [Kind.CLEAR, 1]],
	TerrainGen.Biome.SNOW: [[Kind.SNOW, 5], [Kind.BLIZZARD, 2], [Kind.CLEAR, 2]],
	TerrainGen.Biome.DRY: [[Kind.CLEAR, 4], [Kind.SANDSTORM, 2]],
	TerrainGen.Biome.VOLCANIC: [[Kind.ASHFALL, 5], [Kind.CLEAR, 1]],
	TerrainGen.Biome.CORRUPTED: [[Kind.VOIDMOTES, 5], [Kind.STORM, 1]],
}

## kind -> [fog_extra, fog tint (a = weight), sun_mul, cloud_cover]
const LOOK := {
	Kind.CLEAR: [0.0, Color(0, 0, 0, 0), 1.0, 0.42],
	Kind.RAIN: [0.0035, Color(0.55, 0.6, 0.68, 0.55), 0.55, 0.85],
	Kind.STORM: [0.005, Color(0.38, 0.4, 0.5, 0.7), 0.35, 0.97],
	Kind.MIST: [0.009, Color(0.62, 0.72, 0.72, 0.7), 0.7, 0.7],
	Kind.SNOW: [0.004, Color(0.86, 0.9, 0.98, 0.6), 0.75, 0.8],
	Kind.BLIZZARD: [0.016, Color(0.9, 0.93, 1.0, 0.85), 0.5, 0.98],
	Kind.SANDSTORM: [0.014, Color(0.86, 0.68, 0.45, 0.85), 0.6, 0.6],
	Kind.ASHFALL: [0.006, Color(0.45, 0.4, 0.4, 0.7), 0.6, 0.9],
	Kind.VOIDMOTES: [0.0025, Color(0.45, 0.32, 0.62, 0.6), 0.8, 0.6],
}

var game: Node
var kind: int = Kind.CLEAR
var amount := 0.0
var fog_extra := 0.0
var fog_tint := Color(0, 0, 0, 0)
var sun_mul := 1.0
var cloud_cover := 0.42
var flash := 0.0               ## lightning, 0..1, decays fast

var _target_kind: int = Kind.CLEAR
var _region := -2
var _spell := 0.0
var _forced := false
var _bolt_in := 6.0
var _thunder := -1.0
var _fx := {}                  ## name -> CPUParticles3D
var _rain_sound: AudioStreamPlayer
var _scale := 1.0


func setup(the_game: Node) -> void:
	game = the_game
	_scale = [0.35, 0.6, 1.0, 1.3][clampi(Settings.quality, 0, 3)]
	_fx.rain = _make("rain", Vector2(0.022, 0.75), Color(0.75, 0.82, 0.95, 0.55), false, 900)
	_fx.snow = _make("snow", Vector2(0.07, 0.07), Color(1, 1, 1, 0.9), true, 700)
	_fx.dust = _make("dust", Vector2(0.06, 0.035), Color(0.9, 0.74, 0.5, 0.75), true, 900)
	_fx.ash = _make("ash", Vector2(0.06, 0.06), Color(0.42, 0.4, 0.4, 0.85), true, 500)
	_fx.ember = _make("ember", Vector2(0.05, 0.05), Color(1.0, 0.5, 0.18, 1.0), true, 80, true)
	_fx.motes = _make("motes", Vector2(0.07, 0.07), Color(0.72, 0.45, 1.0, 1.0), true, 160, true)
	_rain_sound = AudioStreamPlayer.new()
	_rain_sound.stream = load("res://assets/audio/ambience/rain.ogg")
	_rain_sound.volume_db = -60.0
	_rain_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_rain_sound)


func force(k: int) -> void:
	_forced = true
	_target_kind = k
	kind = k
	amount = 1.0


func region_weather_name() -> String:
	return NAMES[kind] if amount > 0.3 else NAMES[Kind.CLEAR]


func _make(id: String, size: Vector2, col: Color, flake: bool, count: int, glow := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = id
	var q := QuadMesh.new()
	q.size = size
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if flake else BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	if flake:
		m.albedo_texture = Play3D._spark_texture()
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	p.amount = maxi(16, int(count * _scale))
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.set_meta("alpha", col.a)
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	match id:
		"rain":
			p.emission_box_extents = Vector3(14, 0.2, 14)
			p.direction = Vector3(0.08, -1, 0.04)
			p.spread = 2.0
			p.initial_velocity_min = 17.0
			p.initial_velocity_max = 21.0
			p.gravity = Vector3(0, -6, 0)
			p.lifetime = 1.0
		"snow":
			p.emission_box_extents = Vector3(16, 0.2, 16)
			p.direction = Vector3(0.3, -1, 0.1)
			p.spread = 30.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 1.8
			p.gravity = Vector3(0.25, -0.5, 0.1)
			p.lifetime = 7.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
		"dust":
			p.emission_box_extents = Vector3(18, 3.0, 18)
			p.direction = Vector3(1, 0.05, 0.35)
			p.spread = 8.0
			p.initial_velocity_min = 9.0
			p.initial_velocity_max = 14.0
			p.gravity = Vector3.ZERO
			p.lifetime = 2.6
			p.scale_amount_min = 0.6
			p.scale_amount_max = 2.0
		"ash":
			p.emission_box_extents = Vector3(16, 0.2, 16)
			p.direction = Vector3(0.2, -1, 0.15)
			p.spread = 35.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.2
			p.gravity = Vector3(0.15, -0.35, 0)
			p.lifetime = 9.0
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.2
		"ember", "motes":
			p.emission_box_extents = Vector3(12, 1.5, 12)
			p.direction = Vector3.UP
			p.spread = 25.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.9
			p.gravity = Vector3(0, 0.2, 0)
			p.lifetime = 5.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
			var ramp := Gradient.new()
			ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
			ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
			p.color_ramp = ramp
	add_child(p)
	return p


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p: Vector3 = game.player.global_position
	var region: int = game.world.biome_at(p)
	if not _forced:
		_spell -= delta
		if region != _region or _spell <= 0.0:
			_region = region
			_spell = randf_range(150.0, 300.0)
			_target_kind = _draw(region)
	# Ease out the old weather, switch, ease in the new.
	if kind != _target_kind:
		amount = move_toward(amount, 0.0, delta / 6.0)
		if amount <= 0.0:
			kind = _target_kind
	else:
		amount = move_toward(amount, 1.0, delta / 10.0)
	var look: Array = LOOK[kind]
	var clear: Array = LOOK[Kind.CLEAR]
	fog_extra = lerpf(0.0, float(look[0]), amount)
	fog_tint = look[1]
	fog_tint.a *= amount
	sun_mul = lerpf(1.0, float(look[2]), amount)
	cloud_cover = lerpf(float(clear[3]), float(look[3]), amount)
	_place(p)
	_set_fx("rain", kind == Kind.RAIN or kind == Kind.STORM, 0.75 if kind == Kind.RAIN else 1.0)
	_set_fx("snow", kind == Kind.SNOW or kind == Kind.BLIZZARD, 1.0)
	_set_fx("dust", kind == Kind.SANDSTORM, 1.0)
	_set_fx("ash", kind == Kind.ASHFALL, 1.0)
	_set_fx("ember", kind == Kind.ASHFALL, 1.0)
	_set_fx("motes", kind == Kind.VOIDMOTES, 1.0)
	# Blizzards drive the snow sideways.
	(_fx.snow as CPUParticles3D).gravity = Vector3(6.0, -1.2, 1.5) if kind == Kind.BLIZZARD else Vector3(0.25, -0.5, 0.1)
	var wet := kind == Kind.RAIN or kind == Kind.STORM
	var want_db := linear_to_db(maxf(0.0001, amount * (0.55 if kind == Kind.RAIN else 0.8))) if wet else -60.0
	_rain_sound.volume_db = move_toward(_rain_sound.volume_db, want_db, delta * 20.0)
	if _rain_sound.volume_db > -50.0 and not _rain_sound.playing:
		_rain_sound.play()
	elif _rain_sound.volume_db <= -55.0 and _rain_sound.playing:
		_rain_sound.stop()
	_lightning(delta)


func _draw(region: int) -> int:
	var table: Array = TABLE.get(region, [[Kind.CLEAR, 1]])
	var total := 0
	for e in table:
		total += int(e[1])
	var r := randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return int(e[0])
	return Kind.CLEAR


## The emitters ride above the camera (and a little ahead of it).
func _place(p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam else p
	var fwd := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	fwd.y = 0.0
	var at := c + fwd.normalized() * 6.0
	(_fx.rain as Node3D).global_position = at + Vector3(0, 13, 0)
	(_fx.snow as Node3D).global_position = at + Vector3(0, 9, 0)
	(_fx.ash as Node3D).global_position = at + Vector3(0, 9, 0)
	(_fx.dust as Node3D).global_position = at + Vector3(-12, 1.5, -4)
	(_fx.ember as Node3D).global_position = Vector3(at.x, p.y + 0.5, at.z)
	(_fx.motes as Node3D).global_position = Vector3(at.x, p.y + 0.8, at.z)


func _set_fx(id: String, on: bool, strength: float) -> void:
	var fx: CPUParticles3D = _fx[id]
	var live := on and amount > 0.02
	if fx.emitting != live:
		fx.emitting = live
	var m := fx.material_override as StandardMaterial3D
	m.albedo_color.a = float(fx.get_meta("alpha")) * clampf(amount * 1.2, 0.0, 1.0) * strength


func _lightning(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 5.0)
	if _thunder > 0.0:
		_thunder -= delta
		if _thunder <= 0.0:
			Sfx.play("thunder_close" if randf() < 0.4 else "thunder_far", -4.0, 0.1)
	if kind != Kind.STORM or amount < 0.6:
		return
	_bolt_in -= delta
	if _bolt_in <= 0.0:
		_bolt_in = randf_range(7.0, 18.0)
		flash = 1.0
		_thunder = randf_range(0.4, 2.2)
