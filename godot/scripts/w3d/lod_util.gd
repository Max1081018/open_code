class_name LodUtil
extends RefCounted
## Keeps generated levels of detail honest. The mesh simplifier happily
## reduces a part to a sliver (a strap, an eye, a leaf card) and rates the
## error as tiny, so the renderer switches to it a few metres away and the
## part seems to vanish. Trimmed chains keep at most `max_levels` levels and
## never go below `min_ratio` of the full triangle count; small surfaces get
## no LODs at all (they cost nothing to draw in full).

const MIN_RATIO := 0.15
const MAX_LEVELS := 3
const MIN_TRIS := 400
## No level goes below this many triangles (a strap or trim stays a shape).
const MIN_LEVEL_TRIS := 120


## A copy of `mesh` with every surface's LOD chain trimmed (or the mesh itself
## when nothing needed trimming).
static func trimmed(mesh: ArrayMesh, min_ratio := MIN_RATIO, max_levels := MAX_LEVELS) -> ArrayMesh:
	var surfaces: Array = mesh.get("_surfaces")
	var changed := false
	for k in surfaces.size():
		var d: Dictionary = surfaces[k]
		var flat: Array = d.get("lods", [])
		if flat.is_empty():
			continue
		var full := int(d.get("index_count", 0))
		var wide := int(d.get("vertex_count", 0)) > 65535
		var keep := []
		if full / 3 >= MIN_TRIS:
			for i in range(0, flat.size(), 2):
				var n := (flat[i + 1] as PackedByteArray).size() / (4 if wide else 2)
				if float(n) / full < min_ratio or n / 3 < MIN_LEVEL_TRIS or keep.size() >= max_levels * 2:
					break
				keep.append(flat[i])
				keep.append(flat[i + 1])
		if keep.size() != flat.size():
			d = d.duplicate()
			d["lods"] = keep
			surfaces[k] = d
			changed = true
	if not changed:
		return mesh
	var out := ArrayMesh.new()
	out.set("_blend_shape_names", mesh.get("_blend_shape_names"))
	out.blend_shape_mode = mesh.blend_shape_mode
	out.set("_surfaces", surfaces)
	out.resource_name = mesh.resource_name
	out.custom_aabb = mesh.custom_aabb
	out.blend_shape_mode = mesh.blend_shape_mode
	for m in mesh.get_meta_list():
		out.set_meta(m, mesh.get_meta(m))
	return out
