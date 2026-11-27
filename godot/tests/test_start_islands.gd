extends TestCase
## The three starting lands each have their own spawn on dry ground in the
## right region, and the game spawns the heroine where the profile says.


func test_spawn_points_are_in_their_lands() -> void:
	var gen := TerrainGen.new(1337)
	var j := Realms.spawn_point(gen, "jungle")
	check(gen.biome(j.x, j.z) == TerrainGen.Biome.JUNGLE, "the jungle start is in the Great Jungle")
	check(j.y > TerrainGen.WATER + 1.0, "on dry ground")
	var c := Realms.spawn_point(gen, "coast")
	check(gen.biome(c.x, c.z) in [TerrainGen.Biome.CRYSTAL, TerrainGen.Biome.BEACH], "the coast start is on the Crystal Coast")
	var s := Realms.spawn_point(gen, "sky")
	var isle: Array = Realms.sky_isles(gen)[0]
	check(s.y > (isle[0] as Vector3).y - 1.0, "the Skybound start is up on the main isle")
	check(gen.biome(-1500, -250) == TerrainGen.Biome.DRY, "the heart of the Sunscar Sea is desert")
	check(gen.biome(600, 900) != TerrainGen.Biome.DRY, "and there are no stray desert patches elsewhere")


func test_game_spawns_at_the_chosen_island() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	Account.sign_out()
	Account.sign_in_guest()
	if FileAccess.file_exists(Save3D.path()):
		DirAccess.remove_absolute(Save3D.path())
	Account.set_start_island("sky")
	Save3D.load_on_start = false
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	for i in 20:
		await tree.physics_frame
	var p: Vector3 = main.player.global_position
	var isle: Array = Realms.sky_isles(main.world.gen)[0]
	var c: Vector3 = isle[0]
	check(Vector2(p.x - c.x, p.z - c.z).length() < float(isle[1]), "she starts on Skybound's main isle")
	check(p.y > c.y - 3.0, "standing on it, not fallen through")
	check(main.world.biome_at(p) == TerrainGen.Biome.SKY, "the region reads as Skybound Isle")
	check(main.start_island == "sky", "the game knows the start")
	check(Save3D.capture(main).start_island == "sky", "and saves it")
	main.queue_free()
	await tree.process_frame
	Account.set_start_island("")
	Account.sign_out()
