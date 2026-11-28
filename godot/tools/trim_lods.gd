extends SceneTree
## Trims the characters' LOD chains (LodUtil): at most three levels, none
## below 15% of the triangles, none on small parts.
##   godot --headless --path . -s res://tools/trim_lods.gd

const DIR := "res://assets/models/heroes/"


func _initialize() -> void:
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".scn"):
			continue
		var root: Node = (load(DIR + f) as PackedScene).instantiate()
		var n := 0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh is ArrayMesh:
				var t := LodUtil.trimmed(mi.mesh as ArrayMesh)
				if t != mi.mesh:
					mi.mesh = t
					n += 1
		if n > 0:
			var out := PackedScene.new()
			out.pack(root)
			print("TRIM %s: %d meshes, save=%d" % [f, n, ResourceSaver.save(out, DIR + f, ResourceSaver.FLAG_COMPRESS)])
		root.free()
	quit()
