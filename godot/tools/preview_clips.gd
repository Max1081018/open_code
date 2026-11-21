extends SceneTree
## Contact sheet of one character holding many clips, to inspect animation
## quality, hands and clipping:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/preview_clips.gd -- out.png player 0.4 Idle Walk Jog_Fwd ...
## (the number is the point in each clip, 0..1). Three-quarter front view, game lighting.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var who: String = args[1]
	var at := float(args[2])
	var clips: Array = args.slice(3)
	var cell := Vector2i(420, 600)
	var vp := SubViewport.new()
	vp.size = cell
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.68, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.environment.ambient_light_energy = 0.5
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.35
	vp.add_child(sun)
	var body := CharacterKit.build(who)
	vp.add_child(body)
	body.rotation_degrees.y = 25.0
	var anim: AnimationPlayer = body.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var grip := HumanoidGrip.grip(skeleton, body.get_child(0), "RightHand", "RightIndexProximal", "RightLittleProximal", "RightMiddleProximal")
	var sword := Body3D.item_model("iron_sword")
	if sword:
		grip.add_child(sword)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 0.9, 4.4)
	vp.add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0))
	var sheet := Image.create(cell.x * clips.size(), cell.y + 30, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in clips.size():
		var c: String = clips[i]
		if not anim.has_animation(c):
			print("no clip ", c)
			continue
		anim.play(c)
		anim.seek(anim.get_animation(c).length * at, true)
		anim.pause()
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(i * cell.x, 0))
	sheet.save_png(out)
	print("sheet ", clips)
	quit()
