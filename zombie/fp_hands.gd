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

const ZChar := preload("res://zchar.gd")

const MODEL := "res://assets/chars/AtlasZombieLite_Walker.fbx"
const LIB := "res://assets/chars/zombie_anims.res"

# Where the model sits relative to the camera. The rig's own head bone is the
# thing that should land on the camera, so this is worked out from the rest
# pose at start-up and then nudged by these.
const OFFSET := Vector3(0.0, 0.10, 0.0)      # first guess for the head, before the hand is pinned
# Where the gun hand should sit in view: a little right of centre, below the
# crosshair, a forearm's length out. The whole rig is moved to put it there.
const HAND_AT := Vector3(0.21, -0.21, -0.40)
const RIG_SCALE := 0.45
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
var _rng := RandomNumberGenerator.new()
var _held: Node3D
var _pin := 3
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
	# Slightly slimmed: these are blocky, heavy-set arms, and at this distance
	# from the eye a life-size pair fills half the screen.
	_base.basis = _base.basis.scaled(Vector3.ONE * RIG_SCALE)
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
	# Your own arms: the same model, with a living person's colouring.
	var look := ZChar.new()
	look._model = _model
	look.randomize_look(_rng, true)
	# Only the arms are wanted in shot. The body is one skinned mesh, so the
	# rest of it is hidden by its materials: everything that is not skin goes
	# fully transparent, which leaves a pair of bare arms and nothing else.
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var who := str(src.resource_name) if src else ""
			if "Skin" in who:
				continue
			var hide := StandardMaterial3D.new()
			hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hide.albedo_color = Color(0, 0, 0, 0)
			hide.no_depth_test = true
			hide.render_priority = -10
			m.set_surface_override_material(si, hide)
	_hide_parts()
	_build_flash()
	_ap.play("z/hold_idle")


## Folds away everything that would be in shot: the head you are looking out
## of, and the legs, which the camera sits above anyway.
func _hide_parts() -> void:
	for name in ["neck", "thigh_L", "thigh_R"]:
		var b := _skel.find_bone(name)
		if b >= 0:
			_skel.set_bone_pose_scale(b, Vector3.ONE * SKIN_HIDE)
			_hidden.append(b)


var _flash: MeshInstance3D
var _flash_t := 0.0

## A short bright flare at the muzzle on every shot: two crossed additive
## quads that spin to a random angle each time.
func _build_flash() -> void:
	_flash = MeshInstance3D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 0.85, 1), Color(1, 0.8, 0.35, 0.9),
		Color(1, 0.45, 0.1, 0.35), Color(1, 0.3, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = tex
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	q.material = fm
	_flash.mesh = q
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.omni_range = 5.0
	light.light_energy = 3.0
	light.shadow_enabled = false
	_flash.add_child(light)


func muzzle_flash() -> void:
	if _flash == null:
		return
	_flash_t = 0.06
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	var sz := randf_range(0.8, 1.3)
	_flash.scale = Vector3(sz, sz, sz)
	# At the end of the barrel: a little ahead of and above the hand.
	if _held and is_instance_valid(_held):
		_flash.global_position = _held.global_transform * Vector3(0.0, 0.05, -0.22)
	else:
		_flash.position = Vector3(0.1, -0.1, -0.5)


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
	# The mount already undoes the skeleton's scale, so this is in metres.
	_held.transform = Transform3D((hand_b.inverse() * want).scaled(scale_v), off)


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
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.visible = false
	visible = show_hands
	# Bones set to nothing are re-posed by the animation every frame, so they
	# have to be folded away again after it has had its say.
	for b in _hidden:
		_skel.set_bone_pose_scale(b, Vector3.ONE * SKIN_HIDE)

	# Once the idle pose is on the skeleton, slide the whole rig so the gun
	# hand lands exactly on HAND_AT. Pinning the hand rather than the head is
	# what keeps the arms the same place in view whatever the clip does with
	# the shoulders.
	if _pin > 0:
		_pin -= 1
		if _pin == 0 and _hand_r:
			var cam1 := get_parent() as Node3D
			if cam1:
				var hand_now: Vector3 = cam1.to_local(_hand_r.global_position)
				_base.origin += HAND_AT - hand_now
				_model.transform = _base
	# The weapon is squared up a frame after it is mounted, once the skeleton
	# has actually been posed.
	if _align >= 0:
		_align += 1
		if _align >= 2:
			_align = -1
			_align_weapon()

	if _busy <= 0.0:
		# Low ready. The straight-on aim pose (z/hold_aim, kept in the library
		# for sighting down the barrel later) puts the forearm between the
		# camera and the gun from this angle.
		var want := "z/hold_idle"
		if mode == "melee":
			want = "z/swing_idle"
		elif mode == "bare":
			want = "z/idle"
		if _ap.current_animation != want:
			_ap.play(want, 0.2)

	if OS.get_environment("HANDDBG") != "" and Engine.get_process_frames() % 60 == 30:
		var c0 := get_parent() as Node3D
		var g: Node3D = _held if (_held and is_instance_valid(_held)) else null
		print("HANDDBG hand=%s gun=%s gun_fwd=%s gun_scale=%s vis=%s meshes=%d" % [
			c0.to_local(_hand_r.global_position).snapped(Vector3.ONE * 0.01),
			c0.to_local(g.global_position).snapped(Vector3.ONE * 0.01) if g else "none",
			(c0.global_basis.inverse() * (-g.global_basis.z)).normalized().snapped(Vector3.ONE * 0.01) if g else "none",
			g.global_transform.basis.get_scale().snapped(Vector3.ONE * 0.001) if g else "none",
			g.visible if g else false, g.find_children("*", "MeshInstance3D", true, false).size() if g else 0])
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
		(Basis(Vector3.RIGHT, -_lag.y * 0.6) * Basis(Vector3.UP, PI - _lag.x * 0.6)).scaled(Vector3.ONE * RIG_SCALE),
		_base.origin + off)
	_model.transform = _model.transform.interpolate_with(want_xf, clampf(delta * 18.0, 0.0, 1.0))
