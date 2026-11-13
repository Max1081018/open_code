extends CharacterBody3D
## Walkable player character for Reel Trouble.
##
## The game is first person throughout, so the only part of the body that is
## ever on screen is the pair of arms that ride on the camera (fp_hands.gd),
## which are the survivor model with its head and legs folded away. The player
## body itself is just a capsule: nothing of it is drawn.
##
## game.gd feeds `move_input` (joystick, screen space) and `cam_yaw` (camera
## yaw) each frame; the character moves relative to the camera.


const PLAYER_HEIGHT := 1.75
const WALK_SPEED := 2.9
const RUN_SPEED := 6.2
const ACCEL := 14.0
const GRAVITY := 22.0
const TURN_RATE := 12.0
const JUMP_SPEED := 7.2
const STEP_HEIGHT := 0.45         # walks straight up porch steps and kerbs
# --- swimming ---------------------------------------------------------------
const SWIM_DEEP := 1.62           # water this far over your feet and you're swimming
const SWIM_SPEED := 2.2
const SWIM_FAST := 3.6            # with RUN held
const FLOAT_AT := 1.06            # feet this far under when floating at rest
const BUOY_K := 16.0              # how hard the water pushes you back to the top
const BUOY_DAMP := 4.5
const SWIM_KICK := 3.4            # the JUMP button, used in water

var move_input := Vector2.ZERO   # x = right, y = forward(-) / back(+)
var cam_yaw := 0.0
var frozen := false              # true while fishing / in a menu

var first_person := true
var show_body := true
var sprint := false              # set by the RUN button
var wading := false              # knee-deep or more: slower
var water_y := -1e9              # sea surface over your head, from the game
var cam_pitch := 0.0             # you swim where you look
var swimming := false            # off your feet, in deep water
var submerged := 0.0             # how far the surface is above your feet
var _kick := 0.0                 # a swim stroke still pushing you along
var carry_slow := 1.0            # < 1 while hauling something heavy
var _body_yaw := 0.0
var _steps := 0
var _step_d := 0.0
var _jump_buffer := 0.0          # a tap just before landing still jumps


## Kept for the callers that set the view mode.
func set_first_person(on: bool) -> void:
	first_person = on


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = PLAYER_HEIGHT
	col.shape = cap
	col.position = Vector3(0, PLAYER_HEIGHT * 0.5, 0)
	add_child(col)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)


## Jump on the next physics frame you're on the ground (buffered a moment).
func jump() -> void:
	_jump_buffer = 0.18


## Can you get out here? True when the ground under you is close enough to
## climb onto, which is what makes a beach a beach rather than a wall.
func shallows() -> bool:
	return submerged < SWIM_DEEP


## What the body is doing, for the autotests.
func gait() -> String:
	if not is_on_floor():
		return "air"
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp < 0.3:
		return "idle"
	return "run" if sp > 3.8 else "walk"


## Goes up each time a foot plants; the game hangs the footstep sound off it.
func steps() -> int:
	return _steps


func _physics_process(delta: float) -> void:
	# How deep you are. Past about your own height the ground is no use to
	# you and you start swimming: before this the sea was a hole you fell
	# down, because nothing ever stopped you sinking.
	submerged = water_y - global_position.y
	var was_swimming := swimming
	# Hysteresis: without it a passing wave flips you between swimming and
	# walking several times a second in chest-deep water.
	swimming = submerged > (SWIM_DEEP - 0.3 if swimming else SWIM_DEEP) and not frozen
	if swimming and not was_swimming:
		velocity.y = maxf(velocity.y, -3.2)      # a dive slows as it hits the water
	_kick = maxf(_kick - delta, 0.0)

	if swimming:
		_swim(delta)
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		# Wading out of your depth: the water takes your weight as you go.
		if submerged > 0.2:
			velocity.y += GRAVITY * clampf(submerged / SWIM_DEEP, 0.0, 0.8) * delta
	elif velocity.y < 0.0:
		velocity.y = -2.0  # keep it planted on slopes

	var want := Vector3.ZERO
	var mag := 0.0
	if not frozen:
		mag = clampf(move_input.length(), 0.0, 1.0)
		if mag > 0.08:
			# Joystick is screen-relative; rotate it into camera space.
			var dir := Basis(Vector3.UP, cam_yaw) * Vector3(move_input.x, 0.0, move_input.y)
			dir.y = 0.0
			if dir.length() > 0.001:
				var top_speed := RUN_SPEED if sprint else WALK_SPEED
				if wading:
					top_speed *= 0.5
				top_speed *= carry_slow
				want = dir.normalized() * top_speed * clampf(mag * 1.25, 0.35, 1.0)

	velocity.x = move_toward(velocity.x, want.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, want.z, ACCEL * delta)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _jump_buffer > 0.0 and is_on_floor() and not frozen:
		_jump_buffer = 0.0
		velocity.y = JUMP_SPEED * (0.85 if wading else 1.0)
	# Step up onto low ledges (porch steps, kerbs) instead of stopping dead.
	elif is_on_floor() and is_on_wall() and want.length() > 0.5:
		var ahead := Vector3(want.x, 0.0, want.z).normalized() * 0.22
		var up := Vector3(0, STEP_HEIGHT, 0)
		var t := global_transform
		if test_move(t, ahead) and not test_move(t, up) and not test_move(t.translated(up), ahead):
			global_position += up + ahead * 0.5
	move_and_slide()

	# The hips swing round to follow the camera rather than snapping, so a quick
	# look over your shoulder doesn't teleport your feet.
	var rate := 20.0 if want.length() > 0.01 else 9.0
	_body_yaw = lerp_angle(_body_yaw, cam_yaw, clampf(delta * rate, 0.0, 1.0))
	# Footstep counter, paced by distance rather than by a timer.
	var moved := Vector2(velocity.x, velocity.z).length() * delta
	if is_on_floor():
		_step_d += moved
		if _step_d > 1.8:
			_step_d = 0.0
			_steps += 1


## In deep water: you float with your head out, swim where you look, and kick
## upward with the JUMP button.
##
## The water sets how fast you *move* vertically rather than pushing on you:
## left alone it lifts you to the waterline and holds you there riding the
## swell, and putting your head down and swimming takes you under against it.
## A spring was tried first and it fought itself - any downward glance sank
## you, and you floated with your eyes under the water.
func _swim(delta: float) -> void:
	var mag := clampf(move_input.length(), 0.0, 1.0)
	var top := (SWIM_FAST if sprint else SWIM_SPEED) * carry_slow
	var want := Vector3.ZERO
	var drive := 0.0                     # how hard you are swimming up or down
	# A dead zone round the horizon: a glance down shouldn't sink you.
	var down := clampf((-cam_pitch - 0.25) / 0.85, 0.0, 1.0)
	var up := clampf((cam_pitch - 0.22) / 0.70, 0.0, 1.0)
	if not frozen and mag > 0.08:
		var dir := Basis(Vector3.UP, cam_yaw) * Vector3(move_input.x, 0.0, move_input.y)
		dir.y = 0.0
		if dir.length() > 0.001:
			dir = dir.normalized()
			want = dir * top
			# only what you push *forward* steers you up or down
			var fwd := (Basis(Vector3.UP, cam_yaw) * Vector3(0, 0, -1)).normalized()
			var ahead := clampf(dir.dot(fwd), -1.0, 1.0)
			drive = (up - down) * top * 0.95 * ahead
	velocity.x = move_toward(velocity.x, want.x, ACCEL * 0.6 * delta)
	velocity.z = move_toward(velocity.z, want.z, ACCEL * 0.6 * delta)

	# The lift that holds you at the top, weakened while you swim down so a
	# dive can beat it, and never so weak that letting go leaves you stranded
	# on the bottom.
	var below := (water_y - FLOAT_AT) - global_position.y
	var lift: float = clampf(below * 2.4, -2.2, 1.9) * (1.0 - 0.78 * down)
	var vy_want := lift + drive
	if _kick > 0.0:
		vy_want = maxf(vy_want, SWIM_KICK * 0.6)
	velocity.y = move_toward(velocity.y, vy_want, 13.0 * delta)
	if _jump_buffer > 0.0 and not frozen:
		_jump_buffer = 0.0
		_kick = 0.4
		velocity.y = maxf(velocity.y, SWIM_KICK)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	move_and_slide()

	var rate := 20.0 if want.length() > 0.01 else 9.0
	_body_yaw = lerp_angle(_body_yaw, cam_yaw, clampf(delta * rate, 0.0, 1.0))

