extends SceneTree
## Renders Body3D poses into a strip, for checking the 3D characters by eye:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview_body.gd -- out.png Knight
var bodies: Array = []
var frames := 0
var out := "user://preview.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var who: String = args[1] if args.size() > 1 else "Knight"
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.62, 0.55)
	bg.size = Vector2(2340, 1080)
	root.add_child(bg)
	var setups := [["idle", 0.0, false], ["walk", 260.0, false], ["run", 600.0, false], ["swing_mine", 0.0, false], ["slash", 0.0, false], ["idle", 0.0, true]]
	for i in setups.size():
		var b := Body3D.new(who)
		b.position = Vector2(300 + i * 330, 700)
		root.add_child(b)
		bodies.append([b, setups[i]])

func _process(_delta: float) -> bool:
	frames += 1
	for pair in bodies:
		var b: Body3D = pair[0]
		var s: Array = pair[1]
		b.motion = Vector2(s[1], 0)
		b.flip_h = s[2] and frames > 20
		if frames == 22 and s[0] in ["swing_mine", "slash"]:
			b.play(s[0])
			b.anim.seek(b.anim.current_animation_length * (0.42 if s[0] == "swing_mine" else 0.35), true)
			b.speed_scale = 0.0
	if frames == 40:
		var img := root.get_texture().get_image()
		img.save_png(out)
		return true
	return false
