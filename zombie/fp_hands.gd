extends Node3D
## The arms you see in front of you - the same model and the same skeleton the
## zombies use.
##
## Rather than a separate pair of first-person arms, the player is the survivor
## model with its head and legs folded away: bone scale is set to almost zero
## for the neck and the thighs, which takes their geometry with them, and what
## is left is a torso and two arms hanging under the camera. One art style, one
## rig, one animation library, and anything new that gets retargeted for the
## zombies is immediately usable here too.
##
## The clips come from the same retargeted library: Pistol_Idle while you carry
## a gun, Pistol_Shoot when you fire, Pistol_Reload when you reload, a jab for
## bare fists and a sword swing for melee.

const MODEL := "res://assets/chars/AtlasZombieLite_Walker.fbx"
const LIB := "res://assets/chars/zombie_anims.res"

# Where the model sits relative to the camera. The rig's own head bone is the
# thing that should land on the camera, so this is worked out from the rest
# pose at start-up and then nudged by these.
const OFFSET := Vector3(0.0, 0.12, 0.20)    # where the head bone sits, from the eye
const SKIN_HIDE := 0.001          # bone scale that makes a limb vanish

var mode := "bare"                # bare / gun / melee
var move_speed := 0.0
var sprint := false
var show_hands := true

var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _mount: Node3D                # weapon goes here, in the right hand
var _hand_r: BoneAttachment3D
var _base := Transform3D()
var _t := 0.0
var _phase := 0.0
var _busy := 0.0
var _lag := Vector2.ZERO
var _look_was := Vector2.ZERO
var _hidden: Array[int] = []
var _scale := 1.0
var _held: Node3D
var _align := -1
var _aim_off := Vector3.ZERO


func _ready() -> void:
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.add_animation_library("z", load(LIB))

	# Stand the model so that its own head bone lands just below the camera.
	# The rig is modelled a hundredth of life size and its bone space is not
	# even the same way up as the world, so the head is measured where it
	# actually ends up rather than from the numbers in the rest pose.
	_skel.force_update_all_bone_transforms()
	var head := _skel.find_bone("head")
	var head_world: Vector3 = _skel.global_transform * _skel.get_bone_global_rest(head).origin \
		if head >= 0 else Vector3(0, 1.5, 0)
	var head_local: Vector3 = _model.to_local(head_world)
	var turn := Basis(Vector3.UP, PI)
	_base = Transform3D(turn, OFFSET - turn * head_local)
	_model.transform = _base

	_hand_r = BoneAttachment3D.new()
	_hand_r.bone_name = "hand_R"
	_skel.add_child(_hand_r)
	_mount = Node3D.new()
	_hand_r.add_child(_mount)
	# Bone attachments inherit the skeleton's scale, which here is a hundred.
	# Undo it so a weapon can be placed in metres like everything else.
	_scale = maxf(_skel.global_transform.basis.get_scale().y, 0.0001)
	_mount.scale = Vector3.ONE / _scale

	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.extra_cull_margin = 4.0       # it never leaves the camera
	_hide_parts()
	_ap.play("z/hold_idle")


## Folds away everything that would be in shot: the head you are looking out
## of, and the legs, which the camera sits above anyway.
func _hide_parts() -> void:
	for name in ["neck", "thigh_L", "thigh_R"]:
		var b := _skel.find_bone(name)
		if b >= 0:
			_skel.set_bone_pose_scale(b, Vector3.ONE * SKIN_HIDE)
			_hidden.append(b)


func set_shown(on: bool) -> void:
	show_hands = on
	visible = on


## Puts a weapon in the hand. Whatever pose the arm happens to be in, the
## weapon is then turned to point where you are looking: the hand bone has no
## particular orientation of its own, so rather than guessing angles per model
## the grip is solved once from the posed hand and the camera.
func mount(weapon: Node3D) -> void:
	for c in _mount.get_children():
		c.queue_free()
	_held = weapon
	_align = 0
	if weapon:
		if weapon.get_parent():
			weapon.get_parent().remove_child(weapon)
		_mount.add_child(weapon)


func aim_offset(v: Vector3) -> void:
	_aim_off = v


func _align_weapon() -> void:
	if _held == null or not is_instance_valid(_held):
		return
	var cam := get_parent() as Node3D
	if cam == null:
		return
	var hand_b := _mount.global_transform.basis.orthonormalized()
	# Point the barrel down the view, with a little droop so the gun is not
	# dead level with the crosshair.
	var want := cam.global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, -0.06)
	var scale_v: Vector3 = _held.transform.basis.get_scale()
	# The nudge is given in view space - right, up, forward - and brought into
	# the hand's frame here, since the hand itself is at some arbitrary angle.
	var off: Vector3 = hand_b.inverse() * (cam.global_transform.basis.orthonormalized() * _aim_off)
	_held.transform = Transform3D((hand_b.inverse() * want).scaled(scale_v), off * _scale)


func mount_point() -> Node3D:
	return _mount


func busy() -> bool:
	return _busy > 0.0


func play(what: String, speed := 1.0) -> void:
	var clip := "z/" + what
	if not _ap.has_animation(clip):
		return
	_ap.play(clip, 0.08, speed)
	_busy = _ap.get_animation(clip).length / speed * 0.85


func play_fire() -> void:
	play("hold_shoot", 1.6)


func play_reload(seconds: float) -> void:
	var clip := "z/hold_reload"
	if _ap.has_animation(clip):
		var l := _ap.get_animation(clip).length
		play("hold_reload", maxf(l / maxf(seconds, 0.2), 0.3))


func play_punch() -> void:
	play("punch", 1.5)


func play_swing() -> void:
	play("swing", 1.3)


func _process(delta: float) -> void:
	if _ap == null:
		return
	_t += delta
	_busy = maxf(_busy - delta, 0.0)
	visible = show_hands
	# Bones set to nothing are re-posed by the animation every frame, so they
	# have to be folded away again after it has had its say.
	for b in _hidden:
		_skel.set_bone_pose_scale(b, Vector3.ONE * SKIN_HIDE)

	# The weapon is squared up a frame after it is mounted, once the skeleton
	# has actually been posed.
	if _align >= 0:
		_align += 1
		if _align >= 2:
			_align = -1
			_align_weapon()

	if _busy <= 0.0:
		var want := "z/hold_idle"
		if mode == "melee":
			want = "z/swing_idle"
		elif mode == "bare":
			want = "z/idle"
		if _ap.current_animation != want:
			_ap.play(want, 0.2)

	# Walk bob, breathing, and the hands trailing a quick look.
	_phase += delta * (2.0 + move_speed * 2.2)
	var walk: float = clampf(move_speed / 3.0, 0.0, 1.0)
	var amp: float = walk * (1.5 if sprint else 1.0)
	var off := Vector3(sin(_phase * 0.5) * 0.012 * amp, -absf(sin(_phase)) * 0.015 * amp, 0.0)
	off.y += sin(_t * 1.2) * 0.005 * (1.0 - walk * 0.6)
	off.x += sin(_t * 0.8) * 0.003 * (1.0 - walk * 0.6)
	var cam := get_parent() as Node3D
	if cam:
		var cy := cam.global_rotation.y
		var cp := cam.global_rotation.x
		if _look_was != Vector2.ZERO:
			_lag.x = clampf(_lag.x + wrapf(cy - _look_was.x, -PI, PI) * 0.5, -0.16, 0.16)
			_lag.y = clampf(_lag.y + (cp - _look_was.y) * 0.4, -0.12, 0.12)
		_look_was = Vector2(cy, cp)
	_lag = _lag.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
	off += Vector3(_lag.x * 0.10, -_lag.y * 0.08, 0.0)
	var want_xf := Transform3D(
		Basis(Vector3.RIGHT, -_lag.y * 0.6) * Basis(Vector3.UP, PI - _lag.x * 0.6),
		_base.origin + off)
	_model.transform = _model.transform.interpolate_with(want_xf, clampf(delta * 18.0, 0.0, 1.0))
