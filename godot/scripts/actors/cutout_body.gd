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
	"hurt": 0.32, "interact": 0.35, "death": 0.45, "cheer": 1.0, "dodge": 0.36,
}
const STRIDE := 150.0  ## ground covered by half a walk cycle, in pixels

## The AnimatedSprite2D-like surface the actors already use.
var animation := "idle"
var frame := 0
var speed_scale := 1.0
var flip_h := false:
	set(value):
		flip_h = value  # the body turns toward it over a moment (see _turn)
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
var _limb_front: Limb
var _limb_back: Limb
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
var _seed := randf() * TAU
var _fidget := ""
var _fidget_t := 0.0
var _fidget_timer := randf_range(5.0, 10.0)


## Turning round: the body turns like a card (narrowing to its edge and
## opening the other way) over a fraction of a second, rather than
## snapping to face the other way.
func _turn(delta: float) -> void:
	var target := -1.0 if flip_h else 1.0
	_flip.scale.x = move_toward(_flip.scale.x, target, delta * 14.0)
	if absf(_flip.scale.x) < 0.08:
		_flip.scale.x = 0.08 * target


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
	_flip.scale.x = -1.0 if flip_h else 1.0
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
	if layout.has("back"):
		# Hair behind the head, moving with it.
		var hair := _sprite(_tex("back"), (layout.back as Rect2).position - neck)
		hair.z_index = -2
		_neck.add_child(hair)

	# Arms: shoulder, elbow, wrist. The arm drawing is a sleeve above a
	# forearm, so it is cut at the elbow into two segments; the hand hangs
	# off the forearm's end.
	_limb_back = Limb.new()
	_limb_back.build(self, _torso, sh_b - waist, arm_b, hand_b, sh_b, true, -3)
	_limb_front = Limb.new()
	_limb_front.build(self, _torso, sh_f - waist, arm_f, hand_f, sh_f, false, 2)
	_shoulder_back = _limb_back.shoulder
	_shoulder_front = _limb_front.shoulder
	_hand_back = _limb_back.hand
	_hand_front = _limb_front.hand
	_rest_front = _limb_front.rest_angle()
	_rest_back = _limb_back.rest_angle()


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


## The front arm's natural direction this frame (before any reach),
## rig space degrees.
func front_arm_angle() -> float:
	return _natural_front


## Bend at the elbows for the current gait (degrees), set by the pose.
var elbow_bend := 12.0
## 0..1: how far the shoulders are turned toward a two-handed grip.
var twist := 0.0
var _twist_now := 0.0
var _natural_front := 79.0


## A shoulder's position in rig space (facing right, feet at 0).
func shoulder_rig(front: bool) -> Vector2:
	var limb := _limb_front if front else _limb_back
	return (_pelvis.transform * _torso.transform) * limb.shoulder.position


## Shoulder-to-wrist length when straight.
func arm_length() -> float:
	return _limb_front.upper_length + _limb_front.fore_length


## Put a hand on a point (rig space) with two-bone IK; `hand_angle` turns
## the wrist so the fist lines up with a handle (degrees, rig space).
func reach(front: bool, target_rig: Vector2, hand_angle := NAN) -> void:
	if _pelvis == null:
		return
	var limb := _limb_front if front else _limb_back
	var torso := _pelvis.transform * _torso.transform
	var local := torso.affine_inverse() * target_rig
	var hand_local := NAN if is_nan(hand_angle) else hand_angle - rad_to_deg(_torso.rotation)
	limb.reach(local, hand_local)


## Where a hand is, in rig space.
func hand_rig(front: bool) -> Vector2:
	var hand := _hand_front if front else _hand_back
	return _flip.get_global_transform().affine_inverse() * hand.global_position


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

	_turn(delta)

	# Defaults: standing at ease. Weight drifts from foot to foot, the hips
	# sway with it and the shoulders and head counter it; the chest
	# breathes; the arms hang loose with a little bend.
	var breath := sin(_clock * 2.2)
	var weight := sin(_clock * 0.55 + _seed)
	var pelvis_y := breath * 1.2 + absf(weight) * 1.5
	var pelvis_x := weight * 3.5
	var lean := weight * 1.6
	var leg_f := -weight * 3.0
	var leg_b := -weight * 3.0
	var bend_f := false
	var bend_b := false
	var arm_f := _rest_front + sin(_clock * 1.3) * 2.5 - weight * 2.0
	var arm_b := _rest_back - sin(_clock * 1.3 + 0.6) * 2.5 - weight * 2.0
	var head_tilt := sin(_clock * 0.9) * 1.5 - weight * 2.2
	elbow_bend = 14.0
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

	# Now and then, standing about: a look around, or a stretch.
	if animation == "idle" and grounded and speed < 40.0:
		_fidget_timer -= delta
		if _fidget_timer <= 0.0 and _fidget == "":
			_fidget = ["look", "stretch", "look"][randi() % 3]
			_fidget_t = 0.0
			_fidget_timer = randf_range(7.0, 14.0)
	else:
		_fidget = ""
	if _fidget != "":
		_fidget_t += delta
		var k := sin(clampf(_fidget_t / 1.6, 0.0, 1.0) * PI)
		match _fidget:
			"look":
				face = "head" if _fidget_t < 0.8 else "headSide"
				head_tilt += 6.0 * k * (1.0 if _fidget_t < 0.8 else -1.0)
			"stretch":
				arm_f = lerpf(arm_f, -95.0, k)
				arm_b = lerpf(arm_b, 265.0, k)
				elbow_bend = lerpf(elbow_bend, 40.0, k)
				lean -= 4.0 * k
				torso_squash += 0.03 * k
		if _fidget_t >= 1.6:
			_fidget = ""

	var clip := animation
	if not grounded and not ONE_SHOT.has(clip):
		clip = "jump" if motion.y < 0.0 else "fall"
	elif grounded and speed > 40.0 and not ONE_SHOT.has(clip):
		clip = "walk"

	match clip:
		"walk", "run":
			# Legs stride in step with the ground covered, so feet do not
			# slide. Walking: upright, an easy stride, arms swinging loose.
			# Running: leaning in, a long stride, knees high, elbows bent
			# and the arms pumping; the head stays steady over it all.
			var running := stride > 0.68
			var run_k := smoothstep(0.55, 0.85, stride)
			var reach := lerpf(22.0 + 10.0 * stride, 40.0, run_k)
			leg_f = -s * reach
			leg_b = s * reach
			bend_f = c > lerpf(0.35, 0.05, run_k)
			bend_b = c < -lerpf(0.35, 0.05, run_k)
			pelvis_y = -absf(c) * lerpf(4.0, 9.0, run_k) + 3.0
			pelvis_x = 0.0
			lean = lerpf(3.0, 12.0, run_k)
			var swing := lerpf(18.0, 42.0, run_k)
			arm_f = _rest_front - 22.0 * run_k + s * swing
			arm_b = _rest_back + 22.0 * run_k - s * swing
			elbow_bend = lerpf(18.0, 82.0, run_k)
			head_tilt = sin(_phase * 2.0) * lerpf(1.8, 0.8, run_k) + lerpf(1.5, -3.0, run_k)
			torso_squash = 1.0 + absf(c) * (0.02 if not running else 0.035)
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
		"dodge":
			# Tucked into a ball, rolling once round its middle.
			bend_f = true
			bend_b = true
			leg_f = -40.0
			leg_b = -20.0
			arm_f = 30.0
			arm_b = 150.0
			lean = 20.0
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
	_natural_front = arm_f
	var bend := elbow_bend
	_limb_front.pose(arm_f, bend + (8.0 if animation == "idle" else 0.0))
	_limb_back.pose(arm_b, bend + 6.0)
	_shoulder_front.z_index = -2 if arm_behind else 2
	# A two-handed grip turns the shoulders toward the work: the far
	# shoulder comes forward so both hands can reach the handle.
	_twist_now = move_toward(_twist_now, twist, get_process_delta_time() * 6.0)
	_shoulder_back.position = _limb_back.base + Vector2(58.0 * _twist_now, 4.0 * _twist_now)
	# Reaching across the chest for the handle, the far arm is seen in front
	# of the body (still under the near arm); otherwise it hangs behind.
	_shoulder_back.z_index = 1 if _twist_now > 0.4 else -3
	_shoulder_front.position = _limb_front.base - Vector2(10.0 * _twist_now, 0)
	if animation == "death":
		# Topple backwards and lie still.
		rotation = deg_to_rad(-88.0 * smoothstep(0.0, 1.0, _death)) * (-1.0 if flip_h else 1.0)
		position.y = -40.0 * _death
	elif animation == "dodge":
		var u := clampf(_t / ONE_SHOT.dodge, 0.0, 1.0)
		var turn := TAU * smoothstep(0.0, 1.0, u) * (-1.0 if flip_h else 1.0)
		var centre := Vector2(0, -105)
		rotation = turn
		position = centre - centre.rotated(turn) + Vector2(0, sin(u * PI) * 30.0)
	else:
		rotation = 0.0
		position = Vector2.ZERO



## One arm: shoulder -> elbow -> wrist, cut from a single arm drawing.
class Limb:
	var shoulder: Node2D
	var elbow: Node2D
	var hand: Node2D
	var base := Vector2.ZERO       ## shoulder position in the torso at rest
	var upper_length := 1.0
	var fore_length := 1.0
	var _upper_rest := 0.0         ## radians: shoulder->elbow at rest
	var _fore_rest := 0.0          ## radians: elbow->wrist at rest

	func build(body: CutoutBody, torso: Node2D, at: Vector2, arm: Rect2, hand_rect: Rect2,
			shoulder_pose: Vector2, flipped: bool, z: int) -> void:
		var wrist := hand_rect.get_center()
		# The elbow: 45% of the way down, where sleeve meets forearm.
		var elbow_pose := shoulder_pose.lerp(wrist, 0.45)
		var cut := clampf(elbow_pose.y - arm.position.y, 4.0, arm.size.y - 4.0)
		base = at
		shoulder = Node2D.new()
		shoulder.position = at
		shoulder.z_index = z
		torso.add_child(shoulder)
		var texture: Texture2D = body._tex("arm")
		var upper := AtlasTexture.new()
		upper.atlas = texture
		upper.region = Rect2(0, 0, arm.size.x, cut + 3.0)
		shoulder.add_child(body._sprite(upper, arm.position - shoulder_pose, flipped))
		elbow = Node2D.new()
		elbow.position = elbow_pose - shoulder_pose
		shoulder.add_child(elbow)
		var lower := AtlasTexture.new()
		lower.atlas = texture
		lower.region = Rect2(0, cut - 3.0, arm.size.x, arm.size.y - cut + 3.0)
		elbow.add_child(body._sprite(lower, arm.position + Vector2(0, cut - 3.0) - elbow_pose, flipped))
		hand = Node2D.new()
		hand.position = wrist - elbow_pose
		hand.z_index = 2 if not flipped else 0
		elbow.add_child(hand)
		hand.add_child(body._sprite(body._tex("hand"), -hand_rect.size * 0.5, flipped))
		upper_length = elbow.position.length()
		fore_length = hand.position.length()
		_upper_rest = elbow.position.angle()
		_fore_rest = hand.position.angle()

	## Direction shoulder->wrist at rest (degrees), for the pose tables.
	func rest_angle() -> float:
		return rad_to_deg((elbow.position + hand.position).angle())

	## A natural pose: the arm points at `angle` (shoulder to wrist), bent
	## `bend` degrees at the elbow with the forearm coming forward.
	func pose(angle: float, bend: float) -> void:
		var a := deg_to_rad(angle)
		var b := deg_to_rad(bend)
		var upper_dir := a + b * 0.5
		var fore_dir := a - b * 0.5
		shoulder.rotation = upper_dir - _upper_rest
		elbow.rotation = (fore_dir - upper_dir) - (_fore_rest - _upper_rest)
		hand.rotation = 0.0

	## Two-bone IK: put the wrist on `target` (torso space), the elbow bent
	## the natural way; turn the wrist to `hand_angle` if given (degrees).
	func reach(target: Vector2, hand_angle := NAN) -> void:
		var to := target - shoulder.position
		var l1 := upper_length
		var l2 := fore_length
		var d := clampf(to.length(), absf(l1 - l2) + 0.5, l1 + l2 - 0.5)
		var aim := to.angle()
		var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var upper_dir := aim + acos(cos_a)
		var joint := Vector2.from_angle(upper_dir) * l1
		var fore_dir := (to.normalized() * d - joint).angle()
		shoulder.rotation = upper_dir - _upper_rest
		elbow.rotation = (fore_dir - upper_dir) - (_fore_rest - _upper_rest)
		if not is_nan(hand_angle):
			# The fist drawing holds a handle at about -60 degrees; turn it
			# from there so the handle runs straight through the grip.
			var total := deg_to_rad(hand_angle + 60.0)
			hand.rotation = total - (fore_dir - _fore_rest)
