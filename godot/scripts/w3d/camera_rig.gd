class_name CameraRig
extends Node3D
## The camera. Third person: an orbit over the right shoulder on a spring
## arm, so walls and slopes push it in rather than letting it clip through;
## it eases after the player and leans its pitch with the ground. First
## person: at the hero's eyes (on the head bone), the head and hood hidden
## from it so the player sees their own arms and what they hold.

var target: Node3D
var head: Node3D            ## first-person anchor (a BoneAttachment3D on Head)
var first_person := false
var yaw := 0.0
var pitch := -0.16
var distance := 3.5
## Where the look input wants the camera; yaw/pitch glide toward these.
var yaw_target := 0.0
var pitch_target := -0.16
var arm: SpringArm3D
var camera: Camera3D
var _blend := 0.0           ## 0 third person, 1 first person (eased)
## A great foe to keep in the frame during its fight: the view pulls back
## and, when it is up in the air, tilts up to hold it below the top edge. An
## offset on the player's own look, eased in and out, never a takeover.
var focus: Node3D
var focus_height := 1.5     ## where on the focus to frame (its chest)
var _frame := 0.0           ## 0..1 eased
var _lift := 0.0            ## extra pitch to hold the focus in view


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.margin = 0.25
	arm.collision_mask = 1
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 3500.0
	camera.current = true
	arm.add_child(camera)


func apply_look(look: Vector2) -> void:
	yaw_target -= look.x
	pitch_target = clampf(pitch_target - look.y, -1.2, 0.95 if first_person else 0.5)


## Set the view directly (no glide), e.g. at spawn or in tests.
func set_view(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	yaw_target = new_yaw
	pitch = new_pitch
	pitch_target = new_pitch


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_blend = move_toward(_blend, 1.0 if first_person else 0.0, delta * 4.0)
	# Look glides toward its target: responsive but never jerky.
	var glide := 1.0 - exp(-delta * 18.0)
	yaw = lerp_angle(yaw, yaw_target, glide)
	pitch = lerpf(pitch, pitch_target, glide)
	# Third-person pivot: centred on the hero at upper-chest height, so they
	# stand in the middle of the frame (as in Genshin), the world around them.
	var pivot_tp := target.global_position + Vector3(0, 1.3, 0)
	var pivot_fp: Vector3 = head.global_position + Vector3(0, 0.1, 0) if head else target.global_position + Vector3(0, 1.65, 0)
	# Just ahead of the eyes, along the view, so the face (part of the body
	# mesh) stays behind the camera while arms and weapon come into view.
	var look_dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	pivot_fp += look_dir * 0.26
	var pivot := pivot_tp.lerp(pivot_fp, _blend)
	# Ease the pivot toward its target (smooth follow), snapping in first person.
	var follow := 1.0 - exp(-delta * (24.0 if _blend > 0.5 else 10.0))
	global_position = global_position.lerp(pivot, follow) if global_position.distance_to(pivot) < 6.0 else pivot
	var want := 0.0
	var lift := 0.0
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		var to := focus.global_position + Vector3(0, focus_height, 0) - pivot_tp
		var flat := Vector2(to.x, to.z).length()
		if flat < 40.0:
			want = 1.0
			# Its elevation seen from her; keep it within ~0.25 rad of the
			# view's centre line (the half-height of the frame is ~0.5).
			lift = clampf(atan2(to.y, maxf(flat, 1.0)) - 0.25 - pitch, 0.0, 0.38)
	_frame = move_toward(_frame, want, delta * 1.2)
	_lift = lerpf(_lift, lift, 1.0 - exp(-delta * 3.0))
	var shown := 1.0 - _blend   # never in first person
	rotation = Vector3(minf(pitch + _lift * _frame * shown, 0.6), yaw, 0)
	arm.spring_length = lerpf(distance + 1.3 * _frame, 0.0, _blend)
	camera.fov = lerpf(58.0, 72.0, _blend)


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))
