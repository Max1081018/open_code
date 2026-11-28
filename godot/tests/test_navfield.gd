extends TestCase
## Recast navigation: a window of ground is baked around the heroine off the
## main thread, paths go around solid trees and rocks, and foes use it.


func test_navmesh_bakes_and_paths() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var nav: NavField = main.nav
	for i in 600:
		if nav.bakes > 0:
			break
		await tree.process_frame
	check(nav.bakes > 0, "a navmesh window was baked around her")
	print("    nav bake: %.0f ms (worker thread)" % nav.last_bake_ms)
	var nm := nav.region.navigation_mesh
	check(nm != null and nm.get_polygon_count() > 20, "the baked window has walkable polygons")
	# Let the map sync (a few frames under load), then ask for a path
	# across the window.
	var p: Vector3 = main.player.global_position
	var map: RID = main.get_world_3d().navigation_map
	var to := p + Vector3(18, 0, 14)
	to.y = main.world.height_at(to.x, to.z)
	var path := PackedVector3Array()
	for i in 30:
		await tree.physics_frame
		path = NavigationServer3D.map_get_path(map, p, to, true)
		if path.size() >= 2:
			break
	check(path.size() >= 2, "a path is found across the baked ground")
	if path.size() >= 2:
		check(path[path.size() - 1].distance_to(to) < 3.0, "the path reaches the goal")
	var cache := {}
	var d := nav.path_dir(p, to, cache)
	check_near(d.length(), 1.0, 0.01, "path_dir gives a unit direction")
	check(not nav.ready_near(p + Vector3(500, 0, 500)), "far outside the window foes walk straight")
	main.queue_free()
	await tree.process_frame
