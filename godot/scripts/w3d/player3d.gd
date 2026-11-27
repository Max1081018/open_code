class_name Player3D
extends CharacterBody3D
## The hero in the open world: the downloaded hooded wanderer on the shared
## humanoid rig, moved relative to the camera and turning smoothly toward
## where they go. Walk, run, sprint (stamina), jump with fall and landing,
## a dodge roll with invulnerable frames, wading then swimming when the water
## is chest deep. Holds items in a grip on the right hand bone.

signal swung(kind: String)
signal burned   ## stepped into lava
signal died     ## health ran out; the game revives her (revive())

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
var gliding := false
## Upward wind from an updraft this frame (set by WorldFeatures).
var updraft := 0.0
const GLIDE_SPEED := 9.0
const GLIDE_SINK := 2.2
var _dodge := 0.0
var _dodge_dir := Vector3.ZERO
var _action := 0.0         ## seconds left of an attack/use animation
var _action_name := ""
var _air_time := 0.0
var _landing := 0.0
var _glided := false   ## glided since leaving the ground (lands softly)
var _lean := 0.0
var _clip := ""
var invulnerable := false
var _head_meshes: Array = []
var _idle_time := 0.0
var _idle_break := 0.0
## Little things she does when left standing.
## Idle breaks: [clip, seconds, speed, weight]. The spell flourish lights
## violet sparks at her hand; the little dance is rare.
const IDLE_BREAKS := [["Idle_Own", 4.0, 1.0, 4], ["Idle_FoldArms", 3.2, 1.0, 3], ["Yes", 2.0, 1.0, 2],
	["Idle_Talking", 3.0, 1.0, 4], ["Spell_Simple_Idle", 2.6, 1.0, 3], ["Idle_No", 2.0, 1.0, 1],
	["Dance", 3.4, 1.0, 1]]


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(48)
	floor_snap_length = 0.5
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.56
	shape.shape = capsule
	shape.position = Vector3(0, 0.78, 0)
	add_child(shape)
	model = CharacterKit.build(Account.character_kit())
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for clip in ["Idle_FoldArms", "Idle_Talking", "Idle", "ual/Idle", "Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Swim_Fwd", "Swim_Idle", "Jump", "Sword_Block", "Sword_Idle", "ual/Jog_Fwd", "ual/Sprint"]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).extra_cull_margin = 2.0
	_build_look()
	right_hand = HumanoidGrip.grip(skeleton, model, "RightHand", "RightIndexProximal", "RightLittleProximal", "RightMiddleProximal")
	left_hand = HumanoidGrip.grip(skeleton, model, "LeftHand", "LeftIndexProximal", "LeftLittleProximal", "LeftMiddleProximal")
	var head := BoneAttachment3D.new()
	head.bone_name = "Head"
	skeleton.add_child(head)
	head_anchor = head
	_find_head_meshes()
	_build_tree()
	_gait(0.0)
	_float_pose = FloatPose.new()
	skeleton.add_child(_float_pose)


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


## Weapons and tools are summoned to the hand when used (a burst of
## starlight) and dismissed a few seconds after, as in anime action RPGs;
## torches and the like stay in hand.
const SUMMON_TIME := 3.5
var _summoned := 0.0


## Her head turns to look at someone nearby (set by the townsfolk logic).
var _look: LookAtModifier3D
var _look_target: Node3D
var look_at_point = null   ## Vector3 or null


func _build_look() -> void:
	_look_target = Node3D.new()
	add_child(_look_target)
	_look = LookAtModifier3D.new()
	_look.bone_name = "Head"
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.primary_rotation_axis = Vector3.AXIS_Y
	_look.use_angle_limitation = true
	_look.primary_limit_angle = deg_to_rad(120.0)
	_look.secondary_limit_angle = deg_to_rad(50.0)
	_look.duration = 0.45
	_look.transition_type = Tween.TRANS_SINE
	_look.influence = 0.0
	skeleton.add_child(_look)
	_look.target_node = _look.get_path_to(_look_target)


func _update_look(delta: float) -> void:
	if _look == null:
		return
	var want := 0.0
	if look_at_point != null and not busy() and not gliding:
		_look_target.global_position = look_at_point
		var to: Vector3 = (look_at_point as Vector3) - global_position
		to.y = 0.0
		var fwd := model.global_transform.basis.z
		fwd.y = 0.0
		if to.length() > 0.1 and fwd.normalized().dot(to.normalized()) > -0.1:
			want = 0.85
	_look.influence = move_toward(_look.influence, want, delta * 2.5)


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
		if id == "moonblade":
			_moonblade_aura(_held)
		if _summonable(id) and _summoned <= 0.0:
			_held.visible = false


## While a heavy stroke charges, the Moonblade's light swells; a chime and
## a burst of motes say it is ready.
var _charged := false


func _charge_glow() -> void:
	var ch: float = input.charge
	if _held != null:
		for l in _held.get_children():
			if l is OmniLight3D:
				(l as OmniLight3D).light_energy = 0.7 + ch * 2.2
	if ch >= 1.0 and not _charged:
		_charged = true
		Sfx.play("magic_slash", -8.0, 0.0, 1.4)
		if _held != null:
			Arcana.sparks(get_parent(), _held.global_position + Vector3(0, 0.4, 0), Color(0.85, 0.6, 1.0), 18, 3.0, 0.08)
	elif ch < 1.0:
		_charged = false


## Violet arcana around the Moonblade: motes drifting up off the blade and
## a soft light on her hand.
func _moonblade_aura(blade: Node3D) -> void:
	var length: float = blade.get_meta("length", 1.0)
	var motes := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	motes.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.vertex_color_use_as_albedo = true
	motes.material_override = m
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.95, 0.85, 1.0, 0.0), Color(0.8, 0.55, 1.0, 0.9), Color(0.6, 0.35, 1.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	motes.color_ramp = ramp
	motes.amount = 22
	motes.lifetime = 0.9
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(0.03, length * 0.38, 0.03)
	motes.position = Vector3(0, length * 0.55, 0)
	motes.direction = Vector3.UP
	motes.spread = 40.0
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.4
	motes.gravity = Vector3(0, 0.6, 0)
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.4
	blade.add_child(motes)
	var light := OmniLight3D.new()
	light.light_color = Color(0.72, 0.45, 1.0)
	light.light_energy = 0.7
	light.omni_range = 2.2
	light.shadow_enabled = false
	light.position = Vector3(0, length * 0.6, 0)
	blade.add_child(light)


static func _summonable(id: String) -> bool:
	return Items.kind(id) in [Items.Kind.SWORD, Items.Kind.AXE, Items.Kind.PICKAXE, Items.Kind.HAMMER, Items.Kind.SHIELD]


## Bring the held weapon or tool into the hand (if it is away).
func summon() -> void:
	if _held == null or not _summonable(held_id):
		return
	var was := _summoned
	_summoned = SUMMON_TIME
	if was <= 0.0 or not _held.visible:
		_held.visible = true
		_held.scale = Vector3.ONE * 0.2
		_held.create_tween().tween_property(_held, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_sparkle(right_hand.global_position)


func _dismiss() -> void:
	if _held == null or not _held.visible:
		return
	_sparkle(right_hand.global_position)
	var t := _held.create_tween()
	t.tween_property(_held, "scale", Vector3.ONE * 0.05, 0.18).set_ease(Tween.EASE_IN)
	t.tween_callback(_put_away.bind(_held))


func _put_away(h: Node3D) -> void:
	if is_instance_valid(h) and _summoned <= 0.0:
		h.visible = false
		h.scale = Vector3.ONE


## Footsteps: one footfall per stride, its sound by the ground underfoot,
## and dust kicked up when running.
const STEP_SOUND := {"stone": "step_stone", "snow": "step_snow", "sand": "step", "grass": "step_grass"}
const DUST := {"stone": Color(0.86, 0.84, 0.8, 0.55), "snow": Color(0.97, 0.98, 1.0, 0.7),
	"sand": Color(0.92, 0.84, 0.66, 0.6), "grass": Color(0.78, 0.82, 0.62, 0.4)}
var _stride := 0.0
static var _dust_mat: StandardMaterial3D


func _surface() -> String:
	if world == null:
		return "grass"
	var p := global_position
	var gen: TerrainGen = world.gen
	if gen.paved(p.x, p.z) > 0.5:
		return "stone"
	var h := gen.height(p.x, p.z)
	if p.y > h + 1.5:
		return "stone"  # on a bridge, a roof, an isle's rock
	match gen.biome(p.x, p.z):
		TerrainGen.Biome.SNOW:
			return "snow"
		TerrainGen.Biome.DRY, TerrainGen.Biome.BEACH:
			return "sand"
	return "grass"


func _footfall(delta: float, hspeed: float) -> void:
	if not is_on_floor() or swimming or hspeed < 1.2:
		_stride = 0.0
		return
	_stride += delta * hspeed
	var stride_len := 1.3 if hspeed > 5.0 else 0.95
	if _stride < stride_len:
		return
	_stride -= stride_len
	var surf := _surface()
	Sfx.play(STEP_SOUND[surf], -12.0 if hspeed < 5.0 else -8.0, 0.12)
	if hspeed > 4.0:
		_puff(global_position, surf, 5 if hspeed > 6.5 else 3, 0.8)


## A puff of dust at the feet, tinted to the ground.
func _puff(at: Vector3, surf: String, amount: int, spread: float) -> void:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.albedo_texture = Play3D._spark_texture()
		_dust_mat.vertex_color_use_as_albedo = true
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	p.mesh = q
	p.material_override = _dust_mat
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.2 * spread
	p.emission_ring_inner_radius = 0.05
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 75.0
	p.gravity = Vector3(0, -0.4, 0)
	p.initial_velocity_min = 0.4 * spread
	p.initial_velocity_max = 1.1 * spread
	p.damping_min = 2.5
	p.damping_max = 3.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var c: Color = DUST[surf]
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([c, Color(c.r, c.g, c.b, 0.0)])
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(get_tree().current_scene if get_tree().current_scene else get_parent()).add_child(p)
	p.global_position = at + Vector3(0, 0.05, 0)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static var _sparkle_mat: StandardMaterial3D


## A small burst of starlight at the hand.
func _sparkle(at: Vector3) -> void:
	if _sparkle_mat == null:
		_sparkle_mat = StandardMaterial3D.new()
		_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sparkle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_sparkle_mat.albedo_texture = Play3D._spark_texture()
		_sparkle_mat.vertex_color_use_as_albedo = true
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	p.mesh = q
	p.material_override = _sparkle_mat
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 18
	p.lifetime = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.75, 0.9, 1.0, 1.0), Color(1.0, 0.86, 0.5, 0.0)])
	p.color_ramp = ramp
	(get_tree().current_scene if get_tree().current_scene else get_parent()).add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _physics_process(delta: float) -> void:
	if input == null or cam == null:
		return
	_grace -= delta
	if dead:
		# Fallen: no control; she settles where she fell.
		velocity.x = move_toward(velocity.x, 0.0, delta * 20.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 20.0)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		input.move = Vector2.ZERO
		input.jump = false
		input.attack = false
		input.heavy = false
		input.dodge = false
		return
	if _summoned > 0.0 and not busy():
		_summoned -= delta
		if _summoned <= 0.0:
			_dismiss()
	cam.apply_look(input.look)
	input.look = Vector2.ZERO
	if input.toggle_view:
		input.toggle_view = false
		cam.first_person = not cam.first_person
		set_first_person(cam.first_person)

	var wish := cam.right_flat() * input.move.x + cam.forward_flat() * input.move.y
	var water_depth := TerrainGen.WATER - global_position.y
	swimming = water_depth > 1.15
	_lava_check(water_depth, delta)
	_charge_glow()
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
	# A tap during a swing is kept for a moment and becomes the next blow.
	_buffer -= delta
	_since_blow += delta
	if input.attack or input.heavy:
		_buffer = 0.4
		_buffer_heavy = input.heavy
	if _buffer > 0.0 and _action <= 0.0 and _dodge <= 0.0 and not swimming:
		_buffer = 0.0
		_start_action(_buffer_heavy)

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
	if gliding:
		speed = GLIDE_SPEED
	if _action > 0.0:
		speed *= 0.25

	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var target := wish * speed
	if _dodge > 0.0:
		target = _dodge_dir * DODGE_SPEED * clampf(_dodge / DODGE_TIME + 0.3, 0.0, 1.0)
	var accel := 14.0 if is_on_floor() or swimming else (2.5 if gliding else 4.0)
	if gliding and wish.length() < 0.1:
		target = model.global_transform.basis.z * GLIDE_SPEED * 0.7  # keep flying forward
	horizontal = horizontal.lerp(target, 1.0 - exp(-accel * delta))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if swimming:
		# Float with the chest at the surface; jump swims upward.
		var float_y := TerrainGen.WATER - 1.2
		velocity.y = lerpf(velocity.y, (float_y - global_position.y) * 3.0 + (3.0 if input.jump else 0.0), 1.0 - exp(-4.0 * delta))
	elif gliding:
		# Wings out: a slow sink, lifted by updrafts; stamina drains.
		var sink := -GLIDE_SINK + updraft
		velocity.y = lerpf(velocity.y, sink, 1.0 - exp(-3.0 * delta))
		stamina -= delta * (5.0 if updraft <= 0.0 else 0.0)
		_stamina_wait = 0.6
		if stamina <= 0.0 or input.jump:
			input.jump = false
			_set_glide(false)
	else:
		velocity.y -= GRAVITY * delta
		velocity.y += updraft * delta * 3.0
		var jump_now := input.jump
		input.jump = false
		if jump_now and is_on_floor() and _dodge <= 0.0 and _spend(8.0):
			velocity.y = JUMP
			_play("Jump_Start", 1.4, true)
			Sfx.play("jump", -8.0)
		elif jump_now and not is_on_floor() and _air_time > 0.2 and stamina > 5.0:
			_set_glide(true)
	var was_air := not is_on_floor()
	move_and_slide()
	if is_on_floor() or swimming:
		if gliding:
			_set_glide(false)
	if is_on_floor():
		if was_air and _air_time > 1.3 and not _glided:
			# A long drop: a crouching hard landing that costs a moment.
			_landing = 0.55
			_play("NinjaJump_Land", 1.3, true)
			_puff(global_position, _surface(), 24, 2.4)
		elif was_air and _air_time > 0.35:
			_landing = 0.25
			_play("Jump_Land", 1.6, true)
			var surf := _surface()
			_puff(global_position, surf, 16, 1.6)
			Sfx.play("land", -4.0)
		_air_time = 0.0
		_glided = false
	else:
		_air_time += delta
		if gliding:
			_glided = true
	_landing -= delta
	_footfall(delta, Vector2(velocity.x, velocity.z).length())
	_update_look(delta)

	# Face where we move (or where the camera looks while acting / in first person).
	var face := Vector3.ZERO
	if cam.first_person or _action > 0.0:
		face = cam.forward_flat()
	elif horizontal.length() > 0.4:
		face = horizontal.normalized()
	var turn := 0.0
	if face != Vector3.ZERO:
		var want := atan2(face.x, face.z)
		var before := model.rotation.y
		model.rotation.y = lerp_angle(model.rotation.y, want, 1.0 - exp(-12.0 * delta))
		turn = angle_difference(before, model.rotation.y) / maxf(delta, 0.001)
	# Lean into turns at speed (a banked run), never while acting or swimming.
	var lean_want := 0.0
	if is_on_floor() and _action <= 0.0 and not swimming:
		lean_want = clampf(-turn * horizontal.length() * 0.012, -0.22, 0.22)
	_lean = lerpf(_lean, lean_want, 1.0 - exp(-8.0 * delta))
	model.rotation.z = _lean
	_animate(horizontal.length())
	_update_float(delta, horizontal.length())
	_ground_feet(delta)


## Keep the lowest foot on the ground whatever the animation does to the
## hips (clips from other rigs carry their own hip height).
func _ground_feet(delta: float) -> void:
	var inner: Node3D = model.get_child(0)
	var base: float = model.get_meta("model_y", inner.position.y)
	if not is_on_floor() or swimming or _float > 0.02:
		inner.position.y = lerpf(inner.position.y, base, 1.0 - exp(-10.0 * delta))
		return
	var l := skeleton.find_bone("LeftFoot")
	var r := skeleton.find_bone("RightFoot")
	if l < 0 or r < 0:
		return
	var foot := minf((skeleton.global_transform * skeleton.get_bone_global_pose(l)).origin.y,
		(skeleton.global_transform * skeleton.get_bone_global_pose(r)).origin.y)
	var ankle: float = model.get_meta("ankle", 0.08)
	var gap := foot - ankle - global_position.y
	var want := clampf(inner.position.y - gap, base - 0.35, base + 0.15)
	inner.position.y = lerpf(inner.position.y, want, 1.0 - exp(-14.0 * delta))


## Glide: arms out, a slow fall (she has no wings: the float is magic).
func _set_glide(on: bool) -> void:
	gliding = on
	if on:
		velocity.y = maxf(velocity.y, -1.0)
		_play("Jump", 0.6, true)


## The sword combo: A, B, then C (a finisher), if each blow follows the
## last quickly; a pause starts it again.
var combo_step := 0
var _since_blow := 9.0
var _buffer := 0.0
var _buffer_heavy := false


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
				combo_step = 0
			else:
				combo_step = (combo_step + 1) % 3 if _since_blow < 0.75 else 0
				clip = ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C"][combo_step]
				time = [0.48, 0.5, 0.68][combo_step]
	_action = time
	_since_blow = -time   # counts from when this blow ends
	_action_name = kind
	summon()
	_play(clip, 1.2, true)
	swung.emit(kind + ("_heavy" if heavy else ""))


## Play a scripted move (skills): locks movement like an attack.
func perform(clip: String, seconds: float, speed := 1.0) -> void:
	_action = seconds
	summon()
	_play(clip, speed, true)


func busy() -> bool:
	return _action > 0.0 or _dodge > 0.0


func _spend(amount: float) -> bool:
	if stamina < amount * 0.5:
		return false
	stamina = maxf(0.0, stamina - amount)
	_stamina_wait = 0.9
	return true


## Floating repose: still for a few seconds (no foes near), she rises half a
## metre and reclines on the air, a violet rune circle turning beneath her,
## motes rising and light at her hands; anything she does brings her down.
var _float := 0.0
var _still := 0.0
var _float_pose: FloatPose
var _float_fx: Node3D
var _float_circle: ShaderMaterial
var _float_shade: ShaderMaterial
var _float_light: OmniLight3D
var _float_motes: CPUParticles3D
var _float_t := 0.0
## Capture harness: float as soon as she is calm.
var force_float := false


func floating() -> bool:
	return _float > 0.3


func _update_float(delta: float, speed: float) -> void:
	var calm := speed < 0.3 and is_on_floor() and not swimming and _action <= 0.0 and _dodge <= 0.0 \
		and not _on_guard and not input.block and not dead and _landing <= 0.0
	_still = _still + delta if calm else 0.0
	var want := 1.0 if calm and _idle_break <= 0.0 and (_still > 1.6 or force_float) else 0.0
	_float = move_toward(_float, want, delta * (0.9 if want > _float else 3.5))
	_float_t += delta
	var k := _float * _float * (3.0 - 2.0 * _float)
	model.position.y = k * (0.5 + sin(_float_t * 1.3) * 0.06)
	model.rotation.x = -0.6 * k
	if _float_pose:
		_float_pose.amount = k
	if _float > 0.01 and _float_fx == null:
		_make_float_fx()
	if _float_fx:
		_float_fx.visible = _float > 0.01
		_float_circle.set_shader_parameter("fade", k)
		_float_circle.set_shader_parameter("grow", clampf(k * 1.2, 0.0, 1.0))
		_float_shade.set_shader_parameter("amount", k * 0.85)
		_float_light.light_energy = 1.3 * k
		_float_motes.emitting = k > 0.4
		_float_fx.global_position = global_position + Vector3(0, 0.06, 0)
		_float_fx.rotation.y += delta * 0.2


func _make_float_fx() -> void:
	_float_fx = Node3D.new()
	_float_fx.top_level = true
	add_child(_float_fx)
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2, 2.2)
	ring.mesh = plane
	_float_circle = ShaderMaterial.new()
	_float_circle.shader = load("res://scripts/shaders/magic_circle.gdshader")
	_float_circle.set_shader_parameter("tint", Color(0.62, 0.3, 1.0))
	_float_circle.set_shader_parameter("strength", 1.0)
	_float_circle.set_shader_parameter("spin", 0.18)
	ring.material_override = _float_circle
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A violet dusk under the lines keeps them coloured in bright sun.
	var under := MeshInstance3D.new()
	var up := PlaneMesh.new()
	up.size = Vector2(2.6, 2.6)
	under.mesh = up
	_float_shade = ShaderMaterial.new()
	_float_shade.shader = load("res://scripts/shaders/magic_shade.gdshader")
	under.material_override = _float_shade
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	under.position.y = -0.005
	_float_fx.add_child(under)
	_float_fx.add_child(ring)
	_float_light = OmniLight3D.new()
	_float_light.light_color = Color(0.72, 0.48, 1.0)
	_float_light.omni_range = 4.0
	_float_light.shadow_enabled = false
	_float_light.position = Vector3(0, 0.9, 0)
	_float_fx.add_child(_float_light)
	_float_motes = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	_float_motes.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Play3D._spark_texture()
	m.vertex_color_use_as_albedo = true
	_float_motes.material_override = m
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.95, 0.85, 1.0, 0.0), Color(0.82, 0.6, 1.0, 0.9), Color(0.6, 0.35, 1.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	_float_motes.color_ramp = ramp
	_float_motes.amount = 34
	_float_motes.lifetime = 2.2
	_float_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_float_motes.emission_ring_axis = Vector3.UP
	_float_motes.emission_ring_radius = 0.9
	_float_motes.emission_ring_inner_radius = 0.2
	_float_motes.emission_ring_height = 0.05
	_float_motes.direction = Vector3.UP
	_float_motes.spread = 12.0
	_float_motes.initial_velocity_min = 0.3
	_float_motes.initial_velocity_max = 0.8
	_float_motes.gravity = Vector3(0, 0.25, 0)
	_float_motes.scale_amount_min = 0.6
	_float_motes.scale_amount_max = 1.5
	_float_fx.add_child(_float_motes)
	_float_motes.position = Vector3(0, 0.05, 0)


## On guard: foes near or a fight just now: she stands in a sword stance.
var _on_guard := false
var _guard_hold := 0.0


func _update_guard(dt: float) -> void:
	_guard_hold -= dt
	if _action > 0.0 and _action_name == "attack":
		_guard_hold = 4.0
	var near := _guard_hold > 0.0
	if not near:
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.dead and e.global_position.distance_to(global_position) < 14.0:
				near = true
				break
	if near != _on_guard and tree:
		_on_guard = near
		var gait := (tree.tree_root as AnimationNodeBlendTree).get_node("gait") as AnimationNodeBlendSpace1D
		var style: Dictionary = model.get_meta("style", {})
		var idle: String = "Sword_Idle" if near else String(style.get("clips", {}).get("Idle", "Idle"))
		(gait.get_blend_point_node(0) as AnimationNodeAnimation).animation = idle


func _animate(speed: float) -> void:
	var dt := get_physics_process_delta_time()
	_update_guard(dt)
	if _action > 0.0 or _dodge > 0.0 or _landing > 0.0:
		_idle_time = 0.0
		_idle_break = 0.0
		return
	if speed < 0.3 and is_on_floor() and not swimming and not input.block:
		_idle_time += dt
		if _idle_break > 0.0:
			_idle_break -= dt
			if _float > 0.01:
				_idle_break = 0.0  # never strike a pose while rising into the float
			if _idle_break > 0.0:
				return
		elif _idle_time > 2.6 and randf() < dt * 0.9 and not _on_guard and _still < 1.4 and _float < 0.01:
			var total := 0
			for e in IDLE_BREAKS:
				total += int(e[3])
			var pick := randi() % total
			var b: Array = IDLE_BREAKS[0]
			for e in IDLE_BREAKS:
				pick -= int(e[3])
				if pick < 0:
					b = e
					break
			_idle_break = b[1]
			_idle_time = 0.0
			_play(b[0], b[2], true)
			if b[0] == "Spell_Simple_Idle":
				get_tree().create_timer(0.5).timeout.connect(func():
					if is_instance_valid(right_hand):
						Arcana.sparks(get_parent(), right_hand.global_position, Color(0.8, 0.55, 1.0), 22, 2.0, 0.07, 0.8))
			return
	else:
		_idle_time = 0.0
		_idle_break = 0.0
	if swimming:
		_play("Swim_Fwd" if speed > 0.5 else "Swim_Idle")
	elif gliding or (not is_on_floor() and _air_time > 0.15):
		_play("Jump")
	elif input.block:
		_play("Sword_Block")
	else:
		_gait(speed)


## The heroine's AnimationTree. Two inputs feed a crossfading Transition:
## "gait", a 1D blend space of idle, walk, jog and sprint placed along her
## speed (so starting and stopping blend through the walk instead of
## popping), played at the rate that keeps a planted foot still on the
## ground; and two clip slots ("a", "b") taking turns for every other move,
## so one action can crossfade into the next, even into itself.
## Measured ground speeds of the clips (tools/measure_gait.gd), m/s.
const GAIT_SPEED := {"Walk": 2.35, "Jog_Fwd": 5.4, "Sprint": 4.9}
var tree: AnimationTree
var _slot := "b"
var _mode := ""


func _build_tree() -> void:
	var style: Dictionary = model.get_meta("style", {})
	var clips: Dictionary = style.get("clips", {})
	var gait := AnimationNodeBlendSpace1D.new()
	gait.min_space = 0.0
	gait.max_space = 10.0
	gait.sync = true
	# Points: idle at rest; walk alone up to 3 m/s; jog 3.8-6; sprint beyond 7.2.
	for p in [["Idle", 0.0], ["Walk", 1.2], ["Walk", 3.0], ["Jog_Fwd", 3.8], ["Jog_Fwd", 6.0], ["Sprint", 7.2]]:
		var a := AnimationNodeAnimation.new()
		a.animation = clips.get(p[0], p[0])
		gait.add_blend_point(a, p[1])
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("gait", gait, Vector2(0, 0))
	bt.add_node("gait_rate", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("gait_rate", 0, "gait")
	var mix := AnimationNodeTransition.new()
	mix.xfade_time = 0.15
	for input in ["gait", "a", "b"]:
		mix.add_input(input)
	bt.add_node("mix", mix, Vector2(600, 0))
	bt.connect_node("mix", 0, "gait_rate")
	for slot in ["a", "b"]:
		bt.add_node(slot, AnimationNodeAnimation.new(), Vector2(0, 200))
		bt.add_node(slot + "_rate", AnimationNodeTimeScale.new(), Vector2(200, 200))
		bt.connect_node(slot + "_rate", 0, slot)
		bt.connect_node("mix", 1 if slot == "a" else 2, slot + "_rate")
	bt.connect_node("output", 0, "mix")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	anim.get_parent().add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	# Track paths resolve from the same node as the player's.
	tree.root_node = tree.get_path_to(anim.get_node(anim.root_node))
	anim.stop()
	anim.active = false
	tree.active = true


## Drive the gait at `speed` m/s.
func _gait(speed: float) -> void:
	var rate := 1.0
	if speed > 1.2:
		# The clip speed at this point of the blend, and the rate that matches it.
		var natural: float = GAIT_SPEED["Walk"]
		if speed > 3.0:
			natural = lerpf(GAIT_SPEED["Walk"], GAIT_SPEED["Jog_Fwd"], clampf((speed - 3.0) / 0.8, 0.0, 1.0))
		if speed > 6.0:
			natural = lerpf(GAIT_SPEED["Jog_Fwd"], GAIT_SPEED["Sprint"], clampf((speed - 6.0) / 1.2, 0.0, 1.0))
		rate = clampf(speed / natural, 0.5, 1.55)
	else:
		rate = lerpf(1.0, 1.2 / GAIT_SPEED["Walk"], speed / 1.2)
	tree.set("parameters/gait/blend_position", speed)
	tree.set("parameters/gait_rate/scale", rate * float(model.get_meta("style", {}).get("speed", 1.0)))
	if _mode != "gait":
		_mode = "gait"
		_clip = ""
		tree.set("parameters/mix/transition_request", "gait")


func _play(clip: String, speed := 1.0, restart := false) -> void:
	var style: Dictionary = model.get_meta("style", {})
	clip = style.get("clips", {}).get(clip, clip)
	speed *= float(style.get("speed", 1.0))
	if not anim.has_animation(clip):
		return
	if clip == _clip and not restart:
		tree.set("parameters/%s_rate/scale" % _slot, speed)
		return
	_clip = clip
	_mode = "clip"
	_slot = "a" if _slot == "b" else "b"
	var bt := tree.tree_root as AnimationNodeBlendTree
	(bt.get_node(_slot) as AnimationNodeAnimation).animation = clip
	tree.set("parameters/%s_rate/scale" % _slot, speed)
	tree.set("parameters/mix/transition_request", _slot)


## The Ashlands' lakes are lava: touching one burns and throws the heroine
## back to the last firm ground she stood on.
var _safe_pos := Vector3.ZERO
var _burn_wait := 0.0


func _lava_check(water_depth: float, delta: float) -> void:
	_burn_wait -= delta
	if world == null:
		return
	var lava := world.gen.volcanic(global_position.x, global_position.z) > 0.5
	if water_depth < -0.3 and is_on_floor():
		_safe_pos = global_position
	if not lava or water_depth < 0.1 or _burn_wait > 0.0 or dead:
		return
	_burn_wait = 0.6
	health = maxf(0.0, health - 18.0)
	if health <= 0.0:
		_die()
		return
	_play("Hit_Chest", 1.3, true)
	_action = 0.35
	if _safe_pos == Vector3.ZERO:
		_safe_pos = _nearest_shore()
	global_position = _safe_pos + Vector3(0, 0.5, 0)
	velocity = Vector3(0, 4.0, 0)
	burned.emit()


## The closest dry ground, searched in widening rings.
func _nearest_shore() -> Vector3:
	var gen: TerrainGen = world.gen
	for ring in range(1, 40):
		var r := ring * 4.0
		for k in 16:
			var a := k * TAU / 16.0
			var x := global_position.x + cos(a) * r
			var z := global_position.z + sin(a) * r
			var h := gen.height(x, z)
			if h > TerrainGen.WATER + 0.6:
				return Vector3(x, h, z)
	return global_position + Vector3(0, 2, 0)


var dead := false
var _hits := 0
var _grace := 0.0   ## seconds of mercy after reviving


func _die() -> void:
	dead = true
	if gliding:
		_set_glide(false)
	_action = 0.0
	_dodge = 0.0
	_play("Death01", 1.0, true)
	died.emit()


## Back on her feet at `at`: full health and stamina, getting up from the
## ground, briefly untouchable.
func revive(at: Vector3) -> void:
	dead = false
	health = max_health
	stamina = max_stamina
	global_position = at
	velocity = Vector3.ZERO
	_safe_pos = at
	_grace = 3.0
	_action = 1.6
	_play("LayToIdle", 1.0, true)


func hurt(amount: float, from: Vector3) -> void:
	if invulnerable or dead or _grace > 0.0:
		return
	if input.block and _spend(amount * 0.8):
		amount *= 0.2
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()
		return
	var push := (global_position - from)
	push.y = 0
	if amount >= 25.0:
		# A heavy blow throws her back.
		velocity += push.normalized() * 10.0 + Vector3(0, 3.5, 0)
		_play("Hit_Knockback", 1.2, true)
		_action = 0.8
	else:
		velocity += push.normalized() * 6.0 + Vector3(0, 2.5, 0)
		_hits += 1
		_play("Hit_Head" if _hits % 2 == 0 else "Hit_Chest", 1.3, true)
		_action = 0.35
