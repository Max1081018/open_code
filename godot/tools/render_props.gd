extends SceneTree
## Render Kenney 3D props to 2D sprites in the game's style.
##
##   xvfb-run godot --path godot --rendering-driver opengl3 -s res://tools/render_props.gd
##
## The 2D packs have no chest, workbench, anvil or lantern. The Survival and
## Graveyard kits do, in the same flat-shaded style as the Voxel item
## icons (which are themselves renders of Kenney models). Rendering them
## here, with one camera angle and one light rig for every prop, keeps
## the set consistent with each other and with the items.

const SOURCES := ["res://assets/models/survival", "res://assets/models/graveyard"]
const OUTPUT := "res://assets/rendered/"
const SIZE := 512
const MAX_OUTPUT := 160


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))

	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.80, 0.92)
	environment.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	viewport.add_child(world_env)

	# Key light from the upper left, matching the 2D art's lighting.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_energy = 1.25
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.35
	viewport.add_child(fill)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)

	var rendered := 0
	for source in SOURCES:
		var dir := DirAccess.open(source)
		for file in dir.get_files():
			# Each model is listed twice, as itself and as its .import.
			if not file.ends_with(".glb"):
				continue
			var name := file
			var scene: PackedScene = load(source + "/" + name)
			if scene == null:
				printerr("could not load ", name)
				continue
			var model := scene.instantiate()
			viewport.add_child(model)

			var bounds := _bounds(model)
			var centre := bounds.get_center()
			var extent := bounds.size.length()
			# A shallow three-quarter view: mostly front-on, as a side-view
			# world needs, with enough top and side to read as solid.
			var direction := Vector3(0.42, 0.38, 1.0).normalized()
			camera.size = extent * 1.05
			camera.position = centre + direction * extent * 3.0
			camera.look_at(centre, Vector3.UP)
			camera.near = 0.01
			camera.far = extent * 8.0

			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw

			var image := viewport.get_texture().get_image()
			image = _trimmed(image)
			var longest: int = max(image.get_width(), image.get_height())
			if longest > MAX_OUTPUT:
				var scale := float(MAX_OUTPUT) / longest
				image.resize(int(image.get_width() * scale), int(image.get_height() * scale),
					Image.INTERPOLATE_LANCZOS)
			image.save_png(ProjectSettings.globalize_path(OUTPUT + name.get_basename() + ".png"))
			rendered += 1
			model.queue_free()
			await process_frame

	print("rendered %d props" % rendered)
	quit()


func _bounds(node: Node) -> AABB:
	var total := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child
		var box := mesh.global_transform * mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total


func _trimmed(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0:
		return image
	used = used.grow(4).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(used)
