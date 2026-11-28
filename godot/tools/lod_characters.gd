extends SceneTree
## Adds levels of detail to every packed character (assets/models/heroes/*.scn).
##
## The downloaded cast is dense: the knight model (every armoured foe and two
## guardians) is 118k triangles, the Warden 130k, and each is drawn three
## times (colour, shadow, ink outline). Godot picks a mesh LOD by how big the
## mesh is on screen, so close up nothing changes and a figure across the
## field costs a fraction. Skin and skeleton bindings are kept: only the mesh
## resource is swapped, its vertices untouched (LODs are index lists).
##   godot --headless --path . -s res://tools/lod_characters.gd

const DIR := "res://assets/models/heroes/"


func _initialize() -> void:
	var dir := DirAccess.open(DIR)
	var total_before := 0
	for f in dir.get_files():
		if not f.ends_with(".scn"):
			continue
		var path := DIR + f
		var packed := load(path) as PackedScene
		var root := packed.instantiate()
		var done := 0
		var already := 0
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var mesh := mi.mesh as ArrayMesh
			if mesh == null:
				continue
			if _has_lods(mesh):
				already += 1
				continue
			mi.mesh = _with_lods(mesh)
			done += 1
		if done > 0:
			var out := PackedScene.new()
			out.pack(root)
			var err := ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)
			print("LOD %s: %d meshes given LODs (%d had them) save=%d" % [f, done, already, err])
		else:
			print("LOD %s: nothing to do (%d had them)" % [f, already])
		root.free()
	quit()


func _has_lods(mesh: ArrayMesh) -> bool:
	var im := ImporterMesh.new()
	return false if mesh.get_surface_count() == 0 else mesh.has_meta("lods_generated")


func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	im.set_blend_shape_mode(mesh.blend_shape_mode)
	for b in mesh.get_blend_shape_count():
		im.add_blend_shape(mesh.get_blend_shape_name(b))
	for k in mesh.get_surface_count():
		# Keep the surface's flags (8 bone weights, custom channel formats),
		# not its per-array presence bits.
		var flags := mesh.surface_get_format(k) & ~0x1FFF
		im.add_surface(mesh.surface_get_primitive_type(k), mesh.surface_get_arrays(k),
			mesh.surface_get_blend_shape_arrays(k), {}, mesh.surface_get_material(k),
			mesh.surface_get_name(k), flags)
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	out.resource_name = mesh.resource_name
	out.set_meta("lods_generated", true)
	out.custom_aabb = mesh.custom_aabb
	return out
