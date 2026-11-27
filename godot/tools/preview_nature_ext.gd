extends SceneTree
## Contact sheet of the split nature pieces (assets/models/nature_ext), each
## fitted to its cell and labelled:  -- out.png prefix
func _initialize():
	await process_frame
	var args := OS.get_cmdline_user_args()
	var names: Array = []
	for f in DirAccess.get_files_at("res://assets/models/nature_ext/"):
		if f.ends_with(".res") and f.begins_with(args[1]):
			names.append(f.get_basename())
	names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	var cols := 8
	var cell := 220
	var rows := int(ceil(names.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	var vp := SubViewport.new()
	vp.size = Vector2i(cell, cell)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	for i in names.size():
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://assets/models/nature_ext/%s.res" % names[i])
		vp.add_child(mi)
		var box: AABB = mi.get_aabb()
		var c := box.get_center()
		cam.size = maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.15
		cam.look_at_from_position(c + Vector3(0.6, 0.35, 1).normalized() * box.size.length() * 2.0, c)
		for f in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		mi.queue_free()
		await process_frame
	sheet.save_png(args[0])
	print(names)
	quit()
