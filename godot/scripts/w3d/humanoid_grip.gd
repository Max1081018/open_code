class_name HumanoidGrip
extends RefCounted
## A grip node in a humanoid's fist, the frame every packed item is made for
## (tools/pack_items.gd: shaft +Y, head +X): the shaft runs along the
## knuckles out of the thumb side, set into the palm, scale-corrected so a
## sword stays sword-sized whatever units the rig was built in.


static func grip(skeleton: Skeleton3D, model: Node3D, hand: String, index: String, pinky: String, middle: String) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = hand
	skeleton.add_child(attachment)
	var h := skeleton.find_bone(hand)
	var to_local := skeleton.get_bone_global_rest(h).affine_inverse()
	var i := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(index)).origin
	var p := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(pinky)).origin
	var m := to_local * skeleton.get_bone_global_rest(skeleton.find_bone(middle)).origin
	var along := -(i - p).normalized()
	var fingers := m.normalized()
	var palm := along.cross(fingers).normalized()
	if hand.begins_with("Left"):
		palm = -palm
	fingers = palm.cross(along).normalized()
	var g := Node3D.new()
	g.name = "Grip"
	g.transform = Transform3D(Basis(fingers, along, palm), (i + p) * 0.5 * 0.9 + palm * m.length() * 0.35)
	attachment.add_child(g)
	var rig_scale := (skeleton.global_transform * skeleton.get_bone_global_rest(h)).basis.get_scale()
	var model_scale := model.global_transform.basis.get_scale()
	g.scale = model_scale / rig_scale
	return g
