extends SceneTree
## Renders dialogue portraits from the 3D characters: the head and
## shoulders, turned a little toward the viewer, on a transparent ground.
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/render_portraits.gd
const WHO := ["wren", "bram", "mira", "tobin", "aldous", "player"]
var bodies := []
var frames := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/portraits"))
	for id in WHO:
		var b := Body3D.new(id)
		root.add_child(b)
		bodies.append([id, b])

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		for pair in bodies:
			var b: Body3D = pair[1]
			b.set_process(false)
			b.model.rotation_degrees.y = 28.0
			b.camera.size = 1.4
			b.camera.position = Vector3(0, 1.55, 10)
			b.camera.rotation_degrees = Vector3(-2, 0, 0)
	if frames == 8:
		for pair in bodies:
			var b: Body3D = pair[1]
			var image: Image = b.viewport.get_texture().get_image()
			image.save_png("res://assets/portraits/%s.png" % pair[0])
			print("portrait ", pair[0])
		return true
	return false
