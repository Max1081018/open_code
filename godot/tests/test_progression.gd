extends TestCase
## Levels and the Moonblade's arts: XP raises levels, levels open arts in
## order, and a level-up makes her stronger.


func test_levels_and_unlocks() -> void:
	var p := Progression.new()
	check_eq(p.level, 1, "she starts at level 1")
	check(not p.unlocked("crescent") and not p.unlocked("comet") and not p.unlocked("starfall"), "no arts at first")
	var ups: Array = []
	p.leveled.connect(func(lv, art): ups.append([lv, art]))
	p.gain(Progression.need(1))
	check_eq(p.level, 2, "enough XP: level 2")
	check(p.unlocked("crescent") and not p.unlocked("comet"), "level 2 opens the Crescent Wave only")
	check_eq(ups.back(), [2, "crescent"], "the level-up names the new art")
	p.gain(Progression.need(2) + Progression.need(3) + Progression.need(4))
	check_eq(p.level, 5, "XP carries over several levels")
	check(p.unlocked("comet") and p.unlocked("starfall"), "level 5 opens every art")
	check(p.damage_bonus() > 1.2, "the blade hits harder")
	check(Progression.max_health_at(5) > Progression.max_health_at(1), "more health")
	var q := Progression.new()
	q.from_dict(p.to_dict())
	check_eq(q.level, 5, "level survives a save")


func test_arts_sealed_in_game() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	check_eq(main.play.held_id(), "moonblade", "she starts with her Moonblade")
	main.play.energy = Play3D.BURST_COST
	main.play.use_skill()
	check_eq(main.play.skill_cooldown, 0.0, "Arcane Comet is sealed at level 1")
	main.play.use_burst()
	check_eq(main.play.energy, Play3D.BURST_COST, "Violet Starfall is sealed at level 1")
	main.play.prog.gain(Progression.need(1) + Progression.need(2) + Progression.need(3) + Progression.need(4))
	check_eq(main.player.max_health, Progression.max_health_at(5), "levelling raises max HP")
	main.play.use_skill()
	check(main.play.skill_cooldown > 0.0, "at level 5 the comet flies")
	main.queue_free()
	await tree.process_frame
