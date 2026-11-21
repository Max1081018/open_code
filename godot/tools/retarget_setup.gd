extends SceneTree
## Sets up Godot's humanoid retargeting for downloaded character models and
## animation sources, whatever rig they came with (Mixamo, Unreal/Quaternius,
## Character Creator, 3ds Max Biped):
##   godot --headless --path . -s res://tools/retarget_setup.gd -- res://dir/a.glb res://dir/b.glb ...
## For each file it finds the skeleton, maps its bones onto
## SkeletonProfileHumanoid by name, saves the BoneMap beside the file and
## writes the import options (bone map, renamed bones, unified rest axes),
## so after a reimport every character's skeleton is "%GeneralSkeleton" with
## the same bone names and axes, and one animation library plays on all.

const PREFIXES := ["mixamorig_", "mixamorig:", "mixamorig", "unknownsoldier_", "cc_base_", "bip01_", "rl_"]

## profile bone -> candidate (normalised) names, left side; right is derived.
const TABLE := {
	"Hips": ["hips", "hip", "pelvis"],
	"Neck": ["neck", "neck_01", "neck1", "necktwist01"],
	"Head": ["head", "head1"],
	"LeftShoulder": ["leftshoulder", "clavicle_l", "l_clavicle"],
	"LeftUpperArm": ["leftarm", "upperarm_l", "l_upperarm"],
	"LeftLowerArm": ["leftforearm", "lowerarm_l", "l_forearm"],
	"LeftHand": ["lefthand", "hand_l", "l_hand"],
	"LeftUpperLeg": ["leftupleg", "thigh_l", "l_thigh"],
	"LeftLowerLeg": ["leftleg", "calf_l", "l_calf"],
	"LeftFoot": ["leftfoot", "foot_l", "l_foot"],
	"LeftToes": ["lefttoebase", "ball_l", "l_toebase", "l_toe0"],
	"LeftThumbMetacarpal": ["lefthandthumb1", "thumb_01_l", "l_thumb1", "l_finger00", "l_finger0"],
	"LeftThumbProximal": ["lefthandthumb2", "thumb_02_l", "l_thumb2", "l_finger01"],
	"LeftThumbDistal": ["lefthandthumb3", "thumb_03_l", "l_thumb3", "l_finger02"],
	"LeftIndexProximal": ["lefthandindex1", "index_01_l", "l_index1", "l_finger10", "l_finger1"],
	"LeftIndexIntermediate": ["lefthandindex2", "index_02_l", "l_index2", "l_finger11"],
	"LeftIndexDistal": ["lefthandindex3", "index_03_l", "l_index3", "l_finger12"],
	"LeftMiddleProximal": ["lefthandmiddle1", "middle_01_l", "l_mid1", "l_finger20", "l_finger2"],
	"LeftMiddleIntermediate": ["lefthandmiddle2", "middle_02_l", "l_mid2", "l_finger21"],
	"LeftMiddleDistal": ["lefthandmiddle3", "middle_03_l", "l_mid3", "l_finger22"],
	"LeftRingProximal": ["lefthandring1", "ring_01_l", "l_ring1", "l_finger30", "l_finger3"],
	"LeftRingIntermediate": ["lefthandring2", "ring_02_l", "l_ring2", "l_finger31"],
	"LeftRingDistal": ["lefthandring3", "ring_03_l", "l_ring3", "l_finger32"],
	"LeftLittleProximal": ["lefthandpinky1", "pinky_01_l", "l_pinky1", "l_finger40", "l_finger4"],
	"LeftLittleIntermediate": ["lefthandpinky2", "pinky_02_l", "l_pinky2", "l_finger41"],
	"LeftLittleDistal": ["lefthandpinky3", "pinky_03_l", "l_pinky3", "l_finger42"],
}


static func normalise(bone: String, strip_number := true) -> String:
	var n := bone.to_lower().replace(" ", "_")
	if strip_number:
		# Sketchfab's exporter appends "_<index>" to every bone name.
		n = RegEx.create_from_string("_\\d+$").sub(n, "")
	for p in PREFIXES:
		if n.begins_with(p):
			n = n.substr(p.length())
	return n


static func right(name: String) -> String:
	if name.begins_with("left"):
		return "right" + name.substr(4)
	if name.ends_with("_l"):
		return name.left(-2) + "_r"
	if name.begins_with("l_"):
		return "r_" + name.substr(2)
	return name


func _initialize() -> void:
	# "raw:res://..." marks a file whose bone names carry no exporter
	# suffix, so trailing numbers are meaningful (spine_01, spine_02...).
	for arg in OS.get_cmdline_user_args():
		var raw := String(arg).begins_with("raw:")
		_setup(String(arg).trim_prefix("raw:"), not raw)
	quit()


func _setup(path: String, strip_numbers: bool) -> void:
	var scene: Node = load(path).instantiate()
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		print(path, ": no skeleton")
		scene.free()
		return
	var skeleton: Skeleton3D = skeletons[0]
	var by_norm := {}
	for i in skeleton.get_bone_count():
		var n := normalise(skeleton.get_bone_name(i), strip_numbers)
		if not by_norm.has(n):
			by_norm[n] = skeleton.get_bone_name(i)
	var table := TABLE.duplicate()
	# The spine: three spine bones (Quaternius/UE4/Mixamo/Biped) or five (UE5).
	if by_norm.has("spine_05"):
		table["Spine"] = ["spine_01"]
		table["Chest"] = ["spine_03"]
		table["UpperChest"] = ["spine_05"]
	else:
		table["Spine"] = ["spine", "spine_01", "waist"]
		table["Chest"] = ["spine1", "spine_02", "spine01"]
		table["UpperChest"] = ["spine2", "spine_03", "spine02"]
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	var found := 0
	var missing := []
	for profile_bone in table.keys():
		var sides := [[profile_bone, table[profile_bone]]]
		if profile_bone.begins_with("Left"):
			var candidates: Array = []
			for c in table[profile_bone]:
				candidates.append(right(c))
			sides.append([profile_bone.replace("Left", "Right"), candidates])
		for side in sides:
			var hit := ""
			for c in side[1]:
				if by_norm.has(c):
					hit = by_norm[c]
					break
			if hit != "":
				map.set_skeleton_bone_name(StringName(side[0]), StringName(hit))
				found += 1
			else:
				missing.append(side[0])
	var map_path := path.get_basename() + "_bonemap.tres"
	ResourceSaver.save(map, map_path)
	var node_path := String(scene.get_path_to(skeleton))
	print(path, ": ", found, " bones mapped; skeleton ", node_path, "; missing ", missing)
	scene.free()
	_write_import(path, node_path, map_path)


## The .import options: retarget this skeleton with the map.
func _write_import(path: String, node_path: String, map_path: String) -> void:
	var config := ConfigFile.new()
	config.load(path + ".import")
	var subresources: Dictionary = config.get_value("params", "_subresources", {})
	var nodes: Dictionary = subresources.get("nodes", {})
	nodes["PATH:" + node_path] = {
		"retarget/bone_map": load(map_path),
		"retarget/bone_renamer/rename_bones": true,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
		"retarget/rest_fixer/apply_node_transforms": true,
		"retarget/rest_fixer/normalize_position_tracks": true,
		"retarget/rest_fixer/overwrite_axis": true,
		"retarget/rest_fixer/fix_silhouette/enable": false,
	}
	subresources["nodes"] = nodes
	config.set_value("params", "_subresources", subresources)
	config.save(path + ".import")
