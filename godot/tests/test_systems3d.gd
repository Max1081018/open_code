extends TestCase
## Tobin's stall (buying and selling for Old Coins) and the starstones
## (attuning by walking up; travelling to one).


func _game() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	return main


func test_shop() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _game()
	var menu: GameMenu3D = main.hud.menu
	var inv: Inventory = main.play.inventory
	inv.add("gold_coin", 10)
	menu.open("shop")
	menu._shop_page = "buy"
	var torch: Dictionary = menu._shop_rows()[0]
	check_eq(torch.id, "torch", "torches first on the stall")
	var torches := inv.count("torch")
	menu._shop_qty = 1
	menu._trade(torch)
	check_eq(inv.count("gold_coin"), 10 - int(torch.price), "coins paid")
	check_eq(inv.count("torch"), torches + int(torch.count), "torches bought")
	var heart: Dictionary = {}
	for r in menu._shop_rows():
		if r.id == "heart_crystal":
			heart = r
	var before := inv.count("heart_crystal")
	menu._trade(heart)
	check_eq(inv.count("heart_crystal"), before, "not without the coins")
	menu._shop_page = "sell"
	inv.add("stone", 5)
	var coins := inv.count("gold_coin")
	var stone: Dictionary = {}
	for r in menu._shop_rows():
		if r.id == "stone":
			stone = r
	menu._shop_qty = 5
	menu._trade(stone)
	check_eq(inv.count("stone"), 0, "stone sold")
	check(inv.count("gold_coin") > coins, "for coins")
	var ids := []
	for r in menu._shop_rows():
		ids.append(r.id)
	check(not ("moonblade" in ids), "her Moonblade is never for sale")
	menu.close()
	main.queue_free()
	await tree.process_frame


func test_starstones() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _game()
	var ss: Starstones = main.starstones
	check(ss.stones.size() >= 5, "a starstone in the town and in each region")
	var far: Dictionary = ss.stones.back()
	check(not ss.attuned.has(far.id), "a distant stone starts dormant")
	main.player.global_position = far.pos + Vector3(1.5, 1.0, 0)
	for i in 5:
		await tree.process_frame
	check(ss.attuned.has(far.id), "walking up to it attunes it")
	main.player.global_position = Vector3(10, main.world.height_at(10, 14) + 0.5, 14)
	await ss.travel(far.id)
	check(main.player.global_position.distance_to(far.pos) < 6.0, "travel brings her beside it")
	main.queue_free()
	await tree.process_frame
