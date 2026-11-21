extends SceneTree
## Plays the shared retargeted clips on downloaded characters and films them
## from the game's side angle, to judge models before they go in:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/preview_retarget.gd -- out.png clip id id id...

const LIB := "res://assets/models/heroes/anim/humanoid.res"


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var clip: String = args[1]
	var ids: Array = args.slice(2)
	var cell := 360
	var vp := SubViewport.new()
	vp.size = Vector2i(cell * ids.size(), cell * 2)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.36, 0.42)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.48, 0.54, 0.7)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -28, 0)
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_color = Color(0.62, 0.76, 1.0)
	rim.light_energy = 0.9
	vp.add_child(rim)
	var library: AnimationLibrary = load(LIB)
	var models := []
	for i in ids.size():
		var model: Node3D = load(("res://assets/models/sf_src/%s.glb" % ids[i]) if not ids[i].begins_with("a") else ("res://assets/models/sf_src/anime/%s.glb" % ids[i])).instantiate()
		var holder := Node3D.new()
		vp.add_child(holder)
		holder.add_child(model)
		var player := AnimationPlayer.new()
		model.add_child(player)
		player.root_node = NodePath("..")
		player.add_animation_library("", library)
		for old in model.find_children("*", "AnimationPlayer", true, false):
			if old != player:
				old.stop()
		player.play(clip)
		player.seek(0.35, true)
		models.append([holder, model])
	await process_frame
	await process_frame
	for i in models.size():
		var holder: Node3D = models[i][0]
		var model: Node3D = models[i][1]
		# Height from the posed skeleton (head over feet), not the mesh
		# bounds, which can be in other units after the rest fixer.
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))).origin
		var foot_l := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("LeftFoot"))).origin
		var foot_r := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightFoot"))).origin
		var floor_y := minf(foot_l.y, foot_r.y)
		var tall := (head.y - floor_y) * 1.13 + 0.08 * (head.y - floor_y)
		var k := 1.8 / maxf(tall, 0.0001)
		holder.scale = Vector3.ONE * k
		holder.position = Vector3(i * 2.0, -(floor_y - 0.06 * (head.y - floor_y)) * k, 0)
		for m in model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).extra_cull_margin = 16000.0
		var box := AABB(Vector3.ZERO, Vector3(0, tall, 0))
		print(ids[i], " height ", snappedf(box.size.y, 0.01), " scale ", snappedf(k, 0.001))
	# Two rows: the game's side angle, then front. One camera, moved.
	vp.size = Vector2i(cell, cell)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.2
	vp.add_child(cam)
	var sheet := Image.create(cell * ids.size(), cell * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		for i in ids.size():
			var yaw := deg_to_rad(72.0 if row == 0 else 0.0)
			for j in models.size():
				(models[j][0] as Node3D).visible = j == i
			var target := Vector3(i * 2.0, 0.95, 0)
			cam.position = target + Vector3(sin(yaw), 0.15, cos(yaw)) * 8.0
			cam.look_at(target)
			for f in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var img: Image = vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(i * cell, row * cell))
	sheet.save_png(out)
	quit()
