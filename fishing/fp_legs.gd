extends Node3D
## The legs you see when you look down.
##
## The character pack we use elsewhere is a chibi: huge torso, stubby legs. From
## an eye-height camera that reads as a beach ball with feet, so the first-person
## body is built here instead - shorts, bare legs and deck shoes, proportioned
## for looking straight down at them, and posed procedurally.
##
## The gait is driven by distance travelled rather than a clip, so the feet never
## skate however fast you move, and the legs turn to face the way you're actually
## walking: side-step and they side-step, back up and they back up. Six boxes and
## cylinders in all - far cheaper than skinning a 41-bone skeleton every frame.

const HIP_Y := 0.95        # hip joint above the feet
const HIP_X := 0.125       # half the stance width
const THIGH := 0.44
const SHIN := 0.42
const SKIN := Color(0.95, 0.78, 0.63)
const SHORTS := Color(0.16, 0.37, 0.44)
const SHOE := Color(0.31, 0.21, 0.15)
const SOLE := Color(0.74, 0.62, 0.46)
const FOOT_DROP := 0.1   # sole below the ankle joint
const STAND_TH := 0.17     # resting lean of the thighs
const STAND_KN := 0.17     # and the matching soft knee

var gait := "idle"          # idle / walk / run / back / air, for tests
var steps := 0              # goes up every time a foot plants

var _hip: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _ankle: Array[Node3D] = []
var _phase := 0.0
var _yaw := 0.0
var _blend := 0.0           # 0 standing, 1 full stride
var _air := 0.0
var _bob := 0.0
var _land := 0.0            # landing dip, counts down
var _was_air := false
var _acc := 0.0             # unwrapped stride phase, for counting steps
var _step_k := 0
var _t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	# No belly: at this camera height a torso is just a dome filling the screen.
	# The shorts meet at the top instead, which reads as a waist from above and
	# leaves the view between your feet clear.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := Node3D.new()
		hip.position = Vector3(HIP_X * side, HIP_Y, 0)
		add_child(hip)
		_ball(hip, 0.128, SHORTS)
		_tube(hip, 0.128, 0.102, 0.2, SHORTS).position = Vector3(0, -0.055, 0)
		_tube(hip, 0.082, 0.068, THIGH, SKIN).position = Vector3(0, -THIGH * 0.5, 0)

		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_ball(knee, 0.068, SKIN)
		_tube(knee, 0.068, 0.050, SHIN, SKIN).position = Vector3(0, -SHIN * 0.5, 0)

		var ankle := Node3D.new()
		ankle.position = Vector3(0, -SHIN, 0)
		knee.add_child(ankle)
		_ball(ankle, 0.050, SKIN)            # the ankle, so the leg meets the shoe
		# Deck shoe: a canvas upper on a pale sole, toes forward (-Z). The sole
		# is inset so from above you only see shoe.
		_box(ankle, Vector3(0.115, 0.075, 0.25), SHOE).position = Vector3(0, -0.03, -0.055)
		# The sole is inset on every side: when it was wider than the shoe the
		# two surfaces sat 2 mm apart and shimmered against each other.
		_box(ankle, Vector3(0.10, 0.05, 0.228), SOLE).position = Vector3(0, -0.082, -0.055)

		_hip.append(hip)
		_knee.append(knee)
		_ankle.append(ankle)


func set_shown(on: bool) -> void:
	visible = on


## Called every physics frame by the player.
func pose(delta: float, vel: Vector3, body_yaw: float, on_floor: bool, frozen: bool) -> void:
	_t += delta
	var flat := Vector2(vel.x, vel.z)
	var speed := flat.length()
	var moving := speed > 0.3 and not frozen

	# Point the legs the way the feet are really going; past a quarter turn it's
	# a backpedal, so turn them round and run the cycle the other way.
	var back := false
	var want_yaw := body_yaw
	if moving:
		var mv := atan2(-flat.x, -flat.y)
		if absf(wrapf(mv - body_yaw, -PI, PI)) > PI * 0.5:
			back = true
			want_yaw = mv + PI
		else:
			want_yaw = mv
	_yaw = lerp_angle(_yaw, want_yaw, clampf(delta * 10.0, 0.0, 1.0))

	# Stride length grows with speed: a walk is short steps, a run is long ones.
	if moving:
		var stride: float = lerpf(1.2, 2.0, clampf((speed - 1.0) / 5.0, 0.0, 1.0))
		var step: float = (-1.0 if back else 1.0) * speed * delta / stride * TAU
		_phase = wrapf(_phase + step, -PI, PI)
		# A foot comes down every half cycle, at the end of its forward swing.
		_acc += step
		var k := floori((_acc - PI * 0.5) / PI)
		if k != _step_k:
			_step_k = k
			steps += 1
	else:
		_phase = lerp_angle(_phase, 0.0, clampf(delta * 7.0, 0.0, 1.0))
	_blend = lerpf(_blend, 1.0 if moving else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, clampf(delta * 9.0, 0.0, 1.0))

	# Land from a jump and the knees take it: a quick dip, then back up.
	if on_floor and _was_air:
		_land = 0.22
	_was_air = not on_floor
	_land = maxf(_land - delta, 0.0)
	var crouch: float = sin(PI * clampf(_land / 0.22, 0.0, 1.0))

	var amp: float = clampf(0.2 + speed * 0.072, 0.2, 0.62) * _blend
	var bend: float = clampf(0.5 + speed * 0.13, 0.5, 1.2) * _blend
	var idle := sin(_t * 1.5) * 0.028 * (1.0 - _blend)
	var low := 10.0

	for i in 2:
		var p: float = _phase + (0.0 if i == 0 else PI)
		var swing: float = amp * sin(p)
		# Standing, the legs rest slightly forward with soft knees - bolt
		# upright reads as a mannequin, and from above you'd see nothing but
		# the tops of two tubes.
		var th: float = swing + idle * (1.0 if i == 0 else -1.0) + STAND_TH * (1.0 - _blend)
		# The knee folds through the swing and straightens under your weight.
		var kn: float = -(0.08 + STAND_KN * (1.0 - _blend) + bend * maxf(0.0, cos(p)))
		# Mid-air both legs tuck, the trailing one a little more.
		th = lerpf(th, 0.52 - 0.22 * float(i), _air)
		kn = lerpf(kn, -0.95 - 0.2 * float(i), _air)
		kn -= crouch * 0.55
		# Heel first on the way down, push off the toes on the way back: a
		# foot held flat through the whole cycle is what makes walk cycles
		# look like a doll being slid along the floor.
		var an: float = clampf(-(th + kn) * 0.8 + sin(p) * 0.26 * _blend, -0.5, 0.55)
		an = lerpf(an, -0.3, _air)
		_hip[i].rotation.x = th
		_knee[i].rotation.x = kn
		_ankle[i].rotation.x = an
		# How high this sole ends up, for the hip bob below.
		low = minf(low, HIP_Y - THIGH * cos(th) - SHIN * cos(th + kn) - FOOT_DROP)

	# A spread stride is shorter than a straight leg, so the hips have to drop
	# or the back foot hovers. This is the bob you feel when you walk.
	_bob = lerpf(_bob, -low * (1.0 - _air), clampf(delta * 20.0, 0.0, 1.0))
	# Breathing when you stand still, and the hips rolling toward whichever
	# leg has the weight as you walk.
	position.y = _bob + sin(_t * 0.9) * 0.006 * (1.0 - _blend)
	rotation = Vector3(0.0, _yaw, sin(_phase) * 0.04 * _blend)

	if _air > 0.5:
		gait = "air"
	elif not moving:
		gait = "idle"
	elif back:
		gait = "back"
	else:
		gait = "run" if speed > 3.8 else "walk"


# --- little mesh helpers -------------------------------------------------------

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	return m


func _tube(parent: Node3D, top: float, bottom: float, h: float, c: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	# Twelve sides instead of eight: a leg you look straight down at reads as
	# round rather than as a stop sign, and it costs a few dozen triangles.
	m.radial_segments = 12
	m.rings = 1
	m.material = _mat(c)
	return _put(parent, m)


func _ball(parent: Node3D, r: float, c: Color) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	m.material = _mat(c)
	return _put(parent, m)


func _box(parent: Node3D, size: Vector3, c: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	m.material = _mat(c)
	return _put(parent, m)


func _put(parent: Node3D, m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
