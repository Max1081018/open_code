class_name Body3D
extends Node2D
## A real rigged 3D character standing in the 2D world.
##
## The model (KayKit, CC0) lives in its own little 3D world inside a
## SubViewport, filmed by an orthographic camera from the side and a touch
## above; the picture is shown here on a sprite whose bottom centre is the
## character's feet. So the character is truly side-on, turns by actually
## turning round (through facing the camera), animates with the pack's
## skeletal clips, and holds things on its real hand bones.
##
## It speaks the same small language as the old cut-out body (play(),
## flip_h, motion, grounded, speed_scale, footstep...), so actors can use
## either.

signal footstep(running: bool)

## Pixels of viewport per world pixel of height: renders crisp, then is
## scaled down onto the screen.
const SUPERSAMPLE := 1.5
## The picture in world pixels: tall enough for raised arms and a swung
## tool, wide enough for a long reach either side.
const FRAME := Vector2(300, 300)
## World pixels per metre of model.
const PIXELS_PER_METRE := 108.0
## How far round the character turns from facing the camera: 90 would be a
## pure profile. A little less keeps the face readable.
const SIDE_YAW := 72.0

## Game clip -> [model animation, loops, seconds at speed 1].
const CLIPS := {
	"idle": ["Idle", true],
	"walk": ["Walking_A", true],
	"run": ["Running_A", true],
	"jump": ["Jump_Idle", true],
	"fall": ["Jump_Idle", true],
	"land": ["Jump_Land", false],
	"swing_mine": ["2H_Melee_Attack_Chop", false],
	"swing_chop": ["1H_Melee_Attack_Chop", false],
	"slash": ["1H_Melee_Attack_Slice_Diagonal", false],
	"stab": ["1H_Melee_Attack_Stab", false],
	"use": ["Interact", false],
	"interact": ["Interact", false],
	"pickup": ["PickUp", false],
	"talk": ["Interact", false],
	"dodge": ["Dodge_Forward", false],
	"hurt": ["Hit_A", false],
	"death": ["Death_A", false],
	"block": ["Blocking", true],
	"cheer": ["Cheer", false],
	"cast": ["Spellcast_Shoot", false],
	"attack": ["1H_Melee_Attack_Chop", false],
	"spin": ["2H_Melee_Attack_Spin", false],
	"throw": ["Throw", false],
}

## Who plays whom: game character -> [KayKit model, palette swap or ""].
const CAST := {
	"player": ["Rogue_Hooded", ""],
	"wren": ["Mage", ""],
	"bram": ["Barbarian", ""],
	"tobin": ["Barbarian", "tobin"],
	"mira": ["Rogue", "mira"],
	"aldous": ["Knight", ""],
	"zombie": ["Skeleton_Minion", ""],
	"robot": ["Skeleton_Warrior", ""],
	"shade": ["Skeleton_Rogue", ""],
	"warden": ["Skeleton_Warrior", ""],
	"gloam": ["Skeleton_Mage", ""],
}

var character := "Knight"
var palette := ""
var animation := "idle"
var speed_scale := 1.0
var motion := Vector2.ZERO
var grounded := true
var run_speed := 620.0
## Compatibility with the cut-out body: unused here.
var twist := 0.0
var guard := false
var arm_behind := false

var flip_h := false:
	set(value):
		flip_h = value
var facing_yaw := SIDE_YAW   ## current yaw, eased toward the target

var viewport: SubViewport
var picture: Sprite2D
var camera: Camera3D
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var right_hand: BoneAttachment3D
var left_hand: BoneAttachment3D
var _step_phase := 0.0
var _last_step_sign := 1.0
var _held: Node3D
var _off: Node3D
var _one_shot_until := 0.0
var _clock := 0.0


func _init(who := "Knight") -> void:
	var role: Array = CAST.get(who, [who, ""])
	character = role[0]
	palette = role[1]


func _ready() -> void:
	_build()
	play("idle")


func _build() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(FRAME * SUPERSAMPLE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.62, 0.62, 0.7)
	environment.environment.ambient_light_energy = 0.9
	world.add_child(environment)
	# Key light from the upper front, a cool rim from behind.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_energy = 1.15
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.75, 0.85, 1.0)
	world.add_child(rim)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = FRAME.y / PIXELS_PER_METRE
	camera.near = 0.1
	camera.far = 40.0
	# A little above eye level, looking slightly down: the floor plane and
	# the tops of things read as having depth.
	var height := FRAME.y / PIXELS_PER_METRE * 0.5 - 0.35
	camera.position = Vector3(0, height + 1.2, 10)
	camera.rotation_degrees = Vector3(-6.8, 0, 0)
	world.add_child(camera)

	var scene: PackedScene = load("res://assets/models/kaykit/characters/%s.glb" % character)
	model = scene.instantiate()
	world.add_child(model)
	if palette != "":
		_repaint(model, load("res://assets/models/kaykit/textures/%s.png" % palette))
	skeleton = _find(model, func(n): return n is Skeleton3D)
	anim = _find(model, func(n): return n is AnimationPlayer)
	for clip in CLIPS.values():
		var a := anim.get_animation(clip[0]) if anim and anim.has_animation(clip[0]) else null
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if clip[1] else Animation.LOOP_NONE
	# Everything the pack hangs on the hands by default is hidden; held
	# items are chosen by the game.
	if skeleton:
		for child in skeleton.get_children():
			if child is BoneAttachment3D:
				for item in child.get_children():
					if item is MeshInstance3D:
						item.visible = false
		right_hand = _attachment("handslot.r")
		left_hand = _attachment("handslot.l")

	picture = Sprite2D.new()
	picture.texture = viewport.get_texture()
	picture.centered = false
	picture.scale = Vector2.ONE / SUPERSAMPLE
	# Feet (the model's origin) at this node's origin: wherever the tilted
	# camera sees the origin, in viewport pixels.
	var feet := camera.unproject_position(Vector3.ZERO) / SUPERSAMPLE
	picture.position = -feet
	add_child(picture)


## Swap the texture on every surface of the model (a palette variant).
static func _repaint(node: Node, texture: Texture2D) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(i)
			if material is BaseMaterial3D:
				var copy: BaseMaterial3D = material.duplicate()
				copy.albedo_texture = texture
				node.set_surface_override_material(i, copy)
	for child in node.get_children():
		_repaint(child, texture)


func _attachment(bone: String) -> BoneAttachment3D:
	for child in skeleton.get_children():
		if child is BoneAttachment3D and child.bone_name == bone:
			return child
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	return attachment


static func _find(node: Node, test: Callable) -> Node:
	if test.call(node):
		return node
	for child in node.get_children():
		var found := _find(child, test)
		if found:
			return found
	return null


# --- The AnimatedSprite2D-like surface ------------------------------------

func play(clip: String = "", _custom_speed := 1.0, _from_end := false) -> void:
	if clip == "" or anim == null:
		return
	var spec: Array = CLIPS.get(clip, CLIPS.idle)
	var name: String = spec[0]
	if not anim.has_animation(name):
		return
	var loops: bool = spec[1]
	if clip == animation and loops and anim.is_playing():
		return
	animation = clip
	anim.play(name, 0.12 if loops else 0.06)
	if not loops:
		anim.seek(0.0, true)
		_one_shot_until = _clock + anim.get_animation(name).length / maxf(speed_scale, 0.01)


func is_playing() -> bool:
	return anim != null and anim.is_playing()


## Seconds the clip lasts at speed 1.
func clip_length(clip: String) -> float:
	var spec: Array = CLIPS.get(clip, CLIPS.idle)
	if anim and anim.has_animation(spec[0]):
		return anim.get_animation(spec[0]).length
	return 0.5


## Items with a 3D model of their own: item id or kind -> [model, tint].
## Everything else is held as its picture on a card (see _card).
const MODELS := {
	"sword": "sword_1handed", "great_sword": "sword_2handed", "axe": "axe_1handed",
	"shield": "shield_round", "iron_shield": "shield_badge", "staff": "staff", "dagger": "dagger",
}
## Length in metres of each kind of carded item, grip to tip.
const CARD_LENGTH := {"tool": 1.0, "sword": 1.15, "torch": 0.9, "block": 0.42, "other": 0.5}

var _card: Node3D        ## the carded item's pivot, turned to face the camera
var _card_tip := 0.0     ## metres from grip to tip along the card


## Hold an item in the right hand. `kind` is the rig's word for it
## ("tool", "sword", "torch", "block"); "" empties the hand.
func hold_item(id: String, kind: String, picture: Texture2D = null, grip_key := "") -> void:
	if _held:
		_held.queue_free()
	_held = null
	_card = null
	if id == "" or right_hand == null:
		return
	var model_name: String = MODELS.get(id, MODELS.get(kind, "")) if kind == "sword" else MODELS.get(id, "")
	if model_name != "":
		_held = _weapon(model_name)
		_card_tip = 1.3
	else:
		_held = _make_card(picture, grip_key, kind)
	right_hand.add_child(_held)


## A shield (or nothing) on the left arm.
func hold_off_hand(id: String) -> void:
	if _off:
		_off.queue_free()
	_off = null
	if id == "" or left_hand == null:
		return
	_off = _weapon(MODELS.get(id, "shield_round"))
	left_hand.add_child(_off)


func _weapon(name: String) -> Node3D:
	var scene: PackedScene = load("res://assets/models/kaykit/weapons/%s.gltf" % name)
	return scene.instantiate()


func _make_card(texture: Texture2D, key: String, kind: String) -> Node3D:
	var grip: Array = RigData.GRIPS.get(key, [])
	var pivot := Node3D.new()
	var card := Sprite3D.new()
	card.texture = texture
	card.double_sided = true
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	card.shaded = false
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var size := texture.get_size() if texture else Vector2(64, 64)
	var length: float = CARD_LENGTH.get(kind, CARD_LENGTH.other)
	if grip.is_empty():
		# No handle: held in the palm, centred.
		card.pixel_size = length / maxf(size.x, size.y)
		card.position = Vector3(0, length * 0.35, 0)
		_card_tip = length * 0.5
	else:
		var span: float = grip[2]
		card.pixel_size = length / span
		var from_centre: Vector2 = grip[0] - size * 0.5
		card.position = -Vector3(from_centre.x, -from_centre.y, 0) * card.pixel_size
		# The handle-to-head direction (image space) becomes the card's +Y.
		card.rotation.z = 0.0
		var a: float = grip[1]
		var holder := Node3D.new()
		holder.rotation.z = PI * 0.5 + a
		holder.add_child(card)
		pivot.add_child(holder)
		_card_tip = length
		_card = pivot
		return pivot
	pivot.add_child(card)
	_card = pivot
	return pivot


## Where the held item's far end is, in world space (for trails, flames).
func item_tip() -> Vector2:
	if _held == null or not is_instance_valid(_held):
		return front_hand()
	return project(_held.global_position + _held.global_transform.basis.y.normalized() * _card_tip * 0.9)


# --- Where things are, in world space ---------------------------------------

## A point on the model (model space) to world space.
func project(point: Vector3) -> Vector2:
	if camera == null:
		return global_position
	var pixel := camera.unproject_position(point)
	return picture.to_global(pixel)


func front_hand() -> Vector2:
	return project(right_hand.global_position) if right_hand else global_position


func back_hand() -> Vector2:
	return project(left_hand.global_position) if left_hand else global_position


func hip() -> Vector2:
	return global_position + Vector2(0, -95)


func head_position() -> Vector2:
	return global_position + Vector2(0, -190)


func _process(delta: float) -> void:
	_clock += delta
	if anim == null:
		return
	# Turning: round through facing the camera, quickly, as a person does.
	var target := -SIDE_YAW if flip_h else SIDE_YAW
	facing_yaw = move_toward(facing_yaw, target, 900.0 * delta)
	model.rotation_degrees.y = facing_yaw
	_face_card()

	var speed := absf(motion.x)
	var locomotion := animation in ["idle", "walk", "run", "jump", "fall"]
	var one_shot_running := _clock < _one_shot_until and not locomotion
	if not one_shot_running and animation not in ["death", "block"]:
		var clip := "idle"
		if not grounded:
			clip = "jump"
		elif speed > run_speed * 0.62:
			clip = "run"
		elif speed > 40.0:
			clip = "walk"
		if clip != animation:
			play(clip)
	# Gait speed matched to ground speed, so feet do not slide.
	if animation == "walk":
		anim.speed_scale = clampf(speed / 260.0, 0.6, 1.6)
	elif animation == "run":
		anim.speed_scale = clampf(speed / 560.0, 0.8, 1.5)
	else:
		anim.speed_scale = speed_scale
	# Footsteps twice a cycle, on the clip's own timing.
	if animation in ["walk", "run"] and grounded:
		var length := anim.current_animation_length
		if length > 0.0:
			var phase := fmod(anim.current_animation_position / length, 1.0)
			var side := 1.0 if phase < 0.5 else -1.0
			if side != _last_step_sign:
				_last_step_sign = side
				footstep.emit(animation == "run")


## The carded item points along the hand's grip axis but always shows its
## face to the camera, so it never turns edge-on and vanishes.
func _face_card() -> void:
	if _card == null or not is_instance_valid(_card) or right_hand == null:
		return
	var along := right_hand.global_transform.basis.y
	along.z = 0.0
	if along.length() < 0.05:
		along = Vector3.UP
	along = along.normalized()
	var toward_camera := Vector3(0, 0, 1)
	var across := along.cross(toward_camera).normalized()
	_card.global_transform = Transform3D(Basis(across, along, toward_camera), right_hand.global_position)
	# Facing left, the picture is mirrored so the head stays forward.
	if flip_h:
		_card.global_transform.basis.x = -_card.global_transform.basis.x
