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
const SOLE := Color(0.90, 0.86, 0.76)
const HEM := Color(0.22, 0.46, 0.53)
const LACE := Color(0.93, 0.91, 0.84)
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
var _lay := -1.55           # how far the body is laid out, swimming


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
		# Shorts: a rounded seat, a leg that widens a touch toward the hem and
		# a lighter turn-up, so the cloth reads as cloth and not as more leg.
		_ball(hip, 0.130, SHORTS)
		_tube(hip, 0.126, 0.112, 0.21, SHORTS).position = Vector3(0, -0.06, 0)
		_tube(hip, 0.115, 0.116, 0.028, HEM).position = Vector3(0, -0.176, 0)
		# Thigh: full at the top, narrowing to the knee, with the muscle
		# sitting forward of the bone the way a real one does.
		_tube(hip, 0.092, 0.066, THIGH, SKIN).position = Vector3(0, -THIGH * 0.5, 0)
		_lump(hip, Vector3(0.082, 0.17, 0.086), SKIN).position = Vector3(0, -0.19, -0.016)

		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		_ball(knee, 0.066, SKIN)
		_lump(knee, Vector3(0.044, 0.05, 0.03), SKIN).position = Vector3(0, 0.0, -0.05)   # kneecap
		# Shin: slim down the front, with the calf swelling out behind and
		# tapering into a narrow ankle.
		_tube(knee, 0.060, 0.041, SHIN, SKIN).position = Vector3(0, -SHIN * 0.5, 0)
		_lump(knee, Vector3(0.062, 0.145, 0.070), SKIN).position = Vector3(0, -0.14, 0.026)

		var ankle := Node3D.new()
		ankle.position = Vector3(0, -SHIN, 0)
		knee.add_child(ankle)
		_ball(ankle, 0.043, SKIN)
		_lump(ankle, Vector3(0.022, 0.024, 0.022), SKIN).position = Vector3(0.04 * side, 0.0, 0.004)  # ankle bone
		# Deck shoe, toes forward (-Z): a low upper with a rounded toe and
		# heel instead of a brick, a collar round the ankle, a white lace
		# panel and a pale sole showing as a thin line all the way round.
		_box(ankle, Vector3(0.104, 0.062, 0.150), SHOE).position = Vector3(0, -0.036, -0.045)
		_lump(ankle, Vector3(0.052, 0.036, 0.062), SHOE).position = Vector3(0, -0.040, -0.128)     # toe cap
		_lump(ankle, Vector3(0.050, 0.040, 0.040), SHOE).position = Vector3(0, -0.034, 0.034)      # heel
		_tube(ankle, 0.052, 0.054, 0.03, SHOE).position = Vector3(0, -0.012, 0.004)                # collar
		_box(ankle, Vector3(0.046, 0.008, 0.070), LACE).position = Vector3(0, -0.003, -0.072)
		# The sole is inset on every side: when it was wider than the shoe the
		# two surfaces sat 2 mm apart and shimmered against each other.
		_box(ankle, Vector3(0.098, 0.030, 0.150), SOLE).position = Vector3(0, -0.080, -0.045)
		_lump(ankle, Vector3(0.049, 0.015, 0.058), SOLE).position = Vector3(0, -0.080, -0.128)
		_lump(ankle, Vector3(0.047, 0.015, 0.038), SOLE).position = Vector3(0, -0.080, 0.034)

		_hip.append(hip)
		_knee.append(knee)
		_ankle.append(ankle)


## Swimming: the legs trail out behind you and flutter-kick. Called instead of
## pose() while the player is off their feet in deep water.
func swim(delta: float, vel: Vector3, body_yaw: float, cam_pitch: float, kicking: bool) -> void:
	_t += delta
	gait = "swim"
	var speed := Vector2(vel.x, vel.z).length()
	_blend = lerpf(_blend, 1.0 if kicking else 0.35, clampf(delta * 6.0, 0.0, 1.0))
	# A flutter kick: quick and shallow, quicker the harder you are swimming.
	_phase = wrapf(_phase + delta * (5.0 + speed * 1.1) * TAU * 0.25, -PI, PI)
	var amp: float = 0.30 * _blend
	for i in 2:
		var p: float = _phase + (0.0 if i == 0 else PI)
		var th: float = 0.26 + sin(p) * amp
		# The knee trails the hip, which is what makes a kick look like a kick
		# rather than two poles scissoring.
		var kn: float = -(0.22 + 0.30 * _blend * maxf(0.0, sin(p - 0.9)))
		_hip[i].rotation.x = th
		_knee[i].rotation.x = kn
		_ankle[i].rotation.x = clampf(-0.35 + sin(p - 1.4) * 0.3, -0.6, 0.35)
	# Your body lines up with the way you are looking, so the legs trail out
	# behind the camera: level when you swim flat, up over your head when you
	# duck down for the bottom. They used to hang off the hips wherever the
	# hips happened to be, which put both shins across the middle of the
	# screen the moment you looked down.
	var lay: float = clampf(-1.55 + cam_pitch, -2.70, -0.55)
	_lay = lerp_angle(_lay, lay, clampf(delta * 6.0, 0.0, 1.0))
	var yaw: float = lerp_angle(rotation.y, body_yaw, clampf(delta * 8.0, 0.0, 1.0))
	# Hold the hip joint just below eye level and set the legs back from it,
	# whatever angle the body is at (the node pivots at the feet, so this is
	# worked back from where the hips have to end up).
	var back: float = 0.10 - 0.95 * sin(_lay)
	position = Vector3(sin(yaw) * back, 1.15 - 0.95 * cos(_lay), cos(yaw) * back)
	rotation = Vector3(_lay, yaw, sin(_t * 1.7) * 0.05)
	_air = 0.0
	_land = 0.0
	_was_air = true


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
	# Back to standing: clear any offset the swim pose left behind.
	position = Vector3(0.0, _bob + sin(_t * 0.9) * 0.006 * (1.0 - _blend), 0.0)
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

var _mats := {}

func _mat(c: Color) -> StandardMaterial3D:
	if _mats.has(c):
		return _mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	_mats[c] = m
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


## An ellipsoid with the given half-sizes: calves, kneecaps, toe caps.
func _lump(parent: Node3D, half: Vector3, c: Color) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 12
	m.rings = 6
	m.material = _mat(c)
	var mi := _put(parent, m)
	mi.scale = half
	return mi


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
