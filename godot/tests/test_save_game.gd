extends TestCase
## Saving and loading through the real Level, not just the data layer.


func _make_level(seed_value: int, saved := {}) -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(seed_value, saved)
	return level


func test_a_saved_game_comes_back_exactly() -> void:
	Game.delete_save()
	var level := _make_level(4242)
	var player := level.player

	# Change things the player would change.
	player.inventory.add("iron_pickaxe", 1)
	player.inventory.add("glowshard", 17)
	player.lantern_tier = 1
	player.glow = 63.0
	player.health = 55.0
	var dug := Vector2i(level.data.spawn.x + 3, level.data.spawn.y + 1)
	level.world.set_block(dug, WorldData.AIR)
	var built := Vector2i(level.data.spawn.x - 2, level.data.spawn.y)
	level.world.add_object(built, {"type": "torch"})
	player.global_position += Vector2(256, 0)
	level.world.time_of_day = 0.81

	check(level.save(), "save succeeded")
	var expected_position := player.global_position
	var expected_tiles := level.data.tiles
	level.free()

	var saved := Game.load_game()
	check(not saved.is_empty(), "save file read back")
	var loaded := _make_level(0, saved)
	var p := loaded.player
	check_eq(p.inventory.count("iron_pickaxe"), 1, "tools kept")
	check_eq(p.inventory.count("glowshard"), 17, "materials kept")
	check_eq(p.lantern_tier, 1, "lantern tier kept")
	check_near(p.glow, 63.0, 0.01, "lantern oil kept")
	check_near(p.health, 55.0, 0.01, "health kept")
	check(p.global_position.distance_to(expected_position) < 1.0, "position kept")
	check(loaded.data.tiles == expected_tiles, "every tile kept, including the dug one")
	check_eq(loaded.data.get_tile(dug.x, dug.y), WorldData.AIR, "the dug cell is still open")
	check_eq(loaded.world.object_at(built).get("type", ""), "torch", "the placed torch is still there")
	check_near(loaded.world.time_of_day, 0.81, 0.001, "time of day kept")
	loaded.free()
	Game.delete_save()


func test_a_corrupt_save_is_refused_rather_than_crashing() -> void:
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string("this is not a save file")
	file.close()
	var saved := Game.load_game()
	check(saved.is_empty(), "garbage is rejected")
	Game.delete_save()


func test_saving_while_dead_is_refused() -> void:
	# Saving a corpse would load straight into a death loop.
	Game.delete_save()
	var level := _make_level(77)
	level.player.health = 0.0
	level.player._dead = true
	check(not level.save(), "no save while dead")
	check(not Game.has_save(), "nothing written")
	level.free()
