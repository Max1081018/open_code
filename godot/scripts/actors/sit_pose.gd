class_name SitPose
extends SkeletonModifier3D
## Sitting on a ledge with the legs hanging over the drop, layered on the
## standing idle: thighs forward, shins down, hands resting on the stone
## behind the hips, chest easy. The shins swing slowly, out of step and not
## quite regularly, the head drifts to look out and back, and she breathes.
## `amount` blends it in (0..1). Offsets are local rotations in degrees on
## her humanoid bones, found by rendering them side-on (tools/_float.gd).

const OFFSETS := {
	"LeftUpperLeg": Vector3(55, 0, 5), "RightUpperLeg": Vector3(60, 0, -5),
	"LeftLowerLeg": Vector3(50, 0, 0), "RightLowerLeg": Vector3(70, 0, 0),
	"Spine": Vector3(8, 0, 0), "Head": Vector3(6, 0, 0),
	"LeftUpperArm": Vector3(-35, 0, -20), "RightUpperArm": Vector3(-35, 0, 20),
	"LeftLowerArm": Vector3(0, 0, -15), "RightLowerArm": Vector3(0, 0, 15),
}

var amount := 1.0
var swing := 1.0
var _ids := {}
var _t := 0.0


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for n in OFFSETS:
		var b := sk.find_bone(n)
		if b >= 0:
			_ids[n] = b


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.001:
		return
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	# Two slow, slightly detuned swings so the legs never move in lockstep.
	var left := sin(_t * 2.1) * 16.0 + sin(_t * 0.7) * 5.0
	var right := sin(_t * 1.83 + 2.2) * 14.0 + sin(_t * 0.55 + 1.0) * 6.0
	var breathe := sin(_t * 1.4) * 1.6
	var look := sin(_t * 0.23) * 14.0 + sin(_t * 0.61) * 4.0
	for n in _ids:
		var off: Vector3 = OFFSETS[n]
		match n:
			"LeftLowerLeg":
				off.x += left * swing
			"RightLowerLeg":
				off.x += right * swing
			"LeftUpperLeg":
				off.x += left * 0.15 * swing
			"RightUpperLeg":
				off.x += right * 0.15 * swing
			"Spine":
				off.x += breathe
			"Head":
				off.y += look
		var b: int = _ids[n]
		var q := Quaternion.from_euler(off * (PI / 180.0))
		var pose := sk.get_bone_pose_rotation(b)
		sk.set_bone_pose_rotation(b, pose * Quaternion.IDENTITY.slerp(q, amount))
