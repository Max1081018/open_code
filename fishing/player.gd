extends CharacterBody3D
## Walkable player character for Reel Trouble.
##
## The game is first person throughout, so the only part of the body that is
## ever on screen is the pair of legs you see when you look down (fp_legs.gd)
## and the close-up hand rig, which rides on the camera. Nothing else is drawn
## or skinned, which keeps the player free on phones.
##
## game.gd feeds `move_input` (joystick, screen space) and `cam_yaw` (camera
## yaw) each frame; the character moves relative to the camera.

const Legs := preload("res://fp_legs.gd")

const PLAYER_HEIGHT := 1.75
const WALK_SPEED := 2.9
const RUN_SPEED := 6.2
const ACCEL := 14.0
const GRAVITY := 22.0
const TURN_RATE := 12.0
const JUMP_SPEED := 7.2
const STEP_HEIGHT := 0.45         # walks straight up porch steps and kerbs

var move_input := Vector2.ZERO   # x = right, y = forward(-) / back(+)
var cam_yaw := 0.0
var frozen := false              # true while fishing / in a menu

var legs: Legs
var first_person := true
var show_body := true
var sprint := false              # set by the RUN button
var wading := false              # knee-deep or more: slower
var carry_slow := 1.0            # < 1 while hauling something heavy
var _body_yaw := 0.0
var _jump_buffer := 0.0          # a tap just before landing still jumps


## Kept for the callers that set the view mode; the legs are the only body we
## have, and the "Show your body" setting turns them off for players who would
## rather see nothing but the water.
func set_first_person(on: bool) -> void:
	first_person = on
	if legs:
		legs.set_shown(show_body and on)


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = PLAYER_HEIGHT
	col.shape = cap
	col.position = Vector3(0, PLAYER_HEIGHT * 0.5, 0)
	add_child(col)
	legs = Legs.new()
	add_child(legs)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)


## Jump on the next physics frame you're on the ground (buffered a moment).
func jump() -> void:
	_jump_buffer = 0.18


## What the legs are doing, for the autotests.
func gait() -> String:
	return legs.gait if legs else "none"


## Goes up each time a foot plants; the game hangs the footstep sound off it.
func steps() -> int:
	return legs.steps if legs else 0


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
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
	if legs:
		legs.pose(delta, velocity, _body_yaw, is_on_floor(), frozen)
