class_name MeshMerge
extends RefCounted
## Static props from Sketchfab arrive as dozens of small meshes (a house as
## 145 pieces sharing two materials). Each piece is a draw call, twice with
## shadows. This folds every static mesh under a model into one ArrayMesh
## with a single surface per material, in the model's own frame, cached per
## model so repeated props (lanterns, benches, chests) share it.

static var _cache := {}


## The merged mesh of `root` (an instantiated model), or null if it has
## skinned or animated parts that must stay separate.
static func merged(key: String, root: Node3D) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	if not root.find_children("*", "AnimationPlayer", true, false).is_empty():
		return null
	var tools := {}       ## material (or "none") -> SurfaceTool
	var materials := {}   ## same key -> Material
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if mi.skin != null:
			return null
		var t := _to_root(mi, root)
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s)
			var k: Variant = mat if mat != null else "none"
			if not tools.has(k):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[k] = st
				materials[k] = mat
			(tools[k] as SurfaceTool).append_from(mi.mesh, s, t)
	var out := ArrayMesh.new()
	for k in tools:
		var st: SurfaceTool = tools[k]
		st.commit(out)
		if materials[k] != null:
			out.surface_set_material(out.get_surface_count() - 1, materials[k])
	_cache[key] = out
	return out


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func release() -> void:
	_cache.clear()
