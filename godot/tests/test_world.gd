extends TestCase

static var _shared: WorldData


func world() -> WorldData:
	# Generation takes a moment; share one world across the read-only tests.
	if _shared == null:
		_shared = WorldData.new()
		_shared.generate(1234)
	return _shared


func test_generation_is_deterministic() -> void:
	var a := WorldData.new(160, 200)
	var b := WorldData.new(160, 200)
	a.generate(77)
	b.generate(77)
	check(a.tiles == b.tiles, "same seed, same tiles")
	check(a.ores == b.ores, "same seed, same ores")


func test_different_seeds_make_different_worlds() -> void:
	var a := WorldData.new(160, 200)
	var b := WorldData.new(160, 200)
	a.generate(1)
	b.generate(2)
	check(a.tiles != b.tiles, "seeds matter")


func test_the_player_spawns_standing_on_ground_under_open_sky() -> void:
	var w := world()
	check(not w.is_solid(w.spawn.x, w.spawn.y), "spawn cell is open")
	check(not w.is_solid(w.spawn.x, w.spawn.y - 1), "room for a head")
	check(w.is_solid(w.spawn.x, w.spawn.y + 1), "ground underfoot")
	check(w.sees_sky(w.spawn.x, w.spawn.y), "spawn is outdoors")


func test_the_world_is_sealed_at_the_edges_and_bottom() -> void:
	var w := world()
	for y in w.height:
		check_eq(w.get_tile(0, y), WorldData.BEDROCK, "west edge sealed at %d" % y)
		check_eq(w.get_tile(w.width - 1, y), WorldData.BEDROCK, "east edge sealed")
	for x in w.width:
		check_eq(w.get_tile(x, w.height - 1), WorldData.BEDROCK, "floor sealed at %d" % x)


func test_three_surface_biomes_exist_in_order() -> void:
	var w := world()
	check_eq(w.biome_columns[10], WorldData.Biome.TUNDRA, "tundra in the west")
	check_eq(w.biome_columns[w.width / 2], WorldData.Biome.MEADOW, "meadow in the middle")
	check_eq(w.biome_columns[w.width - 10], WorldData.Biome.DESERT, "desert in the east")


func test_each_biome_has_its_own_surface_material() -> void:
	var w := world()
	var tops := {}
	for x in range(5, w.width - 5):
		var biome := w.biome_columns[x]
		var top := w.get_tile(x, w.surface[x])
		if not tops.has(biome):
			tops[biome] = {}
		tops[biome][top] = tops[biome].get(top, 0) + 1
	check(tops[WorldData.Biome.MEADOW].get(WorldData.GRASS, 0) > 50, "meadow is grassy")
	check(tops[WorldData.Biome.TUNDRA].get(WorldData.SNOW, 0) > 50, "tundra is snowy")
	check(tops[WorldData.Biome.DESERT].get(WorldData.SAND, 0) > 50, "desert is sandy")


func test_there_are_caves_underground() -> void:
	var w := world()
	var air := 0
	var total := 0
	for x in range(0, w.width, 3):
		for y in range(w.surface[x] + 20, w.height - 2, 3):
			total += 1
			if not w.is_solid(x, y):
				air += 1
	var fraction := air / float(total)
	check(fraction > 0.12, "underground is not solid rock (%.2f open)" % fraction)
	check(fraction < 0.55, "underground is not mostly hollow (%.2f open)" % fraction)


func test_ores_follow_their_depth_rules() -> void:
	var w := world()
	var counts := {}
	for x in w.width:
		for y in w.height:
			var ore := w.get_ore(x, y)
			if ore == WorldData.ORE_NONE:
				continue
			counts[ore] = counts.get(ore, 0) + 1
			check(w.is_solid(x, y), "ore at (%d,%d) sits in solid rock" % [x, y])
			if ore == WorldData.GOLD:
				check(y - w.surface[x] >= 120, "gold is deep")
			if ore == WorldData.RUBY:
				check(w.get_tile(x, y) == WorldData.BASALT, "rubies only in basalt")
	for ore in [WorldData.COAL, WorldData.COPPER, WorldData.IRON, WorldData.SILVER,
			WorldData.GOLD, WorldData.GLOWSHARD]:
		check(counts.get(ore, 0) > 20, "ore %d is findable (%d)" % [ore, counts.get(ore, 0)])


func test_the_ore_progression_gets_rarer_with_value() -> void:
	var w := world()
	var counts := {}
	for i in w.ores.size():
		counts[w.ores[i]] = counts.get(w.ores[i], 0) + 1
	check(counts.get(WorldData.COAL, 0) > counts.get(WorldData.IRON, 0), "coal commoner than iron")
	check(counts.get(WorldData.IRON, 0) > counts.get(WorldData.GOLD, 0), "iron commoner than gold")


func test_crystal_hollows_exist_and_glow() -> void:
	var w := world()
	var crystal_walls := 0
	var shards := 0
	for i in w.walls.size():
		if w.walls[i] == WorldData.CRYSTAL:
			crystal_walls += 1
		if w.ores[i] == WorldData.GLOWSHARD:
			shards += 1
	check(crystal_walls > 300, "hollows are substantial (%d)" % crystal_walls)
	check(shards > 30, "they carry glowshards (%d)" % shards)


func test_pools_are_contained() -> void:
	# A liquid cell must have something under it: rock or more liquid.
	var w := world()
	var pools := 0
	for x in w.width:
		for y in range(0, w.height - 1):
			if w.get_liquid(x, y) == WorldData.DRY:
				continue
			pools += 1
			check(w.is_solid(x, y + 1) or w.get_liquid(x, y + 1) != WorldData.DRY,
				"liquid at (%d,%d) is floating" % [x, y])
			check(not w.is_solid(x, y), "liquid only in open cells")
	check(pools > 0, "some pools exist")


func test_lava_only_in_the_depths() -> void:
	var w := world()
	for i in w.liquids.size():
		if w.liquids[i] == WorldData.LAVA:
			check(i / w.width > WorldData.DEEP_Y, "lava at row %d is too shallow" % (i / w.width))


func test_the_starting_cabin_offers_shelter_and_tools() -> void:
	var w := world()
	var types := {}
	for key in w.objects:
		var cell := Vector2i(key % w.width, key / w.width)
		if cell.distance_to(w.spawn) < 30:
			types[w.objects[key].type] = true
	check(types.has("workbench"), "a workbench near spawn")
	check(types.has("chest"), "a chest near spawn")
	check(types.has("sign"), "the note near spawn")


func test_the_vault_and_its_altar_exist_deep_down() -> void:
	var w := world()
	check(w.vault.y > WorldData.DEEP_Y, "the vault is in the deep dark")
	var key := w.idx(w.vault.x, w.vault.y)
	check(w.objects.has(key) and w.objects[key].type == "altar", "altar inside")


func test_trees_stand_on_the_surface() -> void:
	var w := world()
	var trees := 0
	for key in w.objects:
		if w.objects[key].type != "tree":
			continue
		trees += 1
		var x: int = key % w.width
		var y: int = key / w.width
		check(w.is_solid(x, y + 1), "tree at %d has ground under it" % x)
		check(not w.is_solid(x, y), "tree at %d is not buried" % x)
	check(trees > 40, "there is a forest (%d trees)" % trees)


func test_mask_reports_open_sides() -> void:
	var w := WorldData.new(5, 5)
	w.set_tile(2, 2, WorldData.ROCK)
	check_eq(w.mask(2, 2), 15, "a lone block is open on every side")
	w.set_tile(2, 1, WorldData.ROCK)
	check_eq(w.mask(2, 2), 14, "covered from above")


func test_ore_hardness_overrides_its_host_rock() -> void:
	var w := WorldData.new(4, 4)
	w.set_tile(1, 1, WorldData.ROCK)
	var plain := w.hardness(1, 1)
	w.ores[w.idx(1, 1)] = WorldData.GOLD
	check(w.hardness(1, 1) > plain, "gold is harder than the rock around it")


func test_mining_a_tile_clears_its_ore() -> void:
	var w := WorldData.new(4, 4)
	w.set_tile(1, 1, WorldData.ROCK)
	w.ores[w.idx(1, 1)] = WorldData.IRON
	w.set_tile(1, 1, WorldData.AIR)
	check_eq(w.get_ore(1, 1), WorldData.ORE_NONE, "no floating ore left behind")


func test_save_round_trip_preserves_everything() -> void:
	var a := WorldData.new(120, 160)
	a.generate(9)
	a.set_tile(10, 10, WorldData.PLANKS)
	var bytes := var_to_bytes(a.to_dict())
	var b := WorldData.from_dict(bytes_to_var(bytes))
	check(a.tiles == b.tiles, "tiles survive")
	check(a.walls == b.walls, "walls survive")
	check(a.ores == b.ores, "ores survive")
	check(a.liquids == b.liquids, "liquids survive")
	check_eq(b.spawn, a.spawn, "spawn survives")
	check_eq(b.objects.size(), a.objects.size(), "objects survive")
	check(bytes.size() < a.tiles.size(), "saves are compressed (%d bytes)" % bytes.size())


func test_full_size_generation_is_fast_enough_for_a_phone() -> void:
	var started := Time.get_ticks_msec()
	var w := WorldData.new()
	w.generate(4321)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	# A desktop core is several times a phone's; keep generous headroom.
	check(seconds < 6.0, "generation took %.2fs" % seconds)


func test_sunlight_depth_tracks_digging_and_building() -> void:
	# The lighting reads a cached "first solid row" per column; it must
	# follow every change or shafts stay dark and roofs leak light.
	var w := WorldData.new(8, 20)
	for x in 8:
		for y in range(10, 20):
			w.set_tile(x, y, WorldData.ROCK)
	w.recompute_all_sky()
	check_eq(w.sky_depth[3], 10, "sunlight stops at the ground")
	w.set_tile(3, 10, WorldData.AIR)
	w.set_tile(3, 11, WorldData.AIR)
	check_eq(w.sky_depth[3], 12, "digging a shaft lets the sun further down")
	w.set_tile(3, 4, WorldData.PLANKS)
	check_eq(w.sky_depth[3], 4, "a roof stops it higher up")
	w.set_tile(3, 4, WorldData.AIR)
	check_eq(w.sky_depth[3], 12, "removing the roof restores the shaft")
	w.set_tile(5, 15, WorldData.AIR)
	check_eq(w.sky_depth[5], 10, "a buried pocket does not see the sky")


func test_a_loaded_world_rebuilds_its_sunlight_depths() -> void:
	var a := WorldData.new(60, 120)
	a.generate(5)
	var b := WorldData.from_dict(bytes_to_var(var_to_bytes(a.to_dict())))
	check(a.sky_depth == b.sky_depth, "derived state rebuilt identically on load")
