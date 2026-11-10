class_name FPHands
extends Node3D
## First-person hands. A child of the camera, so every pose here is in camera
## space. The game sets `mode` and a few live parameters each frame; this node
## blends both hands toward the pose for that mode and adds the motion on top
## (walk bob, reel cranking, whack swing, the grab reach, a shield-your-face
## flinch when a fish winds up to jump...).
##
## Hand model: "Hand (low poly)" by scribbletoad, CC-BY-4.0
## (https://sketchfab.com/3d-models/hand-low-poly-d6c802a74a174c8c805deb20186d1877).
## It's a single static left hand, so it's baked once into a clean mesh (wrist
## at the origin, fingers down -Z, palm down) plus a mirrored right hand, and
## the fingers are closed by the hand shader.

const HAND_LEN := 0.205          # wrist to fingertip, metres
const SKIN := Color(0.93, 0.72, 0.58)
const SLEEVE := Color(0.20, 0.36, 0.42)
const CUFF := Color(0.86, 0.80, 0.66)

var mode := "hidden"   # hidden, bare, rod, weapon, clam, carry, sail
var show_hands := true # off: poses still drive the held tool, hands not drawn

# Live parameters, set by the game.
var move_speed := 0.0          # horizontal m/s
var sprint := false
var reach := 0.0               # 0..1, looking at something you can grab/buy/hit
var carry_point := Vector3(0, -0.3, -0.8)   # held fish, camera space
var carry_half := 0.18         # half the held fish's length
var carry_heavy := false
var rod: Node3D                # camera-space rod (for the rod pose)
var paddle: Node3D             # camera-space tool (weapon) that rides in the right fist
var charge := 0.0              # 0..1 cast charge (rod pulls back)
var tension := 0.0             # 0..1 fish fighting on the line (rod shakes)
var rod_load := 0.0            # 0..1 weight hanging off the rod tip
var windup := 0.0              # 0..1 a fish is about to jump at you: shield your face
var whack_style := "chop"      # chop (blade/paddle) or punch (knuckle grips)

var left: Node3D
var right: Node3D
var _mat_l: ShaderMaterial
var _mat_r: ShaderMaterial
var _curl_l := 0.6
var _curl_r := 0.6
var _phase := 0.0
var _t := 0.0
var _was_hidden := true
var _reel: Node3D
var _crank_arm: Node3D
var _crank := 0.0
var _rod_base := Transform3D()
var _clam_prop: Node3D

# One-shot gesture timers, 1 -> 0.
var _punch_t := 0.0
var _punch_side := 1.0         # which fist is punching (+1 right, -1 left)
var _next_side := 1.0
var _swing_t := 0.0
var _pick_t := 0.0
var _drop_t := 0.0
var _throw_t := 0.0
var _cast_t := 0.0
var _hook_t := 0.0
var _reel_t := 0.0
var _hit_t := 0.0
var _swap_t := 0.0

static var _meshes: Array = []   # [left_mesh, right_mesh], built once


func _ready() -> void:
	if _meshes.is_empty():
		_meshes = _bake_meshes()
	var sh: Shader = load("res://assets/hand.gdshader")
	_mat_l = ShaderMaterial.new()
	_mat_l.shader = sh
	_mat_l.set_shader_parameter("skin", SKIN)
	_mat_l.set_shader_parameter("thumb_side", 1.0)
	_mat_l.set_shader_parameter("knuckle", HAND_LEN * 0.46)
	_mat_l.set_shader_parameter("finger_len", HAND_LEN * 0.54)
	_mat_l.set_shader_parameter("thumb_x", HAND_LEN * 0.235)
	_mat_r = _mat_l.duplicate()
	_mat_r.set_shader_parameter("thumb_side", -1.0)
	left = _make_hand(_meshes[0], _mat_l, -1.0)
	right = _make_hand(_meshes[1], _mat_r, 1.0)
	visible = false


## One hand: the baked mesh plus a sleeve running back from the wrist and off
## screen, so you never see a floating stump.
func _make_hand(mesh: Mesh, mat: ShaderMaterial, side: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = SLEEVE
	sm.roughness = 0.9
	var sleeve := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.034
	cm.bottom_radius = 0.052
	cm.height = 0.62
	cm.radial_segments = 10
	cm.rings = 1
	cm.material = sm
	sleeve.mesh = cm
	sleeve.rotation_degrees = Vector3(-90, 0, 0)     # along +Z, from the wrist back
	sleeve.position = Vector3(0, 0, 0.31)
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The forearm isn't stuck to the hand: it runs from the wrist back to a fixed
	# shoulder point every frame, so wrist flicks never swing it into your face.
	var arm := Node3D.new()
	add_child(arm)
	arm.add_child(sleeve)
	root.set_meta("arm", arm)
	var cuff := MeshInstance3D.new()
	var cf := CylinderMesh.new()
	cf.top_radius = 0.037
	cf.bottom_radius = 0.039
	cf.height = 0.035
	cf.radial_segments = 10
	cf.rings = 1
	var cfm := StandardMaterial3D.new()
	cfm.albedo_color = CUFF
	cfm.roughness = 0.9
	cf.material = cfm
	cuff.mesh = cf
	cuff.rotation_degrees = Vector3(-90, 0, 0)
	cuff.position = Vector3(0, 0.004, 0.028)
	cuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cuff)
	root.set_meta("side", side)
	return root




# --- One-shot gestures ----------------------------------------------------------

const PUNCH_TIME := 0.30
const SWING_TIME := 0.36

## A jab. Fists alternate unless one is busy (rod or tool in the right hand,
## so the left does the punching).
func play_punch() -> void:
	var side := _next_side
	if mode in ["rod", "weapon", "clam"]:
		side = -1.0
	_punch_side = side
	_next_side = -side
	_punch_t = 1.0


func play_swing() -> void:
	_swing_t = 1.0


func play_pickup() -> void:
	_pick_t = 1.0


func play_drop() -> void:
	_drop_t = 1.0


func play_grab() -> void:
	_pick_t = 1.0


func play_throw() -> void:
	_throw_t = 1.0


func play_cast() -> void:
	_cast_t = 1.0


func play_hook() -> void:
	_hook_t = 1.0


func play_reel() -> void:
	_reel_t = 1.0


func play_hit() -> void:
	_hit_t = 1.0


## Hands dip out of view and come back with the new item.
func play_swap() -> void:
	_swap_t = 1.0


func busy() -> bool:
	return _punch_t > 0.35 or _swing_t > 0.3 or _pick_t > 0.4


# --- Rod dressing: a small reel with a crank the left hand turns ---------------

func attach_reel(r: Node3D) -> void:
	rod = r
	_rod_base = r.transform
	_reel = Node3D.new()
	_reel.position = Vector3(0, -0.075, -0.16)
	r.add_child(_reel)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045
	cm.bottom_radius = 0.045
	cm.height = 0.05
	cm.radial_segments = 14
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.80, 0.84)
	m.metallic = 0.6
	m.roughness = 0.35
	cm.material = m
	body.mesh = cm
	body.rotation_degrees = Vector3(0, 0, 90)    # spool axis across the rod
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reel.add_child(body)
	var foot := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.016, 0.06, 0.03)
	fb.material = m
	foot.mesh = fb
	foot.position = Vector3(0, 0.04, 0)
	_reel.add_child(foot)
	_crank_arm = Node3D.new()
	_crank_arm.position = Vector3(-0.032, 0, 0)
	_reel.add_child(_crank_arm)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.008, 0.012, 0.075)
	ab.material = m
	arm.mesh = ab
	arm.position = Vector3(0, 0, 0.032)
	_crank_arm.add_child(arm)
	var knob := MeshInstance3D.new()
	var kb := CylinderMesh.new()
	kb.top_radius = 0.011
	kb.bottom_radius = 0.011
	kb.height = 0.03
	kb.radial_segments = 8
	kb.rings = 1
	var km := StandardMaterial3D.new()
	km.albedo_color = Color(0.14, 0.12, 0.12)
	kb.material = km
	knob.mesh = kb
	knob.rotation_degrees = Vector3(0, 0, 90)
	knob.position = Vector3(-0.016, 0, 0.066)
	_crank_arm.add_child(knob)




## A clam that sits in the right palm while you hold one.
func _make_clam_prop() -> Node3D:
	var n := Node3D.new()
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.93, 0.80, 0.70)
	shell.roughness = 0.6
	for k in 2:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.042
		sm.height = 0.042
		sm.is_hemisphere = true
		sm.radial_segments = 10
		sm.rings = 4
		sm.material = shell
		mi.mesh = sm
		mi.scale = Vector3(1.0, 0.55, 0.85)
		if k == 1:
			mi.rotation_degrees = Vector3(180 - 18, 0, 0)
			mi.position = Vector3(0, 0.004, 0.012)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	return n


# --- Per frame --------------------------------------------------------------------

## 0 -> 1 -> 0 bump over a gesture's life (t runs 1 -> 0).
static func _arc(t: float) -> float:
	return sin((1.0 - t) * PI) if t > 0.0 else 0.0


func _process(delta: float) -> void:
	_t += delta
	_punch_t = maxf(_punch_t - delta / PUNCH_TIME, 0.0)
	_swing_t = maxf(_swing_t - delta / SWING_TIME, 0.0)
	_pick_t = maxf(_pick_t - delta / 0.48, 0.0)
	_drop_t = maxf(_drop_t - delta / 0.36, 0.0)
	_throw_t = maxf(_throw_t - delta / 0.45, 0.0)
	_cast_t = maxf(_cast_t - delta / 0.5, 0.0)
	_hook_t = maxf(_hook_t - delta / 0.32, 0.0)
	_reel_t = maxf(_reel_t - delta / 0.22, 0.0)
	_hit_t = maxf(_hit_t - delta / 0.4, 0.0)
	_swap_t = maxf(_swap_t - delta / 0.34, 0.0)
	_animate_rod(delta)
	if mode == "hidden":
		visible = false
		_was_hidden = true
		return
	visible = true
	for h in [left, right]:
		h.visible = show_hands
		(h.get_meta("arm") as Node3D).visible = show_hands
	if _clam_prop == null:
		_clam_prop = _make_clam_prop()
		right.add_child(_clam_prop)
		_clam_prop.position = Vector3(0.0, -0.045, -0.085)
	_clam_prop.visible = mode == "clam"

	var walk := clampf(move_speed / 3.0, 0.0, 1.0)
	_phase += delta * (2.0 + move_speed * 2.1)
	var amp := walk * (1.7 if sprint else 1.0)
	var sw := sin(_phase)
	var idle := sin(_t * 1.3) * 0.005
	var bob := absf(sw) * 0.010 * amp

	var pl := Transform3D()
	var pr := Transform3D()
	var cl := 0.6
	var cr := 0.6
	match mode:
		"bare":
			# Relaxed guard: loose fists, palms turned in, knuckles forward,
			# swinging gently with your stride.
			pl = _pose(Vector3(-0.21, -0.25 + idle - bob, -0.43 - sw * 0.035 * amp),
				Vector3(-6 + sw * 6.0 * amp, -6, 38))
			pr = _pose(Vector3(0.21, -0.25 - idle - bob, -0.43 + sw * 0.035 * amp),
				Vector3(-6 - sw * 6.0 * amp, 6, -38))
			cl = 0.9 if not sprint else 1.0
			cr = cl
			if reach > 0.0:
				pr = pr.interpolate_with(_pose(Vector3(0.13, -0.20, -0.53), Vector3(-6, 6, -30)), reach * 0.6)
				cr = lerpf(cr, 0.25, reach * 0.8)
		"clam":
			pl = _pose(Vector3(-0.21, -0.25 + idle - bob, -0.43 - sw * 0.03 * amp), Vector3(-6, -6, 38))
			cl = 0.9
			# palm up, cupping the clam
			pr = _pose(Vector3(0.17, -0.19 - idle - bob, -0.44), Vector3(-14, 14, -168))
			cr = 0.42
		"carry":
			var c := carry_point
			var half := clampf(carry_half, 0.08, 0.5)
			var cb := sin(_t * 3.0) * 0.008 + bob
			# Gripping it from below by the head and the tail.
			pl = _pose(c + Vector3(-half * 0.7, -0.035 + cb, 0.12), Vector3(30, 14, 70))
			pr = _pose(c + Vector3(half * 0.55, -0.035 - cb, 0.12), Vector3(30, -14, -70))
			cl = 0.55
			cr = 0.55
			if carry_heavy:
				pl.origin.y -= 0.02 + sin(_t * 7.0) * 0.006
				pr.origin.y -= 0.02 + sin(_t * 7.0 + 1.0) * 0.006
		"rod":
			if rod:
				var rt := rod.transform
				# right hand wrapped round the grip, thumb on top
				pr = rt * _pose(Vector3(0.05, 0.0, 0.10), Vector3(0, 0, -90))
				cr = 0.95
				# left hand pinching the crank knob
				var knob := _reel.position + Vector3(-0.048, sin(_crank) * 0.066, cos(_crank) * 0.066) if _reel \
					else Vector3(-0.05, -0.08, -0.16)
				pl = rt * _pose(knob + Vector3(-0.022, 0.0, 0.10), Vector3(-8, 4, 90))
				cl = 0.8
		"weapon":
			if whack_style == "punch":
				pr = _pose(Vector3(0.21, -0.24 - bob, -0.40), Vector3(10, 10, -40))
			else:
				# Held low and ready, blade tipped forward.
				pr = _pose(Vector3(0.24, -0.27 - idle - bob, -0.45 + sw * 0.02 * amp), Vector3(-48, 12, -80))
			cr = 1.0
			pl = _pose(Vector3(-0.21, -0.25 + idle - bob, -0.43 - sw * 0.035 * amp), Vector3(-6, -6, 38))
			cl = 0.9
		"sail":
			var sway := sin(_t * 1.7) * 0.012
			pl = _pose(Vector3(-0.25, -0.27 + sway, -0.46), Vector3(-18, 8, 60))
			pr = _pose(Vector3(0.25, -0.27 - sway, -0.46), Vector3(-18, -8, -60))
			cl = 0.85
			cr = 0.85

	# --- gestures layered on top ---
	if _punch_t > 0.0:
		var k := 1.0 - _punch_t
		var ext := sin(clampf(k / 0.32, 0.0, 1.0) * PI * 0.5) if k < 0.32 else 1.0 - smoothstep(0.32, 1.0, k)
		var tgt := _pose(Vector3(_punch_side * 0.05, -0.16, -0.64), Vector3(0, 0, -16.0 * _punch_side))
		if _punch_side > 0.0:
			pr = pr.interpolate_with(tgt, ext)
			cr = lerpf(cr, 1.0, minf(ext * 2.0, 1.0))
		else:
			pl = pl.interpolate_with(tgt, ext)
			cl = lerpf(cl, 1.0, minf(ext * 2.0, 1.0))
	if _swing_t > 0.0 and mode == "weapon":
		var k := 1.0 - _swing_t
		# wind up quickly over the shoulder, then chop through the middle
		var up := sin(clampf(k / 0.30, 0.0, 1.0) * PI * 0.5) if k < 0.30 else 1.0 - smoothstep(0.30, 0.55, k)
		var down := smoothstep(0.28, 0.55, k) * (1.0 - smoothstep(0.7, 1.0, k))
		if whack_style == "punch":
			var e := sin(clampf(k / 0.35, 0.0, 1.0) * PI * 0.5) if k < 0.35 else 1.0 - smoothstep(0.35, 1.0, k)
			pr = pr.interpolate_with(_pose(Vector3(0.06, -0.16, -0.72), Vector3(2, 4, -18)), e)
		else:
			pr = pr.interpolate_with(_pose(Vector3(0.26, -0.10, -0.38), Vector3(48, 26, -64)), up)
			pr = pr.interpolate_with(_pose(Vector3(0.10, -0.32, -0.56), Vector3(-62, 30, -72)), down)
	if _pick_t > 0.0:
		var g := _arc(_pick_t)
		pr.origin += Vector3(-0.08, -0.07, -0.20) * g
		pr.basis = pr.basis.slerp(Basis.from_euler(Vector3(deg_to_rad(-40), deg_to_rad(10), deg_to_rad(-20))), g * 0.8)
		cr = lerpf(cr, 0.05, g) if _pick_t > 0.55 else lerpf(cr, 0.85, g)
	if _drop_t > 0.0:
		var g := _arc(_drop_t)
		pr.origin += Vector3(-0.06, -0.10, -0.12) * g
		pl.origin += Vector3(0.06, -0.10, -0.12) * g
		cr = lerpf(cr, 0.0, g)
		cl = lerpf(cl, 0.0, g)
	if _throw_t > 0.0:
		var g := _arc(_throw_t)
		pl.origin += Vector3(0.02, 0.10, -0.24) * g
		pr.origin += Vector3(-0.02, 0.10, -0.24) * g
		cl = lerpf(cl, 0.0, g)
		cr = lerpf(cr, 0.0, g)
	if _hit_t > 0.0:
		var g := _hit_t * _hit_t
		var j := Vector3(sin(_t * 61.0), cos(_t * 53.0), 0) * 0.015 * g
		pl.origin += j + Vector3(0, -0.05, 0.05) * g
		pr.origin += -j + Vector3(0, -0.05, 0.05) * g
	if windup > 0.0 and mode != "carry":
		# A fish is about to jump: the free hand comes up in front of your face.
		var k := clampf(windup * 1.6, 0.0, 1.0)
		pl = pl.interpolate_with(_pose(Vector3(-0.08, -0.08 + sin(_t * 30.0) * 0.006, -0.32), Vector3(78, -10, 12)), k)
		cl = lerpf(cl, 0.1, k)
	if _swap_t > 0.0:
		var g := _arc(_swap_t)
		pl.origin.y -= 0.22 * g
		pr.origin.y -= 0.22 * g

	# Blend toward the target (snap straight there when first shown).
	var k2 := 1.0 if _was_hidden else clampf(delta * 18.0, 0.0, 1.0)
	_was_hidden = false
	left.transform = left.transform.interpolate_with(pl, k2)
	right.transform = right.transform.interpolate_with(pr, k2)
	# The tool rides in the right fist.
	if paddle and mode == "weapon":
		if whack_style == "punch":
			paddle.transform = right.transform * Transform3D(Basis(), Vector3(0, -0.01, -0.13))
		else:
			paddle.transform = right.transform * Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5),
				Vector3(0, -0.03, -0.10))
	_aim_arm(left, -1.0)
	_aim_arm(right, 1.0)
	_curl_l = lerpf(_curl_l, cl, clampf(delta * 14.0, 0.0, 1.0))
	_curl_r = lerpf(_curl_r, cr, clampf(delta * 14.0, 0.0, 1.0))
	_mat_l.set_shader_parameter("curl", _curl_l)
	_mat_r.set_shader_parameter("curl", _curl_r)


## The rod moves too: pulled back while charging, a flick on the cast, a jerk
## on the hook, shaking while a fish fights, bowed by a fish hanging off it, and
## the crank spins with every reel tap.
func _animate_rod(delta: float) -> void:
	if rod == null:
		return
	if _reel_t > 0.0:
		_crank -= delta * 16.0
	if _crank_arm:
		_crank_arm.rotation.x = _crank
	var t := _rod_base
	var back := charge * charge
	var flick := _arc(_cast_t)
	var hook := _arc(_hook_t)
	var shake := tension * 0.05 + _arc(_reel_t) * 0.02
	t.origin += Vector3(0.02 * back, 0.06 * back + 0.03 * hook, 0.10 * back)
	var b := Basis.from_euler(Vector3(deg_to_rad(28.0 * back - 34.0 * flick + 16.0 * hook - 9.0 * rod_load)
		+ sin(_t * 37.0) * shake, sin(_t * 29.0) * shake, 0.0))
	t.basis = _rod_base.basis * b
	if _swap_t > 0.0:
		t.origin.y -= 0.22 * _arc(_swap_t)
	rod.transform = t


const SHOULDER := Vector3(0.30, -0.50, 0.30)
const ARM_LEN := 0.62

func _aim_arm(h: Node3D, side: float) -> void:
	var arm: Node3D = h.get_meta("arm")
	var wrist := h.transform * Vector3(0, 0.004, 0.035)
	var sh := Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)
	var d := sh - wrist
	if d.length() < 0.01:
		return
	arm.transform = Transform3D(Basis.looking_at(-d, Vector3.UP), wrist)
	arm.scale = Vector3(1, 1, clampf(d.length() / ARM_LEN, 0.4, 1.6))


func _pose(pos: Vector3, rot_deg: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)


# --- Mesh baking ------------------------------------------------------------------

## Loads the hand model and bakes its mesh into hand space: wrist at the
## origin, fingers along -Z, palm facing -Y, HAND_LEN long. Returns the left
## hand (as modelled) and a mirrored right hand.
static func _bake_meshes() -> Array:
	var scene: Node3D = load("res://assets/hands/hand.glb").instantiate()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for mi in scene.find_children("*", "MeshInstance3D", true):
		var xf := Transform3D()
		var n: Node = mi
		while n != null and n != scene:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		xf = scene.transform * xf
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var base := verts.size()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((xf.basis * nn[i]).normalized() if i < nn.size() else Vector3.UP)
				uvs.append(Vector2.ZERO)
			var ii = arr[Mesh.ARRAY_INDEX]
			if ii == null or (ii as PackedInt32Array).is_empty():
				for i in v.size():
					idx.append(base + i)
			else:
				for i in (ii as PackedInt32Array):
					idx.append(base + i)
	scene.free()

	# Model space: fingers hang down -Y, palm faces -X, thumb toward +Z.
	# Hand space: x = model z, y = model x, z = model y (a rotation, det +1).
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in verts.size():
		var p := verts[i]
		var q := Vector3(p.z, p.x, p.y)
		verts[i] = q
		var m := norms[i]
		norms[i] = Vector3(m.z, m.x, m.y)
		lo = lo.min(q)
		hi = hi.max(q)
	var sc := HAND_LEN / maxf(hi.z - lo.z, 0.0001)
	var origin := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, hi.z)
	for i in verts.size():
		verts[i] = (verts[i] - origin) * sc

	var left_mesh := _commit(verts, norms, idx, false)
	var right_mesh := _commit(verts, norms, idx, true)
	return [left_mesh, right_mesh]


static func _commit(v: PackedVector3Array, n: PackedVector3Array, idx: PackedInt32Array,
		mirror: bool) -> ArrayMesh:
	var vv := v.duplicate()
	var nn := n.duplicate()
	var ii := idx.duplicate()
	if mirror:
		for i in vv.size():
			vv[i].x = -vv[i].x
			nn[i].x = -nn[i].x
		for t in range(0, ii.size() - 2, 3):
			var a := ii[t + 1]
			ii[t + 1] = ii[t + 2]
			ii[t + 2] = a
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vv
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_INDEX] = ii
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
