extends SceneTree
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		print("=== ", path)
		var sc: Node = (load(path) as PackedScene).instantiate()
		for sk in sc.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			var names: Array = []
			for i in mini(s.get_bone_count(), 70):
				names.append(s.get_bone_name(i))
			print("SKEL %s bones=%d: %s" % [s.name, s.get_bone_count(), ", ".join(names)])
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			print("MESH ", mi.name, " surf=", (mi as MeshInstance3D).mesh.get_surface_count(), " aabb=", (mi as MeshInstance3D).mesh.get_aabb().size.snapped(Vector3.ONE*0.01))
		for ap in sc.find_children("*", "AnimationPlayer", true, false):
			var a := ap as AnimationPlayer
			var l := a.get_animation_list()
			print("ANIMS n=", l.size())
			var out: Array = []
			for n in l:
				out.append("%s(%.1fs)" % [n, a.get_animation(n).length])
			print("  ", ", ".join(out))
		quit()
