class_name Player3D
extends CharacterBody3D
## The hero in the open world: the downloaded hooded wanderer on the shared
## humanoid rig, moved relative to the camera and turning smoothly toward
## where they go. Walk, run, sprint (stamina), jump with fall and landing,
## a dodge roll with invulnerable frames, wading then swimming when the water
## is chest deep. Holds items in a grip on the right hand bone.

signal swung(kind: String)

const WALK := 2.4
const RUN := 5.2
const SPRINT := 8.2
const SWIM := 2.8
const JUMP := 7.2
const GRAVITY := 22.0
const DODGE_SPEED := 9.5
const DODGE_TIME := 0.62

var input: Input3D
var cam: CameraRig
var world: OpenWorld
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var right_hand: Node3D
var left_hand: Node3D
var head_anchor: Node3D
var held_id := ""
var _held: Node3D

var health := 100.0
var max_health := 100.0
var stamina := 100.0
var max_stamina := 100.0
var _stamina_wait := 0.0
var swimming := false
var _dodge := 0.0
var _dodge_dir := Vector3.ZERO
var _action := 0.0         ## seconds left of an attack/use animation
var _action_name := ""
var _air_time := 0.0
var _landing := 0.0
var _clip := ""
var invulnerable := false
var _head_meshes: Array = []


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.5
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0, 0.875, 0)
	add_child(shape)
	model = CharacterKit.build("player")
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for clip in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Swim_Fwd", "Swim_Idle", "Jump", "Sword_Block", "Sword_Idle"]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).extra_cull_margin = 2.0
	right_hand = HumanoidGrip.grip(skeleton, model, "RightHand", "RightIndexProximal", "RightLittleProximal", "RightMiddleProximal")
	left_hand = HumanoidGrip.grip(skeleton, model, "LeftHand", "LeftIndexProximal", "LeftLittleProximal", "LeftMiddleProximal")
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	skeleton.add_child(head)
	head_anchor = head
	_find_head_meshes()
	_play("Idle")


## Meshes of the head and hood: hidden from the first-person camera (layer 2).
func _find_head_meshes() -> void:
	var neck_y := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone("Neck"))).origin.y
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		if box.position.y > neck_y - 0.12 and box.size.y < 0.6:
			_head_meshes.append(mi)


func set_first_person(on: bool) -> void:
	for mi in _head_meshes:
		mi.layers = 2 if on else 1
	cam.camera.cull_mask = 0xFFFFF & ~2 if on else 0xFFFFF


func hold(id: String) -> void:
	if _held:
		_held.queue_free()
	_held = null
	held_id = id
	if id == "":
		return
	_held = Body3D.item_model(id)
	if _held:
		right_hand.add_child(_held)


func _physics_process(delta: float) -> void:
	if input == null or cam == null:
		return
	cam.apply_look(input.look)
	input.look = Vector2.ZERO
	if input.toggle_view:
		input.toggle_view = false
		cam.first_person = not cam.first_person
		set_first_person(cam.first_person)

	var wish := cam.right_flat() * input.move.x + cam.forward_flat() * input.move.y
	var water_depth := TerrainGen.WATER - global_position.y
	swimming = water_depth > 1.15
	_stamina_wait -= delta
	if _stamina_wait <= 0.0:
		stamina = minf(max_stamina, stamina + delta * 22.0)

	# Actions (attack/use) lock movement to a slow drift while they play.
	_action -= delta
	_dodge -= delta
	invulnerable = _dodge > DODGE_TIME * 0.25
	var dodge_now := input.dodge
	input.dodge = false
	if dodge_now and _dodge <= 0.0 and is_on_floor() and _spend(22.0):
		_dodge = DODGE_TIME
		_dodge_dir = wish.normalized() if wish.length() > 0.1 else -model.global_transform.basis.z
		_play("Roll", 1.25, true)
	if (input.attack or input.heavy) and _action <= 0.0 and _dodge <= 0.0 and not swimming:
		_start_action(input.heavy)

	var speed := RUN
	if input.move.length() < 0.55:
		speed = WALK
	var sprinting := input.sprint and wish.length() > 0.1 and not swimming and _action <= 0.0
	if sprinting and stamina > 1.0:
		speed = SPRINT
		stamina -= delta * 14.0
		_stamina_wait = 0.6
	if swimming:
		speed = SWIM
	if _action > 0.0:
		speed *= 0.25

	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var target := wish * speed
	if _dodge > 0.0:
		target = _dodge_dir * DODGE_SPEED * clampf(_dodge / DODGE_TIME + 0.3, 0.0, 1.0)
	var accel := 14.0 if is_on_floor() or swimming else 4.0
	horizontal = horizontal.lerp(target, 1.0 - exp(-accel * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if swimming:
		# Float with the chest at the surface; jump swims upward.
		var float_y := TerrainGen.WATER - 1.2
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 3.0 + (3.0 if input.jump else 0.0), 1.0 - exp(-4.0 * delta))
	else:
		velocity.y -= GRAVITY * delta
		var jump_now := input.jump
		input.jump = false
		if jump_now and is_on_floor() and _dodge <= 0.0 and _spend(8.0):
			velocity.y = JUMP
			_play("Jump_Start", 1.4, true)
	var was_air := not is_on_floor()
	move_and_slide()
	if is_on_floor():
		if was_air and _air_time > 0.35:
			_landing = 0.25
			_play("Jump_Land", 1.6, true)
		_air_time = 0.0
	else:
		_air_time += delta
	_landing -= delta

	# Face where we move (or where the camera looks while acting / in first person).
	var face := Vector3.ZERO
	if cam.first_person or _action > 0.0:
		face = cam.forward_flat()
	elif horizontal.length() > 0.4:
		face = horizontal.normalized()
	if face != Vector3.ZERO:
		var want := atan2(face.x, face.z)
		model.rotation.y = lerp_angle(model.rotation.y, want, 1.0 - exp(-12.0 * delta))
	_animate(horizontal.length())


func _start_action(heavy: bool) -> void:
	var kind := "attack"
	var held_kind := Items.kind(held_id) if held_id != "" else -1
	if held_kind == Items.Kind.AXE:
		kind = "chop"
	elif held_kind == Items.Kind.PICKAXE:
		kind = "mine"
	var cost := 18.0 if heavy else 9.0
	if not _spend(cost):
		return
	var clip := "Sword_Regular_A"
	var time := 0.6
	match kind:
		"chop":
			clip = "TreeChopping"
			time = 0.9
		"mine":
			clip = "Sword_Regular_C"
			time = 0.75
		_:
			if heavy:
				clip = "Sword_Heavy_Combo"
				time = 1.1
			else:
				clip = ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C"][int(Time.get_ticks_msec() / 600) % 3]
	_action = time
	_action_name = kind
	_play(clip, 1.2, true)
	swung.emit(kind + ("_heavy" if heavy else ""))


func _spend(amount: float) -> bool:
	if stamina < amount * 0.5:
		return false
	stamina = maxf(0.0, stamina - amount)
	_stamina_wait = 0.9
	return true


func _animate(speed: float) -> void:
	if _action > 0.0 or _dodge > 0.0 or _landing > 0.0:
		return
	var clip := "Idle"
	if swimming:
		clip = "Swim_Fwd" if speed > 0.5 else "Swim_Idle"
	elif not is_on_floor() and _air_time > 0.15:
		clip = "Jump"
	elif input.block:
		clip = "Sword_Block"
	elif speed > 6.5:
		clip = "Sprint"
	elif speed > 3.2:
		clip = "Jog_Fwd"
	elif speed > 0.3:
		clip = "Walk"
	var scale := 1.0
	if clip == "Walk":
		scale = speed / 1.6
	elif clip == "Jog_Fwd":
		scale = speed / 4.6
	_play(clip, clampf(scale, 0.6, 1.6))


func _play(clip: String, speed := 1.0, restart := false) -> void:
	if not anim.has_animation(clip):
		return
	if clip == _clip and not restart:
		anim.speed_scale = speed
		return
	_clip = clip
	anim.play(clip, 0.15)
	anim.speed_scale = speed
	if restart:
		anim.seek(0.0, true)


func hurt(amount: float, from: Vector3) -> void:
	if invulnerable:
		return
	if input.block and _spend(amount * 0.8):
		amount *= 0.2
	health = maxf(0.0, health - amount)
	var push := (global_position - from)
	push.y = 0
	velocity += push.normalized() * 6.0 + Vector3(0, 2.5, 0)
	_play("Hit_Chest", 1.3, true)
	_action = 0.35
