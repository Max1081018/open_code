extends SceneTree
## Inspect downloaded character models: skeleton, bones, clips, size,
## and render each from the front and from the game's side angle.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/inspect_models.gd -- <folder> <out_dir>

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var folder: String = args[0] if args.size() > 0 else "res://assets/models/sf_src/"
	var out: String = args[1] if args.size() > 1 else "/tmp/inspect"
	DirAccess.make_dir_recursive_absolute(out)
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".glb"):
			continue
		var scene: PackedScene = load(folder + file)
		if scene == null:
			print(file, " FAILED TO LOAD")
			continue
		var model: Node3D = scene.instantiate()
		var skel := model.find_children("*", "Skeleton3D", true, false)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		var box := AABB()
		var first := true
		var vp := SubViewport.new()
		vp.size = Vector2i(512, 512)
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.25, 0.27, 0.3)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.6, 0.62, 0.7)
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, -30, 0)
		vp.add_child(sun)
		vp.add_child(model)
		await process_frame
		for m in meshes:
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var bones := []
		var tris := 0
		for m in meshes:
			var mesh: Mesh = (m as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
		if skel:
			var sk: Skeleton3D = skel[0]
			for i in mini(sk.get_bone_count(), 70):
				bones.append(sk.get_bone_name(i))
		var clips := []
		for p in players:
			clips.append_array((p as AnimationPlayer).get_animation_list())
		print("== ", file, " size ", box.size.snapped(Vector3.ONE * 0.01), " pos ", box.position.snapped(Vector3.ONE * 0.01),
			" tris ", tris, " skeletons ", skel.size(), " bones ", (skel[0] as Skeleton3D).get_bone_count() if skel else 0)
		print("   clips ", clips.slice(0, 20))
		print("   bones ", bones)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		var h: float = maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.1
		cam.size = h
		vp.add_child(cam)
		var centre := box.get_center()
		for view in [["front", 0.0], ["side", 72.0]]:
			var yaw: float = deg_to_rad(view[1])
			cam.position = centre + Vector3(sin(yaw), 0, cos(yaw)) * (h * 3.0)
			cam.look_at(centre)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/%s_%s.png" % [out, file.get_basename(), view[0]])
		vp.queue_free()
		await process_frame
	quit()
