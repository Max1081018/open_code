extends SceneTree
## Bakes animation clips from one rig onto another and saves them as an
## AnimationLibrary.
##
## The zombie model ships with three clips (idle, walk, attack) on an 18-bone
## rig. Everything else a zombie needs - running, being shot, staggering,
## dying, crawling, getting back up - comes from the Universal Animation
## Library (Quaternius, CC0), which is a 65-bone Unreal-style rig. The two
## skeletons have different bone names, different rest poses and different
## proportions, so the clips are retargeted here, once, offline, rather than
## being matched up at runtime on a phone.
##
## The method is the usual one: for each frame, work out how far a source bone
## has turned away from its own rest pose, in world space, and turn the
## matching target bone by that same amount away from *its* rest pose. Bones
## the target skeleton doesn't have (fingers, the second spine joint) fold into
## whichever of its bones comes next, because each target bone is positioned
## from its source counterpart's accumulated world rotation.
##
##   godot --headless --path zombie --script res://tools/retarget.gd

const SRC := "res://assets/chars/ual.glb"
const DST := "res://assets/chars/AtlasZombieLite_Walker.fbx"
const OUT := "res://assets/chars/zombie_anims.res"
const FPS := 30.0

# target bone -> source bone
const MAP := {
	"hips": "pelvis", "spine": "spine_01", "chest": "spine_03",
	"neck": "neck_01", "head": "Head",
	"upper_arm_L": "upperarm_l", "forearm_L": "lowerarm_l", "hand_L": "hand_l",
	"upper_arm_R": "upperarm_r", "forearm_R": "lowerarm_r", "hand_R": "hand_r",
	"thigh_L": "thigh_l", "shin_L": "calf_l", "foot_L": "foot_l",
	"thigh_R": "thigh_r", "shin_R": "calf_r", "foot_R": "foot_r",
}

# new name -> [source clip, loop]
const WANT := {
	"idle": ["Idle", true],
	"walk": ["Walk", true],
	"run": ["Jog_Fwd", true],
	"chase": ["Sprint", true],
	"attack": ["Punch_Cross", false],
	"bite": ["Punch_Jab", false],
	"hit": ["Hit_Chest", false],
	"stagger": ["Hit_Head", false],
	"death": ["Death01", false],
	"crawl": ["Swim_Fwd", true],
	"crawl_idle": ["Swim_Idle", true],
	"getup": ["Sitting_Exit", false],
	"feed": ["Fixing_Kneeling", true],
	"reach": ["Interact", false],
	# The player's own hands use the same rig and the same library: the arms
	# you see in first person are this model's arms.
	"hold_idle": ["Pistol_Idle", true],
	"hold_aim": ["Pistol_Aim_Neutral", true],
	"hold_shoot": ["Pistol_Shoot", false],
	"hold_reload": ["Pistol_Reload", false],
	"aim_up": ["Pistol_Aim_Up", false],
	"punch": ["Punch_Jab", false],
	"jump": ["Jump_Start", false],
	"land": ["Jump_Land", false],
	"crouch_idle": ["Crouch_Idle", true],
	"crouch_walk": ["Crouch_Fwd", true],
	"swing": ["Sword_Attack", false],
	"swing_idle": ["Sword_Idle", true],
}


func _initialize() -> void:
	var src: Node3D = (load(SRC) as PackedScene).instantiate()
	var dst: Node3D = (load(DST) as PackedScene).instantiate()
	get_root().add_child(src)
	get_root().add_child(dst)
	var ss: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var ts: Skeleton3D = dst.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]

	# Proportions: the mannequin is a head taller than the zombie, so hip
	# travel is scaled by the ratio of their heights. Measured off the meshes,
	# not off the hip bones: the two rigs do not agree on which axis is up in
	# their rest data, and a bone height of "0" silently zeroed the scale.
	# Hip travel is written in bone-space units, and the two rigs are not
	# modelled at the same size: the zombie is imported small and scaled up by
	# its root node. So each height is brought back into its own skeleton's
	# units before the ratio is taken.
	var src_u: float = _height(src) / maxf(ss.global_transform.basis.get_scale().y, 0.0001)
	var dst_u: float = _height(dst) / maxf(ts.global_transform.basis.get_scale().y, 0.0001)
	var hip_scale: float = dst_u / maxf(src_u, 0.000001)
	print("heights: src=%.3f dst=%.3f  bone units: %.4f / %.4f  hip scale=%.5f" % [
		_height(src), _height(dst), src_u, dst_u, hip_scale])

	# The two skeletons do not have to sit in the world the same way round, so
	# every turn is carried through world space and brought back into the
	# target's own frame.
	var qs := ss.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var qt := ts.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var frame := qt.inverse() * qs
	print("frame correction: ", frame)

	# Look-up tables built once.
	var pairs: Array = []            # [target idx, source idx]
	for tname in MAP:
		var ti := ts.find_bone(tname)
		var si := ss.find_bone(str(MAP[tname]))
		if ti < 0 or si < 0:
			print("MISSING %s -> %s" % [tname, MAP[tname]])
			continue
		pairs.append([ti, si])
	var src_rest_inv := {}
	for p in pairs:
		src_rest_inv[p[1]] = ss.get_bone_global_rest(p[1]).basis.get_rotation_quaternion().inverse()

	# The clips have to point at the skeleton the way the model's own
	# AnimationPlayer sees it, or they play into thin air.
	var dap0: AnimationPlayer = dst.find_children("*", "AnimationPlayer", true, false)[0]
	var skel_path := str(dap0.get_node(dap0.root_node).get_path_to(ts))
	print("skeleton track path: ", skel_path)
	var lib := AnimationLibrary.new()
	var clips: Array = ap.get_animation_list()
	for out_name in WANT:
		var want: Array = WANT[out_name]
		if not clips.has(str(want[0])):
			# the library prefixes clips with the armature name on some exports
			var found := ""
			for c in clips:
				if str(c).ends_with(str(want[0])):
					found = str(c)
					break
			if found == "":
				print("NO CLIP %s" % want[0])
				continue
			want[0] = found
		var anim: Animation = ap.get_animation(str(want[0]))
		var baked := _bake(ap, str(want[0]), anim.length, ss, ts, pairs, src_rest_inv,
			hip_scale, skel_path, frame)
		baked.loop_mode = Animation.LOOP_LINEAR if want[1] else Animation.LOOP_NONE
		lib.add_animation(out_name, baked)
		print("baked %-10s <- %-18s %.2fs tracks=%d" % [out_name, want[0], baked.length, baked.get_track_count()])

	# The model's own three clips keep their place in the same library.
	var dap: AnimationPlayer = dst.find_children("*", "AnimationPlayer", true, false)[0]
	for c in dap.get_animation_list():
		var short := str(c).get_slice("|", 1).to_lower().replace("atlas_zombie_", "")
		if short == "":
			short = str(c).to_lower()
		var a: Animation = dap.get_animation(str(c)).duplicate()
		a.loop_mode = Animation.LOOP_LINEAR if short in ["idle", "walk"] else Animation.LOOP_NONE
		if lib.has_animation("own_" + short):
			continue
		lib.add_animation("own_" + short, a)
		print("kept   own_%s (%.2fs)" % [short, a.length])

	var err := ResourceSaver.save(lib, OUT)
	print("saved %s err=%d anims=%d" % [OUT, err, lib.get_animation_list().size()])
	quit()


## Visible height of a model, for matching proportions between rigs.
func _height(n: Node3D) -> float:
	var box := AABB()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		box = box.merge(m.global_transform * m.get_aabb())
	return box.size.y


func _bake(ap: AnimationPlayer, clip: String, length: float, ss: Skeleton3D,
		ts: Skeleton3D, pairs: Array, src_rest_inv: Dictionary, hip_scale: float,
		skel_path: String, frame: Quaternion) -> Animation:
	var out := Animation.new()
	var frames := maxi(int(round(length * FPS)), 2)
	var step := length / float(frames - 1)
	var hips_i := ts.find_bone("hips")
	var hips_src := ss.find_bone("pelvis")
	var hips_rest := ts.get_bone_rest(hips_i).origin
	var src_hips_rest := ss.get_bone_global_rest(hips_src).origin

	# One rotation track per mapped bone, plus hip travel.
	var track := {}
	for p in pairs:
		var ti: int = p[0]
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath("%s:%s" % [skel_path, ts.get_bone_name(ti)]))
		out.track_set_interpolation_loop_wrap(t, true)
		track[ti] = t
	var hip_pos_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hip_pos_track, NodePath(skel_path + ":hips"))

	for f in frames:
		var t := minf(float(f) * step, length)
		ap.play(clip)
		ap.seek(t, true)
		ss.force_update_all_bone_transforms()
		# Desired world rotation for every mapped target bone.
		var want_global := {}
		for p in pairs:
			var ti: int = p[0]
			var si: int = p[1]
			var gs: Quaternion = ss.get_bone_global_pose(si).basis.get_rotation_quaternion()
			var delta: Quaternion = frame * (gs * (src_rest_inv[si] as Quaternion)) * frame.inverse()
			want_global[ti] = delta * ts.get_bone_global_rest(ti).basis.get_rotation_quaternion()
		for p in pairs:
			var ti: int = p[0]
			var parent := ts.get_bone_parent(ti)
			var parent_g: Quaternion
			if want_global.has(parent):
				parent_g = want_global[parent]
			else:
				parent_g = ts.get_bone_global_rest(parent).basis.get_rotation_quaternion() \
					if parent >= 0 else Quaternion.IDENTITY
			out.rotation_track_insert_key(track[ti], t, parent_g.inverse() * (want_global[ti] as Quaternion))
		var hip_off: Vector3 = frame * ((ss.get_bone_global_pose(hips_src).origin - src_hips_rest) * hip_scale)
		out.position_track_insert_key(hip_pos_track, t, hips_rest + hip_off)
	out.length = length
	return out
