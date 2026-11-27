extends TestCase
## The game's screens in the live scene: every screen opens; the backpack
## equips, uses and discards (with a confirm, never her Moonblade); crafting
## spends materials and makes the item; the pause screen resumes.


func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	return main


func _slot_of(inv: Inventory, id: String) -> int:
	for i in inv.size():
		var s = inv.get_slot(i)
		if s != null and s.id == id:
			return i
	return -1


func test_every_screen_opens() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _game()
	var menu: GameMenu3D = main.hud.menu
	for t in ["bag", "craft", "book", "map", "person", "pause", "gear"]:
		menu.open(t)
		await tree.process_frame
		check(menu.is_open and menu.tab == t, "the %s screen opens" % t)
		check(menu._body.get_child_count() > 0, "the %s screen has content" % t)
	check(tree.paused, "the world waits while a screen is open")
	menu._pause_pick("resume")
	check(not menu.is_open and not tree.paused, "Resume closes the menu and the world moves again")
	main.queue_free()
	await tree.process_frame


func test_backpack_actions() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _game()
	var menu: GameMenu3D = main.hud.menu
	var inv: Inventory = main.play.inventory
	inv.add("iron_sword", 1)
	inv.add("cooked_fish", 2)
	menu.open("bag")
	# Equip the iron sword.
	menu._selected = _slot_of(inv, "iron_sword")
	menu._equip()
	check_eq(main.play.held_id(), "iron_sword", "Equip puts it in her hand")
	# Use a fish when hurt.
	main.player.health = 40.0
	menu._selected = _slot_of(inv, "cooked_fish")
	menu._use()
	check(main.player.health > 40.0, "Use heals")
	check_eq(inv.count("cooked_fish"), 1, "one fish eaten")
	# Discard asks first.
	menu._selected = _slot_of(inv, "cooked_fish")
	menu._discard()
	check_eq(inv.count("cooked_fish"), 1, "the first press only asks")
	menu._discard()
	check_eq(inv.count("cooked_fish"), 0, "the second press discards")
	# Her Moonblade cannot be discarded: no button is offered.
	menu._selected = _slot_of(inv, "moonblade")
	menu._fill_detail()
	await tree.process_frame
	var offered := false
	for c in menu._detail.get_children():
		if c is Button and (c as Button).text in ["Discard", "Confirm?"]:
			offered = true
	check(not offered, "the Moonblade has no Discard")
	menu.close()
	main.queue_free()
	await tree.process_frame


func test_crafting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _game()
	var menu: GameMenu3D = main.hud.menu
	var inv: Inventory = main.play.inventory
	inv.add("wood", 16)
	menu.open("craft")
	var idx := -1
	for i in Items.recipes.size():
		if Items.recipes[i][0] == "wood_shield":
			idx = i
	menu._recipe = idx
	menu._craft_qty = 1
	menu._do_craft()
	check_eq(inv.count("wood_shield"), 1, "a shield is crafted")
	check_eq(inv.count("wood"), 2, "its wood is spent")
	menu._do_craft()
	check_eq(inv.count("wood_shield"), 1, "not without the wood")
	menu.close()
	main.queue_free()
	await tree.process_frame
