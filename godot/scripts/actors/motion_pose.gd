class_name MotionPose
extends SkeletonModifier3D
## Movement layers on top of the clips (degrees, local bone axes; signs found
## with tools/_float.gd):
##   lean  — her sprint: body pitched forward from the hips, chin kept level,
##           arms swept a little back. An agile, eager anime run.
##   fall  — airborne and dropping: one knee tucked, the other leg trailing,
##           arms opened back for balance (rising keeps the jump clip pure).
## Each blends 0..1 and is eased by the player.

const LEAN := {"Spine": Vector3(8, 0, 0), "Chest": Vector3(8, 0, 0), "Neck": Vector3(-4, 0, 0), "Head": Vector3(-9, 0, 0),
	"LeftUpperArm": Vector3(-14, 0, 0), "RightUpperArm": Vector3(-14, 0, 0)}
const FALL := {"LeftUpperLeg": Vector3(30, 0, 0), "LeftLowerLeg": Vector3(42, 0, 0),
	"RightUpperLeg": Vector3(6, 0, 0), "RightLowerLeg": Vector3(22, 0, 0),
	"LeftUpperArm": Vector3(-18, 0, -30), "RightUpperArm": Vector3(-18, 0, 30),
	"Spine": Vector3(-4, 0, 0), "Head": Vector3(-6, 0, 0)}

var lean := 0.0
var fall := 0.0
var _ids := {}


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for d in [LEAN, FALL]:
		for n in d:
			var b := sk.find_bone(n)
			if b >= 0:
				_ids[n] = b


func _process_modification() -> void:
	if lean <= 0.001 and fall <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	for n in _ids:
		var e: Vector3 = LEAN.get(n, Vector3.ZERO) * lean + FALL.get(n, Vector3.ZERO) * fall
		if e == Vector3.ZERO:
			continue
		var b: int = _ids[n]
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * Quaternion.from_euler(e * (PI / 180.0)))
