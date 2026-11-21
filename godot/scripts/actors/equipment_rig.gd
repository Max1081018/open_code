class_name EquipmentRig
extends Node2D
## What the player carries, drawn in their hands.
##
## Every pose frame of the character art has known fist positions
## (RigData.HANDS, extracted from the art), and every item icon a known
## grip and axis (RigData.GRIPS). So an item sits in the actual fist, the
## right way round, whatever the pose, rather than floating beside it.
##
## Swings are angle curves per kind of use, with anticipation, a fast
## strike, overshoot and recovery; the use's effect is called at the
## moment of contact, not when the button is pressed.
##
## Also here: the lantern on the belt (the visible source of the lantern
## light), a held torch's flame and light, and the shield.

const TILE := 128.0

## Swing curves: [time 0..1, item angle in degrees], facing right.
## 0 = pointing forward, -90 = straight up, 90 = straight down.
const CURVES := {
	# Overhead strike: lifted behind the head, brought down hard.
	"mine": [[0.0, -55.0], [0.36, -168.0], [0.54, 28.0], [0.66, 42.0], [1.0, -50.0]],
	# Chop: a flatter, heavier blow that stops level, into the trunk.
	"chop": [[0.0, -55.0], [0.40, -150.0], [0.58, -4.0], [0.70, 8.0], [1.0, -50.0]],
	# Sword: a wide, fast sweep from high behind to low in front.
	"slash": [[0.0, -40.0], [0.22, -150.0], [0.46, 78.0], [0.62, 86.0], [1.0, -40.0]],
	# Placing: a short push forward.
	"place": [[0.0, -55.0], [0.30, -25.0], [0.48, 12.0], [1.0, -55.0]],
}
## When the use lands, as a fraction of the swing.
const IMPACT := {"mine": 0.54, "chop": 0.58, "slash": 0.42, "place": 0.45}
## Body frames for each swing.
const BODY := {"mine": "swing_mine", "chop": "swing_chop", "slash": "slash", "place": "use"}
## Length on screen of each kind of held thing, in pixels.
const LENGTH := {"tool": 128.0, "sword": 146.0, "torch": 118.0, "block": 74.0, "shield": 104.0}

var player: Player
var main: Sprite2D       ## the front hand's item
var shield: Sprite2D     ## the back arm's shield
var lantern: Sprite2D    ## on the belt
var trail: Line2D
var _flame: Node2D
var _held_kind := ""     ## "tool", "sword", "torch", "block" or ""
var _two_handed := false ## picks and axes; a hammer is swung one-handed
var _grip := []          ## RigData.GRIPS entry of the held icon
var _swing := {}         ## kind, t, duration, on_impact, impacted
var _lantern_angle := 0.0
var _lantern_speed := 0.0
var _trail_points: Array[Vector2] = []
var blocking := false


func setup(the_player: Player) -> void:
	player = the_player
	main = Sprite2D.new()
	# Draw order around the hand: the front arm (12) behind the item (13),
	# the fist (14) over it, so the item is gripped in front of the arm and
	# the fingers close round the handle, rather than the arm hiding it.
	main.z_index = 3
	add_child(main)

	shield = Sprite2D.new()
	shield.texture = null
	shield.z_index = -2
	add_child(shield)

	lantern = Sprite2D.new()
	lantern.texture = load("res://assets/rendered/lantern-glass.png")
	lantern.scale = Vector2.ONE * (54.0 / float(lantern.texture.get_height()))
	lantern.offset = Vector2(0, lantern.texture.get_height() * 0.5)  # hangs from its handle
	lantern.z_index = -1
	add_child(lantern)
	var halo := Glow.make(Color(1.0, 0.82, 0.5), 0.9)
	halo.position = Vector2(0, lantern.texture.get_height() * 0.55)
	halo.scale /= lantern.scale
	lantern.add_child(halo)

	trail = Line2D.new()
	trail.width = 34.0
	trail.z_as_relative = false
	trail.z_index = 62
	trail.top_level = true
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.0))
	curve.add_point(Vector2(1, 1.0))
	trail.width_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 0.97, 0.85, 0.75))
	trail.gradient = ramp
	trail.material = Effects.additive()
	add_child(trail)


## Show this item in the front hand ("" for empty hands).
func hold(id: String) -> void:
	var kind := Items.kind(id) if id != "" else -1
	_held_kind = ""
	if _flame:
		_flame.queue_free()
		_flame = null
	if id == "torch":
		_set_main(load("res://assets/equipment/torch_held.png"), "equipment/torch_held", "torch")
		_flame = Node2D.new()
		var tip := _tip_local(0.92)
		_flame.position = tip
		# The flame: Kenney's torch flame drawing, flickering, plus sparks.
		var flame := Sprite2D.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/props/torch_on_a.png")
		atlas.region = Rect2(28, 0, 72, 70)
		flame.texture = atlas
		flame.offset = Vector2(0, -26)
		flame.scale = Vector2.ONE * 0.75 / main.scale
		flame.z_index = 2
		_flame.add_child(flame)
		var flicker := flame.create_tween().set_loops()
		var base := flame.scale
		flicker.tween_property(flame, "scale", base * Vector2(0.92, 1.08), 0.11)
		flicker.tween_property(flame, "scale", base * Vector2(1.05, 0.94), 0.13)
		var fire := Effects.fire(Vector2(0, -10))
		fire.scale = Vector2.ONE / main.scale
		fire.amount = maxi(fire.amount / 2, 4)
		fire.emission_rect_extents = Vector2(7, 3)
		_flame.add_child(fire)
		_flame.add_child(Effects.embers(Vector2.ZERO))
		var halo := Glow.make(Color(1.0, 0.7, 0.35), 1.3)
		halo.position = Vector2.ZERO
		halo.scale /= main.scale
		_flame.add_child(halo)
		main.add_child(_flame)
	elif kind in [Items.Kind.PICKAXE, Items.Kind.AXE, Items.Kind.HAMMER]:
		_set_main(Items.icon(id), _icon_key(id), "tool")
		_two_handed = kind != Items.Kind.HAMMER
	elif kind == Items.Kind.SWORD:
		_set_main(Items.icon(id), _icon_key(id), "sword")
	elif kind in [Items.Kind.BLOCK, Items.Kind.PLACEABLE]:
		# Blocks and placeables are carried flat in the palm.
		_set_main(Items.icon(id), "", "block")
	else:
		main.visible = false


func _icon_key(id: String) -> String:
	return String(Items.def(id).get("icon", ""))


func _set_main(texture: Texture2D, key: String, kind: String) -> void:
	main.texture = texture
	main.visible = texture != null
	_held_kind = kind
	_grip = RigData.GRIPS.get(key, [])
	if texture == null:
		return
	var span: float = _grip[2] if not _grip.is_empty() else float(texture.get_width())
	main.scale = Vector2.ONE * (LENGTH[kind] / span)


## The item's far end, in the sprite's local space (origin at the grip).
func _tip_local(fraction: float) -> Vector2:
	if _grip.is_empty():
		return Vector2.ZERO
	var axis := Vector2.from_angle(_grip[1])
	return axis * _grip[2] * fraction * 0.86


## Show the best shield carried, or none.
func carry_shield(id: String) -> void:
	if id == "":
		shield.texture = null
		shield.visible = false
		return
	shield.texture = Items.icon(id)
	shield.visible = true
	shield.scale = Vector2.ONE * (LENGTH.shield / float(shield.texture.get_width()))


func has_shield() -> bool:
	return shield.visible


## Start a swing; `on_impact` is called when it lands.
func swing(kind: String, duration: float, on_impact := Callable()) -> void:
	_swing = {"kind": kind, "t": 0.0, "duration": maxf(duration, 0.12), "on_impact": on_impact,
		"impacted": false}
	_trail_points.clear()


func swinging() -> bool:
	return not _swing.is_empty()


## The body clip for a swing of this kind.
static func body_clip(kind: String) -> String:
	return BODY.get(kind, "use")


func _process(delta: float) -> void:
	if player == null:
		return
	var facing := float(player.facing)
	var hands := _hands()
	var front: Vector2 = hands[0]
	var back: Vector2 = hands[1]

	# --- The front hand's item ---------------------------------------------
	var body := player.body
	var angle := _rest_angle()
	var swinging_now := not _swing.is_empty()
	var swing_kind: String = _swing.get("kind", "")
	if not _swing.is_empty():
		_swing.t += delta / _swing.duration
		var kind: String = _swing.kind
		angle = _curve(CURVES[kind], minf(_swing.t, 1.0))
		if not _swing.impacted and _swing.t >= IMPACT[kind]:
			_swing.impacted = true
			if _swing.on_impact.is_valid():
				_swing.on_impact.call()
		if _swing.t >= 1.0:
			_swing = {}
	if blocking:
		angle = -70.0
	# The item is placed first, then the hands are put on it.
	#
	# Where the grip is: at the end of the front arm, pointing along the
	# blow during a swing, held up and out for a torch, otherwise wherever
	# the arm's natural swing has it (walking, breathing). The arm is not
	# quite straight, so the elbow always shows a little bend.
	var arm_dir: float
	var reach := body.arm_length()
	if swinging_now:
		arm_dir = clampf(angle + 55.0, -150.0, 120.0)
		reach *= 0.95
	elif _held_kind == "torch":
		arm_dir = 28.0
		reach *= 0.9
	else:
		arm_dir = body.front_arm_angle()
		reach *= 0.88
		if _held_kind in ["tool", "sword"]:
			# Carried forward and a little up, clear of the face.
			angle = arm_dir - (98.0 if _held_kind == "tool" else 105.0)
	if blocking:
		angle = -70.0
	var grip := body.shoulder_rig(true) + Vector2.from_angle(deg_to_rad(arm_dir)) * reach
	if main.visible and main.texture:
		body.reach(true, grip, angle)
	# Picks and axes are swung with both hands: the far hand takes the
	# handle further up, and the shoulders turn into the blow.
	var two_handed: bool = swinging_now and _held_kind == "tool" and _two_handed and swing_kind in ["mine", "chop"]
	body.twist = 1.0 if two_handed else 0.0
	if two_handed and not _grip.is_empty():
		var length: float = _grip[2] * main.scale.x
		var second := grip + Vector2.from_angle(deg_to_rad(angle)) * length * 0.26
		body.reach(false, second, angle)
	body.guard = blocking
	# Lifted back over the shoulder, the item and arm go behind the head.
	var behind := swinging_now and angle < -105.0
	body.arm_behind = behind
	main.z_index = -3 if behind else 3
	_place_main(_rig_to_player(grip), angle, facing)
	_update_trail(delta)

	# --- The shield: held in the far hand --------------------------------------
	if shield.visible:
		if blocking:
			# Brought round in front of the chest, the far arm holding it out.
			var guard_at := body.shoulder_rig(false) + Vector2(70, 26)
			body.reach(false, guard_at, -90.0)
		shield.position = _rig_to_player(body.hand_rig(false)) + Vector2(0, -6)
		shield.z_index = 3 if blocking else -4
		shield.rotation = 0.0 if blocking else -0.25 * facing
		shield.flip_h = facing < 0

	# --- The lantern on the belt: a pendulum pushed by the player's motion ---
	var hip := body.hip() - player.global_position + Vector2(-36 * facing, 12)
	var push := -player.velocity.x * 0.0022 - (player.velocity.y * 0.0008 if not player.is_on_floor() else 0.0)
	_lantern_speed += (-_lantern_angle * 38.0 + push * 60.0) * delta
	_lantern_speed *= exp(-3.2 * delta)
	_lantern_angle = clampf(_lantern_angle + _lantern_speed * delta, -0.9, 0.9)
	lantern.position = hip
	lantern.rotation = _lantern_angle
	lantern.visible = _held_kind != "torch"


## A point in the rig's space (facing right) to the player's space.
func _rig_to_player(p: Vector2) -> Vector2:
	return player.to_local(player.body._flip.to_global(p))


## The skeleton's hands, in the player's space.
func _hands() -> Array:
	var origin := player.global_position
	return [player.body.front_hand() - origin, player.body.back_hand() - origin]


func _rest_angle() -> float:
	var bob := 0.0
	if player.is_on_floor() and absf(player.velocity.x) > 60.0:
		bob = sin(Time.get_ticks_msec() / 95.0) * 7.0
	elif not player.is_on_floor():
		bob = -18.0 if player.velocity.y < 0.0 else 10.0
	match _held_kind:
		"torch":
			return -78.0 + bob * 0.5
		"sword":
			return -38.0 + bob
		"block":
			return -45.0
	return -58.0 + bob


func _place_main(hand: Vector2, angle_deg: float, facing: float) -> void:
	if not main.visible or main.texture == null:
		return
	var size := main.texture.get_size()
	main.position = hand
	if _grip.is_empty():
		# No grip data (blocks): centred on the palm, no spin.
		main.offset = Vector2.ZERO
		main.rotation = deg_to_rad(angle_deg + 45.0) * 0.25 * facing
		main.flip_h = facing < 0
		return
	var grip: Vector2 = _grip[0]
	var axis: float = _grip[1]
	var rotation_right := deg_to_rad(angle_deg) - axis
	if facing > 0:
		main.flip_h = false
		main.offset = -(grip - size * 0.5)
		main.rotation = rotation_right
	else:
		main.flip_h = true
		main.offset = -(Vector2(size.x - grip.x, grip.y) - size * 0.5)
		main.rotation = -rotation_right
	# Turn with the body when it turns over (a roll, a fall).
	main.rotation += player.body.rotation
	if _flame:
		var tip := _tip_local(0.92)
		_flame.position = Vector2(tip.x * facing, tip.y)


## The far end of the held item, in world space.
func tip_global() -> Vector2:
	if _grip.is_empty() or not main.visible:
		return player.global_position + Vector2(90 * player.facing, -120)
	var tip := _tip_local(1.0)
	tip.x *= player.facing
	return main.to_global(tip)


func _update_trail(delta: float) -> void:
	var active: bool = not _swing.is_empty() and _swing.kind in ["slash", "chop"] and Settings.particles > 0
	if active:
		_trail_points.append(tip_global())
		while _trail_points.size() > 7:
			_trail_points.pop_front()
	elif not _trail_points.is_empty():
		_trail_points.pop_front()
	trail.points = PackedVector2Array(_trail_points)
	trail.visible = _trail_points.size() > 1


static func _curve(keys: Array, t: float) -> float:
	for i in range(1, keys.size()):
		var a: Array = keys[i - 1]
		var b: Array = keys[i]
		if t <= b[0]:
			var u: float = (t - a[0]) / maxf(b[0] - a[0], 0.0001)
			# Ease: slow into the wind-up, snapping through the strike.
			u = u * u * (3.0 - 2.0 * u) if i != 2 else u * u
			return lerpf(a[1], b[1], u)
	return keys[keys.size() - 1][1]


## Light from a held torch: [position in tiles, radius, colour].
func torch_light() -> Array:
	if _held_kind != "torch" or not is_inside_tree():
		return []
	var tip := tip_global() if _flame == null else _flame.global_position
	var flicker := randf_range(0.9, 1.0)
	return [[tip / TILE, 9.0, Color(1.0, 0.72, 0.42) * flicker]]


## Where the lantern hangs, for its light.
func lantern_position() -> Vector2:
	return lantern.global_position + Vector2(0, 30).rotated(lantern.rotation)
