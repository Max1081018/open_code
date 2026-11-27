extends SceneTree
## Renders ArchKit buildings side by side:  -- out.png
func _initialize():
	await process_frame
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.72, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.76, 0.9)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 0.66, 0.38)
	ground.material_override = gm
	vp.add_child(ground)
	var items := [
		[ArchKit.house(8, 7, 2, "cobalt", {"seed": 1}), Vector3(-26, 0, 0)],
		[ArchKit.house(7, 6, 2, "teal", {"seed": 2, "roof_style": "gable", "tower": true}), Vector3(-13, 0, 0)],
		[ArchKit.tower(3.0, 14.0, "violet"), Vector3(0, 0, -2)],
		[ArchKit.house(10, 7, 3, "rose", {"seed": 3, "tower": true}), Vector3(14, 0, 0)],
		[ArchKit.star_fountain(), Vector3(27, 0, 4)],
		[ArchKit.gate(5.0), Vector3(0, 0, 14)],
	]
	for it in items:
		var mi := MeshInstance3D.new()
		mi.mesh = it[0]
		mi.position = it[1]
		vp.add_child(mi)
	var cr := MeshInstance3D.new()
	cr.mesh = ArchKit.star_crystal()
	cr.position = Vector3(27, 6.4, 4)
	vp.add_child(cr)
	var cam := Camera3D.new()
	cam.fov = 50
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(4, 13, 40), Vector3(1, 5, 0))
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
