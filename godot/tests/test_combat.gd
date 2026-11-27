extends TestCase
## Combat maths and arts: one damage formula (armour, resistance, crits,
## Mark, guard; never NaN, negative or infinite), the number shown is the
## health taken, one swing cuts each foe once, arts respect cooldowns and
## unlock levels, Blade Orbit cuts a foe at most every 0.45 s, and skill
## points buy ranks that raise damage and survive a save.


func test_formula() -> void:
	var her := {"weapon": 20.0, "level": 1, "crit_chance": 0.1, "crit_damage": 1.6}
	check_eq(int(DamageCalc.compute(her, {}, 1.0, "", 1.0, 0.5).amount), 20, "a plain blow is the weapon's power")
	check_eq(int(DamageCalc.compute(her, {"defense": 100.0}, 1.0, "", 1.0, 0.5).amount), 10, "100 armour halves it")
	check_eq(int(DamageCalc.compute(her, {"resist": {"arcane": 0.3}}, 1.0, "arcane", 1.0, 0.5).amount), 14, "30% resistance")
	check_eq(int(DamageCalc.compute(her, {"resist": {"arcane": -0.2}}, 1.0, "arcane", 1.0, 0.5).amount), 24, "a weakness")
	var crit := DamageCalc.compute(her, {}, 1.0, "", 0.0, 0.5)
	check(crit.crit and int(crit.amount) == 32, "a critical is x1.6")
	check_eq(int(DamageCalc.compute(her, {"vulnerable": 0.2}, 1.0, "", 1.0, 0.5).amount), 24, "Mark: +20%")
	check_eq(int(DamageCalc.compute(her, {"reduction": 0.8}, 1.0, "", 1.0, 0.5).amount), 4, "a guard of 80%")
	check_eq(int(DamageCalc.compute(her, {"reduction": 5.0}, 1.0, "", 1.0, 0.5).amount), 2, "guard caps at 90%")
	var lv5 := DamageCalc.power({"weapon": 20.0, "level": 5})
	check(lv5 > 20.0 * 1.3 and lv5 < 20.0 * 1.7, "levels raise her power (%.1f at Lv 5)" % lv5)
	# Nonsense never escapes.
	var bad := DamageCalc.compute({"weapon": NAN, "level": -3, "buff": INF}, {"defense": -50.0, "vulnerable": NAN}, NAN, "x", 0.5, 0.5)
	check(int(bad.amount) >= 0 and int(bad.amount) <= DamageCalc.MAX_HIT, "NaN and INF inputs give a sane number")
	check_eq(int(DamageCalc.compute(her, {}, -2.0, "", 1.0, 0.5).amount), 0, "a negative multiplier deals nothing, never heals")
	check(int(DamageCalc.compute({"weapon": 1e9, "level": 20, "buff": 1e9}, {}, 1e9, "", 1.0, 1.0).amount) == DamageCalc.MAX_HIT, "damage is capped")
	check_eq(DamageCalc.incoming(10.0, 0.0, 0.0, 0.5), 10, "a foe's blow on bare skin")


func test_hits_arts_and_ranks() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var play: Play3D = main.play
	var p: Player3D = main.player
	p.hold("moonblade")
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await tree.process_frame
	var fwd: Vector3 = p.model.global_transform.basis.z
	var foe: Enemy3D = play.spawn_enemy("zombie", p.global_position + fwd * 1.5)
	foe.max_health = 5000.0
	foe.health = 5000.0
	await tree.process_frame
	# The number shown is the health taken.
	var before := foe.health
	var dealt := play.hit(foe, 1.0, p.global_position, false, "arcane")
	check(dealt > 0, "a hit deals damage")
	check_eq(before - foe.health, float(dealt), "health falls by exactly the number shown")
	# One swing, one cut per foe.
	before = foe.health
	play._weapon_strike("moonblade", false, p.global_position, fwd)
	var drop := before - foe.health
	check(drop > 0.0, "a swing in reach cuts")
	check(drop < 200.0, "only once (%.0f)" % drop)
	# Arts are sealed until their level; cooldowns hold.
	play.prog.level = 1
	play.use_phase()
	check_eq(play.cooldowns.phase, 0.0, "Phase Step is sealed at Lv 1")
	play.prog.level = 7
	p._action = 0.0
	p._dodge = 0.0
	var from := p.global_position
	play.use_phase()
	check(play.cooldowns.phase > 0.0, "Phase Step at Lv 7 goes on cooldown")
	check(p.global_position.distance_to(from) > 1.0, "and she blinks forward")
	var cd: float = play.cooldowns.phase
	p._action = 0.0
	var at := p.global_position
	play.use_phase()
	check(p.global_position.distance_to(at) < 0.01 and play.cooldowns.phase <= cd, "a second Phase Step waits for the cooldown")
	await tree.create_timer(0.5).timeout
	check(foe.mark > 0.0 or foe.dead or from.distance_to(foe.global_position) > 9.0, "foes on her line are Marked")
	# Blade Orbit: hits are rate-limited per foe.
	foe.global_position = p.global_position + Vector3(2.4, 0, 0)
	play.cooldowns.orbit = 0.0
	play.use_orbit()
	check(play.cooldowns.orbit > 0.0 and p.magic_hold.mode != -1, "Blade Orbit starts")
	var hp0 := foe.health
	var hits := 0
	for i in 60:
		var h := foe.health
		await tree.process_frame
		if foe.health < h:
			hits += 1
	check(hits <= int(ceil(60.0 / 60.0 / 0.45)) + 3, "the orbit cuts a foe a limited number of times (%d)" % hits)
	check(foe.health <= hp0, "and it does cut")
	# Ranks.
	play.prog.level = 5
	play.prog.ranks = {}
	check_eq(play.prog.points(), 4, "Lv 5 has four points")
	var m1 := play.prog.art_mult("comet")
	check(play.prog.upgrade("comet"), "a point buys Comet rank 2")
	check(play.prog.art_mult("comet") > m1, "rank 2 hits harder")
	check(play.prog.art_cooldown("comet") < 6.0, "and recovers sooner")
	check(play.prog.upgrade("comet"), "two more buy rank 3")
	check(not play.prog.upgrade("comet"), "rank 3 is the most")
	check_eq(play.prog.points(), 1, "points are spent")
	check(not play.prog.upgrade("orbit"), "a sealed art cannot be bought")
	var copy := Progression.new()
	copy.from_dict(play.prog.to_dict())
	check_eq(copy.rank("comet"), 3, "ranks are saved")
	var cheat := Progression.new()
	cheat.from_dict({"level": 2, "xp": 0, "ranks": {"comet": 2, "phase": 2}})
	check(cheat.points() >= 0, "a save cannot spend points it never earned")
	main.queue_free()
	await tree.process_frame
