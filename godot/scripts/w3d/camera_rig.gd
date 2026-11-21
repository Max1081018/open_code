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
var pitch := -0.18
var distance := 4.4
var arm: SpringArm3D
var camera: Camera3D
var _blend := 0.0           ## 0 third person, 1 first person (eased)


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
	camera.far = 900.0
	camera.current = true
	arm.add_child(camera)


func apply_look(look: Vector2) -> void:
	yaw -= look.x
	pitch = clampf(pitch - look.y, -1.25, 0.95 if first_person else 0.55)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_blend = move_toward(_blend, 1.0 if first_person else 0.0, delta * 4.0)
	# Third-person pivot: above the shoulder, a little to the right.
	var pivot_tp := target.global_position + Vector3(0, 1.55, 0)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	pivot_tp += right * 0.45
	var pivot_fp: Vector3 = head.global_position + Vector3(0, 0.08, 0) if head else target.global_position + Vector3(0, 1.65, 0)
	var pivot := pivot_tp.lerp(pivot_fp, _blend)
	# Ease the pivot toward its target (smooth follow), snapping in first person.
	var follow := 1.0 - exp(-delta * (22.0 if _blend > 0.5 else 12.0))
	global_position = global_position.lerp(pivot, follow) if global_position.distance_to(pivot) < 6.0 else pivot
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = lerpf(distance, 0.0, _blend)
	camera.fov = lerpf(62.0, 74.0, _blend)


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))
