extends TestCase
## Budgets for the code that runs every frame or several times a second.
## A desktop core is several times a phone's, so the limits leave room.


func _level() -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(9001)
	return level


func test_a_light_map_update_fits_a_phone_frame_budget() -> void:
	var level := _level()
	var world := level.world
	world._update_lighting()  # warm up
	var started := Time.get_ticks_usec()
	var runs := 20
	for i in runs:
		world._update_lighting()
	var ms := (Time.get_ticks_usec() - started) / 1000.0 / runs
	# Updated 6-20 times a second, not every frame; 4 ms on a desktop is
	# comfortably inside a phone's share of a 16.6 ms frame at that rate.
	print("  light map update: %.2f ms over a %s region" % [ms, world.light_map.region.size])
	check(ms < 4.0, "light update took %.2f ms" % ms)
	level.free()


func test_streaming_a_chunk_is_cheap() -> void:
	var level := _level()
	var world := level.world
	var started := Time.get_ticks_usec()
	var count := 0
	for cy in range(4, 12):
		for cx in range(4, 12):
			var chunk := Vector2i(cx, cy)
			if not world._loaded.has(chunk):
				world._load_chunk(chunk)
				count += 1
	var ms: float = (Time.get_ticks_usec() - started) / 1000.0 / max(count, 1)
	# Three chunks load per frame at most, so each must stay well under 3 ms.
	print("  chunk load: %.2f ms each" % ms)
	check(ms < 2.5, "one chunk took %.2f ms" % ms)
	level.free()


func test_a_burst_still_fires_after_its_pooled_emitter_was_freed() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var doomed := Node2D.new()
	root.add_child(doomed)
	Effects.burst(doomed, Vector2.ZERO, "splinters")
	var emitter: CPUParticles2D = doomed.get_child(0)
	Effects._retire(emitter, "splinters")  # finished: back in the pool, still parented
	doomed.free()                           # and then its parent goes away
	var other := Node2D.new()
	root.add_child(other)
	Effects.burst(other, Vector2.ZERO, "splinters")
	check_eq(other.get_child_count(), 1, "a fresh emitter fires in the new place")
	other.free()
