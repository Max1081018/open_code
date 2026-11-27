extends SceneTree
func _initialize():
	var before := {}
	var t0 := Time.get_ticks_msec()
	var m: Node3D = CharacterKit.build("player")
	print("BUILD ms ", Time.get_ticks_msec() - t0)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var x := mi as MeshInstance3D
		print("MESH ", x.name, " tris=", x.mesh.surface_get_array_index_len(0) / 3)
	quit()
