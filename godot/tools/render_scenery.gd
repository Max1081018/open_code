extends SceneTree
## Renders downloaded scenery models (assets/models/sf_src/env, not shipped)
## to sprites for the 2.5D world (assets/rendered/scenery3d/<name>.png):
## framed by their true bounds, lit like the game's art direction (a warm
## golden key from the upper left, cool blue fill and rim), filmed from a
## slight three-quarter angle so buildings show depth.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/render_scenery.gd [-- name ...]

const SRC := "res://assets/models/sf_src/env/"
const OUT := "res://assets/rendered/scenery3d/"
## name -> [yaw degrees, pitch degrees, output height px]
const SHOTS := {
	"castle": [-28.0, -8.0, 900],
	"house_generic": [-30.0, -6.0, 640],
	"house_tall": [-30.0, -6.0, 700],
	"house_timber": [-30.0, -6.0, 620],
	"tavern": [-30.0, -6.0, 640],
	"waterfall": [0.0, -6.0, 700],
	"lamp": [-25.0, -4.0, 400],
	"fence": [-15.0, -6.0, 220],
	"abbey": [-20.0, -6.0, 640],
	"archway": [-20.0, -5.0, 560],
	"bridge": [0.0, -5.0, 420],
}


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_cmdline_user_args()
	for name in SHOTS:
		if only.is_empty() or name in only:
			await _render(name, SHOTS[name])
	quit()


func _render(name: String, shot: Array) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 1600)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.58, 0.78)
	env.environment.ambient_light_energy = 0.75
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -40, 0)
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 1.6
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 0.7
	vp.add_child(rim)
	var model: Node3D = load(SRC + name + ".glb").instantiate()
	vp.add_child(model)
	await process_frame
	var box := AABB()
	var first := true
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var radius := box.size.length() * 0.5
	cam.size = radius * 2.1
	cam.near = 0.01
	cam.far = radius * 20.0
	var centre := box.get_center()
	var yaw := deg_to_rad(shot[0])
	var pitch := deg_to_rad(shot[1])
	cam.position = centre + Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * radius * 6.0
	vp.add_child(cam)
	cam.look_at(centre)
	key.directional_shadow_max_distance = radius * 12.0
	for f in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	var used := image.get_used_rect()
	image = image.get_region(used)
	var height: int = shot[2]
	if image.get_height() > 0:
		image.resize(maxi(1, int(image.get_width() * float(height) / image.get_height())), height, Image.INTERPOLATE_LANCZOS)
	image.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print(name, " ", image.get_size(), " box ", box.size.snapped(Vector3.ONE * 0.01))
	vp.queue_free()
	await process_frame
