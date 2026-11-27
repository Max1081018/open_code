extends TestCase
## The touch controls: jump is exactly as large as attack and sits apart from
## it in the thumb's corner; no two controls overlap; every control lies on
## screen; a tap on each reaches the game; and the player's button-size,
## opacity and camera-sensitivity settings take effect.


func test_layout_is_clear_and_equal() -> void:
	check_eq(Hud3D.BUTTON_R.jump, Hud3D.BUTTON_R.attack, "jump is the same size as attack")
	var keys: Array = Hud3D.SKILL_POS.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: String = keys[i]
			var b: String = keys[j]
			var gap: float = (Hud3D.SKILL_POS[a] as Vector2).distance_to(Hud3D.SKILL_POS[b]) - Hud3D.BUTTON_R[a] - Hud3D.BUTTON_R[b]
			check(gap >= 12.0, "%s and %s keep apart (%.0f px)" % [a, b, gap])
	var ja: float = (Hud3D.SKILL_POS.jump as Vector2).distance_to(Hud3D.SKILL_POS.attack)
	check(ja - Hud3D.BUTTON_R.jump - Hud3D.BUTTON_R.attack >= 30.0, "jump and attack are not cramped")
	# On screen at 16:9 and on a tall phone at the largest button size.
	for screen in [Vector2(1920, 1080), Vector2(2400, 1080)]:
		for k in keys:
			var c: Vector2 = screen + Hud3D.SKILL_POS[k] * 1.4
			var r: float = Hud3D.BUTTON_R[k] * 1.4
			check(c.x - r >= 0.0 and c.x + r <= screen.x and c.y - r >= 0.0 and c.y + r <= screen.y, "%s fits on a %dx%d screen" % [k, screen.x, screen.y])


func test_taps_and_settings() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var hud: Hud3D = main.hud
	var screen := hud.root.get_viewport_rect().size
	var old_scale := Settings.control_scale
	var old_opacity := Settings.control_opacity
	var old_sens := Settings.look_sensitivity
	for cs in [1.0, 1.3]:
		Settings.control_scale = cs
		for k in ["jump", "attack", "dash"]:
			main.input.touch_buttons.clear()
			var tap := InputEventScreenTouch.new()
			tap.pressed = true
			tap.position = screen + Hud3D.SKILL_POS[k] * cs + Vector2(Hud3D.BUTTON_R[k] * cs * 0.7, 0)
			hud._input(tap)
			check(main.input.touch_buttons.has(k), "a tap near the edge of %s reaches it at size %.1f" % [k, cs])
	Settings.control_opacity = 0.5
	await tree.process_frame
	check_eq(hud._skills.scale, Vector2.ONE * 1.3, "button size scales the controls")
	check(absf(hud._skills.modulate.a - 0.5) < 0.01, "button opacity fades them")
	# Camera sensitivity scales touch look.
	Settings.look_sensitivity = 2.0
	main.input.touch_look = Vector2.ZERO
	hud._look_touch = 7
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.relative = Vector2(10, 0)
	hud._input(drag)
	check(absf(main.input.touch_look.x - 10 * 0.005 * 2.0) < 1e-5, "camera sensitivity scales touch look")
	Settings.control_scale = old_scale
	Settings.control_opacity = old_opacity
	Settings.look_sensitivity = old_sens
	main.queue_free()
	await tree.process_frame
