extends TestCase
## Foes think: they keep their own post, need a clear line to see her, hunt
## where she was last seen, go home, and break away when badly hurt. Island
## guardians fight in phases with telegraphed moves she can avoid (jump the
## shockwave), wake in their arenas and stay beaten. The world's secrets:
## discovery, starlit chests, rune shrines in order, all saved.


func _main() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	main.play._spawn_timer = 9999.0
	await tree.process_frame
	return main


func test_senses_search_and_retreat() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _main()
	var p: Player3D = main.player
	var spot: Vector3 = p.global_position + Vector3(0, 0, -11)
	# A wall between them: it does not see her.
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 8, 1)
	cs.shape = box
	wall.add_child(cs)
	wall.collision_layer = 1
	main.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 2, -5.5)
	for i in 3:
		await tree.physics_frame
	var foe: Enemy3D = main.play.spawn_enemy("zombie", spot)
	await tree.process_frame
	check(foe._home.distance_to(spot) < 1.0, "a foe's post is where it was set down")
	foe._sense = 0.0
	await tree.physics_frame
	await tree.physics_frame
	check(not foe._aggro, "behind a wall it does not see her")
	wall.queue_free()
	await tree.physics_frame
	foe._sense = 0.0
	await tree.physics_frame
	await tree.physics_frame
	check(foe._aggro, "in the open it does")
	check_eq(foe.state, "chase", "and gives chase")
	# She vanishes: it searches where she was, then goes home.
	p.global_position += Vector3(120, 0, 0)
	p.global_position.y = main.world.height_at(p.global_position.x, p.global_position.z) + 0.3
	for i in 6:
		await tree.physics_frame
	check(not foe._aggro and foe._search > 0.0, "losing her, it searches")
	check_eq(foe.state, "search", "its state says so")
	foe.global_position = foe._home + Vector3(9, 0.5, 0)
	foe._search = 0.001
	await tree.physics_frame
	await tree.physics_frame
	check(foe._returning, "then heads back to its post")
	# Badly hurt, a skirmisher breaks away for a moment.
	p.global_position = spot + Vector3(0, 0, 6)
	var runner: Enemy3D = main.play.spawn_enemy("thornling", spot + Vector3(3, 0, 0))
	await tree.process_frame
	runner._aggro = true
	runner.health = runner.max_health * 0.2
	await tree.physics_frame
	await tree.physics_frame
	check_eq(runner.state, "retreat", "a badly hurt thornling retreats")
	main.queue_free()
	await tree.process_frame


func test_guardians() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _main()
	var p: Player3D = main.player
	var gb: IslandBosses = main.bosses
	check(gb != null, "the island guardians exist")
	for id in ["jungle", "sky", "coast"]:
		check(gb.arenas.has(id), "%s has an arena" % id)
	var boss: Enemy3D = gb.wake("jungle")
	await tree.process_frame
	check(boss.is_boss and boss.spec.has("patterns"), "the Thornmother is a guardian with moves")
	# Phases.
	boss.take_hit(boss.max_health * 0.45, boss.global_position, false)
	check_eq(boss.phase, 2, "at 55% health it enters phase two")
	boss.take_hit(boss.max_health * 0.3, boss.global_position, false)
	check_eq(boss.phase, 3, "below 30%, phase three")
	# The shockwave: standing in it hurts, jumping it does not.
	p.global_position = boss.global_position + Vector3(3, 0, 0)
	p._grace = 0.0
	p.health = p.max_health
	boss._move_ring(Color.GREEN)
	await tree.create_timer(1.05).timeout
	check(p.health < p.max_health, "the shockwave hits her on the ground")
	p.health = p.max_health
	p._grace = 0.0
	boss._move_ring(Color.GREEN)
	await tree.create_timer(0.85).timeout
	p.global_position.y += 2.0
	p.velocity = Vector3.ZERO
	await tree.create_timer(0.2).timeout
	check_eq(p.health, p.max_health, "jumping clears it")
	# Beaten, and it stays beaten.
	boss.take_hit(99999.0, boss.global_position, true)
	await tree.process_frame
	check(gb.defeated.has("jungle"), "the jungle's guardian is recorded as beaten")
	var copy := IslandBosses.new()
	copy.from_dict(gb.to_dict())
	check(copy.defeated.has("jungle"), "and saved")
	copy.free()
	check(gb.pending("jungle").is_empty() and not gb.pending("coast").is_empty(), "the tracker points only to guardians still waiting")
	main.queue_free()
	await tree.process_frame


func test_secrets() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _main()
	var sec: Secrets = main.secrets
	check(sec != null, "the world has secrets")
	var lm: Dictionary = main.realms.landmarks
	check(lm.has("world_tree"), "the World Tree is a landmark")
	main.player.global_position = lm.world_tree.pos + Vector3(4, 2, 0)
	sec._check = 0.0
	await tree.process_frame
	await tree.process_frame
	check(sec.discovered.has("world_tree"), "coming near discovers it")
	check(sec._chests.size() >= 6, "starlit chests are hidden (%d)" % sec._chests.size())
	var c: Array = sec._chests[0]
	var before: int = main.play.inventory.count(String(c[2][0][0]))
	sec._open_chest(c)
	check(sec.opened.has(c[0]), "a chest opens once")
	await tree.create_timer(0.3).timeout
	check(tree.get_nodes_in_group("pickups").size() > 0 or main.play.inventory.count(String(c[2][0][0])) > before, "and spills its treasure")
	# A rune shrine: the stones in the order of their marks.
	check(sec._shrines.size() >= 1, "rune shrines stand")
	var sh: Array = sec._shrines[0]
	var by_place := {}
	for pillar: Node3D in sh[2]:
		by_place[int(pillar.get_meta("place"))] = pillar
	sec.strike_near((by_place[2] as Node3D).global_position)
	check_eq(int(sh[3]), 0, "a stone out of order puts the runes out")
	for k in [1, 2, 3]:
		sec.strike_near((by_place[k] as Node3D).global_position)
	check(sec.solved.has(sh[0]), "one, two, three: the shrine wakes")
	var copy := Secrets.new()
	copy.from_dict(sec.to_dict())
	check(copy.discovered.has("world_tree") and copy.opened.has(c[0]) and copy.solved.has(sh[0]), "secrets are saved")
	copy.free()
	main.queue_free()
	await tree.process_frame


func test_island_creatures() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _main()
	var p: Player3D = main.player
	var play: Play3D = main.play
	p.hold("moonblade")
	# An ambusher waits unseen, then springs when she is close.
	var lurk: Enemy3D = play.spawn_enemy("vine_stalker", p.global_position + Vector3(0, 0, -12))
	await tree.physics_frame
	await tree.physics_frame
	check(not lurk.model.visible and not lurk._aggro, "a vine stalker lies hidden")
	p.global_position = lurk.global_position + Vector3(0, 0, 4)
	await tree.physics_frame
	await tree.physics_frame
	check(lurk._emerged and lurk.model.visible and lurk._aggro, "close by, it springs out")
	# A shield turns aside light blows from the front, and the number shown is
	# still exactly the health taken.
	var knight: Enemy3D = play.spawn_enemy("coral_knight", p.global_position + Vector3(4, 0, 0))
	knight.max_health = 5000.0
	knight.health = 5000.0
	await tree.process_frame
	var front := knight.global_position + knight.model.global_transform.basis.z * 2.0
	var back := knight.global_position - knight.model.global_transform.basis.z * 2.0
	var h0 := knight.health
	var d_front := play.hit(knight, 1.0, front, false, "arcane")
	check_eq(h0 - knight.health, float(d_front), "a guarded hit takes what it shows")
	var h1 := knight.health
	var d_back := play.hit(knight, 1.0, back, false, "arcane")
	check_eq(h1 - knight.health, float(d_back), "a hit from behind takes what it shows")
	# Compare the guard itself with the crit roll and variance pinned: a random
	# crit on the guarded blow (or rounding at single digits) must not decide it.
	var atk := play.attacker_stats()
	var g_front: int = DamageCalc.compute(atk, knight.combat_stats(front, false), 4.0, "arcane", 0.99, 0.5).amount
	var g_back: int = DamageCalc.compute(atk, knight.combat_stats(back, false), 4.0, "arcane", 0.99, 0.5).amount
	var g_heavy: int = DamageCalc.compute(atk, knight.combat_stats(front, true), 4.0, "arcane", 0.99, 0.5).amount
	check(g_back > g_front * 2, "from behind it is far more telling (%d vs %d)" % [g_back, g_front])
	check(g_heavy > g_front * 2, "a heavy blow breaks through the guard (%d vs %d)" % [g_heavy, g_front])
	var h2 := knight.health
	var d_heavy := play.hit(knight, 1.0, front, true, "arcane")
	check_eq(h2 - knight.health, float(d_heavy), "a heavy blow takes what it shows")
	# Elites.
	var plain: Enemy3D = play.spawn_enemy("thornling", p.global_position + Vector3(-6, 0, 0))
	var elite: Enemy3D = play.spawn_enemy("thornling", p.global_position + Vector3(-8, 0, 0), true)
	await tree.process_frame
	check(elite.elite and elite.max_health > plain.max_health * 2.0, "an elite is far tougher")
	check(String(elite.spec.name).begins_with("Elite"), "and named so")
	main.queue_free()
	await tree.process_frame
