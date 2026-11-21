extends SceneTree
## Lines up the packed hand-held items (assets/models/items) in their common
## frame: grip at the red dot, shaft up (+Y), head toward +X (right).
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/preview_items.gd -- out.png

func _initialize() -> void:
	await process_frame
	var names := ["starlit", "autumn", "crystal", "jade"]
	var vp := SubViewport.new()
	vp.size = Vector2i(220 * names.size(), 420)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.33, 0.38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(sun)
	for i in names.size():
		var item: Node3D = load("res://assets/models/items/%s.scn" % names[i]).instantiate()
		item.position = Vector3(i * 1.0 - (names.size() - 1) * 0.5, -0.6, 0)
		vp.add_child(item)
		var dot := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		dot.mesh = sphere
		var red := StandardMaterial3D.new()
		red.albedo_color = Color.RED
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.no_depth_test = true
		dot.material_override = red
		dot.position = item.position
		vp.add_child(dot)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.95
	cam.position = Vector3(0, 0.25, 5)
	vp.add_child(cam)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
