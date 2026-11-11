class_name FPArms
extends Node3D
## First-person arms: the rigged, animated "PSX First Person Arms" (free game
## assets). A child of the camera; the rig is lined up so its own "camera" bone
## sits on our camera, which is how the animations were authored.
##
## The game sets `mode` and a few live values each frame and calls play_*()
## for one-shot actions. Clips used from the pack:
##   relax / guard_idle / guard_draw   idle with empty hands, fists up
##   jab.L / jab.R                     punches (alternating)
##   grab.R                            picking something up
##   push.R                            dropping / throwing / handing over
##   knife_draw / knife_idle / knife_hit_01/02   holding things, weapon swings
## The rod, the weapon, a clam or a fish ride in (or with) the right hand.

const RIG := "res://assets/arms/arms_rig.glb"
const RAISE := 0.06                 # lift the rig a touch so idle hands show on phones

var mode := "hidden"   # hidden, bare, rod, weapon, clam, fish, carry, sail
var show_hands := true

# Live values from the game
var move_speed := 0.0
var sprint := false
var reach := 0.0
var carry_point := Vector3(0, -0.3, -0.8)
var carry_half := 0.18
var carry_heavy := false
var rod: Node3D
var paddle: Node3D
var charge := 0.0
var tension := 0.0
var rod_load := 0.0
var windup := 0.0
var whack_style := "chop"
var prop: Node3D                    # clam or fish model held in the right fist
var prop_offset := Vector3.ZERO     # (unused, kept for older callers)
var prop_half := 0.15               # half the held fish's length
var prop_two_hands := false         # big fish: carried across both open hands

var _rig: Node3D
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _mesh: MeshInstance3D
var _hand_r: BoneAttachment3D
var _tool_mount: Node3D
var _base := Transform3D()
var _t := 0.0
var _phase := 0.0
var _oneshot := 0.0                 # seconds left of a one-shot clip
var _combat := 0.0                  # fists stay up for a moment after a punch
var _next_side := 1
var _swing_alt := false
var _mode_was := ""
var _cast_t := 0.0
var _hook_t := 0.0
var _reel_t := 0.0
var _hit_t := 0.0
var _swap_t := 0.0
var _land_t := 0.0
var _crank := 0.0
var _crank_arm: Node3D
var _rod_mount: Node3D
var _aim: GripAim
var _layer: ArmLayer
var _tips: Array = []               # thumb and index fingertip attachments
var _hand_l: BoneAttachment3D
var _grip_l: Node3D
const ROD_AIM := Vector3(0.02, 0.50, -1.0)    # player view: forward and up
const WEAPON_AIM := Vector3(-0.10, 1.0, -0.55) # blade up and forward, ready
const HOLD_SHIFT := Vector3(-0.075, 0.035, 0)  # holding something: right hand clears the buttons
var _shift := 0.0


## Layers one clip onto just the right arm (shoulder to fingertips) on top of
## whatever the AnimationPlayer posed: the body stays relaxed with an open left
## hand while the right hand closes its grip and lifts what it holds.
class ArmLayer extends SkeletonModifier3D:
	var clip: Animation
	var time := 0.0
	var weight := 0.0
	var _tracks: Array = []        # [track index, bone index, type]
	# Open-hand fingers (from the relax clip) with a thumb-index pinch:
	# `pinch` 0 = all fingers open, 1 = thumb and index closed together.
	var open_clip: Animation
	var pinch := 0.0
	var finger_weight := 0.0
	var _fingers: Array = []       # [open track, bone index, curl 0..1 for the pinch]

	func set_open_clip(a: Animation, sk: Skeleton3D) -> void:
		open_clip = a
		_fingers.clear()
		if a == null:
			return
		for i in a.get_track_count():
			if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var bn := str(a.track_get_path(i).get_concatenated_subnames())
			if not bn.ends_with(".R") or not (bn.begins_with("f_") or bn.begins_with("thumb")):
				continue
			var bi := sk.find_bone(bn)
			if bi < 0:
				continue
			# index and thumb close into the pinch; the rest stay relaxed open
			var curl := 0.0
			if bn.begins_with("f_index"):
				curl = 0.8
			elif bn.begins_with("thumb"):
				curl = 1.0
			elif bn.begins_with("f_middle"):
				curl = 0.3
			_fingers.append([i, bi, curl])

	func set_clip(a: Animation, sk: Skeleton3D) -> void:
		clip = a
		_tracks.clear()
		if a == null:
			return
		for i in a.get_track_count():
			var bone_name := str(a.track_get_path(i).get_concatenated_subnames())
			if not bone_name.ends_with(".R"):
				continue
			var bi := sk.find_bone(bone_name)
			if bi < 0:
				continue
			var tt := a.track_get_type(i)
			if tt == Animation.TYPE_ROTATION_3D or tt == Animation.TYPE_POSITION_3D:
				_tracks.append([i, bi, tt])

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or clip == null or weight <= 0.001:
			return
		var t := fmod(time, maxf(clip.length, 0.001))
		var w := clampf(weight, 0.0, 1.0)
		for tr in _tracks:
			var i: int = tr[0]
			var bi: int = tr[1]
			if int(tr[2]) == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = clip.rotation_track_interpolate(i, t)
				sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(q, w))
			else:
				var pv: Vector3 = clip.position_track_interpolate(i, t)
				sk.set_bone_pose_position(bi, sk.get_bone_pose_position(bi).lerp(pv, w))
		# Fingers: open hand, with thumb and index pinched together.
		if open_clip and finger_weight > 0.001:
			var fw := clampf(finger_weight, 0.0, 1.0)
			for fr in _fingers:
				var bi2: int = fr[1]
				var fist: Quaternion = sk.get_bone_pose_rotation(bi2)       # what the arm clip posed
				var open: Quaternion = open_clip.rotation_track_interpolate(int(fr[0]), 0.0)
				var want: Quaternion = open.slerp(fist, float(fr[2]) * pinch)
				sk.set_bone_pose_rotation(bi2, fist.slerp(want, fw))


## Turns the right wrist (after the animation has posed it) so whatever the
## fist is gripping points along `want` (skeleton space). The fingers stay
## closed round the handle, so the rod is genuinely held, not floating.
class GripAim extends SkeletonModifier3D:
	var bone := -1
	var want := Vector3.FORWARD
	var weight := 0.0

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or bone < 0 or weight <= 0.001:
			return
		var gp := sk.get_bone_global_pose(bone)
		var cur := (gp.basis * Vector3(0, 0, 1)).normalized()
		var w := want.normalized()
		if cur.dot(w) > 0.9999:
			return
		var turned := Basis(Quaternion(cur, w)) * gp.basis
		var q0 := gp.basis.get_rotation_quaternion()
		var q1 := turned.get_rotation_quaternion()
		var b := Basis(q0.slerp(q1, clampf(weight, 0.0, 1.0)))
		sk.set_bone_global_pose(bone, Transform3D(b.scaled(gp.basis.get_scale()), gp.origin))


func _ready() -> void:
	_rig = load(RIG).instantiate()
	add_child(_rig)
	# rig faces +Z with its camera bone at (0, 1.743, 0): turn and drop it so
	# that bone lands on our camera, looking down -Z.
	_base = Transform3D(Basis(Vector3.UP, PI), Vector3(0, -1.743 + RAISE, 0))
	_rig.transform = _base
	_ap = _rig.find_children("*", "AnimationPlayer", true, false)[0]
	_skel = _rig.find_children("*", "Skeleton3D", true, false)[0]
	for m in _rig.find_children("*", "MeshInstance3D", true, false):
		_mesh = m
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The mesh never leaves the camera; don't let culling think otherwise.
		m.extra_cull_margin = 2.0
		# A little self-light so the arms never go muddy in shade.
		for si in m.mesh.get_surface_count():
			var mat: Material = m.get_active_material(si)
			if mat is StandardMaterial3D:
				var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.emission_enabled = true
				sm.emission = Color(1, 1, 1)
				sm.emission_texture = sm.albedo_texture
				sm.emission_energy_multiplier = 0.12
				sm.roughness = 0.8
				m.set_surface_override_material(si, sm)
	for a in ["relax", "guard_idle", "knife_idle"]:
		if _ap.has_animation(a):
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_hand_r = BoneAttachment3D.new()
	_hand_r.bone_name = "hand.R"
	_skel.add_child(_hand_r)
	_tool_mount = Node3D.new()
	_hand_r.add_child(_tool_mount)
	# tool +Y (blade/handle axis) runs across the palm, out of the thumb side
	_tool_mount.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.085, 0.0))
	# The rod rides in the same grip: its pole runs along the grip axis.
	_rod_mount = Node3D.new()
	_tool_mount.add_child(_rod_mount)
	# Left hand too, for carrying big fish across both palms.
	_hand_l = BoneAttachment3D.new()
	_hand_l.bone_name = "hand.L"
	_skel.add_child(_hand_l)
	_grip_l = Node3D.new()
	_hand_l.add_child(_grip_l)
	_grip_l.position = Vector3(0.0, 0.085, 0.0)
	# Right-arm layer first, then the wrist aim on top of it.
	_layer = ArmLayer.new()
	_skel.add_child(_layer)
	_layer.set_clip(_ap.get_animation(_clip("guard_idle")), _skel)
	_layer.set_open_clip(_ap.get_animation(_clip("relax")), _skel)
	# Fingertips we pinch with (the tail sits between them).
	for bn in ["thumb.03.R", "f_index.03.R"]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = bn
		_skel.add_child(ba)
		_tips.append(ba)
	_aim = GripAim.new()
	_aim.bone = _skel.find_bone("hand.R")
	_skel.add_child(_aim)
	visible = false


# --- clip helpers ------------------------------------------------------------------

func _clip(name: String) -> String:
	if _ap.has_animation(name):
		return name
	var alt := name.replace(".", "_")
	return alt if _ap.has_animation(alt) else ""


func _play_once(name: String, speed := 1.0, blend := 0.08) -> void:
	var c := _clip(name)
	if c == "":
		return
	_ap.play(c, blend, speed)
	_oneshot = _ap.get_animation(c).length / speed * 0.92


func _base_clip() -> String:
	match mode:
		"rod", "weapon":
			return "knife_idle"
		"clam", "fish":
			return "relax"                # open hands; the right arm is layered on top
		"bare":
			return "guard_idle" if windup > 0.0 else "relax"
		_:
			return "relax"


# --- one-shot actions (same API the game used for the old hands) -------------

func play_punch() -> void:
	var side := _next_side
	if mode in ["rod", "weapon", "clam", "fish"]:
		side = -1                          # right hand is busy: left jab
	_next_side = -side
	_combat = 2.5
	_play_once("jab.R" if side > 0 else "jab.L", 1.9, 0.05)


func play_swing() -> void:
	_swing_alt = not _swing_alt
	if whack_style == "punch":
		_play_once("jab.R", 1.9, 0.05)
	else:
		_play_once("knife_hit_01" if _swing_alt else "knife_hit_02", 1.35, 0.05)


func play_pickup() -> void:
	_play_once("grab.R", 1.3)


func play_grab() -> void:
	play_pickup()


func play_drop() -> void:
	_play_once("push.R", 1.5)


func play_throw() -> void:
	_play_once("push.R", 1.7)


func play_cast() -> void:
	_cast_t = 1.0


func play_hook() -> void:
	_hook_t = 1.0


func play_reel() -> void:
	_reel_t = 1.0


func play_hit() -> void:
	_hit_t = 1.0
	_combat = 2.0


func play_land() -> void:
	_land_t = 1.0


func play_swap() -> void:
	_swap_t = 1.0


func busy() -> bool:
	return _oneshot > 0.15


# --- rod dressing: a small reel with a crank -------------------------------------------

func attach_reel(r: Node3D) -> void:
	rod = r
	# Into the fist: the rod's -Z (its pole) runs along the grip's +Y.
	if r.get_parent():
		r.get_parent().remove_child(r)
	_rod_mount.add_child(r)
	r.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)


## The rod model's own reel crank, spun on every reel tap.
func set_crank(pivot: Node3D) -> void:
	_crank_arm = pivot
	_crank = 0.0


## Puts the weapon model holder into the right fist (bone-attached, so it
## follows every swing).
func mount_tool(tool: Node3D) -> void:
	paddle = tool
	if tool.get_parent():
		tool.get_parent().remove_child(tool)
	_tool_mount.add_child(tool)
	tool.transform = Transform3D.IDENTITY


# --- per frame ----------------------------------------------------------------------------

static func _arc(t: float) -> float:
	return sin((1.0 - t) * PI) if t > 0.0 else 0.0


func _process(delta: float) -> void:
	_t += delta
	_oneshot = maxf(_oneshot - delta, 0.0)
	_combat = maxf(_combat - delta, 0.0)
	_cast_t = maxf(_cast_t - delta / 0.5, 0.0)
	_hook_t = maxf(_hook_t - delta / 0.32, 0.0)
	_reel_t = maxf(_reel_t - delta / 0.22, 0.0)
	_hit_t = maxf(_hit_t - delta / 0.4, 0.0)
	_swap_t = maxf(_swap_t - delta / 0.36, 0.0)
	_land_t = maxf(_land_t - delta / 0.3, 0.0)
	if mode == "hidden":
		visible = false
		_mode_was = mode
		return
	visible = true
	if _mesh:
		_mesh.visible = show_hands

	# Changing what's in your hand: a draw clip, then back to idle.
	if mode != _mode_was:
		if _mode_was != "" and _mode_was != "hidden":
			if mode in ["rod", "weapon", "clam", "fish"]:
				_play_once("knife_draw", 1.0, 0.1)
			elif mode == "bare":
				_play_once("guard_draw", 1.2, 0.1)
		_mode_was = mode
	if _oneshot <= 0.0:
		var want := _base_clip()
		if _ap.current_animation != want or not _ap.is_playing():
			_ap.play(want, 0.22)

	# Whole-rig motion: walk bob, swap dip, hit jolt, cast flick, flinch.
	var walk := clampf(move_speed / 3.0, 0.0, 1.0)
	_phase += delta * (2.0 + move_speed * 2.1)
	var amp := walk * (1.6 if sprint else 1.0)
	var off := Vector3(sin(_phase * 0.5) * 0.012 * amp, -absf(sin(_phase)) * 0.016 * amp, 0)
	off.y -= _arc(_swap_t) * 0.22
	off.y -= _arc(_land_t) * 0.05
	if _hit_t > 0.0:
		var g := _hit_t * _hit_t
		off += Vector3(sin(_t * 61.0) * 0.015, -0.05 + cos(_t * 53.0) * 0.01, 0.04) * g
	var pitch := deg_to_rad(10.0 * charge * charge - 14.0 * _arc(_cast_t) + 6.0 * _arc(_hook_t))
	if mode == "rod":
		pitch += sin(_t * 37.0) * tension * 0.012
	_shift = move_toward(_shift, 1.0 if mode in ["rod", "weapon", "clam", "fish"] else 0.0, delta * 4.0)
	off += HOLD_SHIFT * _shift
	var rig_xf := Transform3D(Basis(Vector3.RIGHT, pitch), off) * _base
	_rig.transform = _rig.transform.interpolate_with(rig_xf, clampf(delta * 20.0, 0.0, 1.0))

	# Holding a small fish or a clam: only the right arm lifts and grips.
	var lift := (mode == "clam" or (mode == "fish" and not prop_two_hands)) and _oneshot <= 0.0
	_layer.weight = move_toward(_layer.weight, 1.0 if lift else 0.0, delta * 5.0)
	_layer.finger_weight = _layer.weight
	_layer.pinch = 1.0
	_layer.time += delta
	_aim_wrist(delta)
	_place_rod(delta)
	_place_prop()
	if paddle:
		paddle.visible = mode == "weapon"


## In rod mode the wrist points the gripped rod forward and up; charging pulls
## it back, the cast flicks it forward, the hook jerks it up, a fighting fish
## shakes it and a heavy catch bows it down.
func _aim_wrist(delta: float) -> void:
	var on := mode == "rod" or (mode == "weapon" and whack_style != "punch")
	_aim.weight = move_toward(_aim.weight, 1.0 if (on and _oneshot <= 0.0) else 0.0, delta * 6.0)
	if not on:
		return
	var cam0 := get_parent() as Node3D
	if mode == "weapon":
		if cam0:
			_aim.want = (_skel.global_basis.inverse() * (cam0.global_basis * WEAPON_AIM.normalized())).normalized()
		return
	var back := charge * charge
	var flick := _arc(_cast_t)
	var hook := _arc(_hook_t)
	var shake := tension * 0.06 + _arc(_reel_t) * 0.03
	var a := ROD_AIM.normalized()
	a = (a + Vector3(0, 0.55 * back + 0.35 * hook - 0.45 * flick - 0.25 * rod_load, 0.25 * back)).normalized()
	a += Vector3(sin(_t * 37.0), cos(_t * 31.0), 0) * shake
	var cam := get_parent() as Node3D
	if cam == null:
		return
	# player-view direction -> skeleton space
	var world_dir := cam.global_basis * a.normalized()
	_aim.want = (_skel.global_basis.inverse() * world_dir).normalized()


func _place_rod(delta: float) -> void:
	if rod == null:
		return
	if _reel_t > 0.0:
		_crank -= delta * 16.0
	if _crank_arm and is_instance_valid(_crank_arm):
		_crank_arm.rotation.y = _crank


## A fish hangs by its tail from the right fist; a clam sits in it.
func _place_prop() -> void:
	if prop == null or not is_instance_valid(prop):
		return
	prop.visible = mode in ["clam", "fish"]
	if not prop.visible:
		return
	var grip := _tool_mount.global_position
	var cam := get_parent() as Node3D
	var yaw := cam.global_rotation.y if cam else 0.0
	var sc := prop.scale
	if mode == "fish" and prop_two_hands and cam:
		# Big catch: lying across both open hands, head over one palm, tail
		# over the other, rising and falling a little as you walk.
		var lp := _grip_l.global_position
		var rp := _tool_mount.global_position
		var across := rp - lp
		var mid := (lp + rp) * 0.5
		var upv := cam.global_basis.y.normalized()
		var dx := across.normalized()
		var dz := dx.cross(upv).normalized()
		var dy := dz.cross(dx).normalized()
		var bob := sin(_phase) * 0.008 * clampf(move_speed / 3.0, 0.0, 1.0)
		var fwd := -cam.global_basis.z.normalized()
		# resting on the fingers: a little forward of the grips and just above
		prop.global_transform = Transform3D(Basis(dx, dy, dz).scaled(sc), mid + fwd * 0.07 - dy * (0.035 - bob))
	elif mode == "fish" and cam:
		# Held out by the tail: the body points from your fist toward the middle
		# of the view, drooping a little and swaying as you walk.
		var sway := sin(_t * 2.1) * 0.06 + sin(_phase) * 0.05 * clampf(move_speed / 3.0, 0.0, 1.0)
		var d := (cam.global_basis * Vector3(-0.22 + sway, -1.0, -0.12)).normalized()
		var z := d.cross(Vector3.UP).normalized()
		if z.length() < 0.1:
			z = cam.global_basis.x.normalized()
		var y := z.cross(d).normalized()
		var b := Basis(d, y, z)
		# the tail fin sits between thumb and index, the body hangs from it
		var pinch_pt := _pinch_point(grip)
		prop.global_transform = Transform3D(b.scaled(sc), pinch_pt + d * (prop_half - 0.02))
	else:
		# the clam sits in the curl of the fingers, its edge peeking out on the
		# thumb side, tilted to face you
		# pinched between thumb and index, its face turned toward you
		var pp := _pinch_point(grip)
		var cb := cam.global_basis if cam else Basis()
		var b2 := cb * Basis(Vector3.RIGHT, 1.25)
		prop.global_transform = Transform3D(b2.scaled(sc), pp + cb.y * -0.012 + cb.z * 0.01)


## Where thumb and index fingertips meet (each bone's origin is its last
## joint, so step out along the bone to the actual tip).
func _pinch_point(fallback: Vector3) -> Vector3:
	if _tips.size() != 2:
		return fallback
	var sum := Vector3.ZERO
	for t in _tips:
		var n := t as Node3D
		sum += n.global_position + n.global_basis.y.normalized() * 0.024
	return sum * 0.5


## Right hand position in camera space.
func _hand_cam() -> Vector3:
	var cam := get_parent() as Node3D
	if cam == null or _hand_r == null:
		return Vector3(0.25, -0.3, -0.45)
	return cam.global_transform.affine_inverse() * _hand_r.global_position
