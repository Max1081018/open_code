extends SceneTree
func _initialize() -> void:
	var bad := 0
	for f in ["game.gd", "zombie.gd", "zchar.gd", "fp_hands.gd", "player.gd",
			"touch_controls.gd", "ui_draw.gd", "ui_theme.gd", "status_ui.gd",
			"render_view.gd", "sfx.gd", "world_fx.gd"]:
		if load("res://" + f) == null:
			print(f, " FAILED")
			bad += 1
	print("bad=", bad)
	quit()
