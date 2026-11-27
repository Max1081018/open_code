class_name SkirtFollow
extends SkeletonModifier3D
## Makes a skirt ride on the thighs. Each skirt chain's root bone takes the
## thighs' rotation (from their rest) in proportion to where the chain hangs
## round the waist: chains in front follow the leg on their side, the side
## chains a little, the back ones not at all. Runs after the pose (animation,
## sitting, floating) and before the spring bones, which then drape the rest
## of each chain with gravity and keep it outside the legs. Result: when a leg
## lifts, the skirt lifts over it instead of the leg cutting through.
## Chains are found by name ("skirt" bones whose parent is not a skirt bone).

var _roots: Array = []       ## [bone, weight_left, weight_right]
var _lu := -1
var _ru := -1
var _l_rest := Basis.IDENTITY
var _r_rest := Basis.IDENTITY


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_lu = sk.find_bone("LeftUpperLeg")
	_ru = sk.find_bone("RightUpperLeg")
	var hips := sk.find_bone("Hips")
	if _lu < 0 or _ru < 0 or hips < 0:
		return
	_l_rest = sk.get_bone_global_rest(_lu).basis.orthonormalized()
	_r_rest = sk.get_bone_global_rest(_ru).basis.orthonormalized()
	var centre := sk.get_bone_global_rest(hips).origin
	var left_side := sk.get_bone_global_rest(_lu).origin - centre
	left_side.y = 0.0
	left_side = left_side.normalized()
	# Forward is where the toes point at rest.
	var toe := sk.find_bone("LeftToes")
	if toe < 0:
		toe = sk.find_bone("LeftFoot")
	var fwd := Vector3(0, 0, 1)
	if toe >= 0:
		var f := sk.get_bone_global_rest(toe).origin - sk.get_bone_global_rest(_lu).origin
		f.y = 0.0
		if f.length() > 0.001:
			fwd = f.normalized()
	for i in sk.get_bone_count():
		if not sk.get_bone_name(i).to_lower().contains("skirt"):
			continue
		var parent := sk.get_bone_parent(i)
		if parent >= 0 and sk.get_bone_name(parent).to_lower().contains("skirt"):
			continue
		var d := sk.get_bone_global_rest(i).origin - centre
		# Where the chain hangs: its own start, or its first child's.
		var kids := sk.get_bone_children(i)
		if not kids.is_empty():
			d = sk.get_bone_global_rest(kids[0]).origin - centre
		d.y = 0.0
		if d.length() < 0.0001:
			continue
		d = d.normalized()
		var front := clampf(d.dot(fwd) + 0.25, 0.0, 1.0)
		var side := d.dot(left_side)    # +1 left, -1 right
		var wl := front * clampf(0.5 + side * 0.9, 0.0, 1.0)
		var wr := front * clampf(0.5 - side * 0.9, 0.0, 1.0)
		_roots.append([i, wl, wr])


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _roots.is_empty():
		return
	var lq := Quaternion((sk.get_bone_global_pose(_lu).basis.orthonormalized() * _l_rest.inverse()).orthonormalized())
	var rq := Quaternion((sk.get_bone_global_pose(_ru).basis.orthonormalized() * _r_rest.inverse()).orthonormalized())
	for r in _roots:
		var b: int = r[0]
		var wl: float = r[1]
		var wr: float = r[2]
		if wl + wr < 0.01:
			continue
		var q := Quaternion.IDENTITY.slerp(lq, wl) * Quaternion.IDENTITY.slerp(rq, wr)
		var g := sk.get_bone_global_pose(b)
		sk.set_bone_global_pose(b, Transform3D(Basis(q) * g.basis, g.origin))
