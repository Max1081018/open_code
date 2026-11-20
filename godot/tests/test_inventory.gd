extends TestCase


func test_adding_merges_into_existing_stacks() -> void:
	var bag := Inventory.new(10)
	bag.add("stone", 5)
	bag.add("stone", 7)
	check_eq(bag.count("stone"), 12, "both pickups counted")
	check_eq(bag.slots.filter(func(s): return s != null).size(), 1, "one stack, not two")


func test_overflow_spills_into_a_new_stack() -> void:
	var bag := Inventory.new(10)
	var left := bag.add("apple", 150)  # apples stack to 99
	check_eq(left, 0, "everything fit")
	check_eq(bag.count("apple"), 150, "all counted")
	check_eq(bag.slots[0].count, 99, "first stack full")
	check_eq(bag.slots[1].count, 51, "remainder in the next slot")


func test_a_full_bag_reports_what_did_not_fit() -> void:
	var bag := Inventory.new(2)
	bag.add("wood_sword", 1)
	bag.add("wood_axe", 1)
	check_eq(bag.add("stone", 4), 4, "no room for anything")


func test_removing_more_than_held_changes_nothing() -> void:
	var bag := Inventory.new(5)
	bag.add("coal", 3)
	check(not bag.remove("coal", 4), "refused")
	check_eq(bag.count("coal"), 3, "untouched")


func test_removing_empties_slots() -> void:
	var bag := Inventory.new(5)
	bag.add("coal", 3)
	bag.remove("coal", 3)
	check_eq(bag.slots[0], null, "slot cleared")


func test_crafting_consumes_ingredients_and_yields_the_result() -> void:
	var bag := Inventory.new(10)
	bag.add("wood", 3)
	bag.add("coal", 2)
	var torch_recipe: Array = Items.recipes.filter(func(r): return r[0] == "torch")[0]
	check(bag.craft(torch_recipe), "crafted")
	check_eq(bag.count("torch"), 4, "four torches")
	check_eq(bag.count("wood"), 2, "one wood used")
	check_eq(bag.count("coal"), 1, "one coal used")


func test_crafting_without_ingredients_fails_cleanly() -> void:
	var bag := Inventory.new(10)
	bag.add("wood", 3)
	var bench: Array = Items.recipes.filter(func(r): return r[0] == "workbench")[0]
	check(not bag.craft(bench), "needs ten wood")
	check_eq(bag.count("wood"), 3, "nothing consumed on failure")


func test_crafting_from_a_full_bag_works_when_it_frees_a_slot() -> void:
	# Consuming the only stack of wood frees the slot the result needs.
	var bag := Inventory.new(1)
	bag.add("wood", 10)
	var bench: Array = Items.recipes.filter(func(r): return r[0] == "workbench")[0]
	check(bag.craft(bench), "crafted into the freed slot")
	check_eq(bag.count("workbench"), 1, "got the bench")


func test_best_tool_is_chosen_by_tier_not_order() -> void:
	var bag := Inventory.new(10)
	bag.add("iron_pickaxe", 1)
	bag.add("wood_pickaxe", 1)
	bag.add("gold_pickaxe", 1)
	check_eq(bag.best_of_kind(Items.Kind.PICKAXE), "gold_pickaxe", "highest tier wins")


func test_moving_onto_the_same_item_merges() -> void:
	var bag := Inventory.new(4)
	bag.slots[0] = {"id": "stone", "count": 10}
	bag.slots[2] = {"id": "stone", "count": 5}
	bag.move(0, 2)
	check_eq(bag.slots[0], null, "source emptied")
	check_eq(bag.slots[2].count, 15, "merged")


func test_round_trip_through_an_array() -> void:
	var bag := Inventory.new(8)
	bag.add("torch", 7)
	bag.add("iron_sword", 1)
	var copy := Inventory.new(8)
	copy.from_array(bag.to_array())
	check_eq(copy.count("torch"), 7, "torches restored")
	check_eq(copy.count("iron_sword"), 1, "sword restored")
	check_eq(copy.size(), 8, "same capacity")


func test_loading_a_shorter_save_keeps_the_bag_its_full_size() -> void:
	var bag := Inventory.new(40)
	bag.from_array([{"id": "torch", "count": 2}])
	check_eq(bag.size(), 40, "capacity not shrunk by a short array")


func test_unknown_items_in_a_save_are_dropped_not_crashed_on() -> void:
	var bag := Inventory.new(4)
	bag.from_array([{"id": "no_such_thing", "count": 3}, {"id": "coal", "count": 2}])
	check_eq(bag.count("coal"), 2, "known items kept")
	check_eq(bag.slots[0], null, "unknown item skipped")


func test_every_recipe_names_real_items() -> void:
	for recipe in Items.recipes:
		check(Items.exists(recipe[0]), "result %s exists" % recipe[0])
		for id in recipe[3]:
			check(Items.exists(id), "ingredient %s of %s exists" % [id, recipe[0]])


func test_every_item_has_an_icon_on_disk() -> void:
	for id in Items.defs:
		var path: String = Items.ICON_ROOT + Items.defs[id].icon + ".png"
		check(ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"%s icon missing at %s" % [id, path])


func test_every_ore_drops_a_real_item() -> void:
	for ore in range(1, 9):
		check(Items.exists(Items.drop_for_ore(ore)), "ore %d drops something real" % ore)


func test_tool_tiers_strictly_improve() -> void:
	var picks := ["wood_pickaxe", "copper_pickaxe", "iron_pickaxe", "silver_pickaxe",
		"gold_pickaxe", "lumen_pickaxe"]
	for i in range(1, picks.size()):
		check(Items.def(picks[i]).power > Items.def(picks[i - 1]).power,
			"%s outdigs %s" % [picks[i], picks[i - 1]])
	var swords := ["wood_sword", "copper_sword", "iron_sword", "silver_sword", "gold_sword",
		"lumen_sword"]
	for i in range(1, swords.size()):
		check(Items.def(swords[i]).damage > Items.def(swords[i - 1]).damage,
			"%s outhits %s" % [swords[i], swords[i - 1]])


func test_sorting_merges_and_orders_the_bag_but_not_the_hotbar() -> void:
	var inv := Inventory.new()
	inv.slots[0] = {"id": "torch", "count": 3}
	inv.slots[10] = {"id": "stone", "count": 30}
	inv.slots[20] = {"id": "iron_pickaxe", "count": 1}
	inv.slots[25] = {"id": "stone", "count": 50}
	inv.slots[30] = {"id": "wood_pickaxe", "count": 1}
	inv.sort_bag()
	check_eq(inv.slots[0], {"id": "torch", "count": 3}, "the hotbar is left alone")
	check_eq(inv.count("stone"), 80, "nothing lost")
	var stone_stacks := 0
	var order := []
	for i in range(Inventory.HOTBAR_SIZE, inv.size()):
		if inv.slots[i] != null:
			order.append(inv.slots[i].id)
			if inv.slots[i].id == "stone":
				stone_stacks += 1
	check_eq(stone_stacks, 1, "stone merged into one stack")
	check(order.find("iron_pickaxe") < order.find("wood_pickaxe"), "better tools first")
	check_eq(inv.slots[Inventory.HOTBAR_SIZE + order.size()], null, "packed together, no gaps")


func test_rarity_rises_with_the_good_stuff() -> void:
	check_eq(Items.rarity("wood"), 0, "wood is common")
	check(Items.rarity("iron_pickaxe") > Items.rarity("wood_pickaxe"), "iron beats wood")
	check_eq(Items.rarity("lumen_core"), 4, "a Lumen Core is legendary")
	for id in Items.defs:
		check(Items.rarity(id) >= 0 and Items.rarity(id) < Items.RARITY_NAMES.size(), "%s has a valid rarity" % id)
