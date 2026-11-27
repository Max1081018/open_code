class_name SkirtSolver
extends SkeletonModifier3D
## Skirt cloth on bone chains, solved every frame AFTER the body's pose
## (animation, sitting, floating) so it always meets the legs where they are.
## For every chain hanging from the hips, joint by joint:
##   1. aim the segment where the pose puts it, blended toward hanging under
##      gravity (more so toward the hem) and lagging a little (cloth motion);
##   2. collide its end with capsules on both thighs and shins (from the live
##      pose, sized from the rig) plus cloth thickness, pushing it outward —
##      and keeping a chain that hangs in front of a leg in front of it, so a
##      fast stride can never tunnel through;
##   3. restore the segment's length, collide again, and turn the bone onto it.
## Nothing here waits for a physics step: the skirt is right on every frame.

const STIFF := [0.85, 0.7, 0.55, 0.45, 0.4]   ## how much of the posed direction each segment keeps
const LAG := 16.0                              ## cloth follow rate (1/s); higher = stiffer
const THICK := 0.018                           ## cloth thickness added to the legs (skeleton units)

var _chains: Array = []      ## [[bones...], [lengths...], outward Vector3 (rest), prev ends PackedVector3Array]
var _caps: Array = []        ## [from bone, to bone, radius]
var _hips := -1
var _ready_ok := false


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_hips = sk.find_bone("Hips")
	var lu := sk.find_bone("LeftUpperLeg")
	if _hips < 0 or lu < 0:
		return
	var thigh := sk.get_bone_rest(sk.find_bone("LeftLowerLeg")).origin.length()
	for side in ["Left", "Right"]:
		var u := sk.find_bone(side + "UpperLeg")
		var l := sk.find_bone(side + "LowerLeg")
		var f := sk.find_bone(side + "Foot")
		if u >= 0 and l >= 0:
			_caps.append([u, l, thigh * 0.24])
		if l >= 0 and f >= 0:
			_caps.append([l, f, thigh * 0.16])
	var centre := sk.get_bone_global_rest(_hips).origin
	for i in sk.get_bone_count():
		if not sk.get_bone_name(i).to_lower().contains("skirt"):
			continue
		var p := sk.get_bone_parent(i)
		if p >= 0 and sk.get_bone_name(p).to_lower().contains("skirt"):
			continue
		var bones := [i]
		var b := i
		while true:
			var nx := -1
			for c in sk.get_bone_children(b):
				if sk.get_bone_name(c).to_lower().contains("skirt"):
					nx = c
			if nx < 0:
				break
			bones.append(nx)
			b = nx
		var lengths := []
		for k in range(1, bones.size()):
			lengths.append(sk.get_bone_rest(bones[k]).origin.length())
		# The last bone has no child: give it the same length as the one before.
		lengths.append(lengths[-1] if not lengths.is_empty() else 0.06)
		var out := sk.get_bone_global_rest(bones[bones.size() - 1]).origin - centre
		out.y = 0.0
		var prev := PackedVector3Array()
		prev.resize(bones.size())
		_chains.append([bones, lengths, out.normalized() if out.length() > 0.001 else Vector3.FORWARD, prev, false])
	_ready_ok = not _chains.is_empty()


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or not _ready_ok:
		return
	var dt := clampf(get_process_delta_time() if is_inside_tree() else 0.016, 0.001, 0.05)
	var follow := 1.0 - exp(-LAG * dt)
	var down := (sk.global_transform.basis.inverse() * Vector3.DOWN).normalized()
	# Live leg capsules, in skeleton space.
	var caps := []
	for c in _caps:
		caps.append([sk.get_bone_global_pose(c[0]).origin, sk.get_bone_global_pose(c[1]).origin, float(c[2]) + THICK])
	var hips_pose := sk.get_bone_global_pose(_hips)
	for ch in _chains:
		var bones: Array = ch[0]
		var lengths: Array = ch[1]
		var outward: Vector3 = (hips_pose.basis * (ch[2] as Vector3)).normalized()
		var prev: PackedVector3Array = ch[3]
		var seeded: bool = ch[4]
		var start := sk.get_bone_global_pose(bones[0]).origin
		for k in bones.size():
			var bone: int = bones[k]
			var g := sk.get_bone_global_pose(bone)
			var length: float = lengths[k]
			# Where the pose aims this segment.
			var posed: Vector3
			if k + 1 < bones.size():
				posed = sk.get_bone_global_pose(bones[k + 1]).origin - g.origin
			else:
				posed = g.basis.y.normalized() * length
			if posed.length() < 0.0001:
				posed = down * length
			var stiff: float = STIFF[mini(k, STIFF.size() - 1)]
			var dir := (posed.normalized() * stiff + down * (1.0 - stiff)).normalized()
			var end := start + dir * length
			# Cloth lag, then the constraints that must always hold.
			if seeded:
				end = (prev[k] as Vector3).lerp(end, follow)
			end = _collide(end, caps, outward)
			end = start + (end - start).normalized() * length
			end = _collide(end, caps, outward)
			prev[k] = end
			# Turn the bone so it points from `start` to `end`.
			var cur := posed.normalized()
			var want := (end - start).normalized()
			if cur.dot(want) < 0.99999:
				var q := Quaternion(cur, want)
				sk.set_bone_global_pose(bone, Transform3D(Basis(q) * g.basis, start))
			else:
				sk.set_bone_global_pose(bone, Transform3D(g.basis, start))
			start = end
		ch[3] = prev
		ch[4] = true


## Push `p` out of every leg capsule. A point hanging on the outer side of a
## leg (along `outward`, the chain's side of the body) is pushed out that way.
static func _collide(p: Vector3, caps: Array, outward: Vector3) -> Vector3:
	for c in caps:
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var r: float = c[2]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		var q := a + ab * t
		var d := p - q
		var dist := d.length()
		if dist >= r:
			continue
		var n: Vector3
		if dist < 1e-5:
			n = outward
		else:
			n = d / dist
			# If the leg has swept past this point, keep the cloth on its side.
			var axis := ab.normalized()
			var side := outward - axis * outward.dot(axis)
			if side.length() > 0.001 and n.dot(side.normalized()) < -0.2:
				n = (n + side.normalized() * 2.0).normalized()
		p = q + n * r
	return p
