extends TestCase
## Relics do what they say: worn in three slots from the backpack, each
## changes the game (less harm, faster feet, a second jump, burning blows,
## luck, stamina, swimming), they come off if lost, and they are saved.


func test_relics_take_effect() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var play: Play3D = main.play
	var p: Player3D = main.player
	check(not play.equip_relic("relic_bulwark"), "a relic not carried cannot be worn")
	for r in ["relic_bulwark", "relic_swiftroot", "relic_featherbone", "relic_ember_heart"]:
		play.inventory.add(r, 1)
	check(play.equip_relic("relic_bulwark"), "the Bulwark Sigil is worn")
	check_eq(p.damage_reduction, 0.25, "it turns aside a quarter of harm")
	p._grace = 0.0
	p.health = p.max_health
	p.hurt(40.0, p.global_position + Vector3(0, 0, -1))
	var taken := p.max_health - p.health
	check(taken >= 26.0 and taken <= 34.0, "a 40 blow costs about 30 (%.0f)" % taken)
	check(play.equip_relic("relic_swiftroot"), "Swiftroot is worn")
	check_eq(p.move_mult, 1.12, "she is faster")
	check(play.equip_relic("relic_featherbone"), "Featherbone is worn")
	check_eq(p.air_jumps, 1, "she gains an air jump")
	check(not play.equip_relic("relic_ember_heart"), "only three relics at once")
	play.unequip_relic("relic_swiftroot")
	check_eq(p.move_mult, 1.0, "taking one off ends its effect")
	check(play.equip_relic("relic_ember_heart"), "a freed slot takes another")
	var stats := play.attacker_stats()
	check(absf(float(stats.buff) - 1.15) < 0.001, "Ember Heart adds to her power")
	var copy := play.relics.duplicate()
	check(copy.size() == 3, "three worn")
	# Lost from the bag, a relic is no longer worn.
	play.inventory.remove("relic_featherbone", 1)
	check(not play.wearing("relic_featherbone") and p.air_jumps == 0, "a relic dropped is no longer worn")
	var data := Save3D.capture(main)
	check(data.has("relics") and (data.relics as Array).has("relic_bulwark"), "worn relics are saved")
	main.queue_free()
	await tree.process_frame
