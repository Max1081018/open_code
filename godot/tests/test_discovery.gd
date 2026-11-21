extends TestCase
## Exploration rewards: sealed vaults, the lantern's flare, light-runes and
## relics.


func _make_level() -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(5150, {})
	return level


func test_a_world_hides_sealed_vaults_and_caches() -> void:
	var data := WorldData.new()
	data.generate(5150)
	check_eq(data.vaults.size(), 6, "six sealed vaults")
	check_eq(data.caches.size(), 12, "twelve hidden caches")
	var relics := []
	for vault in data.vaults:
		for cell in vault.door:
			check_eq(data.get_tile(cell.x, cell.y), WorldData.BEDROCK, "the door is rune-stone no pick can break")
		check_eq((vault.braziers as Array).size(), 3, "three braziers to light")
		for cell in vault.braziers:
			check_eq(data.objects.get(data.idx(cell.x, cell.y), {}).get("type", ""), "brazier", "a brazier stands there")
			check(not data.is_solid(cell.x, cell.y), "with room to stand")
		var chest: Dictionary = data.objects.get(data.idx(vault.chest.x, vault.chest.y), {})
		check_eq(chest.get("type", ""), "relic_chest", "a relic chest inside")
		for stack in chest.get("loot", []):
			if Items.kind(stack.id) == Items.Kind.RELIC:
				relics.append(stack.id)
	check_eq(relics.size(), 6, "each holds a relic")
	var unique := {}
	for id in relics:
		unique[id] = true
	check_eq(unique.size(), 6, "and no two the same")
	for cache in data.caches:
		check(data.is_solid(cache.rune.x, cache.rune.y), "the rune is on solid rock")
		check_eq(data.objects.get(data.idx(cache.chest.x, cache.chest.y), {}).get("type", ""), "chest", "a chest is sealed behind it")


func test_lighting_every_brazier_opens_the_vault() -> void:
	var level := _make_level()
	var vault: Dictionary = level.data.vaults[0]
	var chest_cell: Vector2i = vault.chest
	level.open_relic_chest(chest_cell, level.world.object_at(chest_cell))
	check(not level.world.object_at(chest_cell).get("opened", false), "sealed while the braziers are cold")
	var braziers: Array = vault.braziers
	for i in braziers.size():
		level.light_brazier(braziers[i])
		check_eq(vault.open, i == braziers.size() - 1, "open only once all %d burn (%d lit)" % [braziers.size(), i + 1])
	for cell in vault.door:
		check(not level.data.is_solid(cell.x, cell.y), "the door has opened")
	var before := level.drop_layer.get_child_count()
	level.open_relic_chest(chest_cell, level.world.object_at(chest_cell))
	check(level.world.object_at(chest_cell).get("opened", false), "the chest opens")
	var relic_dropped := false
	for drop in level.drop_layer.get_children():
		if drop is ItemDrop and Items.kind(drop.id) == Items.Kind.RELIC:
			relic_dropped = true
	check(relic_dropped and level.drop_layer.get_child_count() > before, "and spills its relic")
	level.free()


func test_the_flare_burns_the_dead_and_wakes_runes() -> void:
	var level := _make_level()
	var p := level.player
	p.glow = 60.0
	var dead := level.spawn_enemy("zombie", p.global_position + Vector2(300, 0))
	var living := level.spawn_enemy("slime", p.global_position + Vector2(-300, 0))
	var far := level.spawn_enemy("zombie", p.global_position + Vector2(2000, 0))
	var hp := [dead.health, living.health, far.health]
	# A brazier close by and one out of the flare's catch.
	var near_cell := World.cell_of(p.global_position + Vector2(0, -110)) + Vector2i(2, 0)
	var far_cell := near_cell + Vector2i(5, 0)
	level.world.add_object(near_cell, {"type": "brazier", "lit": false, "vault": -1})
	level.world.add_object(far_cell, {"type": "brazier", "lit": false, "vault": -1})
	# A rune within reach.
	var rune := World.cell_of(p.global_position) + Vector2i(3, 1)
	level.data.set_tile(rune.x, rune.y, WorldData.ROCK)
	level.data.caches.append({"rune": rune, "chest": rune + Vector2i(2, 0)})
	check(p.flare(), "the flare goes off")
	check_eq(p.glow, 35.0, "it costs glow")
	check(dead.health < hp[0], "the dead burn")
	check_eq(living.health, hp[1], "the living only flinch")
	check_eq(far.health, hp[2], "out of reach, nothing")
	check(level.world.object_at(near_cell).get("lit", false), "a close brazier catches")
	check(not level.world.object_at(far_cell).get("lit", false), "a far one does not")
	check(level.runes.is_shown(rune), "the rune answers the light")
	check(not p.flare(), "not again at once")
	p._flare_cooldown = 0.0
	p.glow = 10.0
	check(not p.flare(), "and not without the glow to spend")
	level.free()


func test_relics_are_worn_and_change_how_you_play() -> void:
	var level := _make_level()
	var p := level.player
	for id in ["relic_bulwark", "relic_swiftroot", "relic_featherbone", "relic_luckstone"]:
		p.inventory.add(id, 1)
	for id in ["relic_bulwark", "relic_swiftroot", "relic_featherbone", "relic_luckstone"]:
		for i in p.inventory.slots.size():
			var stack = p.inventory.get_slot(i)
			if stack != null and stack.id == id:
				p.wear_relic(i)
				break
	check_eq(p.relics.size(), 3, "three slots, no more")
	check(p.inventory.count("relic_luckstone") == 1, "the fourth stays in the pack")
	p.health = 100.0
	p._invulnerable = 0.0
	p.hurt(20.0, p.global_position + Vector2(100, 0))
	check_eq(p.health, 85.0, "the Bulwark Sigil takes a quarter off")
	check(p.remove_relic("relic_bulwark"), "taken off again")
	check(p.inventory.count("relic_bulwark") == 1, "back in the pack")
	var saved := p.to_dict()
	p.relics.clear()
	p.from_dict(saved)
	check_eq(p.relics, ["relic_swiftroot", "relic_featherbone"] as Array[String], "relics are saved")
	level.free()


func test_the_dark_tide_raises_the_dead_except_by_the_light() -> void:
	var level := _make_level()
	var p := level.player
	var director := level.director
	for enemy in Engine.get_main_loop().get_nodes_in_group("enemies"):
		enemy.free()
	director.start_tide()
	check(director.tide, "the tide is up")
	for i in 10:
		director._raise_the_dead()
	var risen := 0
	for enemy in Engine.get_main_loop().get_nodes_in_group("enemies"):
		if enemy.get_meta("tide", false):
			risen += 1
			check(enemy.is_undead(), "only the dead rise")
	check(risen >= 1 and risen <= 5, "the dead rise around you, a handful at a time (%d)" % risen)
	for enemy in Engine.get_main_loop().get_nodes_in_group("enemies"):
		enemy.free()
	# A ring of lit torches: sanctuary.
	var here := World.cell_of(p.global_position)
	for dx in [-10, -5, 0, 5, 10]:
		level.world.add_object(here + Vector2i(dx, -1), {"type": "torch", "lit": true})
	for i in 10:
		director._raise_the_dead()
	check_eq(Engine.get_main_loop().get_nodes_in_group("enemies").size(), 0, "nothing rises by the light")
	p.glow = 5.0
	director.end_tide()
	check(not director.tide and p.glow == p.max_glow(), "dawn ends it and fills the lantern")
	level.free()


func test_fishing_casts_waits_for_a_bite_and_lands_a_catch() -> void:
	var level := _make_level()
	var p := level.player
	p.inventory.slots[0] = {"id": "fishing_rod", "count": 1}
	p.hotbar_index = 0
	p._refresh_held()
	var cell := World.cell_of(p.global_position) + Vector2i(2, 0)
	level.data.set_tile(cell.x, cell.y, WorldData.AIR)
	level.data.liquids[level.data.idx(cell.x, cell.y)] = WorldData.WATER
	p.fish_at(cell)
	check(not p._fishing.is_empty(), "the line is in the water")
	# Striking too soon reels in with nothing.
	p.fish_at(cell)
	check(p._fishing.is_empty(), "too soon: reeled in empty")
	p.fish_at(cell)
	p._fishing.wait = 0.0
	p._update_fishing(0.016)
	check(p._fishing.bite > 0.0, "a bite: the bobber dips")
	var before := level.drop_layer.get_child_count()
	p.fish_at(cell)
	check(p._fishing.is_empty() and level.drop_layer.get_child_count() > before, "struck in time: a catch")
	# Deep water is where glowfin live.
	var deep_glowfin := 0.0
	var shallow_glowfin := 0.0
	for entry in p._catch_table(true):
		if entry[0] == "glowfin":
			deep_glowfin = entry[1]
	for entry in p._catch_table(false):
		if entry[0] == "glowfin":
			shallow_glowfin = entry[1]
	check(deep_glowfin > shallow_glowfin * 5.0, "glowfin are a deep-water catch")
	level.free()


func test_the_drowned_halls_are_flooded_with_air_pockets_and_a_shrine() -> void:
	var data := WorldData.new()
	data.generate(5150)
	check_eq(data.drowned.size(), 2, "two drowned halls")
	var hall: Rect2i = data.drowned[0]
	var wet := 0
	var pockets := 0
	for x in range(hall.position.x + 1, hall.end.x - 1):
		for y in range(hall.position.y + 5, hall.end.y - 1):
			if data.get_liquid(x, y) == WorldData.WATER:
				wet += 1
			elif not data.is_solid(x, y) and data.is_solid(x, y - 1):
				pockets += 1
	check(wet > 300, "mostly under water (%d cells)" % wet)
	check(pockets >= 2, "with air trapped under bells on the way down (%d)" % pockets)
	var shrine := Vector2i(hall.position.x + hall.size.x / 2, hall.end.y - 2)
	var chest: Dictionary = data.objects.get(data.idx(shrine.x, shrine.y), {})
	check_eq(chest.get("type", ""), "relic_chest", "the sunken shrine")
	check(chest.get("loot", []).any(func(s): return s.id == "relic_tidecaller"), "keeps the Tidecaller's Scale")
	check(data.in_drowned_halls(shrine), "and the place knows its name")


func test_breath_runs_out_under_water_unless_you_wear_the_scale() -> void:
	var level := _make_level()
	var p := level.player
	var head := World.cell_of(p.global_position + Vector2(0, -170))
	for dy in range(-1, 3):
		level.data.set_tile(head.x, head.y + dy, WorldData.AIR)
		level.data.liquids[level.data.idx(head.x, head.y + dy)] = WorldData.WATER
	var hp := p.health
	for i in 60 * 12:
		p._breathe(1.0 / 60.0)
	check_eq(p.breath, 0.0, "twelve seconds under: no air left")
	check(p.health < hp, "and drowning hurts")
	p.health = hp
	p.relics.append("relic_tidecaller")
	p.breath = Player.BREATH
	for i in 60 * 12:
		p._breathe(1.0 / 60.0)
	check_eq(p.breath, Player.BREATH, "the Scale: water is air")
	check_eq(p.health, hp, "and no harm")
	level.free()


func test_biters_keep_to_the_water() -> void:
	var level := _make_level()
	var hall: Rect2i = level.data.drowned[0]
	# A cell in the top row of the water, with air above it.
	var top := Vector2i(hall.position.x + 3, hall.position.y + 4)
	check_eq(level.data.get_liquid(top.x, top.y), WorldData.WATER, "the water line")
	check(level.data.get_liquid(top.x, top.y - 1) == WorldData.DRY, "with air above")
	var biter := level.spawn_enemy("biter", World.centre_of(top) + Vector2(0, 40))
	check_eq(biter.spec.mode, Enemy.Mode.SWIM, "a swimmer")
	biter.velocity = Vector2(0, -400)  # heading for the surface
	biter._swim(1.0 / 60.0, Vector2(0, -600), false)
	check(biter.velocity.y > 0.0, "turns back down rather than leave the water")
	level.free()
