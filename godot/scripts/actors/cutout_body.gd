class_name CutoutBody
extends Node2D
## A character built from separate parts (Kenney's Toon "Parts HD": head,
## body, arm, hand, leg, bent leg) on a skeleton, animated in code every
## frame. It replaces a handful of fixed pose drawings: legs stride in step
## with the ground covered, arms swing against them, the chest breathes,
## the head bobs and looks, the front arm carries whatever is held through
## each swing, and the face changes with what the character is doing.
##
## Joint positions are measured from each character's own idle pose
## (RigData.LAYOUT, by tools/build_rig.py), so at rest the rig lines up
## with the original drawing exactly.
##
## Angles below are in degrees in the rig's own space, facing right:
## 0 = pointing forward, 90 = straight down, -90 = straight up.

const ONE_SHOT := {
	"attack": 0.3, "use": 0.3, "swing_mine": 0.3, "swing_chop": 0.35, "slash": 0.3,
	"hurt": 0.32, "interact": 0.35, "death": 0.45, "cheer": 1.0,
}
const STRIDE := 150.0  ## ground covered by half a walk cycle, in pixels

## The AnimatedSprite2D-like surface the actors already use.
var animation := "idle"
var frame := 0
var speed_scale := 1.0
var flip_h := false:
	set(value):
		flip_h = value
		if _flip:
			_flip.scale.x = -1.0 if value else 1.0
var offset := Vector2.ZERO  ## kept for compatibility; the rig places itself

## Set by the owner each frame.
var motion := Vector2.ZERO
var grounded := true
var run_speed := 620.0

## The front arm's direction while something drives it (swings, holding a
## torch up), or NAN to let the rig swing it naturally.
var arm_override := NAN
var arm_blend := 0.0
## The back arm raised in front (a shield).
var guard := false
## The front arm reaching back past the head (an overhead wind-up): it and
## whatever it holds pass behind the head rather than across the face.
var arm_behind := false

var character := "player"
var _flip: Node2D
var _pelvis: Node2D
var _torso: Node2D
var _neck: Node2D
var _head: Sprite2D
var _shoulder_front: Node2D
var _shoulder_back: Node2D
var _hand_front: Node2D
var _hand_back: Node2D
var _leg_front: Node2D
var _leg_back: Node2D
var _leg_front_sprite: Sprite2D
var _leg_back_sprite: Sprite2D
var _parts: Array[Sprite2D] = []
var _textures := {}
var _rest_front := 79.0   ## natural hang of each arm, from the art
var _rest_back := 101.0
var _t := 0.0             ## seconds into the current one-shot
var _clock := 0.0
var _phase := 0.0         ## walk cycle
var _look := 0.0
var _look_timer := 3.0
var _death := 0.0


func _init(who := "player") -> void:
	character = who


func _ready() -> void:
	_build()


func _tex(name: String) -> Texture2D:
	if not _textures.has(name):
		var path := "res://assets/characters/%s/parts/%s.png" % [character, name]
		if not ResourceLoader.exists(path) and name == "headSide":
			path = "res://assets/characters/%s/parts/head.png" % character
		_textures[name] = load(path)
	return _textures[name]


## Pose pixels -> rig space (feet at 0, centred).
static func _local(p: Vector2) -> Vector2:
	return p - Vector2(96, 254)


func _sprite(texture: Texture2D, at: Vector2, flipped := false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.position = at
	s.flip_h = flipped
	_parts.append(s)
	return s


func _build() -> void:
	var layout: Dictionary = RigData.LAYOUT.get(character, RigData.LAYOUT.player)
	var head: Rect2 = layout.head
	var body: Rect2 = layout.body
	var arm_f: Rect2 = layout.arm_front
	var arm_b: Rect2 = layout.arm_back
	var hand_f: Rect2 = layout.hand_front
	var hand_b: Rect2 = layout.hand_back
	var leg_f: Rect2 = layout.leg_front
	var leg_b: Rect2 = layout.leg_back

	_flip = Node2D.new()
	add_child(_flip)

	# Joints, in pose pixels.
	var hip_f := Vector2(leg_f.position.x + leg_f.size.x * 0.5, leg_f.position.y + 5)
	var hip_b := Vector2(leg_b.position.x + leg_b.size.x * 0.5, leg_b.position.y + 5)
	var pelvis := (hip_f + hip_b) * 0.5
	var waist := Vector2(body.get_center().x, body.end.y - 10)
	var neck := Vector2(head.get_center().x, head.end.y - 10)
	var sh_f := Vector2(arm_f.position.x + 14, arm_f.position.y + 9)
	var sh_b := Vector2(arm_b.end.x - 14, arm_b.position.y + 9)

	_pelvis = Node2D.new()
	_pelvis.position = _local(pelvis)
	_flip.add_child(_pelvis)

	# Legs hang from the pelvis.
	_leg_back = Node2D.new()
	_leg_back.position = hip_b - pelvis
	_leg_back.z_index = -2
	_pelvis.add_child(_leg_back)
	_leg_back_sprite = _sprite(_tex("leg"), leg_b.position - hip_b, true)
	_leg_back.add_child(_leg_back_sprite)
	_leg_front = Node2D.new()
	_leg_front.position = hip_f - pelvis
	_leg_front.z_index = -1
	_pelvis.add_child(_leg_front)
	_leg_front_sprite = _sprite(_tex("leg"), leg_f.position - hip_f)
	_leg_front.add_child(_leg_front_sprite)

	# Torso, from the waist.
	_torso = Node2D.new()
	_torso.position = waist - pelvis
	_pelvis.add_child(_torso)
	_torso.add_child(_sprite(_tex("body"), body.position - waist))

	_neck = Node2D.new()
	_neck.position = neck - waist
	_neck.z_index = 1
	_torso.add_child(_neck)
	_head = _sprite(_tex("head"), head.position - neck)
	_neck.add_child(_head)

	# Arms from the shoulders; hands at the arms' ends.
	_shoulder_back = Node2D.new()
	_shoulder_back.position = sh_b - waist
	_shoulder_back.z_index = -3
	_torso.add_child(_shoulder_back)
	_shoulder_back.add_child(_sprite(_tex("arm"), arm_b.position - sh_b, true))
	_hand_back = Node2D.new()
	_hand_back.position = hand_b.get_center() - sh_b
	_shoulder_back.add_child(_hand_back)
	var hb := _sprite(_tex("hand"), -hand_b.size * 0.5, true)
	_hand_back.add_child(hb)

	_shoulder_front = Node2D.new()
	_shoulder_front.position = sh_f - waist
	_shoulder_front.z_index = 2
	_torso.add_child(_shoulder_front)
	_shoulder_front.add_child(_sprite(_tex("arm"), arm_f.position - sh_f))
	_hand_front = Node2D.new()
	_hand_front.position = hand_f.get_center() - sh_f
	_hand_front.z_index = 2  # over a held item (z 13), which is over the arm (12)
	_shoulder_front.add_child(_hand_front)
	_hand_front.add_child(_sprite(_tex("hand"), -hand_f.size * 0.5))

	_rest_front = rad_to_deg(_hand_front.position.angle())
	_rest_back = rad_to_deg(Vector2(-_hand_back.position.x, _hand_back.position.y).angle())
	_rest_back = 180.0 - _rest_back


# --- The AnimatedSprite2D-like surface ------------------------------------

func play(clip: String = "", custom_speed := 1.0, _from_end := false) -> void:
	if clip == "":
		return
	if clip != animation or ONE_SHOT.has(clip):
		_t = 0.0
	animation = clip
	frame = 0
	if clip == "death":
		_death = 0.0


func is_playing() -> bool:
	return true


## How long the current one-shot lasts at the current speed.
func clip_length(clip: String) -> float:
	return ONE_SHOT.get(clip, 0.3)


# --- Where things are ------------------------------------------------------

func front_hand() -> Vector2:
	return _hand_front.global_position if _hand_front else global_position


func back_hand() -> Vector2:
	return _hand_back.global_position if _hand_back else global_position


func hip() -> Vector2:
	return _pelvis.global_position if _pelvis else global_position


func head_position() -> Vector2:
	return _neck.global_position if _neck else global_position


## The front arm's current direction, rig space degrees.
func front_arm_angle() -> float:
	return rad_to_deg(_shoulder_front.rotation) + _rest_front if _shoulder_front else _rest_front


# --- Animation -------------------------------------------------------------

func _process(delta: float) -> void:
	if _pelvis == null:
		return
	_clock += delta
	_t += delta * speed_scale
	# Hit flashes and tints set on this node reach every part.
	for part in _parts:
		part.self_modulate = self_modulate

	var speed := absf(motion.x)
	var stride := clampf(speed / run_speed, 0.0, 1.2)
	if grounded:
		_phase += speed * delta / STRIDE * PI
	var s := sin(_phase)
	var c := cos(_phase)

	# Defaults: standing, breathing.
	var breath := sin(_clock * 2.2)
	var pelvis_y := breath * 1.2
	var pelvis_x := sin(_clock * 0.7) * 1.2
	var lean := 0.0
	var leg_f := 0.0
	var leg_b := 0.0
	var bend_f := false
	var bend_b := false
	var arm_f := _rest_front + sin(_clock * 1.3) * 2.0
	var arm_b := _rest_back - sin(_clock * 1.3 + 0.6) * 2.0
	var head_tilt := sin(_clock * 0.9) * 1.5
	# Facing where they are going (the three-quarter head); a glance at the
	# camera now and then while standing about.
	var face := "headSide"
	var torso_squash := 1.0 + breath * 0.012

	# The occasional glance about.
	_look_timer -= delta
	if _look_timer <= 0.0:
		_look = randf_range(-5.0, 5.0) if absf(_look) < 0.1 else 0.0
		_look_timer = randf_range(1.2, 4.5)
	head_tilt += _look
	if _look > 2.5 and animation == "idle" and grounded and absf(motion.x) < 40.0:
		face = "head"

	var clip := animation
	if not grounded and not ONE_SHOT.has(clip):
		clip = "jump" if motion.y < 0.0 else "fall"
	elif grounded and speed > 40.0 and not ONE_SHOT.has(clip):
		clip = "walk"

	match clip:
		"walk", "run":
			# Legs stride in step with the ground covered, so feet do not
			# slide; arms swing against them; the body rises as each leg
			# passes under it and leans into the pace.
			var reach := 26.0 + 10.0 * stride
			leg_f = -s * reach
			leg_b = s * reach
			bend_f = c > 0.35
			bend_b = c < -0.35
			pelvis_y = -absf(c) * (4.0 + 4.0 * stride) + 3.0
			pelvis_x = 0.0
			lean = 3.0 + 4.0 * stride
			arm_f = _rest_front + s * (20.0 + 14.0 * stride)
			arm_b = _rest_back - s * (20.0 + 14.0 * stride)
			head_tilt = sin(_phase * 2.0) * 1.8 + 1.5
			torso_squash = 1.0 + absf(c) * 0.02
		"jump":
			leg_f = -32.0
			bend_f = true
			leg_b = 14.0
			arm_f = -35.0
			arm_b = 205.0
			lean = -3.0
			pelvis_y = -4.0
		"fall":
			var flutter := sin(_clock * 13.0) * 5.0
			leg_f = -14.0
			bend_f = true
			leg_b = 20.0 + flutter * 0.5
			arm_f = 15.0 + flutter
			arm_b = 165.0 - flutter
			head_tilt = -3.0
		"hurt":
			face = "headShock"
			var k := clampf(1.0 - _t / 0.32, 0.0, 1.0)
			lean = -12.0 * k
			arm_f = lerpf(_rest_front, -50.0, k)
			arm_b = lerpf(_rest_back, 230.0, k)
			leg_f = -10.0 * k
			bend_f = k > 0.3
		"interact":
			face = "headFocus"
			var k := sin(clampf(_t / 0.35, 0.0, 1.0) * PI)
			arm_f = lerpf(_rest_front, 0.0, k)
			lean = 4.0 * k
		"cheer":
			arm_f = -70.0 + sin(_clock * 8.0) * 10.0
			arm_b = 250.0 - sin(_clock * 8.0) * 10.0
			pelvis_y = -absf(sin(_clock * 8.0)) * 6.0
		"death":
			face = "headShock"
			_death = minf(_death + delta / 0.45, 1.0)
		"attack", "use", "swing_mine", "swing_chop", "slash":
			face = "headFocus"
			var u := clampf(_t / ONE_SHOT[clip], 0.0, 1.0)
			# Weight goes back on the wind-up and drives forward into the
			# strike, with a dip of the hips as the blow lands.
			var drive := sin(u * PI)
			lean = lerpf(-6.0, 9.0, smoothstep(0.25, 0.6, u)) * drive
			pelvis_y = smoothstep(0.35, 0.6, u) * (1.0 - smoothstep(0.6, 1.0, u)) * 7.0
			leg_f = -12.0 * drive
			leg_b = 10.0 * drive
			bend_f = drive > 0.5
			arm_b = _rest_back + 35.0 * drive
			if is_nan(arm_override):
				# Nothing in hand (a zombie's grab): both arms lunge forward.
				arm_f = lerpf(_rest_front, -8.0, drive)
				arm_b = lerpf(_rest_back, 188.0, drive)

	if ONE_SHOT.has(animation) and animation != "death" and _t >= ONE_SHOT[animation]:
		animation = "idle"

	# The front arm follows whatever drives it (a swing, a held torch).
	if not is_nan(arm_override):
		arm_f = lerpf(arm_f, arm_override, arm_blend)
	if guard:
		arm_b = 175.0  # brought round in front of the chest, shield up

	# Apply.
	var layout: Dictionary = RigData.LAYOUT.get(character, RigData.LAYOUT.player)
	var leg_rect: Rect2 = layout.leg_front
	var base_y := leg_rect.position.y + 5 - 254.0
	_pelvis.position = Vector2(_pelvis.position.x, base_y + pelvis_y)
	_pelvis.position.x = ((layout.leg_front.position.x + layout.leg_front.size.x * 0.5
		+ layout.leg_back.position.x + layout.leg_back.size.x * 0.5) * 0.5 - 96.0) + pelvis_x
	_torso.rotation = deg_to_rad(lean)
	_torso.scale = Vector2(1.0 / sqrt(torso_squash), torso_squash)
	_neck.rotation = deg_to_rad(head_tilt - lean * 0.4)
	_head.texture = _tex(face)
	_leg_front.rotation = deg_to_rad(leg_f)
	_leg_back.rotation = deg_to_rad(leg_b)
	_leg_front_sprite.texture = _tex("legBend" if bend_f else "leg")
	_leg_back_sprite.texture = _tex("legBend" if bend_b else "leg")
	_shoulder_front.rotation = deg_to_rad(arm_f - _rest_front)
	_shoulder_front.z_index = -2 if arm_behind else 2
	_shoulder_back.rotation = deg_to_rad(arm_b - _rest_back)
	if animation == "death":
		# Topple backwards and lie still.
		rotation = deg_to_rad(-88.0 * smoothstep(0.0, 1.0, _death)) * (-1.0 if flip_h else 1.0)
		position.y = -40.0 * _death
	else:
		rotation = 0.0
		position.y = 0.0
