extends SceneTree
## Splits downloaded nature packs (assets/models/sf_src/nature/<pack>.glb, not
## shipped) into one mesh per piece: assets/models/nature_ext/<pack>_<n>.res.
## A "piece" is a group of meshes whose combined footprint does not overlap
## another group's (a tree's trunk and leaves stay together). Each piece is
## merged to one surface per material, centred on its base, with textures
## capped at 512 px for phones.
##   godot --headless --path . -s res://tools/split_nature.gd -- pack1 pack2 ...
## Prints each piece's size so foliage specs can be written.

const SRC := "res://assets/models/sf_src/nature/%s.glb"
const OUT := "res://assets/models/nature_ext/"
const TEX_MAX := 512

var _tex_cache := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "tex"))
	# "pack:each" — every mesh is its own piece (packs authored all at the origin).
	for arg in OS.get_cmdline_user_args():
		_each = String(arg).ends_with(":each")
		_split(String(arg).trim_suffix(":each"))
	quit()


var _pack := ""
var _each := false


func _split(pack: String) -> void:
	_pack = pack
	var root: Node3D = (load(SRC % pack) as PackedScene).instantiate()
	get_root().add_child(root)
	# World-space boxes of every mesh.
	var items: Array = []
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		items.append([mi, mi.global_transform * mi.get_aabb()])
	# Group meshes whose ground footprints overlap.
	var groups: Array = []
	for it in items:
		var box: AABB = it[1]
		var placed := false
		for g in groups:
			var gb: AABB = g[1]
			if not _each and _footprints_touch(gb, box):
				g[0].append(it[0])
				g[1] = gb.merge(box)
				placed = true
				break
		if not placed:
			groups.append([[it[0]], box])
	var n := 0
	for g in groups:
		var box: AABB = g[1]
		if box.size.y < 0.001:
			continue
		var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
		var tools := {}
		var mats := {}
		for mi in g[0]:
			var t: Transform3D = Transform3D(Basis.IDENTITY, -base) * (mi as MeshInstance3D).global_transform
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				var mat: Material = (mi as MeshInstance3D).get_active_material(s)
				var k: Variant = mat if mat else "none"
				if not tools.has(k):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					tools[k] = st
					mats[k] = _small(mat)
				(tools[k] as SurfaceTool).append_from((mi as MeshInstance3D).mesh, s, t)
		var mesh := ArrayMesh.new()
		for k in tools:
			(tools[k] as SurfaceTool).commit(mesh)
			if mats[k]:
				mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
		var path := OUT + "%s_%d.res" % [pack, n]
		ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		print("PIECE %s_%d size=%s surfaces=%d" % [pack, n, box.size, mesh.get_surface_count()])
		n += 1
	root.queue_free()


func _footprints_touch(a: AABB, b: AABB) -> bool:
	var grow := -0.05 * minf(a.size.length(), b.size.length())
	return a.position.x - grow < b.end.x and b.position.x - grow < a.end.x \
		and a.position.z - grow < b.end.z and b.position.z - grow < a.end.z


## A copy of the material with every texture shrunk to TEX_MAX.
func _small(mat: Material) -> Material:
	if not (mat is BaseMaterial3D):
		return mat
	var m := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	for slot in ["albedo_texture", "normal_texture", "roughness_texture", "emission_texture", "metallic_texture", "ao_texture"]:
		var tex: Texture2D = m.get(slot)
		if tex == null:
			continue
		if not _tex_cache.has(tex):
			var img := tex.get_image()
			if img == null:
				_tex_cache[tex] = null
			else:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				if maxi(img.get_width(), img.get_height()) > TEX_MAX:
					var k := float(TEX_MAX) / maxi(img.get_width(), img.get_height())
					img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
				img.generate_mipmaps()
				# Saved once and shared by every piece that uses it.
				var tpath := OUT + "tex/%s_%d.res" % [_pack, _tex_cache.size()]
				ResourceSaver.save(ImageTexture.create_from_image(img), tpath, ResourceSaver.FLAG_COMPRESS)
				_tex_cache[tex] = load(tpath)
		m.set(slot, _tex_cache[tex])
	return m
