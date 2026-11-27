class_name FloatPose
extends SkeletonModifier3D
## The heroine's floating repose, layered on whatever she is playing: legs
## softly bent at different heights, arms drifting open, chest and chin
## lifted, all breathing slowly. `amount` blends it in (0..1). Offsets are
## local rotations (degrees) on her humanoid bones, found by rendering.

const OFFSETS := {
	"LeftUpperLeg": Vector3(24, 0, 4), "LeftLowerLeg": Vector3(30, 0, 0),
	"RightUpperLeg": Vector3(12, 0, -4), "RightLowerLeg": Vector3(60, 0, 0),
	"Head": Vector3(-7, 0, 0), "Spine": Vector3(-6, 0, 0), "Chest": Vector3(-8, 0, 0),
	"LeftUpperArm": Vector3(32, 0, 0), "RightUpperArm": Vector3(0, 0, 42),
}
## Slow drift on top (degrees of extra swing, per bone).
const DRIFT := {"LeftUpperArm": Vector3(6, 0, 0), "RightUpperArm": Vector3(0, 0, 6),
	"LeftLowerLeg": Vector3(6, 0, 0), "RightLowerLeg": Vector3(-5, 0, 0), "Head": Vector3(2, 3, 0)}

var amount := 0.0
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
	if amount <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	_t += get_process_delta_time()
	var breath := sin(_t * 1.3)
	for n in _ids:
		var b: int = _ids[n]
		var e: Vector3 = OFFSETS[n] + DRIFT.get(n, Vector3.ZERO) * breath
		var q := Quaternion.from_euler(e * (PI / 180.0))
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion.IDENTITY.slerp(q, amount))
