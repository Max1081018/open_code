extends SceneTree
func _initialize() -> void:
	for p in OS.get_cmdline_user_args():
		var sc: Node3D = (load(p) as PackedScene).instantiate()
		var out := []
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				var c: Color = (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(9,9,9)
				var t = (mat as BaseMaterial3D).albedo_texture if mat is BaseMaterial3D else null
				out.append("%s:(%.2f,%.2f,%.2f)%s" % [mat.resource_name if mat else "none", c.r, c.g, c.b, "+tex" if t else ""])
		print("%-26s %s" % [p.get_file(), ", ".join(out)])
	quit()
