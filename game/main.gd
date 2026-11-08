extends Node3D
## Orb Drift: roll around a floating island and collect every orb before the
## timer runs out. The whole level is built in code from primitive meshes, so
## there are no imported assets to manage.
##
## Controls: left half of the screen is a virtual joystick, right half jumps.
## On desktop: WASD / arrow keys and Space (mouse clicks also act as touches).
##
## Headless self-test (used by game/tools/play.sh):
##   godot --path game -- --autotest --frames=600 --shot=/tmp/shot.png
## drives the joystick with synthetic touch events toward the nearest orb,
## saves a screenshot and prints "AUTOTEST ..." before quitting.

const Hud := preload("res://hud.gd")

const ORB_COUNT := 10
const ROUND_TIME := 60.0
const ISLAND_SIZE := 24.0
const FALL_LIMIT := -12.0
const FALL_PENALTY := 5.0
const MOVE_FORCE := 22.0
const JUMP_IMPULSE := 5.5
const CAMERA_OFFSET := Vector3(0, 8, 10)
const SPAWN := Vector3(0, 1.5, 6)

var player: RigidBody3D
var camera: Camera3D
var hud
var orbs: Array[Area3D] = []
var score := 0
var time_left := ROUND_TIME
var state := "playing"  # playing | won | lost
var elapsed := 0.0

var autotest := false
var autotest_frames := 600
var autotest_shot := ""
var frame := 0


func _ready() -> void:
	_parse_args()
	if autotest:
		seed(42)
	else:
		randomize()
	_setup_input()
	_build_environment()
	_build_island()
	_spawn_player()
	_spawn_orbs()
	_build_camera()
	hud = Hud.new()
	add_child(hud)
	hud.restart_pressed.connect(_restart)
	_update_hud()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autotest":
			autotest = true
		elif arg.begins_with("--frames="):
			autotest_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--shot="):
			autotest_shot = arg.get_slice("=", 1)


func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("jump", [KEY_SPACE])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


# --- World --------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.85)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky_mat.ground_horizon_color = Color(0.72, 0.84, 0.96)
	sky_mat.ground_bottom_color = Color(0.12, 0.2, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# A flat ambient colour: sky-sourced ambient washes everything out to pale
	# cyan in the Compatibility renderer.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.84, 0.96)
	env.fog_density = 0.006

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat


func _add_box(pos: Vector3, size: Vector3, color: Color, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rot_y
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = _material(color)
	mesh.mesh = box_mesh
	body.add_child(mesh)
	add_child(body)
	return body


func _build_island() -> void:
	# Grass top and a darker earth slab underneath so the island reads as floating.
	_add_box(Vector3(0, -0.5, 0), Vector3(ISLAND_SIZE, 1, ISLAND_SIZE), Color(0.36, 0.7, 0.38))
	_add_box(Vector3(0, -2.0, 0), Vector3(ISLAND_SIZE - 2, 2, ISLAND_SIZE - 2), Color(0.45, 0.32, 0.22))
	_add_box(Vector3(0, -4.0, 0), Vector3(ISLAND_SIZE - 8, 2, ISLAND_SIZE - 8), Color(0.38, 0.27, 0.19))

	# Scattered rocks to roll around, kept clear of the spawn point.
	var placed := 0
	while placed < 7:
		var p := Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
		if p.distance_to(Vector3(SPAWN.x, 0, SPAWN.z)) < 4.0:
			continue
		var s := Vector3(randf_range(1.2, 2.6), randf_range(0.8, 2.2), randf_range(1.2, 2.6))
		_add_box(p + Vector3(0, s.y / 2, 0), s, Color(0.55, 0.56, 0.6), randf() * TAU)
		placed += 1

	# A ramp and a raised ledge with an orb-worthy view.
	var ramp := _add_box(Vector3(-7, 0.6, -6), Vector3(3, 0.4, 6), Color(0.8, 0.62, 0.35))
	ramp.rotation.x = deg_to_rad(-14)
	_add_box(Vector3(-7, 0.75, -10.5), Vector3(4, 1.5, 3), Color(0.8, 0.62, 0.35))


func _spawn_player() -> void:
	player = RigidBody3D.new()
	player.position = SPAWN
	player.mass = 1.0
	player.linear_damp = 0.4
	player.angular_damp = 0.8
	player.contact_monitor = true
	player.max_contacts_reported = 4
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.15
	player.physics_material_override = phys

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	player.add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 1.0
	sphere_mesh.material = _material(Color(1.0, 0.78, 0.2))
	mesh.mesh = sphere_mesh
	player.add_child(mesh)

	# A stripe so you can see the ball rolling.
	var stripe := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.47
	torus.outer_radius = 0.53
	torus.material = _material(Color(1.0, 0.35, 0.2))
	stripe.mesh = torus
	stripe.rotation.z = PI / 2
	player.add_child(stripe)

	add_child(player)


func _spawn_orbs() -> void:
	var mat := _material(Color(0.35, 0.95, 1.0), 2.5)
	var spots: Array[Vector3] = [Vector3(-7, 2.5, -10.5)]  # one on the ledge
	while spots.size() < ORB_COUNT:
		var p := Vector3(randf_range(-10.5, 10.5), 0.9, randf_range(-10.5, 10.5))
		if p.distance_to(SPAWN) < 3.0:
			continue
		var too_close := false
		for s in spots:
			if s.distance_to(p) < 3.0:
				too_close = true
				break
		if not too_close:
			spots.append(p)

	for p in spots:
		var orb := Area3D.new()
		orb.position = p
		orb.set_meta("base_y", p.y)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.7
		shape.shape = sphere
		orb.add_child(shape)
		var mesh := MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.32
		sphere_mesh.height = 0.64
		sphere_mesh.material = mat
		mesh.mesh = sphere_mesh
		orb.add_child(mesh)
		orb.body_entered.connect(_on_orb_body_entered.bind(orb))
		add_child(orb)
		orbs.append(orb)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 60
	add_child(camera)
	camera.position = player.position + CAMERA_OFFSET
	camera.look_at(player.position)


# --- Game loop ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state != "playing":
		return

	var dir: Vector2 = hud.joystick_vector()
	dir += Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	dir = dir.limit_length(1.0)
	player.apply_central_force(Vector3(dir.x, 0, dir.y) * MOVE_FORCE)

	if (hud.consume_jump() or Input.is_action_just_pressed("jump")) and player.get_contact_count() > 0:
		player.apply_central_impulse(Vector3.UP * JUMP_IMPULSE)

	if player.position.y < FALL_LIMIT:
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		player.global_position = SPAWN
		time_left -= FALL_PENALTY
		hud.flash("Fell off! -%d s" % int(FALL_PENALTY))


func _process(delta: float) -> void:
	elapsed += delta
	for orb in orbs:
		orb.position.y = orb.get_meta("base_y") + sin(elapsed * 3.0 + orb.position.x) * 0.15
		orb.rotate_y(delta * 2.0)

	var target := player.position + CAMERA_OFFSET
	camera.position = camera.position.lerp(target, clamp(delta * 4.0, 0.0, 1.0))
	camera.look_at(player.position)

	if state == "playing":
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_end("lost")
	_update_hud()

	if autotest:
		_autotest_step()


func _on_orb_body_entered(body: Node3D, orb: Area3D) -> void:
	if body != player or state != "playing":
		return
	orbs.erase(orb)
	orb.queue_free()
	score += 1
	if score >= ORB_COUNT:
		_end("won")


func _end(result: String) -> void:
	state = result
	if result == "won":
		hud.show_end("You collected every orb!\n%.1f s to spare" % time_left)
	else:
		hud.show_end("Out of time!\n%d / %d orbs" % [score, ORB_COUNT])


func _update_hud() -> void:
	hud.set_status(score, ORB_COUNT, time_left)


func _restart() -> void:
	get_tree().reload_current_scene()


# --- Self-test ----------------------------------------------------------------

## Steers through the HUD's real touch path: press on the left half, then drag
## toward the nearest orb every frame.
func _autotest_step() -> void:
	frame += 1
	var origin := Vector2(260, 500)
	if frame == 1:
		var press := InputEventScreenTouch.new()
		press.index = 0
		press.position = origin
		press.pressed = true
		Input.parse_input_event(press)
	elif orbs.size() > 0:
		var nearest: Area3D = orbs[0]
		for orb in orbs:
			if orb.position.distance_to(player.position) < nearest.position.distance_to(player.position):
				nearest = orb
		var to := nearest.position - player.position
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = origin + Vector2(to.x, to.z).normalized() * 80.0
		Input.parse_input_event(drag)
		if to.y > 1.0 and frame % 30 == 0:
			var tap := InputEventScreenTouch.new()
			tap.index = 1
			tap.position = Vector2(1100, 500)
			tap.pressed = true
			Input.parse_input_event(tap)

	if frame >= autotest_frames or state != "playing":
		if autotest_shot != "":
			var img := get_viewport().get_texture().get_image()
			img.save_png(autotest_shot)
		print("AUTOTEST frames=%d score=%d/%d time_left=%.1f state=%s player=%s camera=%s" % [
			frame, score, ORB_COUNT, time_left, state, player.position.snapped(Vector3.ONE * 0.1), camera.position.snapped(Vector3.ONE * 0.1)])
		get_tree().quit()
