extends TestCase
## Regional weather: each region draws from its own table, a spell eases in,
## rain thickens the fog and dims the sun, and storms throw lightning.


func test_tables_are_regional() -> void:
	var w := Weather3D.new()
	for i in 60:
		var k := w._draw(TerrainGen.Biome.SNOW)
		check(k in [Weather3D.Kind.SNOW, Weather3D.Kind.BLIZZARD, Weather3D.Kind.CLEAR], "Frostpeaks only snows or clears")
		var a := w._draw(TerrainGen.Biome.VOLCANIC)
		check(a in [Weather3D.Kind.ASHFALL, Weather3D.Kind.CLEAR], "the Ashlands rain ash")
	w.free()


func test_rain_darkens_and_storm_flashes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var base_fog: float = main.environment.fog_density
	main.weather.force(Weather3D.Kind.STORM)
	main.weather._bolt_in = 0.0
	var flashed := false
	for i in 30:
		await tree.process_frame
		if main.weather.flash > 0.0:
			flashed = true
	check(main.environment.fog_density > base_fog + 0.003, "a storm thickens the air")
	check(main.weather.sun_mul < 0.5, "and dims the sun")
	check(flashed, "and throws lightning")
	check((main.weather._fx.rain as CPUParticles3D).emitting, "rain falls")
	main.weather.force(Weather3D.Kind.SNOW)
	await tree.process_frame
	check(not (main.weather._fx.rain as CPUParticles3D).emitting, "snow replaces rain")
	check((main.weather._fx.snow as CPUParticles3D).emitting, "snow falls")
	main.queue_free()
	await tree.process_frame
