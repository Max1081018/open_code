extends Node3D
## Lazy Lake — a calm, funny, low-poly first-person fishing game.
##
## Loop: HOLD the button to charge a cast, release to fling the bobber out, wait
## for a bite, TAP to hook it, then HOLD to reel while keeping the line tension
## out of the red. Land it and a goofy fish pops up with its name and weight.
##
## Everything (island, water, rod, fish, sounds) is generated in code from
## primitives and sine-wave shaders, so there are no assets to import.
##
## Headless self-test (game/tools/play.sh calls this):
##   godot --path fishing -- --autotest --frames=1800 --shot=out.png
## plays several full casts with synthetic input, screenshots, and prints
## "AUTOTEST ..." before quitting.

const Hud := preload("res://hud.gd")

# Shared wave parameters — MUST match water.gdshader so the bobber sits on the
# surface instead of floating above or sinking through it.
const WAVE_SPEED := 0.9
const WAVE_HEIGHT := 0.16

const DOCK_TIP := Vector3(0, 0, 4)       # end of the jetty, where we stand
const EYE := Vector3(0, 2.1, 5.2)        # camera position
const MIN_CAST := 9.0
const MAX_CAST := 40.0

var camera: Camera3D
var rod: Node3D
var rod_tip: Marker3D
var line: MeshInstance3D
var bobber: Node3D
var hud
var caught_fish: Node3D

var players := {}  # name -> AudioStreamPlayer
var reel_click_t := 0.0

# Fish table: name, colour, weight range (kg). A few junk "catches" for laughs.
var fish_table := [
	{"name": "Dizzy Perch", "color": Color(0.5, 0.8, 0.4), "min": 0.2, "max": 1.1, "junk": false},
	{"name": "Grumpy Carp", "color": Color(0.8, 0.6, 0.3), "min": 0.8, "max": 3.5, "junk": false},
	{"name": "Rubber Trout", "color": Color(0.9, 0.4, 0.5), "min": 0.4, "max": 2.0, "junk": false},
	{"name": "Lord Bassington", "color": Color(0.3, 0.5, 0.7), "min": 1.5, "max": 5.0, "junk": false},
	{"name": "Tiny Terror", "color": Color(0.95, 0.75, 0.2), "min": 0.05, "max": 0.3, "junk": false},
	{"name": "a Soggy Boot", "color": Color(0.3, 0.25, 0.22), "min": 0.6, "max": 0.9, "junk": true},
	{"name": "an Old Tin Can", "color": Color(0.6, 0.62, 0.65), "min": 0.2, "max": 0.4, "junk": true},
]

enum { IDLE, CHARGING, FLYING, WAITING, BITE, FIGHT, CAUGHT, SNAP }
var state := IDLE
var power := 0.0
var elapsed := 0.0

var cast_from := Vector3.ZERO
var cast_to := Vector3.ZERO
var flight_t := 0.0

var bite_timer := 0.0
var bite_window := 0.0

var distance := 1.0
var tension := 0.0
var lunge_timer := 0.0
var fish_strength := 1.0
var pending_fish := {}

var catches := 0
var best_weight := 0.0
var best_name := ""

# Autotest
var autotest := false
var autotest_frames := 1800
var autotest_shot := ""
var shot_on := "end"  # "end" or "caught": when to grab the screenshot
var sim_action := false
var sim_tap := false
var frame := 0


func _ready() -> void:
	_parse_args()
	if autotest:
		seed(7)
	else:
		randomize()
	_build_world()
	_build_player_view()
	_build_sounds()
	hud = Hud.new()
	add_child(hud)
	_enter_idle()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest": autotest = true
		elif a.begins_with("--frames="): autotest_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--shot="): autotest_shot = a.get_slice("=", 1)
		elif a.begins_with("--shot-on="): shot_on = a.get_slice("=", 1)


# --- Wave height (mirror of the shader) --------------------------------------

func wave_height(x: float, z: float) -> float:
	var t := elapsed * WAVE_SPEED
	var h := sin(x * 0.60 + t) * 0.5 + sin(z * 0.80 + t * 1.3) * 0.5 + sin((x + z) * 0.40 + t * 0.7) * 0.5
	return h * WAVE_HEIGHT


# --- World --------------------------------------------------------------------

func _mat(color: Color, rough := 0.9, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color)
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	# Sky + warm light.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.86)
	sky_mat.sky_horizon_color = Color(0.85, 0.9, 0.95)
	sky_mat.ground_horizon_color = Color(0.85, 0.9, 0.95)
	sky_mat.ground_bottom_color = Color(0.6, 0.72, 0.8)
	sky_mat.sun_angle_max = 40.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.74)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.82, 0.92)
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 40, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	# Water: a big subdivided plane with the wave shader.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	plane.subdivide_width = 90
	plane.subdivide_depth = 90
	var smat := ShaderMaterial.new()
	smat.shader = load("res://water.gdshader")
	smat.set_shader_parameter("wave_speed", WAVE_SPEED)
	smat.set_shader_parameter("wave_height", WAVE_HEIGHT)
	plane.material = smat
	water.mesh = plane
	water.position = Vector3(0, 0, -20)
	add_child(water)

	_build_island()
	_build_scenery()


func _build_island() -> void:
	# The island/shore sits behind the camera (positive Z) so we look out over
	# open water. Grass cap + dirt underside for a floating low-poly look.
	var grass := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 11.0
	gc.bottom_radius = 11.0
	gc.height = 1.2
	gc.radial_segments = 9
	gc.material = _mat(Color(0.42, 0.72, 0.36))
	grass.mesh = gc
	grass.position = Vector3(0, -0.6, 12)
	add_child(grass)

	var dirt := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 10.0
	dc.bottom_radius = 3.0
	dc.height = 6.0
	dc.radial_segments = 9
	dc.material = _mat(Color(0.46, 0.33, 0.22))
	dirt.mesh = dc
	dirt.position = Vector3(0, -4.0, 12)
	add_child(dirt)

	# Wooden jetty reaching out to where we stand.
	for i in 4:
		_box(self, Vector3(0, -0.05, 9.0 - i * 1.6), Vector3(2.2, 0.25, 1.4), Color(0.62, 0.45, 0.28))
	# Posts at the tip.
	_box(self, Vector3(-1.0, -0.4, 4.0), Vector3(0.25, 1.4, 0.25), Color(0.5, 0.36, 0.22))
	_box(self, Vector3(1.0, -0.4, 4.0), Vector3(0.25, 1.4, 0.25), Color(0.5, 0.36, 0.22))


func _tree(pos: Vector3, scale := 1.0) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18 * scale
	tm.bottom_radius = 0.26 * scale
	tm.height = 1.6 * scale
	tm.material = _mat(Color(0.45, 0.32, 0.2))
	trunk.mesh = tm
	trunk.position = pos + Vector3(0, 0.8 * scale, 0)
	add_child(trunk)
	for k in 3:
		var leaf := MeshInstance3D.new()
		var lm := CylinderMesh.new()  # cone = top_radius 0
		lm.top_radius = 0.0
		lm.bottom_radius = (1.1 - k * 0.22) * scale
		lm.height = 1.1 * scale
		lm.radial_segments = 6
		lm.material = _mat(Color(0.26, 0.56, 0.3).lerp(Color(0.4, 0.7, 0.4), k / 3.0))
		leaf.mesh = lm
		leaf.position = pos + Vector3(0, (1.6 + k * 0.6) * scale, 0)
		add_child(leaf)


func _build_scenery() -> void:
	# A couple of trees on our island (off to the sides, behind the camera).
	_tree(Vector3(-6, -0.1, 14), 1.1)
	_tree(Vector3(5.5, -0.1, 15), 0.9)
	_tree(Vector3(-2, -0.1, 17), 1.0)

	# Distant low-poly islets across the lake for depth.
	for spot in [Vector3(-34, 0, -40), Vector3(30, 0, -52), Vector3(-8, 0, -70)]:
		var islet := MeshInstance3D.new()
		var im := CylinderMesh.new()
		im.top_radius = randf_range(5, 9)
		im.bottom_radius = randf_range(2, 4)
		im.height = 5.0
		im.radial_segments = 7
		im.material = _mat(Color(0.4, 0.6, 0.45))
		islet.mesh = im
		islet.position = spot + Vector3(0, -1.0, 0)
		add_child(islet)
		_tree(spot + Vector3(0, 1.5, 0), randf_range(1.4, 2.2))

	# A funny rubber duck bobbing nearby.
	var duck := _make_duck()
	duck.position = Vector3(-4.5, 0, -2)
	add_child(duck)
	duck.set_meta("duck", true)


func _make_duck() -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.5
	bm.height = 0.8
	bm.material = _mat(Color(1.0, 0.85, 0.1))
	body.mesh = bm
	n.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	hm.material = bm.material
	head.mesh = hm
	head.position = Vector3(0, 0.45, 0.25)
	n.add_child(head)
	var beak := _box(n, Vector3(0, 0.45, 0.55), Vector3(0.18, 0.1, 0.22), Color(0.95, 0.5, 0.1))
	return n


# --- Player view: camera, rod, line, bobber ----------------------------------

func _build_player_view() -> void:
	camera = Camera3D.new()
	camera.fov = 62
	camera.position = EYE
	camera.rotation_degrees = Vector3(-6, 0, 0)  # look slightly down at the water
	add_child(camera)

	# First-person rod, held in the bottom-right, angled out over the water.
	rod = Node3D.new()
	camera.add_child(rod)
	rod.position = Vector3(0.6, -0.5, -0.8)
	rod.rotation_degrees = Vector3(28, -8, -10)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.012
	pm.bottom_radius = 0.045
	pm.height = 2.6
	pm.material = _mat(Color(0.15, 0.12, 0.12), 0.5)
	pole.mesh = pm
	pole.position = Vector3(0, 0, -1.3)
	pole.rotation_degrees = Vector3(90, 0, 0)  # lay it along -Z
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no weird line on the water
	rod.add_child(pole)
	# Handle grip.
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.05
	gm.bottom_radius = 0.05
	gm.height = 0.4
	gm.material = _mat(Color(0.3, 0.2, 0.1), 0.7)
	grip.mesh = gm
	grip.rotation_degrees = Vector3(90, 0, 0)
	grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rod.add_child(grip)
	rod_tip = Marker3D.new()
	rod_tip.position = Vector3(0, 0, -2.6)
	rod.add_child(rod_tip)

	# The line (updated every frame).
	line = MeshInstance3D.new()
	line.material_override = _mat(Color(0.95, 0.95, 0.95), 0.4)
	add_child(line)

	# Bobber: classic red-over-white.
	bobber = Node3D.new()
	var top := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 0.16
	tsm.height = 0.32
	tsm.material = _mat(Color(0.9, 0.2, 0.2))
	top.mesh = tsm
	top.position = Vector3(0, 0.08, 0)
	bobber.add_child(top)
	var bot := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.16
	bsm.height = 0.32
	bsm.material = _mat(Color(0.95, 0.95, 0.95))
	bot.mesh = bsm
	bot.position = Vector3(0, -0.08, 0)
	bobber.add_child(bot)
	add_child(bobber)
	bobber.visible = false


# --- Sound --------------------------------------------------------------------

func _build_sounds() -> void:
	var streams := {
		"whoosh": Sfx.whoosh(), "splash": Sfx.splash(), "bite": Sfx.bite(),
		"click": Sfx.click(), "caught": Sfx.caught(), "snap": Sfx.snap(),
	}
	for key in streams:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		add_child(p)
		players[key] = p


func _play(key: String) -> void:
	if players.has(key):
		players[key].play()


# --- State helpers ------------------------------------------------------------

func _enter_idle() -> void:
	state = IDLE
	power = 0.0
	bobber.visible = false
	hud.mode = Hud.M_IDLE
	hud.message = ""
	hud.power = 0.0
	hud.distance = 1.0
	hud.tension = 0.0
	if caught_fish:
		caught_fish.queue_free()
		caught_fish = null
	_update_info()


func _update_info() -> void:
	var s := "Catches: %d" % catches
	if best_name != "":
		s += "   Best: %s (%.2f kg)" % [best_name, best_weight]
	hud.info = s


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	if autotest:
		_autotest(delta)

	var action: bool = hud.action_down() or sim_action
	var tap: bool = hud.consume_tap() or sim_tap
	sim_tap = false

	match state:
		IDLE, CHARGING:
			if action:
				state = CHARGING
				hud.mode = Hud.M_CHARGING
				power = min(power + delta * 1.1, 1.0)
				hud.power = power
				hud.message = ""
			elif power > 0.0:
				_do_cast(power)
		FLYING:
			_update_flight(delta)
		WAITING:
			_update_bobber()
			bite_timer -= delta
			if bite_timer <= 0.0:
				_start_bite()
		BITE:
			_update_bobber()
			bite_window -= delta
			if tap:
				_hook_fish()
			elif bite_window <= 0.0:
				hud.message = "...it got away"
				_play("splash")
				await_then_idle(1.0)
		FIGHT:
			_update_fight(delta, action)
			_update_bobber()
		CAUGHT, SNAP:
			if caught_fish:
				caught_fish.rotation.y += delta * 1.5
				caught_fish.position.y = lerpf(caught_fish.position.y, _fish_display_y, delta * 4.0)
			if tap:
				_enter_idle()

	_update_line()
	_hud_sync()


var _idle_delay := 0.0
func await_then_idle(t: float) -> void:
	_idle_delay = t
	state = -1 as int  # transient; handled below
	set_process(true)


func _physics_process(_d: float) -> void:
	# Handle the little post-message pause without a coroutine.
	if _idle_delay > 0.0:
		_idle_delay -= get_physics_process_delta_time()
		if _idle_delay <= 0.0:
			_enter_idle()


func _hud_sync() -> void:
	hud.distance = distance
	hud.tension = tension


# --- Casting ------------------------------------------------------------------

func _do_cast(p: float) -> void:
	var dist: float = lerpf(MIN_CAST, MAX_CAST, p)
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	# Slight random spread so no two casts land the same.
	fwd = fwd.rotated(Vector3.UP, randf_range(-0.12, 0.12))
	cast_from = rod_tip.global_position
	cast_to = DOCK_TIP + fwd * dist
	cast_to.y = 0.0
	flight_t = 0.0
	state = FLYING
	power = 0.0
	bobber.visible = true
	bobber.scale = Vector3.ONE
	hud.mode = Hud.M_WAITING
	hud.message = ""
	_play("whoosh")


func _update_flight(delta: float) -> void:
	flight_t = min(flight_t + delta * 1.4, 1.0)
	var flat := cast_from.lerp(cast_to, flight_t)
	var arc := sin(PI * flight_t) * cast_from.distance_to(cast_to) * 0.12
	bobber.position = flat + Vector3.UP * arc
	if flight_t >= 1.0:
		_play("splash")
		bite_timer = randf_range(2.5, 6.5)
		state = WAITING
		hud.message = "Waiting for a bite..."


func _update_bobber() -> void:
	var x := bobber.position.x
	var z := bobber.position.z
	bobber.position.y = wave_height(x, z)
	# Gentle bob tilt.
	bobber.rotation.z = sin(elapsed * 2.0 + x) * 0.15


func _start_bite() -> void:
	state = BITE
	bite_window = 1.6
	hud.mode = Hud.M_BITE
	hud.message = "!!  TAP  !!"
	_play("bite")
	# Tug the bobber under briefly.
	bobber.position.y -= 0.25


func _hook_fish() -> void:
	# Choose a fish (junk is rarer).
	var pick: Dictionary = fish_table[randi() % fish_table.size()]
	while pick.get("junk", false) and randf() > 0.35:
		pick = fish_table[randi() % fish_table.size()]
	pending_fish = pick
	fish_strength = lerpf(0.5, 1.4, randf()) * (1.0 + float(pick["max"]) * 0.12)
	distance = 1.0
	tension = 0.35
	lunge_timer = randf_range(0.8, 1.8)
	state = FIGHT
	hud.mode = Hud.M_FIGHT
	hud.message = ""


# --- The fight ----------------------------------------------------------------

func _update_fight(delta: float, reeling: bool) -> void:
	if reeling:
		distance = max(distance - delta * 0.17, 0.0)
		tension += delta * (0.42 * fish_strength)
		reel_click_t -= delta
		if reel_click_t <= 0.0:
			_play("click")
			reel_click_t = 0.09
	else:
		# Let the line rest: tension falls, but the fish may swim back out.
		tension = max(tension - delta * 0.6, 0.0)
		distance = min(distance + delta * 0.05 * fish_strength, 1.0)

	lunge_timer -= delta
	if lunge_timer <= 0.0:
		tension += 0.22 * fish_strength
		distance = min(distance + 0.06, 1.0)
		lunge_timer = randf_range(1.0, 2.6)

	if tension >= 1.0:
		_snap_line()
	elif distance <= 0.0:
		_land_fish()


func _snap_line() -> void:
	state = SNAP
	hud.mode = Hud.M_SNAP
	var nm: String = pending_fish.get("name", "it")
	hud.message = "SNAP!  %s got away\n(tap to try again)" % nm
	_play("snap")
	bobber.visible = false


func _land_fish() -> void:
	state = CAUGHT
	hud.mode = Hud.M_CAUGHT
	bobber.visible = false
	var weight: float = lerpf(pending_fish["min"], pending_fish["max"], randf())
	catches += 1
	if weight > best_weight:
		best_weight = weight
		best_name = pending_fish["name"]
	var verb := "Caught" if not pending_fish.get("junk", false) else "Reeled up"
	hud.message = "%s %s!\n%.2f kg  (tap to continue)" % [verb, pending_fish["name"], weight]
	_play("caught")
	_show_catch(pending_fish)
	_update_info()


var _fish_display_y := 0.0

func _show_catch(info: Dictionary) -> void:
	if caught_fish:
		caught_fish.queue_free()
	caught_fish = _make_fish(info["color"], info.get("junk", false))
	# Hold it up in front of the camera.
	var in_front := camera.global_position - camera.global_transform.basis.z * 2.4
	in_front += camera.global_transform.basis.x * 0.3
	caught_fish.position = in_front - Vector3(0, 0.6, 0)
	caught_fish.rotation.y = PI * 0.5  # side profile so the face and tail both read
	_fish_display_y = in_front.y - 0.1
	add_child(caught_fish)


func _make_fish(color: Color, junk: bool) -> Node3D:
	var n := Node3D.new()
	if junk:
		# A boot-ish block for the gag catches.
		_box(n, Vector3.ZERO, Vector3(0.5, 0.4, 0.8), color)
		_box(n, Vector3(0, -0.25, 0.4), Vector3(0.5, 0.2, 0.5), color)
		return n
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.4
	bm.height = 0.8
	bm.material = _mat(color)
	body.mesh = bm
	body.scale = Vector3(1.0, 0.75, 1.7)
	n.add_child(body)
	# Tail.
	var tail := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.35
	tm.height = 0.5
	tm.radial_segments = 4
	tm.material = _mat(color.darkened(0.1))
	tail.mesh = tm
	tail.rotation_degrees = Vector3(90, 0, 0)
	tail.position = Vector3(0, 0, 0.75)
	n.add_child(tail)
	# Googly eyes.
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.12
		em.height = 0.24
		em.material = _mat(Color.WHITE, 0.3)
		eye.mesh = em
		eye.position = Vector3(0.18 * sx, 0.12, -0.5)
		n.add_child(eye)
		var pup := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.055
		pm.height = 0.11
		pm.material = _mat(Color.BLACK, 0.3)
		pup.mesh = pm
		pup.position = Vector3(0.18 * sx, 0.12, -0.6)
		n.add_child(pup)
	return n


# --- Line mesh ----------------------------------------------------------------

func _update_line() -> void:
	var show := state in [FLYING, WAITING, BITE, FIGHT]
	line.visible = show
	if not show:
		return
	var a := rod_tip.global_position
	var b := bobber.global_position
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	# A little sag in the middle.
	var steps := 8
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		p.y -= sin(PI * t) * 0.25
		im.surface_add_vertex(p)
	im.surface_end()
	line.mesh = im


# --- Autotest -----------------------------------------------------------------

func _autotest(_delta: float) -> void:
	frame += 1
	sim_action = false
	match state:
		IDLE, CHARGING:
			# Charge ~0.8s then release.
			sim_action = power < 0.75
		BITE:
			sim_tap = true
		FIGHT:
			# Reel in bursts: pull unless tension is high.
			sim_action = tension < 0.72
			# Test-only: hurry the catch along so a short headless run lands a fish.
			distance = max(distance - 0.012, 0.0)
		CAUGHT, SNAP:
			if frame % 40 == 0:
				sim_tap = true
	if shot_on == "caught" and state == CAUGHT and frame > 30:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST(caught) frames=%d catches=%d best=%.2f" % [frame, catches, best_weight])
		get_tree().quit()
	if frame >= autotest_frames:
		if autotest_shot != "":
			get_viewport().get_texture().get_image().save_png(autotest_shot)
		print("AUTOTEST frames=%d catches=%d best=%.2f state=%d" % [frame, catches, best_weight, state])
		get_tree().quit()
