extends TestCase
## Every island guardian, fought through: it wakes in its arena (named, the
## bar up), every move of every phase runs without error, it changes phase
## as it is hurt, and once beaten it is recorded and saved and does not wake
## again. (test_enemies covers the Thornmother's shockwave in detail.)


func test_every_guardian() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	main.play._spawn_timer = 9999.0
	var gb: IslandBosses = main.bosses
	var p: Player3D = main.player
	for id in ["jungle", "sky", "coast"]:
		var arena: Vector3 = gb.arenas[id]
		main.world.warm(arena)
		p.global_position = arena + Vector3(0, 2, 6)
		for i in 4:
			await tree.physics_frame
		var boss: Enemy3D = gb.wake(id)
		await tree.process_frame
		await tree.process_frame
		check(boss != null and boss.is_boss, "%s: the guardian wakes" % id)
		check(main.hud._boss == boss, "%s: its bar is up" % id)
		check(main.cam.focus == boss, "%s: the camera keeps it in frame" % id)
		# Every move it knows, in every phase.
		var moves := {}
		for phase_moves in boss.spec.patterns:
			for m in phase_moves:
				moves[m] = true
		p.max_health = 99999.0
		for m in moves:
			p.health = p.max_health
			p._grace = 0.0
			var c: Color = boss.spec.element
			match String(m):
				"lines": boss._move_lines(p, c)
				"ring": boss._move_ring(c)
				"rain": boss._move_rain(p, c)
				"dive": boss._move_dive(p, c)
				"volley":
					for k in 5:
						boss._cast_bolt(p, c, (k - 2) * 0.22)
				_:
					# melee, charge, summon: through the move picker itself.
					boss.spec = boss.spec.duplicate(true)
					boss.spec.patterns = [[m], [m], [m]]
					boss._boss_move(p, 2.0 if m == "melee" else 9.0)
			await tree.create_timer(1.4).timeout
			check(not boss.dead, "%s: survives using %s" % [id, m])
		# Phases as it is hurt.
		boss.take_hit(boss.max_health * 0.46, boss.global_position, false)
		check(boss.phase == 2, "%s: phase two below 55%%" % id)
		boss.take_hit(boss.max_health * 0.3, boss.global_position, false)
		check(boss.phase == 3, "%s: phase three below 30%%" % id)
		# Beaten, recorded, saved, and it stays beaten.
		boss.take_hit(999999.0, boss.global_position, true)
		await tree.process_frame
		await tree.process_frame
		check(gb.defeated.has(id), "%s: recorded as beaten" % id)
		check(main.hud._boss == null or main.hud._boss == boss and boss.dead, "%s: its bar goes" % id)
		var saved: Dictionary = Save3D.capture(main)
		check(id in (saved.get("guardians", {}) as Dictionary).get("defeated", []), "%s: the defeat is saved" % id)
		gb._check = 0.0
		await tree.create_timer(0.5).timeout
		check(not gb._live.has(id), "%s: it does not wake again" % id)
		for e in tree.get_nodes_in_group("enemies"):
			e.queue_free()
		await tree.process_frame
	main.queue_free()
	await tree.process_frame
