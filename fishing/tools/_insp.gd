extends SceneTree
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var s: Node3D = (load(path) as PackedScene).instantiate()
		print("== ", path)
		_walk(s, 0, Transform3D())
	quit()
func _walk(n: Node, d: int, xf: Transform3D) -> void:
	var extra := ""
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a: AABB = here * n.mesh.get_aabb()
		var faces: int = n.mesh.get_faces().size() / 3
		extra = " min=%s max=%s tris=%d" % [a.position.snapped(Vector3.ONE*0.01), a.end.snapped(Vector3.ONE*0.01), faces]
	print("  ".repeat(d), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_walk(c, d + 1, here)
