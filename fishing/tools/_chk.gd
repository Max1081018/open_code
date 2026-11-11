extends SceneTree
func _initialize() -> void:
	for f in ["res://menu_ui.gd", "res://game.gd", "res://fp_arms.gd", "res://sfx.gd",
			"res://fp_legs.gd", "res://player.gd", "res://world_fx.gd", "res://touch_controls.gd"]:
		var sc = load(f)
		print("%-26s %s" % [f, "ok" if sc else "FAILED"])
	quit()
