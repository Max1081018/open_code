extends SceneTree
## Ground speed of the heroine's gait clips: how fast a planted foot slides
## backward under her (model space), so playback can match movement speed.
##   godot --headless --path . -s res://tools/measure_gait.gd
var model: Node3D
var _done := false


func _initialize():
	model = CharacterKit.build("player")
	get_root().add_child(model)


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	_measure()
	return true


func _measure():
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var style: Dictionary = model.get_meta("style", {})
	for c in ["NinjaJump_Land", "Hit_Knockback", "Hit_Head", "LayToIdle", "Death01"]:
		print(c, " ", anim.has_animation(style.get("clips", {}).get(c, c)))
	for name in ["Walk", "Jog_Fwd", "Sprint"]:
		var clip: String = style.get("clips", {}).get(name, name)
		if not anim.has_animation(clip):
			print(name, " missing"); continue
		var a := anim.get_animation(clip)
		anim.play(clip)
		var n := 60
		var samples := []
		for i in n + 1:
			anim.seek(a.length * i / n, true)
			sk.force_update_all_bone_transforms() if sk.has_method("force_update_all_bone_transforms") else null
			var row := []
			for f in ["LeftFoot", "RightFoot"]:
				var b := sk.find_bone(f)
				row.append(sk.global_transform * sk.get_bone_global_pose(b).origin)
			samples.append(row)
		# For each foot: the speed along z while it is lowest (planted).
		var speeds := []
		for k in 2:
			var miny := 1e9
			for s in samples: miny = minf(miny, s[k].y)
			for i in n:
				var p0: Vector3 = samples[i][k]
				var p1: Vector3 = samples[i + 1][k]
				if p0.y < miny + 0.03 and p1.y < miny + 0.03:
					speeds.append(absf(p1.z - p0.z) / (a.length / n))
		var zs := []
		for s in samples: zs.append(s[0].z)
		print("  stride range z=%.2f" % [zs.max() - zs.min()])
		speeds.sort()
		var med = speeds[speeds.size() / 2] if speeds.size() > 0 else 0.0
		print("%s clip=%s len=%.2f ground_speed=%.2f m/s (n=%d) style_speed=%s" % [name, clip, a.length, med, speeds.size(), style.get("speed", 1.0)])
