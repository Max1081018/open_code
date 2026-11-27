class_name SecondaryMotion
extends RefCounted
## Spring-bone physics for the soft parts of a character: hair, side tails,
## ribbons, skirt strands, tails, capes and wings swing, lag and settle as the
## body moves (Godot's SpringBoneSimulator3D, the same idea as VRM spring
## bones). Chains are found by bone names, so any rig with such bones gets it.

## name fragment -> [stiffness, drag, gravity, radius]
const KINDS := {
	"skirt": [2.6, 0.45, 0.6, 0.04],
	"tail": [0.9, 0.35, 0.5, 0.02],
	"wing": [3.5, 0.6, 0.15, 0.02],
	"ribon": [0.8, 0.3, 0.6, 0.01],
	"ribbon": [0.8, 0.3, 0.6, 0.01],
	"hair": [1.4, 0.4, 0.35, 0.02],
	"cape": [1.0, 0.4, 0.8, 0.03],
	"cloak": [1.0, 0.4, 0.8, 0.03],
	"coat": [2.0, 0.5, 0.6, 0.03],
	"bust": [6.0, 0.6, 0.0, 0.0],
}


static func kind_of(bone: String) -> String:
	var b := bone.to_lower()
	for k in KINDS:
		if b.contains(k):
			return k
	return ""


## Add a simulator for every soft chain under `skeleton`. Returns chain count.
static func setup(skeleton: Skeleton3D) -> int:
	var chains := []
	for i in skeleton.get_bone_count():
		var kind := kind_of(skeleton.get_bone_name(i))
		if kind == "":
			continue
		var parent := skeleton.get_bone_parent(i)
		if parent >= 0 and kind_of(skeleton.get_bone_name(parent)) != "":
			continue  # not the start of a chain
		# Follow the chain down through soft children to its end.
		var end := i
		var length := 1
		while true:
			var next := -1
			for c in skeleton.get_bone_children(end):
				if kind_of(skeleton.get_bone_name(c)) != "":
					next = c
					break
			if next < 0:
				break
			end = next
			length += 1
		if length < 2 and kind != "hair":
			continue
		chains.append([i, end, kind])
	if chains.is_empty():
		return 0
	var sim := SpringBoneSimulator3D.new()
	sim.name = "SoftBones"
	skeleton.add_child(sim)
	_add_body_colliders(skeleton, sim)
	sim.setting_count = chains.size()
	for n in chains.size():
		var c: Array = chains[n]
		var p: Array = KINDS[c[2]]
		sim.set_root_bone(n, c[0])
		sim.set_end_bone(n, c[1])
		sim.set_extend_end_bone(n, true)
		sim.set_end_bone_length(n, 0.05)
		sim.set_stiffness(n, p[0])
		sim.set_drag(n, p[1])
		sim.set_gravity(n, p[2])
		sim.set_radius(n, p[3])
		# Cloth, tails and hair stay outside the legs and hips.
		sim.set_enable_all_child_collisions(n, c[2] in ["skirt", "tail", "coat", "cape", "cloak", "ribon", "ribbon", "hair"])
	return chains.size()


## Capsules along the thighs and shins and a sphere-ish one at the hips,
## sized from the rig itself, that the soft chains collide with.
static func _add_body_colliders(skeleton: Skeleton3D, sim: SpringBoneSimulator3D) -> void:
	var pairs := [["LeftUpperLeg", "LeftLowerLeg", 0.32], ["RightUpperLeg", "RightLowerLeg", 0.32],
		["LeftLowerLeg", "LeftFoot", 0.22], ["RightLowerLeg", "RightFoot", 0.22], ["Hips", "Spine", 0.9]]
	for pr in pairs:
		var a := skeleton.find_bone(pr[0])
		var b := skeleton.find_bone(pr[1])
		if a < 0 or b < 0:
			continue
		var from := skeleton.get_bone_global_rest(a)
		var to := skeleton.get_bone_global_rest(b).origin
		var local_to := from.affine_inverse() * to
		var length := local_to.length()
		if length < 0.0001:
			continue
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.bone_name = pr[0]
		var r: float = length * float(pr[2])
		cap.radius = r
		cap.height = length + r * 2.0 if pr[0] != "Hips" else r * 2.2
		cap.position_offset = local_to * 0.5 if pr[0] != "Hips" else Vector3.ZERO
		# Capsules run along their Y axis: turn Y onto the bone.
		cap.rotation_offset = Quaternion(Vector3.UP, local_to.normalized())
		sim.add_child(cap)
