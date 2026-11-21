extends SceneTree
## The CharacterKit cast side by side, idling, for art direction:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview_kit.gd -- out.png [yaw] [clip]
var frames := 0
var out := "user://kit.png"
const CAST := ["player", "wren", "bram", "mira", "tobin", "aldous", "zombie", "robot", "shade", "warden", "gloam"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var yaw := float(args[1]) if args.size() > 1 else 35.0
	var clip: String = args[2] if args.size() > 2 else "Idle"
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_color = Color(1.0, 0.88, 0.7)
	key.light_energy = 1.3
	world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 150, 0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 0.7
	world.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.0
	cam.position = Vector3(CAST.size() * 0.45, 1.0, 12)
	world.add_child(cam)
	for i in CAST.size():
		var c := CharacterKit.build(CAST[i])
		c.position = Vector3(i * 0.9, 0, 0)
		c.rotation_degrees.y = yaw
		world.add_child(c)
		var ap: AnimationPlayer = c.get_node("AnimationPlayer")
		ap.play(clip if ap.has_animation(clip) else "Idle")
		ap.seek(0.4 + i * 0.13, true)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 20:
		root.get_texture().get_image().save_png(out)
		return true
	return false
