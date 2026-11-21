extends SceneTree
## Every KayKit character side by side, for casting:
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/preview_cast.gd -- out.png
var frames := 0
var out := "user://cast.png"
const CAST := ["player", "wren", "bram", "tobin", "mira", "aldous", "zombie", "robot", "gloam"]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.62, 0.55)
	bg.size = Vector2(2340, 1080)
	root.add_child(bg)
	for i in CAST.size():
		var b := Body3D.new(CAST[i])
		b.position = Vector2(150 + i * 250, 600)
		b.flip_h = i % 2 == 1
		root.add_child(b)
		var label := Label.new()
		label.text = CAST[i]
		label.position = Vector2(80 + i * 250, 620)
		label.add_theme_font_size_override("font_size", 26)
		root.add_child(label)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		root.get_texture().get_image().save_png(out)
		return true
	return false
