extends SceneTree
## Contact sheet of the world props from four sides (+Z, +X, -Z, -X) to see
## which way each one faces (its door, its front).
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/preview_world_props.gd -- out.png [names...]

const DIR := "res://assets/models/world/"
const CELL := 256


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0]
	var names: Array = args.slice(1)
	if names.is_empty():
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var sheet := Image.create(CELL * 4, CELL * names.size(), false, Image.FORMAT_RGBA8)
	for row in names.size():
		var inst: Node3D = (load(DIR + names[row] + ".glb") as PackedScene).instantiate()
		vp.add_child(inst)
		await process_frame
		var box := AABB()
		var first := true
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var c := box.get_center()
		var r := box.size.length() * 0.5
		cam.size = r * 2.1
		for col in 4:
			var dir := Vector3(0, 0.35, 1).rotated(Vector3.UP, col * PI * 0.5).normalized()
			cam.look_at_from_position(c + dir * r * 3.0, c, Vector3.UP)
			for f in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(col * CELL, row * CELL))
		inst.queue_free()
		await process_frame
	sheet.save_png(out_path)
	quit()
