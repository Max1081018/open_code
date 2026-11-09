extends CharacterBody3D
## Walkable player character for Lazy Lake.
##
## Uses a KayKit character model, which ships with its own AnimationPlayer, so
## Idle / Walking_A / Running_A drive straight off the movement speed. The model
## is auto-fitted at runtime (scaled to PLAYER_HEIGHT with its feet on y=0) so we
## don't depend on the pack's authored scale.
##
## game.gd feeds `move_input` (joystick, screen space) and `cam_yaw` (camera
## yaw) each frame; the character moves relative to the camera.

const PLAYER_HEIGHT := 1.75
const WALK_SPEED := 2.9
const RUN_SPEED := 6.2
const ACCEL := 14.0
const GRAVITY := 22.0
const TURN_RATE := 12.0

var move_input := Vector2.ZERO   # x = right, y = forward(-) / back(+)
var cam_yaw := 0.0
var frozen := false              # true while fishing / in a menu

var model: Node3D
var anim: AnimationPlayer
var _cur := ""
var _model_yaw_offset := 0.0
var _skel: Skeleton3D
var first_person := false
var show_body := true
var sprint := false              # set by the RUN button
var wading := false              # knee-deep or more: slower
var carry_slow := 1.0            # < 1 while hauling something heavy


## In first person we still draw the body (so you can look down and see your
## legs), but everything from the chest up is shrunk away so the camera isn't
## inside your shoulders. Looking down shows hips and legs, like most FPS games.
func set_first_person(on: bool) -> void:
	first_person = on
	if model:
		model.visible = show_body
	if _skel == null:
		return
	var idx := _skel.find_bone("spine")
	if idx >= 0:
		_skel.set_bone_pose_scale(idx, Vector3.ONE * (0.001 if on else 1.0))


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = PLAYER_HEIGHT
	col.shape = cap
	col.position = Vector3(0, PLAYER_HEIGHT * 0.5, 0)
	add_child(col)
	_build_model()


func _build_model() -> void:
	var packed: PackedScene = load("res://assets/models/characters/Rogue.glb")
	model = packed.instantiate()
	add_child(model)

	# Fit the model: scale to PLAYER_HEIGHT and stand it on the origin.
	var box := _local_aabb(model)
	if box.size.y > 0.001:
		var s := PLAYER_HEIGHT / box.size.y
		model.scale = Vector3.ONE * s
		model.position.y = -box.position.y * s

	anim = model.find_child("AnimationPlayer", true, false)
	_skel = model.find_child("Skeleton3D", true, false)
	_play_anim("Idle")


## AABB of a node's meshes in that node's own space.
func _local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true):
		if n.mesh == null:
			continue
		var a: AABB = (inv * n.global_transform) * n.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## World-space AABB of every mesh under a node.
func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in _descendants(node):
		if n is MeshInstance3D and n.mesh:
			var a: AABB = n.global_transform * n.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


func _descendants(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out.append_array(_descendants(c))
	return out


func _play_anim(name: String, speed := 1.0) -> void:
	if anim == null or _cur == name:
		return
	if not anim.has_animation(name):
		return
	_cur = name
	anim.play(name, 0.18, speed)
	var a := anim.get_animation(name)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR


## Plays a one-shot animation (e.g. Interact) then returns to movement anims.
func play_once(name: String) -> void:
	if anim and anim.has_animation(name):
		_cur = ""
		anim.play(name, 0.15)


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
	move_and_slide()

	# In first person the body faces wherever you're looking, so your own legs
	# line up with the camera. Otherwise it turns the way it's walking.
	if model:
		if first_person:
			model.rotation.y = cam_yaw + _model_yaw_offset
		elif want.length() > 0.01:
			var target_yaw := atan2(want.x, want.z) + _model_yaw_offset
			model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(delta * TURN_RATE, 0.0, 1.0))

	_update_anim()
	if first_person and _skel:
		var h := _skel.find_bone("spine")
		if h >= 0:
			_skel.set_bone_pose_scale(h, Vector3.ONE * 0.001)


func _update_anim() -> void:
	if frozen:
		_play_anim("Idle")
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.25:
		_play_anim("Idle")
		if anim:
			anim.speed_scale = 1.0
	elif speed < WALK_SPEED + 0.9:
		_play_anim("Walking_A")
		# Match the stride to the speed so feet don't skate.
		if anim:
			anim.speed_scale = clampf(speed / 2.4, 0.6, 1.45)
	else:
		_play_anim("Running_A")
		if anim:
			anim.speed_scale = clampf(speed / 5.6, 0.85, 1.3)
