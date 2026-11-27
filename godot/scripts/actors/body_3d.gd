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

## Render scale for this body: raise it for big bodies (bosses) drawn
## scaled up, so they stay sharp.
var supersample := SUPERSAMPLE
## Anti-aliasing for this body's render (off for crowds of enemies).
var smooth := true
## The picture in world pixels: tall enough for raised arms and a swung
## tool, wide enough for a long reach either side.
const FRAME := Vector2(300, 300)
## World pixels per metre of model.
const PIXELS_PER_METRE := 108.0
## How far round the character turns from facing the camera: 90 would be a
## pure profile. A little less keeps the face readable.
const SIDE_YAW := 72.0

## The same game clips on the Quaternius characters (Universal Animation
## Library 1 and 2): [clip, loops].
const KIT_CLIPS := {
	"idle": ["Idle", true], "walk": ["Walk", true], "run": ["Jog_Fwd", true], "jump": ["Jump", true],
	"fall": ["Jump", true], "land": ["Jump_Land", false], "swing_mine": ["Sword_Regular_C", false],
	"swing_chop": ["TreeChopping", false], "slash": ["Sword_Regular_A", false], "stab": ["Sword_Regular_B", false],
	"use": ["Interact", false], "interact": ["Interact", false], "pickup": ["PickUp_Table", false],
	"talk": ["Idle_Talking", true], "dodge": ["Roll", false], "hurt": ["Hit_Chest", false],
	"death": ["Death01", false], "block": ["Sword_Block", true], "cheer": ["Yes", false],
	"cast": ["Spell_Simple_Shoot", false], "attack": ["Sword_Attack", false], "spin": ["Sword_Heavy_Combo", false],
	"throw": ["OverhandThrow", false], "rise": ["LayToIdle", false], "taunt": ["Sword_Idle", false],
	"craft": ["Fixing_Kneeling", false], "swim": ["Swim_Fwd", true], "chest": ["Chest_Open", false],
	"eat": ["Consume", false],
}
## The shambling dead walk, idle and claw differently.
const UNDEAD_CLIPS := {
	"idle": ["Zombie_Idle", true], "walk": ["Zombie_Walk_Fwd", true], "run": ["Zombie_Walk_Fwd", true],
	"attack": ["Zombie_Scratch", false],
}
const SHAMBLERS := ["zombie", "shade"]

## Who can be played by a 3D body: every CharacterKit recipe.
const CAST := CharacterKit.RECIPES

var role := ""
var clips: Dictionary = KIT_CLIPS
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
var right_hand: Node3D  ## the grip in the right hand (handslot.r on KayKit)
var left_hand: Node3D
var _step_phase := 0.0
var _last_step_sign := 1.0
var _held: Node3D
var _off: Node3D
var _one_shot_until := 0.0
var _clock := 0.0


func _init(who := "Knight") -> void:
	role = who if CharacterKit.has(who) else "player"
	clips = KIT_CLIPS.duplicate()
	if role in SHAMBLERS:
		clips.merge(UNDEAD_CLIPS, true)


func _ready() -> void:
	_build()
	play("idle")


func _build() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(FRAME * supersample)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	# (Settings is an autoload; tool scripts that film bodies run without it.)
	var settings: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	var low_end: bool = settings != null and settings.lighting < 1
	viewport.msaa_3d = Viewport.MSAA_2X if smooth and not low_end else Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Art direction: warm golden key, cool blue shadow and rim.
	environment.environment.ambient_light_color = Color(0.48, 0.54, 0.7)
	environment.environment.ambient_light_energy = 0.75
	world.add_child(environment)
	# Key light from the upper front, a cool rim from behind.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.35
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.62, 0.76, 1.0)
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

	model = CharacterKit.build(role)
	world.add_child(model)
	skeleton = _find(model, func(n): return n is Skeleton3D)
	anim = _find(model, func(n): return n is AnimationPlayer)
	for clip in clips.values():
		var a := anim.get_animation(clip[0]) if anim and anim.has_animation(clip[0]) else null
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if clip[1] else Animation.LOOP_NONE
	if skeleton:
		if skeleton.find_bone("RightHand") >= 0:
			# A retargeted humanoid (the downloaded cast): standard bone names.
			right_hand = _grip("RightHand", "RightIndexProximal", "RightLittleProximal", "RightMiddleProximal")
			left_hand = _grip("LeftHand", "LeftIndexProximal", "LeftLittleProximal", "LeftMiddleProximal")
		else:
			right_hand = _grip("hand_r", "index_01_r", "pinky_01_r", "middle_01_r")
			left_hand = _grip("hand_l", "index_01_l", "pinky_01_l", "middle_01_l")

	picture = Sprite2D.new()
	picture.texture = viewport.get_texture()
	picture.centered = false
	picture.scale = Vector2.ONE / supersample
	# Feet (the model's origin) at this node's origin: wherever the tilted
	# camera sees the origin, in viewport pixels.
	var feet := camera.unproject_position(Vector3.ZERO) / supersample
	picture.position = -feet
	add_child(picture)

	# Off screen, nothing is drawn or animated: a far-off NPC costs nothing.
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(picture.position, FRAME)
	notifier.screen_entered.connect(_on_screen.bind(true))
	notifier.screen_exited.connect(_on_screen.bind(false))
	add_child(notifier)


func _on_screen(shown: bool) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE if shown \
		else SubViewport.UPDATE_DISABLED
	if anim:
		anim.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED


## A grip in a human hand, worked out from the hand's own bones: the
## handle runs along the knuckles (little finger to index, so the business
## end rises from the thumb side), set into the palm where the fingers close.
## Items hang from it with +Y along the handle, origin at the grip.
func _grip(hand: String, index: String, pinky: String, middle: String) -> Node3D:
	var attachment := _attachment(hand)
	var h := skeleton.find_bone(hand)
	var to_local := skeleton.get_bone_global_rest(h).affine_inverse()
	var i := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(index)).origin
	var p := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(pinky)).origin
	var m := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(middle)).origin
	var along := (i - p).normalized()
	# On the retargeted humanoids (unified bone axes) the knuckle line runs
	# the other way round relative to the fist: the shaft leaves the thumb side.
	if hand.begins_with("Left") or hand.begins_with("Right"):
		along = -along
	var fingers := m.normalized()
	var palm := along.cross(fingers).normalized()
	if hand.ends_with("_l") or hand.begins_with("Left"):
		palm = -palm
	fingers = palm.cross(along).normalized()
	var grip := Node3D.new()
	grip.name = "Grip"
	# Into the palm by a third of the hand's length (3.5 cm on a person),
	# measured in the rig's own units, whatever they are.
	grip.transform = Transform3D(Basis(fingers, along, palm), (i + p) * 0.5 * 0.9 + palm * m.length() * 0.35)
	attachment.add_child(grip)
	# Held things are made in metres: undo any scale the rig carries (some
	# are in centimetres under a 0.01 node) so a sword stays sword-sized.
	var rig_scale := (skeleton.global_transform * skeleton.get_bone_global_rest(h)).basis.get_scale()
	var model_scale := model.global_transform.basis.get_scale() if model else Vector3.ONE
	grip.scale = model_scale / rig_scale
	return grip


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
	var spec: Array = clips.get(clip, clips.idle)
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
	var spec: Array = clips.get(clip, clips.idle)
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
	var item := item_model(id)
	if item:
		_held = item
		_card_tip = float(item.get_meta("length", 0.9))
		right_hand.add_child(_held)
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
	_off = item_model(id)
	if _off == null:
		_off = _weapon(MODELS.get(id, "shield_round"))
	left_hand.add_child(_off)


## Hold a named weapon model (assets/models/kaykit/weapons) in a hand.
func hold_model(right: String, left := "") -> void:
	if right != "" and right_hand:
		if _held:
			_held.queue_free()
		_held = _weapon(right)
		_card_tip = 1.1
		right_hand.add_child(_held)
	if left != "" and left_hand:
		hold_off_hand_model(left)


func hold_off_hand_model(name: String) -> void:
	if _off:
		_off.queue_free()
	_off = _weapon(name)
	left_hand.add_child(_off)


## Real 3D hand-held items (Sketchfab, CC-BY; tools/pack_items.gd), all in
## one frame: grip at the origin, shaft +Y, head +X. id -> [scene, length
## in metres, tint for the metal (null: as modelled)].
const ITEM_MODELS := {
	"wood_pickaxe": ["pickaxe", 0.88, Color(0.62, 0.5, 0.4)], "copper_pickaxe": ["pickaxe", 0.88, Color(1.0, 0.66, 0.45)],
	"iron_pickaxe": ["pickaxe", 0.88, null], "silver_pickaxe": ["pickaxe", 0.88, Color(1.15, 1.18, 1.25)],
	"gold_pickaxe": ["pickaxe", 0.88, Color(1.25, 1.0, 0.45)], "lumen_pickaxe": ["pickaxe", 0.88, Color(0.6, 1.1, 1.3)],
	"wood_axe": ["axe", 0.8, Color(0.62, 0.5, 0.4)], "iron_axe": ["axe", 0.8, null],
	"wood_hammer": ["hammer", 0.7, Color(0.62, 0.5, 0.4)], "iron_hammer": ["hammer", 0.7, null],
	"moonblade": ["starlit", 1.08, Color(0.78, 0.62, 1.0)],
	"wood_sword": ["starlit", 1.0, null], "copper_sword": ["autumn", 1.05, null],
	"iron_sword": ["crystal", 1.05, null], "silver_sword": ["jade", 1.05, null],
	"gold_sword": ["autumn", 1.1, Color(1.25, 1.05, 0.6)], "lumen_sword": ["crystal", 1.1, Color(0.6, 1.1, 1.4)],
	"torch": ["torch", 0.6, null], "fishing_rod": ["rod", 1.7, null],
	"wood_shield": ["shield_wood", 0.6, null], "iron_shield": ["shield_iron", 0.62, null],
}


static func item_model(id: String) -> Node3D:
	if not ITEM_MODELS.has(id):
		return null
	var spec: Array = ITEM_MODELS[id]
	var path := "res://assets/models/items/%s.scn" % spec[0]
	if not ResourceLoader.exists(path):
		return null
	var item: Node3D = load(path).instantiate()
	item.set_meta("length", spec[1])
	if spec[2] != null:
		# Tint the metal, not the wooden handle (the tallest, thinnest part).
		var meshes := item.find_children("*", "MeshInstance3D", true, false)
		var handle: MeshInstance3D = null
		var best := 0.0
		for m in meshes:
			# Measured in the item's frame (shaft along +Y), whatever the
			# mesh's own axes.
			var to_item := Transform3D.IDENTITY
			var n: Node = m
			while n != null and n != item:
				to_item = (n as Node3D).transform * to_item
				n = n.get_parent()
			var box: AABB = to_item * (m as MeshInstance3D).get_aabb()
			var ratio: float = box.size.y / maxf(maxf(box.size.x, box.size.z), 0.001)
			# Only a truly thin part is a bare handle (a blade cast in one
			# piece with its haft is not).
			if meshes.size() > 1 and ratio > best and ratio > 4.0:
				best = ratio
				handle = m
		# With no separate handle the whole item takes a softer tint.
		var tint: Color = spec[2] if handle else Color.WHITE.lerp(spec[2], 0.7)
		for m in meshes:
			if m == handle:
				continue
			for i in (m as MeshInstance3D).mesh.get_surface_count():
				var material := (m as MeshInstance3D).get_active_material(i) as BaseMaterial3D
				if material:
					var copy: BaseMaterial3D = material.duplicate()
					copy.albedo_color = copy.albedo_color * tint
					if id == "moonblade":
						# Violet arcana runs along the edges and runes (where the
						# texture is bright); the steel stays dark.
						copy.emission_enabled = true
						copy.emission = Color(0.7, 0.38, 1.0)
						copy.emission_texture = copy.albedo_texture
						copy.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
						copy.emission_energy_multiplier = 1.6
					elif id.begins_with("lumen"):
						copy.emission_enabled = true
						copy.emission = Color(0.35, 0.85, 1.0)
						copy.emission_energy_multiplier = 0.8
					(m as MeshInstance3D).set_surface_override_material(i, copy)
	return item


func _weapon(name: String) -> Node3D:
	var scene: PackedScene = load("res://assets/models/kaykit/weapons/%s.gltf" % name)
	# KayKit's weapons are sized for its big-handed figures; a person's hands are smaller.
	var held: Node3D = scene.instantiate()
	held.scale = Vector3.ONE * 0.62
	return held


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
