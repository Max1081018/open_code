extends SceneTree
## Packs downloaded, retargeted character models (assets/models/sf_src, not
## shipped) into compact game scenes (assets/models/heroes/<role>.scn):
## textures capped for phones (colour 1024 px, normal/roughness 512 px),
## the files' own animation players removed (the shared library drives
## them), skinned meshes kept on the "%GeneralSkeleton" humanoid rig.
##   godot --headless --path . -s res://tools/pack_characters.gd -- images role=id ...
##   godot --headless --path . --import
##   godot --headless --path . -s res://tools/pack_characters.gd -- scenes role=id ...
## Pass 1 writes each texture as an image file (JPG, or PNG where it has
## alpha) so the importer can VRAM-compress it for phones; pass 2 builds the
## scene against those imported textures, without the files' facial blend
## shapes (the game never plays them; they were most of the size).

const SRC := "res://assets/models/sf_src/%s.glb"
const OUT := "res://assets/models/heroes/%s.scn"
const COLOUR_MAX := 1024
const DETAIL_MAX := 512


var _images_only := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/heroes"))
	var args := OS.get_cmdline_user_args()
	_images_only = args[0] == "images"
	for arg in args.slice(1):
		var pair := String(arg).split("=")
		_pack(pair[0], pair[1])
	quit()


func _pack(role: String, id: String) -> void:
	var root: Node3D = load(SRC % id).instantiate()
	root.name = role
	for player in root.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	var shrunk := {}
	var before := 0
	var after := 0
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(s) as BaseMaterial3D
			if material == null:
				continue
			var copy: BaseMaterial3D = material.duplicate()
			for slot in [["albedo_texture", COLOUR_MAX], ["normal_texture", DETAIL_MAX],
					["roughness_texture", DETAIL_MAX], ["metallic_texture", DETAIL_MAX],
					["emission_texture", DETAIL_MAX], ["ao_texture", DETAIL_MAX], ["orm_texture", DETAIL_MAX]]:
				if not (slot[0] in copy):
					continue
				var texture: Texture2D = copy.get(slot[0])
				if texture == null:
					continue
				if not shrunk.has(texture):
					var image := texture.get_image()
					if image == null:
						continue
					if image.is_compressed():
						image.decompress()
					before += image.get_width() * image.get_height()
					var limit: int = slot[1]
					var big := maxi(image.get_width(), image.get_height())
					if big > limit:
						var k := float(limit) / big
						image.resize(maxi(1, int(image.get_width() * k)), maxi(1, int(image.get_height() * k)), Image.INTERPOLATE_LANCZOS)
					after += image.get_width() * image.get_height()
					var dir := "res://assets/models/heroes/%s/" % role
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
					var alpha := image.detect_alpha() != Image.ALPHA_NONE
					var file := dir + "%s_%d.%s" % [String(slot[0]).trim_suffix("_texture"), shrunk.size(), "png" if alpha or slot[0] == "normal_texture" else "jpg"]
					if _images_only:
						if alpha or slot[0] == "normal_texture":
							image.save_png(ProjectSettings.globalize_path(file))
						else:
							image.convert(Image.FORMAT_RGB8)
							image.save_jpg(ProjectSettings.globalize_path(file), 0.88)
						if slot[0] == "normal_texture":
							_mark_normal(file)
						shrunk[texture] = texture
					else:
						shrunk[texture] = load(file)
				copy.set(slot[0], shrunk[texture])
			mesh_instance.set_surface_override_material(s, copy)
		# Skinned meshes are posed far from their rest bounds: never cull them
		# by the rest box.
		mesh_instance.extra_cull_margin = 4.0
		if not _images_only:
			_strip_blend_shapes(mesh_instance)
			# The converted materials go onto the mesh itself, so the
			# originals (with their full-size embedded images) are dropped.
			var own := mesh_instance.mesh.duplicate() as ArrayMesh
			for s in own.get_surface_count():
				var override := mesh_instance.get_surface_override_material(s)
				if override:
					own.surface_set_material(s, override)
					mesh_instance.set_surface_override_material(s, null)
			mesh_instance.mesh = own
	if _images_only:
		print(role, " <- ", id, ": ", shrunk.size(), " textures written")
		root.free()
		return
	_own(root, root)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OUT % role, ResourceSaver.FLAG_COMPRESS)
	var bytes := FileAccess.get_file_as_bytes(OUT % role).size()
	print(role, " <- ", id, ": ", shrunk.size(), " textures, ", before / 1000000, " -> ", after / 1000000,
		" Mpx, ", bytes / 1024, " KB")
	root.free()


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


## Rebuild a mesh without blend shapes, keeping each surface's material.
func _strip_blend_shapes(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh as ArrayMesh
	if mesh == null or mesh.get_blend_shape_count() == 0:
		return
	var plain := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var flags := 0
		var bones = arrays[Mesh.ARRAY_BONES]
		var verts = arrays[Mesh.ARRAY_VERTEX]
		if bones != null and verts != null and verts.size() > 0 and bones.size() == verts.size() * 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		plain.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays, [], {}, flags)
		plain.surface_set_material(s, mesh_instance.get_surface_override_material(s) if mesh_instance.get_surface_override_material(s) else mesh.surface_get_material(s))
		plain.surface_set_name(s, mesh.surface_get_name(s))
	mesh_instance.mesh = plain


## Import a written normal map as a normal map (VRAM-compressed as one).
func _mark_normal(file: String) -> void:
	var config := ConfigFile.new()
	config.set_value("remap", "importer", "texture")
	config.set_value("remap", "type", "CompressedTexture2D")
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "compress/normal_map", 1)
	config.set_value("params", "mipmaps/generate", true)
	config.save(ProjectSettings.globalize_path(file + ".import"))
