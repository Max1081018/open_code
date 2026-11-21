extends SceneTree
## Renders the village cottage art from Quaternius' Medieval Village MegaKit
## (CC0): the back wall seen from inside (timber-framed plaster, a window)
## and the roof seen end-on (round tiles over a brick gable). The game shows
## houses as cutaways in side view, so these two pictures are a house: the
## wall behind the rooms, the roof on top.
##
##   xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/render_cottage.gd
##
## The kit's glTFs are not shipped: copy its glTF folder (textures beside
## the .gltf files) into assets/models/village_src first.

const SRC := "res://assets/models/village_src/"
const OUT := "res://assets/rendered/village/"
const PX_PER_M := 96.0

## name -> [pieces [file, position, rotation y degrees], view (x0, y0, x1, y1) in metres]
const SHOTS := {
	"cottage_wall": [[
		["Wall_Plaster_WoodGrid", Vector3(-3, 0, 0), 0.0],
		["Wall_Plaster_Window_Thin_Round", Vector3(-1, 0, 0), 0.0],
		["Window_Thin_Round1", Vector3(-1, 0, 0), 0.0],
		["Wall_Plaster_WoodGrid", Vector3(1, 0, 0), 0.0],
		["Wall_Plaster_Window_Thin_Round", Vector3(3, 0, 0), 0.0],
		["Window_Thin_Round1", Vector3(3, 0, 0), 0.0],
		["Wall_Plaster_Straight", Vector3(-3, 3, 0), 0.0],
		["Wall_Plaster_Window_Thin_Round", Vector3(-1, 3, 0), 0.0],
		["Window_Thin_Round1", Vector3(-1, 3, 0), 0.0],
		["Wall_Plaster_WoodGrid", Vector3(1, 3, 0), 0.0],
		["Wall_Plaster_Straight", Vector3(3, 3, 0), 0.0],
		["Corner_ExteriorWide_Wood", Vector3(-4, 0, 0), 0.0],
		["Corner_ExteriorWide_Wood", Vector3(-4, 3, 0), 0.0],
		["Corner_ExteriorWide_Wood", Vector3(4, 0, 0), 0.0],
		["Corner_ExteriorWide_Wood", Vector3(4, 3, 0), 0.0],
	], Rect2(-4.2, -0.1, 8.4, 6.3)],
	"cottage_roof": [[
		["Roof_RoundTiles_8x8", Vector3(0, 0, 0), 0.0],
		["Roof_Front_Brick8", Vector3(0, 0, 4), 0.0],
		["Prop_Chimney", Vector3(2.2, 1.6, -1), 0.0],
	], Rect2(-5.2, -1.0, 10.4, 7.2)],
	# Old brick for the ruins' back walls: exactly four modules, so the
	# strip repeats seamlessly across a hall of any width.
	"ruin_wall": [[
		["Wall_UnevenBrick_Straight", Vector3(-3, 0, 0), 0.0],
		["Wall_UnevenBrick_Window_Wide_Round", Vector3(-1, 0, 0), 0.0],
		["Wall_UnevenBrick_Door_Round", Vector3(1, 0, 0), 0.0],
		["Wall_UnevenBrick_Window_Thin_Round", Vector3(3, 0, 0), 0.0],
		["Prop_Vine2", Vector3(-2.6, 2.2, 0.15), 0.0],
		["Prop_Vine5", Vector3(2.2, 2.4, 0.15), 0.0],
	], Rect2(-4.0, 0.0, 8.0, 3.0)],
}
## Shots kept at their exact view (no trimming), for seamless repeats.
const TILING := ["ruin_wall"]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_cmdline_user_args()
	for shot in SHOTS:
		if only.is_empty() or shot in only:
			await _render(shot, SHOTS[shot][0], SHOTS[shot][1])
	quit()


func _render(shot: String, pieces: Array, view: Rect2) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(view.size.x * PX_PER_M * 2), int(view.size.y * PX_PER_M * 2))
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# The game's light: warm sun from the upper left, cool sky fill.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.8)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.light_energy = 1.5
	viewport.add_child(sun)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = view.size.y
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(view.position.x + view.size.x * 0.5, view.position.y + view.size.y * 0.5, 20)
	viewport.add_child(camera)

	for piece in pieces:
		var scene: PackedScene = load(SRC + piece[0] + ".gltf")
		var node: Node3D = scene.instantiate()
		node.position = piece[1]
		node.rotation_degrees.y = piece[2]
		viewport.add_child(node)

	if shot in ["cottage_wall", "ruin_wall"]:
		# Dusky glass behind the windows and lattices, not holes.
		var glass := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(8.0, 6.0)
		glass.mesh = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.13, 0.13, 0.17) if shot == "cottage_wall" else Color(0.05, 0.045, 0.05)
		glass.material_override = material
		glass.position = Vector3(0, 3.0, -0.12)
		viewport.add_child(glass)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.resize(int(view.size.x * PX_PER_M), int(view.size.y * PX_PER_M), Image.INTERPOLATE_LANCZOS)
	if not shot in TILING:
		image = image.get_region(image.get_used_rect())
	image.save_png(ProjectSettings.globalize_path(OUT + shot + ".png"))
	print(shot, " ", image.get_size())
	viewport.queue_free()
