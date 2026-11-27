extends SceneTree
## The heroine at several moments of a clip: -- out.png clip yaw t1 t2 ...
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var clip: String = args[1]
	var yaw := float(args[2])
	var times: Array = args.slice(3)
	var vp := SubViewport.new()
	vp.size = Vector2i(330 * times.size(), 560)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.44)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(sun)
	for i in times.size():
		var m: Node3D = CharacterKit.build("player")
		vp.add_child(m)
		m.position = Vector3((i - (times.size() - 1) * 0.5) * 1.0, 0, 0)
		m.rotation.y = yaw
		var anim: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		var style: Dictionary = m.get_meta("style", {})
		anim.play(style.get("clips", {}).get(clip, clip))
		anim.seek(float(times[i]), true)
		anim.pause()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	cam.position = Vector3(0, 0.8, 6)
	vp.add_child(cam)
	for f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(args[0])
	quit()
