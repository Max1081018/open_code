extends TestCase
## The townsfolk's quests in the real 3D game scene: offer, goal, hand-in,
## rewards and the follow-on request, plus the conversation lock.


func _read_all(main: Node) -> void:
	var d: DialogueBox3D = main.hud.dialogue
	var guard := 0
	while d.showing and guard < 200:
		d.advance()
		guard += 1


func test_quest_lines() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var q: Quests3D = main.quests
	var inv: Inventory = main.play.inventory

	# Wren: fly to the little isle north of town.
	check_eq(q.marker_for("wren"), "!", "Wren has a request")
	q.start_talk(q.npcs["wren"])
	check(main.input.blocked, "talking holds the heroine still")
	check(main.hud.dialogue.showing, "the dialogue is open")
	_read_all(main)
	check_eq(q.state.get("wings", ""), "active", "the request is accepted")
	check(not main.input.blocked, "the heroine is free again")
	check_eq(q.tracker().title, "Wings of the Wind", "the tracker follows it")
	var top: Array = main.islands.tops[9]
	main.player.global_position = (top[0] as Vector3) + Vector3(0, 1.0, 0)
	main.player.velocity = Vector3.ZERO
	for i in 60:
		await tree.physics_frame
	check_eq(q.state.get("wings", ""), "ready", "landing on the isle meets the goal")
	check_eq(q.marker_for("wren"), "?", "Wren waits to hear about it")
	q.start_talk(q.npcs["wren"])
	_read_all(main)
	check_eq(q.state.get("wings", ""), "done", "handed in")
	check(inv.count("heart_crystal") >= 1, "the reward is in the bag")
	check_eq(q.state.get("starspire", ""), "active", "the Starspire request follows on")

	# Tobin: five iron ore for a sword.
	q.start_talk(q.npcs["tobin"])
	_read_all(main)
	check_eq(q.state.get("ore", ""), "active", "Tobin's request accepted")
	inv.add("iron_ore", 5)
	# process_frame fires before the frame's _process calls: wait a whole one.
	await tree.process_frame
	await tree.process_frame
	check_eq(q.state.get("ore", ""), "ready", "carrying the ore meets the goal")
	q.start_talk(q.npcs["tobin"])
	_read_all(main)
	check_eq(inv.count("iron_ore"), 0, "the ore is handed over")
	check_eq(inv.count("iron_sword"), 1, "the sword is forged")

	# Aldous: six of the risen.
	q.start_talk(q.npcs["aldous"])
	_read_all(main)
	check_eq(q.state.get("hunt", ""), "active", "the hunt is on")
	var dummy := Node.new()
	for i in 5:
		main.play.enemy_killed.emit(dummy)
	check_eq(q.state.get("hunt", ""), "active", "five is not six")
	main.play.enemy_killed.emit(dummy)
	check_eq(q.state.get("hunt", ""), "ready", "six is")
	dummy.free()
	check_eq(q.offer_for("aldous"), {}, "the Warden waits until the hunt is handed in")

	main.queue_free()
	await tree.process_frame
