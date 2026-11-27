extends TestCase
## The heroine in the real 3D scene: her AnimationTree drives the gait, and
## falling in battle brings her back at the town gate, whole and protected.


func test_gait_and_revival() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var p: Player3D = main.player
	check(p.tree != null and p.tree.active, "an AnimationTree drives her")
	check(not p.anim.active, "the bare AnimationPlayer is idle")
	p._gait(4.6)
	check_eq(float(p.tree.get("parameters/gait/blend_position")), 4.6, "the gait follows her speed")
	var rate := float(p.tree.get("parameters/gait_rate/scale"))
	check(absf(rate - 4.6 / 5.4) < 0.05, "a jog at 4.6 m/s plays slower than its natural 5.4 (no sliding)")

	p.hurt(999.0, p.global_position + Vector3(0, 0, -1))
	check(p.dead, "a killing blow fells her")
	var hp := p.health
	p.hurt(10.0, p.global_position)
	check_eq(p.health, hp, "the fallen take no more harm")
	for i in 60:
		await tree.create_timer(0.1).timeout
		if not p.dead:
			break
	check(not p.dead, "she is revived")
	check_eq(p.health, p.max_health, "with full health")
	check(Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(10, 14)) < 2.0, "at the town gate")
	p.hurt(10.0, p.global_position)
	check_eq(p.health, p.max_health, "and briefly untouchable")
	main.queue_free()
	await tree.process_frame
