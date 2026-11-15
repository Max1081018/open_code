extends SceneTree
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var ps = load(path)
		if ps == null:
			print(path.get_file(), " LOAD FAILED"); continue
		var sc: Node3D = ps.instantiate()
		get_root().add_child(sc)
		var box := AABB()
		var tris := 0
		for mi in sc.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			box = box.merge(m.global_transform * m.mesh.get_aabb()) if box.has_volume() else m.global_transform * m.mesh.get_aabb()
			tris += m.mesh.get_faces().size() / 3
		print("%-28s size=%s min_y=%.2f tris=%d" % [path.get_file(), box.size.snapped(Vector3.ONE*0.01), box.position.y, tris])
		sc.queue_free()
	quit()
