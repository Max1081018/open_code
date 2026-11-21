extends SceneTree
## Packs downloaded hand-held items (assets/models/sf_src/items, not shipped)
## into assets/models/items/<name>.scn, every one in the same frame so the
## hand can hold any of them: the grip at the origin, the shaft along +Y
## (toward the head or blade tip), the head/blade sticking out along +X,
## real length in metres. Shields: centred, face toward +Z, up along +Y.
##   godot --headless --path . -s res://tools/pack_items.gd -- images
##   godot --headless --path . --import
##   godot --headless --path . -s res://tools/pack_items.gd -- scenes

const SRC := "res://assets/models/sf_src/items/"
const OUT := "res://assets/models/items/"
const TEX_MAX := 512

## name -> {file, parts: [[node name filter, offset along the handle]],
## kind: tool|sword|torch|rod|shield, length (m), grip (fraction from the end)}
const RECIPES := {
	"pickaxe": {"file": "pickaxe", "kind": "tool", "length": 0.88, "grip": 0.1},
	"axe": {"file": "toolpack", "parts": [["Axe_Handle", 0.0], ["Axe_003", 0.0]], "kind": "tool", "length": 0.8, "grip": 0.1},
	"hammer": {"file": "toolpack", "parts": [["Hammer_Handle", 0.0], ["Hammer_003", 0.0]], "kind": "tool", "length": 0.7, "grip": 0.1},
	"sword": {"file": "sword_iron", "kind": "sword", "length": 1.0, "grip": 0.08},
	"sword_fine": {"file": "sword_fine", "kind": "sword", "length": 1.05, "grip": 0.08},
	"torch": {"file": "torch", "kind": "torch", "length": 0.6, "grip": 0.18, "flip": true},
	"rod": {"file": "rod", "parts": [["fishing_rod_0", 0.0]], "kind": "rod", "length": 1.7, "grip": 0.1, "flip": true},
	"shield_iron": {"file": "shield_iron", "kind": "shield", "length": 0.62},
	"shield_wood": {"file": "shield_wood", "kind": "shield", "length": 0.6},
}

var _images_only := false


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_images_only = OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[0] == "images"
	for name in RECIPES:
		_pack(name, RECIPES[name])
	quit()


func _pack(name: String, recipe: Dictionary) -> void:
	var source: Node3D = load(SRC + String(recipe.file) + ".glb").instantiate()
	root.add_child(source)
	# Gather the wanted meshes, flattened into one holder in source space.
	var holder := Node3D.new()
	var parts: Array = recipe.get("parts", [])
	for mesh_node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		var offset := 0.0
		var wanted := parts.is_empty()
		for part in parts:
			if String(mesh_instance.name).contains(part[0]) or String(mesh_instance.get_parent().name).contains(part[0]):
				wanted = true
				offset = part[1]
		if not wanted:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mesh_instance.mesh
		for s in mesh_instance.mesh.get_surface_count():
			copy.set_surface_override_material(s, mesh_instance.get_active_material(s))
		copy.transform = mesh_instance.global_transform.translated(Vector3(0, offset, 0))
		holder.add_child(copy)
	source.queue_free()
	var points := _points(holder)
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	var frame := _frame(recipe, points, box)
	var item := Node3D.new()
	item.name = name
	item.add_child(holder)
	holder.transform = frame
	_textures(name, holder)
	if _images_only:
		item.free()
		return
	for child in holder.get_children():
		child.owner = item
	holder.owner = item
	var packed := PackedScene.new()
	packed.pack(item)
	ResourceSaver.save(packed, OUT + name + ".scn", ResourceSaver.FLAG_COMPRESS)
	print(name, ": ", FileAccess.get_file_as_bytes(OUT + name + ".scn").size() / 1024, " KB")
	item.free()


func _points(holder: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for child in holder.get_children():
		var mesh_instance := child as MeshInstance3D
		for s in mesh_instance.mesh.get_surface_count():
			for v in mesh_instance.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(mesh_instance.transform * v)
	return points


## The transform taking source space into the item frame.
func _frame(recipe: Dictionary, points: PackedVector3Array, box: AABB) -> Transform3D:
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var sizes := [box.size.x, box.size.y, box.size.z]
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return sizes[a] > sizes[b])
	var long_axis: Vector3 = axes[order[0]]
	var wide_axis: Vector3 = axes[order[1]]
	var thin_axis: Vector3 = axes[order[2]]
	var centre := box.get_center()
	if recipe.kind == "shield":
		# Face (thin axis) toward +Z; scale the disc to the wanted size.
		var k: float = recipe.length / sizes[order[0]]
		var basis := Basis(long_axis, wide_axis, thin_axis).transposed()
		return Transform3D(basis.scaled(Vector3.ONE * k), -(basis * centre) * k)
	var extent: float = sizes[order[0]]
	var lo := long_axis.dot(box.position)
	# Width of the item in a slice along its length, as a fraction 0..1.
	var width := func(from: float, to: float) -> float:
		var w := 0.0
		for p in points:
			var t := (long_axis.dot(p) - lo) / extent
			if t >= from and t <= to:
				# Radial: distance from the shaft's line, any direction.
				var off := p - centre
				w = maxf(w, (off - long_axis * long_axis.dot(off)).length())
		return w
	var grip_at_low := true
	match recipe.kind:
		"tool", "torch":
			grip_at_low = width.call(0.0, 0.2) < width.call(0.8, 1.0)
		"sword":
			# The crossguard sits a little way up from the hilt end.
			grip_at_low = width.call(0.08, 0.35) > width.call(0.65, 0.92)
		"rod":
			grip_at_low = width.call(0.0, 0.15) > width.call(0.85, 1.0)
	# Where the measured guess is wrong for a model, the recipe says so.
	if recipe.get("flip", false):
		grip_at_low = not grip_at_low
	var along := long_axis if grip_at_low else -long_axis
	# The head sticks out to the side it extends further toward.
	var head_side := wide_axis
	if recipe.kind == "tool":
		var plus := 0.0
		var minus := 0.0
		for p in points:
			var t := (long_axis.dot(p) - lo) / extent
			if (t > 0.75) == grip_at_low:
				var d := wide_axis.dot(p - centre)
				plus = maxf(plus, d)
				minus = maxf(minus, -d)
		if minus > plus:
			head_side = -wide_axis
	var third := head_side.cross(along).normalized()
	var basis := Basis(head_side, along, third).transposed()
	var k: float = float(recipe.length) / extent
	var grip_point: Vector3 = centre + long_axis * ((-0.5 + recipe.grip) * extent if grip_at_low else (0.5 - recipe.grip) * extent)
	# Centre the grip on the shaft (the handle's own middle, not the head's).
	var handle := Vector3.ZERO
	var count := 0
	for p in points:
		var t := (long_axis.dot(p) - lo) / extent
		if (t < 0.3) == grip_at_low:
			handle += p
			count += 1
	if count > 0:
		handle /= count
		var axial := long_axis * long_axis.dot(grip_point)
		grip_point = axial + (handle - long_axis * long_axis.dot(handle))
	return Transform3D(basis.scaled(Vector3.ONE * k), -(basis * grip_point) * k)


## Textures out to files (pass 1) or back in from the imported files (pass 2).
func _textures(name: String, holder: Node3D) -> void:
	var done := {}
	var dir := OUT + name + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for child in holder.get_children():
		var mesh_instance := child as MeshInstance3D
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_surface_override_material(s) as BaseMaterial3D
			if material == null:
				continue
			var copy: BaseMaterial3D = material.duplicate()
			for slot in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
				var texture: Texture2D = copy.get(slot)
				if texture == null:
					continue
				if not done.has(texture):
					var alpha := false
					var image := texture.get_image()
					if image and image.is_compressed():
						image.decompress()
					if image:
						alpha = image.detect_alpha() != Image.ALPHA_NONE
					var file := dir + "%s_%d.%s" % [slot.trim_suffix("_texture"), done.size(), "png" if alpha or slot == "normal_texture" else "jpg"]
					if _images_only and image:
						var big := maxi(image.get_width(), image.get_height())
						if big > TEX_MAX:
							var k := float(TEX_MAX) / big
							image.resize(int(image.get_width() * k), int(image.get_height() * k), Image.INTERPOLATE_LANCZOS)
						if alpha or slot == "normal_texture":
							image.save_png(ProjectSettings.globalize_path(file))
						else:
							image.convert(Image.FORMAT_RGB8)
							image.save_jpg(ProjectSettings.globalize_path(file), 0.9)
						done[texture] = texture
					else:
						done[texture] = load(file) if ResourceLoader.exists(file) else null
				copy.set(slot, done[texture])
			# Onto the mesh itself, so the original embedded images are dropped.
			mesh_instance.set_surface_override_material(s, copy)
		if not _images_only:
			var own := mesh_instance.mesh.duplicate() as ArrayMesh
			for s in own.get_surface_count():
				own.surface_set_material(s, mesh_instance.get_surface_override_material(s))
				mesh_instance.set_surface_override_material(s, null)
			mesh_instance.mesh = own
