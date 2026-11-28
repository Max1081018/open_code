extends TestCase
## Each starting island played from arrival to the end of its first chapter,
## the way test_adventure plays the jungle: the sky isle and the coast too,
## with their own landmarks, foes and relic. Along the way: she stands on
## real ground at every landmark the chain sends her to, and the island's
## guardian is waiting (not awake) when the chapter ends.


func test_sky_journey() -> void:
	await _journey("sky")


func test_coast_journey() -> void:
	await _journey("coast")


func _journey(island: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Account.sign_out()
	Account.sign_in_guest()
	if FileAccess.file_exists(Save3D.path()):
		DirAccess.remove_absolute(Save3D.path())
	Account.set_start_island(island)
	Save3D.load_on_start = false
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var adv: Adventure = main.adventure
	check(adv != null and adv.island == island, "%s: a new journey has its adventure" % island)
	check(adv._cine, "%s: it opens with the arrival" % island)
	adv._skip_cb.call()
	await tree.process_frame
	check(not main.input.blocked, "%s: skipping hands control back" % island)
	check(adv._wisp != null, "%s: Lumi has joined" % island)
	main.hud.dialogue.visible = false
	var p: Player3D = main.player
	var spec: Dictionary = Adventure.ISLANDS[island]
	# Every landmark the chain uses exists, with ground (or an isle) under it.
	for key in ["light", "hidden", "relic_at"]:
		var at: Vector3 = adv._landmark(String(spec[key]))
		check(at != Vector3.INF, "%s: the %s landmark (%s) exists" % [island, key, spec[key]])
	check(adv.current().id == "walk", "%s: the first step is the walk" % island)
	p.global_position += Vector3(16, 0, 0)
	await tree.process_frame
	check(adv.current().id == "moves", "%s: walking completes the first step" % island)
	adv._moves = {"jump": true, "dodge": true}
	await tree.process_frame
	check(adv.current().id == "light", "%s: jump and dodge complete the second" % island)
	var light: Vector3 = adv._landmark(String(spec.light))
	check(main.quests.tracker().target is Vector3, "%s: the tracker points at the light" % island)
	await _stand_at(main, light, "%s: the light (%s)" % [island, spec.light])
	check(adv.current().id == "gather", "%s: reaching the light completes the third" % island)
	for i in 6:
		main.play.resource_struck.emit("tree")
	check(adv.current().id == "bag", "%s: gathering completes" % island)
	main.hud.menu.open("bag")
	await tree.process_frame
	main.hud.menu.close()
	check(adv.current().id == "craft", "%s: opening the backpack completes that step" % island)
	main.play.crafted.emit("campfire")
	check(adv.current().id == "hidden", "%s: crafting a campfire completes the next" % island)
	await _stand_at(main, adv._landmark(String(spec.hidden)), "%s: the hidden place (%s)" % [island, spec.hidden])
	check(adv.current().id == "ambush", "%s: finding the hidden place springs the ambush" % island)
	var foes := 0
	for e in tree.get_nodes_in_group("enemies"):
		if e.global_position.distance_to(p.global_position) < 15.0:
			foes += 1
	check(foes >= 4, "%s: foes appear around her (%d)" % [island, foes])
	for i in 4:
		main.play.enemy_killed.emit(null)
	check(adv.current().id == "relic", "%s: defeating them leads to the relic" % island)
	_read(main)
	await tree.process_frame
	check(adv._relic != null, "%s: the relic is placed in the world" % island)
	if adv._relic:
		# The relic must be reachable: on ground she can stand on.
		var below = main.surface_y(adv._relic.global_position)
		check(below != null and absf(adv._relic.global_position.y - float(below)) < 3.0,
			"%s: the relic rests over solid ground (relic y %.1f, ground %s)" % [island, adv._relic.global_position.y, str(below)])
		p.global_position = adv._relic.global_position - Vector3(0, 1.0, 0)
		await tree.process_frame
	check(main.play.inventory.count(String(spec.relic)) == 1, "%s: taking it gives %s" % [island, spec.relic])
	check(adv.current().id == "return", "%s: then back to the light" % island)
	await _stand_at(main, light, "%s: the light again" % island)
	check(adv.done, "%s: returning completes the chapter" % island)
	check(main.play.prog.level >= 3, "%s: the chapter levels her up" % island)
	check(not main.bosses._live.has(island), "%s: the guardian is not awake after the chapter" % island)
	check(not main.bosses.pending(island).is_empty(), "%s: the guardian waits, for the tracker" % island)
	main.queue_free()
	await tree.process_frame
	Account.set_start_island("")
	Account.sign_out()


## Put her at `at` the way she would arrive: on whatever solid ground is
## there, and check it is there (not a hole, not water over her head).
func _stand_at(main: Node, at: Vector3, what: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	main.world.warm(at)
	main.player.global_position = at + Vector3(0, 3.0, 0)
	for i in 3:
		await tree.physics_frame
	var y = main.surface_y(at + Vector3(0, 1.0, 0))
	check(y != null, "%s has solid ground" % what)
	if y != null:
		main.player.global_position = Vector3(at.x, float(y) + 0.1, at.z)
		check(float(y) > TerrainGen.WATER - 0.5, "%s is not under the sea (ground %.1f)" % [what, float(y)])
	await tree.process_frame


func _read(main: Node) -> void:
	for i in 20:
		if not main.hud.dialogue.showing:
			return
		main.hud.dialogue.advance()


## A fall on a starting island wakes her nearby, on solid ground: never the
## town square a continent away (it used to be, from every island).
func test_falls_wake_her_nearby() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for island in ["jungle", "sky", "coast"]:
		Account.sign_out()
		Account.sign_in_guest()
		if FileAccess.file_exists(Save3D.path()):
			DirAccess.remove_absolute(Save3D.path())
		Account.set_start_island(island)
		Save3D.load_on_start = false
		var main: Node = load("res://scenes/main3d.tscn").instantiate()
		tree.root.add_child(main)
		await tree.process_frame
		await tree.process_frame
		if main.adventure:
			main.adventure._skip_cb.call()
		main.play._spawn_timer = 9999.0
		var p: Player3D = main.player
		var landing := Realms.spawn_point(main.world.gen, island)
		p._grace = 0.0
		p.hurt(99999.0, p.global_position + Vector3(1, 0, 0))
		check(p.dead, "%s: she falls" % island)
		var waited := 0.0
		while p.dead and waited < 8.0:
			await tree.create_timer(0.25).timeout
			waited += 0.25
		check(not p.dead, "%s: she wakes again" % island)
		var at := p.global_position
		check(Vector2(at.x - landing.x, at.z - landing.z).length() < 250.0,
			"%s: she wakes on her island, %.0f m from its landing" % [island, Vector2(at.x - landing.x, at.z - landing.z).length()])
		await tree.create_timer(1.0).timeout
		var ground = main.surface_y(p.global_position + Vector3(0, 1.0, 0))
		check(ground != null and p.global_position.y > float(ground) - 0.5, "%s: standing on solid ground (y %.1f, ground %s)" % [island, p.global_position.y, str(ground)])
		main.queue_free()
		await tree.process_frame
	Account.set_start_island("")
	Account.sign_out()


## Falling off a floating isle is not the end: its updraft, from the ground
## (or sea) below its rim, carries her back above it with one jump and one
## tap to open the wings. (A glider used to drift out of the column within a
## second and sink back down: stranded below her island.)
func test_updrafts_carry_her_back_up() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	main.play._spawn_timer = 9999.0
	var p: Player3D = main.player
	var isles := Realms.sky_isles(main.world.gen)
	for want in [0, 2]:   # the Aerie, and the isle whose column stands in the sea
		var top: Vector3 = isles[want][0]
		var column: Array = []
		for u in main.features.updrafts:
			if Vector2(top.x - u[0].x, top.z - u[0].z).length() < float(isles[want][1]) + 12.0:
				column = u
		check(not column.is_empty(), "isle %d has an updraft" % want)
		if column.is_empty():
			continue
		var base: Vector3 = column[0]
		main.world.warm(base)
		p.global_position = base + Vector3(0, 1.0, 0)
		p.velocity = Vector3.ZERO
		p.stamina = p.max_stamina
		for i in 30:
			await tree.physics_frame
		main.input.touch_buttons["jump"] = true
		var tapped := false
		var best := p.global_position.y
		for i in 60 * 25:
			await tree.physics_frame
			if not tapped and not p.gliding and not p.is_on_floor() and not p.swimming and p._air_time > 0.3:
				main.input.touch_buttons["jump"] = true
				tapped = true
			best = maxf(best, p.global_position.y)
			if best > top.y + 2.0:
				break
		check(best > top.y + 1.0, "isle %d: the updraft carries her above it (reached %.0f, isle %.0f)" % [want, best, top.y])
	main.queue_free()
	await tree.process_frame
