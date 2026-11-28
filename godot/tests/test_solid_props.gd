extends TestCase
## Things she should bump into are solid (found by tests/audit_collision.gd,
## which walked rays at every solid-looking thing near each start and arena):
## the guardians' runestones, the rune shrines' stones, starlit chests, the
## sky bridges' rails, and the trees and crystals on the floating isles.


func _main() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	return main


## A ray at hip height from 3 m out toward `at` strikes something.
func _solid_at(main: Node, at: Vector3, height := 1.0) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for d: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
		var to := at + Vector3(0, height, 0)
		var q := PhysicsRayQueryParameters3D.create(to + d * 3.0, to, 1)
		if not space.intersect_ray(q).is_empty():
			return true
	return false


func test_props_are_solid() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = await _main()
	# Runestones round every guardian's arena.
	var stones := 0
	var solid_stones := 0
	for mi in main.bosses.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is ArrayMesh:
			stones += 1
			if _solid_at(main, (mi as Node3D).global_position, 1.2):
				solid_stones += 1
	check(stones >= 20, "the arenas have their runestones (%d)" % stones)
	check_eq(solid_stones, stones, "every runestone is solid")
	# Rune shrines' standing stones and the starlit chests.
	var sec: Secrets = main.secrets
	for sh in sec._shrines:
		for pillar: Node3D in sh[2]:
			check(_solid_at(main, pillar.global_position, 1.0), "a shrine stone is solid")
	for c in sec._chests:
		check(_solid_at(main, (c[1] as Node3D).global_position, 0.6), "a starlit chest is solid")
	# Sky bridges hold her in: the rails are solid.
	var rails := 0
	for body in main.realms.find_children("*", "StaticBody3D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				var size: Vector3 = ((cs as CollisionShape3D).shape as BoxShape3D).size
				if size.x < 0.2 and size.y > 1.0 and size.z > 4.0:
					rails += 1
	check(rails >= 10, "the sky bridges have solid rails both sides (%d)" % rails)
	# Floating isles: trees have trunks to bump into.
	var trunks := 0
	for body in main.islands.find_children("*", "StaticBody3D", true, false):
		for cs in body.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is CylinderShape3D:
				trunks += 1
	check(trunks >= 40, "trees and crystals on the floating isles are solid (%d)" % trunks)
	main.queue_free()
	await tree.process_frame
