extends SceneTree
## Renders inventory icons from the items' real 3D models (assets/icons3d/<id>.png):
## laid diagonally, warm key light and cool rim, transparent background,
## tier tints on the metal. Items without a 3D form keep their drawn icon.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/render_icons.gd

const OUT := "res://assets/icons3d/"
const SIZE := 256
const EXTRA := []  ## resources keep their drawn icons


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ids: Array = Body3D.ITEM_MODELS.keys() + EXTRA
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE * 2, SIZE * 2)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.8)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.6
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_color = Color(0.6, 0.78, 1.0)
	rim.light_energy = 1.2
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	for id in ids:
		var item: Node3D = Body3D.item_model(id)
		if item == null:
			var p := Pickup3D.new()
			p.setup(id, 1, null, Vector3.ZERO)
			p.set_physics_process(false)
			item = p
		var holder := Node3D.new()
		vp.add_child(holder)
		holder.add_child(item)
		# Diagonal, head up and to the right, turned a little toward the light.
		if not id.ends_with("shield") and not (id in EXTRA):
			holder.rotation = Vector3(deg_to_rad(10), deg_to_rad(-25), deg_to_rad(-42))
		else:
			holder.rotation = Vector3(deg_to_rad(25), deg_to_rad(-30), 0)
		await process_frame
		var box := AABB()
		var first := true
		for m in holder.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		cam.size = maxf(box.size.x, box.size.y) * 1.12
		cam.position = box.get_center() + Vector3(0, 0, 10)
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := vp.get_texture().get_image()
		image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		image.save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
		holder.queue_free()
		await process_frame
	print("icons: ", ids.size())
	quit()
