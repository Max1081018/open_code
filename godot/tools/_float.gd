extends SceneTree
## Pose lab: -- out.png yaw "Bone:x,y,z;Bone:x,y,z|..." (degrees, local axes on top of the idle).
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var yaw := float(args[1])
	var cols: Array = String(args[2]).split("|")
	var vp := SubViewport.new()
	vp.size = Vector2i(360 * cols.size(), 600)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.33, 0.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	vp.add_child(sun)
	var models := []
	for i in cols.size():
		var m: Node3D = CharacterKit.build("player")
		vp.add_child(m)
		m.position = Vector3((i - (cols.size() - 1) * 0.5) * 1.15, 0.3, 0)
		m.rotation.y = yaw
		m.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(args[3]) if args.size() > 3 else 0.0))
		var anim: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		anim.play("ual/Idle")
		anim.seek(0.5, true)
		anim.pause()
		models.append(m)
	await process_frame
	for i in cols.size():
		var sk: Skeleton3D = models[i].find_children("*", "Skeleton3D", true, false)[0]
		for item in String(cols[i]).split(";", false):
			var kv := item.split(":")
			var b := sk.find_bone(kv[0])
			if b < 0:
				print("NO BONE ", kv[0])
				continue
			var e := kv[1].split(",")
			var q := Quaternion.from_euler(Vector3(deg_to_rad(float(e[0])), deg_to_rad(float(e[1])), deg_to_rad(float(e[2]))))
			sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * q)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0
	cam.position = Vector3(0, 1.0, 6)
	vp.add_child(cam)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(args[0])
	quit()
