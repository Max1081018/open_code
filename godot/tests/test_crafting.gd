extends TestCase
## Crafting as work: it takes time, and only then uses the materials.


func _make_level() -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(4321)
	return level


func test_crafting_takes_time_and_then_delivers() -> void:
	var level := _make_level()
	var player := level.player
	var bench: Array = []
	for recipe in Items.recipes:
		if recipe[0] == "workbench":
			bench = recipe
	player.inventory.add("wood", 12)
	check(player.start_craft(bench), "a workbench can be started by hand")
	check(not player.start_craft(bench), "one job at a time")
	player._work_craft(Player.craft_time(bench) * 0.5)
	check_eq(player.inventory.count("workbench"), 0, "not done halfway")
	check(player.inventory.count("wood") >= 12, "materials untouched until it is made")
	check(player.craft_progress() > 0.4 and player.craft_progress() < 0.6, "progress shows")
	player._work_craft(Player.craft_time(bench))
	check_eq(player.inventory.count("workbench"), 1, "made")
	check_eq(player.inventory.count("wood"), 2, "ten wood used")
	check(player.crafting().is_empty(), "free to make the next thing")
	level.free()


func test_better_gear_takes_longer() -> void:
	var times := {}
	for recipe in Items.recipes:
		times[recipe[0]] = Player.craft_time(recipe)
	check(times.lumen_pickaxe > times.copper_pickaxe, "lumen work is slower than copper")
	check(times.copper_pickaxe > times.wood_pickaxe, "metal is slower than wood")
	check(times.wood_pickaxe < 2.0 and times.lumen_pickaxe < 3.0, "but never tedious")


func test_crafting_needs_the_station_and_the_stuff() -> void:
	var level := _make_level()
	var player := level.player
	for recipe in Items.recipes:
		if recipe[0] == "copper_pickaxe":
			player.inventory.add("copper_ore", 20)
			player.inventory.add("wood", 10)
			check(not player.start_craft(recipe), "no anvil nearby, no copper pickaxe")
		if recipe[0] == "chest":
			check(not player.start_craft(recipe), "no materials, no chest")
	level.free()


func test_finished_crafts_count_for_quests() -> void:
	var level := _make_level()
	level.quests.talk("wren")
	for i in 1:
		level.quests.event("fell")
	level.player.inventory.add("wood", 20)
	var bench: Array = []
	for recipe in Items.recipes:
		if recipe[0] == "workbench":
			bench = recipe
	level.player.start_craft(bench)
	level.player._work_craft(10.0)
	check_eq(level.quests.state.first_light.step, 3, "crafting the bench moved the tutorial on")
	level.free()
