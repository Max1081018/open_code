extends TestCase
## Collision audit (run on demand: tests/run.sh audit_collision): at each start
## (the town, the jungle, the sky isle, the coast), every solid-looking thing
## within 140 m, a mesh or a multimesh instance at least 1.2 m tall and
## 0.3 m across, is approached by rays from four sides at hip height. One
## that no ray strikes is reported, grouped by what built it.

const RADIUS := 56.0   ## within the near chunks, which always carry colliders


func test_audit() -> void:
	for start in ["", "jungle", "sky", "coast"]:
		await _audit(start)


func _audit(start: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not Account.signed_in():
		Account.sign_in_guest()
	Account.set_start_island(start)
	Save3D.load_on_start = false
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	for i in 30:
		await tree.physics_frame
	var centres: Array = [main.player.global_position]
	var island := start if start != "" else ""
	if island != "" and main.bosses and main.bosses.arenas.has(island):
		centres.append(main.bosses.arenas[island])
	for origin: Vector3 in centres:
		if origin != centres[0]:
			main.player.global_position = origin + Vector3(0, 2, 0)
			main.world.warm(origin)
			for i in 30:
				await tree.physics_frame
		await _scan(main, origin, start, origin == centres[0])
	main.queue_free()
	await tree.process_frame
	Account.set_start_island("")


func _scan(main: Node, origin: Vector3, start: String, at_start: bool) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var missing := {}
	var checked := 0
	for g in main.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree() or _skip(gi, main):
			continue
		var boxes := []
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			boxes.append(gi.global_transform * (gi as MeshInstance3D).mesh.get_aabb())
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			var local := mm.mesh.get_aabb()
			var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for k in mini(n, 4000):
				var it: Transform3D = gi.global_transform * mm.get_instance_transform(k)
				var b: AABB = it * local
				# Aim at the instance's own origin (a trunk), not the middle of
				# a lopsided canopy.
				b = AABB(Vector3(it.origin.x - b.size.x * 0.5, b.position.y, it.origin.z - b.size.z * 0.5), b.size)
				boxes.append(b)
		for box: AABB in boxes:
			var c := box.get_center()
			if Vector2(c.x - origin.x, c.z - origin.z).length() > RADIUS:
				continue
			if box.size.y < 1.2 or minf(box.size.x, box.size.z) < 0.3 or maxf(box.size.x, box.size.z) > 60.0:
				continue
			# Only what stands on the ground she walks on (not canopies, roof
			# ornaments or things hanging in the air).
			var ground = main.surface_y(Vector3(c.x, box.position.y + 1.0, c.z))
			if ground == null or absf(box.position.y - float(ground)) > 1.0:
				continue
			checked += 1
			if not _struck(space, box):
				var key := _owner(gi, main)
				var e: Array = missing.get(key, [0, c])
				e[0] += 1
				missing[key] = e
	print("AUDIT start=%s at=%s checked=%d without_collision_groups=%d" % [start if start != "" else "town", "spawn" if at_start else "arena", checked, missing.size()])
	var keys := missing.keys()
	keys.sort_custom(func(a, b): return missing[a][0] > missing[b][0])
	for k in keys.slice(0, 30):
		print("  NOCOLLIDE %4d  %s   e.g. at %s" % [missing[k][0], k, missing[k][1]])


## Rays from 2 m outside each side toward the middle, at hip height.
func _struck(space: PhysicsDirectSpaceState3D, box: AABB) -> bool:
	var c := box.get_center()
	var y := box.position.y + clampf(box.size.y * 0.35, 0.5, 1.2)
	var half := box.size * 0.5
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var reach := absf(d.x) * half.x + absf(d.z) * half.z + 2.0
		var from := Vector3(c.x, y, c.z) + d * reach
		var to := Vector3(c.x, y, c.z)
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return true
	return false


## Things that should be passable: characters, effects, plants, water, sky.
func _skip(gi: GeometryInstance3D, main: Node) -> bool:
	var n: Node = gi
	while n != null and n != main:
		if n is Player3D or n is Enemy3D or n is Npc3D or n is CPUParticles3D or n is GPUParticles3D:
			return true
		var s: Script = n.get_script()
		if s:
			var name := String(s.get_global_name())
			if name in ["GrassField", "Pickup3D", "Arcana", "SkyDome", "WeatherFx"]:
				return true
		n = n.get_parent()
	var mat := gi.material_override
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		var path := (mat as ShaderMaterial).shader.resource_path
		for word in ["grass", "water", "cloud", "waterfall", "pillar", "magic", "beam", "mist", "fog", "glow", "aurora", "light", "energy", "shaft", "sky", "rune", "foliage_leaf", "flame", "fire", "column", "updraft"]:
			if word in path:
				return true
	if mat is BaseMaterial3D and ((mat as BaseMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD or (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return true
	return false


## The nearest scripted ancestor, plus the mesh's name: what built it.
func _owner(gi: GeometryInstance3D, main: Node) -> String:
	var n: Node = gi.get_parent()
	var script_name := "?"
	while n != null and n != main:
		if n.get_script():
			script_name = String((n.get_script() as Script).get_global_name())
			if script_name == "":
				script_name = (n.get_script() as Script).resource_path.get_file()
			break
		n = n.get_parent()
	var mesh_name := ""
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
		mesh_name = (gi as MeshInstance3D).mesh.resource_name if (gi as MeshInstance3D).mesh.resource_name != "" else (gi as MeshInstance3D).mesh.get_class()
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		var mm := (gi as MultiMeshInstance3D).multimesh
		var m := mm.mesh
		mesh_name = "mm %s %s" % [m.resource_name if m else "-", str(m.get_aabb().size.snapped(Vector3.ONE * 0.1)) if m else ""]
	return "%s / %s" % [script_name, mesh_name.left(70)]
