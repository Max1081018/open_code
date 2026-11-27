extends TestCase
## Foes show their blows coming: a wedge on the ground during the wind-up,
## gone once the blow lands or the foe is staggered.


func test_blows_are_telegraphed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var p: Player3D = main.player
	var e: Enemy3D = main.play.spawn_enemy("zombie", p.global_position + Vector3(0, 0, -1.4))
	var seen := false
	var hp := p.health
	for i in 240:
		await tree.physics_frame
		if e._tele != null:
			seen = true
		if p.health < hp:
			break
	check(seen, "the wind-up shows a telegraph")
	check(p.health < hp, "then the blow lands")
	main.queue_free()
	await tree.process_frame
