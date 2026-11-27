extends TestCase
## The first adventure: a new journey on the Great Jungle opens with the
## arrival, Lumi joins, and the chain teaches by doing — walk, jump and dodge,
## reach the light, strike, open the backpack, craft, find the hidden place,
## win the ambush, take the relic, return — with rewards and saved progress.


func test_jungle_chain_plays_through() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Account.sign_out()
	Account.sign_in_guest()
	if FileAccess.file_exists(Save3D.path()):
		DirAccess.remove_absolute(Save3D.path())
	Account.set_start_island("jungle")
	Save3D.load_on_start = false
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var adv: Adventure = main.adventure
	check(adv != null, "a new jungle journey has an adventure")
	check(adv._cine, "it opens with the arrival")
	check(main.input.blocked, "controls wait during the arrival")
	adv._skip_cb.call()
	await tree.process_frame
	check(not main.input.blocked, "skipping hands control back")
	check(adv.active() and adv.current().id == "walk", "the first step is the walk")
	check(adv._wisp != null, "Lumi has joined")
	main.hud.dialogue.visible = false
	var p: Player3D = main.player
	# Walk.
	p.global_position += Vector3(16, 0, 0)
	await tree.process_frame
	check(adv.current().id == "moves", "walking far enough completes the first step")
	adv._moves = {"jump": true, "dodge": true}
	await tree.process_frame
	check(adv.current().id == "light", "jump and dodge complete the second")
	var light := adv._landmark("jungle_shrine")
	check(light != Vector3.INF, "the shrine is a real place")
	check(main.quests.tracker().target is Vector3, "the tracker points at it")
	p.global_position = light
	await tree.process_frame
	check(adv.current().id == "gather", "reaching the light completes the third")
	for i in 6:
		main.play.resource_struck.emit("tree")
	check(adv.current().id == "bag", "six strikes complete the gathering")
	check(main.play.inventory.count("wood") >= 6, "and the island gives wood")
	main.hud.menu.open("bag")
	await tree.process_frame
	main.hud.menu.close()
	check(adv.current().id == "craft", "opening the backpack completes that step")
	main.play.crafted.emit("campfire")
	check(adv.current().id == "hidden", "crafting a campfire completes the next")
	var hidden := adv._landmark("falls_0")
	p.global_position = hidden
	await tree.process_frame
	check(adv.current().id == "ambush", "finding the hidden falls springs the ambush")
	var foes := 0
	for e in tree.get_nodes_in_group("enemies"):
		if e.global_position.distance_to(p.global_position) < 15.0:
			foes += 1
	check(foes >= 4, "four foes appear around her")
	for i in 4:
		main.play.enemy_killed.emit(null)
	check(adv.current().id == "relic", "defeating them leads to the relic")
	_read(main)
	await tree.process_frame
	check(adv._relic != null, "the relic is placed in the world")
	p.global_position = adv._relic.global_position - Vector3(0, 1.0, 0)
	await tree.process_frame
	check(main.play.inventory.count("relic_moth_lantern") == 1, "taking it gives the Moth Lantern")
	check(adv.current().id == "return", "then back to the shrine")
	var saved: Dictionary = Save3D.capture(main)
	check(int(saved.adventure.step) == adv.step, "the step is saved")
	p.global_position = light
	await tree.process_frame
	check(adv.done, "returning completes the chapter")
	check(not adv.active(), "and the adventure steps aside")
	check(main.play.prog.level >= 3, "the chapter levels her up")
	main.queue_free()
	await tree.process_frame
	Account.set_start_island("")
	Account.sign_out()


## Read through whatever Lumi is saying (as a player tapping through).
func _read(main: Node) -> void:
	for i in 20:
		if not main.hud.dialogue.showing:
			return
		main.hud.dialogue.advance()
