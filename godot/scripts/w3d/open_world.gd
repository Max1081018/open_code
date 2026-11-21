class_name OpenWorld
extends Node3D
## The open world, streamed around the player in 64 m chunks. Near chunks
## are full detail with colliders, trunk/boulder collision and grass; middle
## ones medium detail with trees; far ones coarse terrain only. Chunks are
## built on worker threads (ChunkBuilder) and swapped in a couple per frame,
## so walking never hitches. What the player changed (felled trees, mined
## rocks) is remembered and applied whenever a chunk is rebuilt.

signal resource_broken(kind: String, at: Vector3)

const SIZE := ChunkBuilder.SIZE
## Chunk rings for each level of detail (Chebyshev distance in chunks).
var rings := [1, 3, 5]
var gen: TerrainGen
var focus := Vector3.ZERO
## "cx,cz,i" -> true for flora removed by the player (saved).
var removed := {}
## "cx,cz,i" -> damage taken so far.
var _damage := {}

var _chunks := {}         ## coord -> {lod, node, flora}
var _pending := {}        ## coord -> lod being built
var _results: Array = []
var _mutex := Mutex.new()
var _timer := 0.0
var _material: ShaderMaterial


func setup(the_seed: int) -> void:
	gen = TerrainGen.new(the_seed)
	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/shaders/terrain3d.gdshader")
	for t in ["grass", "soil", "rock", "snow", "sand"]:
		_material.set_shader_parameter(t + "_tex", load("res://assets/textures/terrain/%s.jpg" % t))
	match Settings.quality if "quality" in Settings else 2:
		0:
			rings = [1, 2, 3]
		1:
			rings = [1, 2, 4]
	_build_horizon()


## The whole island as one coarse mesh (24 m cells), drawn only beyond the
## streamed rings: distant mountains and coasts are always on the horizon.
func _build_horizon() -> void:
	var cell := 24.0
	var half := TerrainGen.HALF + 200.0
	var n := int(half * 2.0 / cell) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = gen.height(-half + i * cell, -half + j * cell)
	for j in n:
		for i in n:
			var x := -half + i * cell
			var z := -half + j * cell
			var h := heights[j * n + i]
			var nor := gen.normal(x, z, cell)
			var b := gen.biome(x, z)
			st.set_normal(nor)
			st.set_color(gen.splat(x, z, h, nor, b))
			var t := gen.tint(b)
			st.set_uv(Vector2(x, z))
			st.set_uv2(Vector2((t.r + t.g + t.b) / 3.0, t.a))
			st.add_vertex(Vector3(x, h - 0.6, z))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("cull_radius", SIZE * (rings[rings.size() - 1] - 0.5))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	add_child(mi)
	_horizon = mi


var _horizon: MeshInstance3D


func height_at(x: float, z: float) -> float:
	return gen.height(x, z)


func coord_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / SIZE), floori(p.z / SIZE))


## Build everything around `at` now, blocking (start of the game, tests).
func warm(at: Vector3) -> void:
	focus = at
	var centre := coord_of(at)
	for dz in range(-rings[1], rings[1] + 1):
		for dx in range(-rings[1], rings[1] + 1):
			var c := centre + Vector2i(dx, dz)
			var lod := _lod_for(c, centre)
			_apply(ChunkBuilder.build(gen, c, lod, lod == 0))
	_update(true)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_reap_tasks()
		_update(false)
	# Swap in finished chunks, two per frame at most.
	for i in 2:
		_mutex.lock()
		var r = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if r == null:
			break
		_pending.erase(r.coord)
		_apply(r)


func _lod_for(c: Vector2i, centre: Vector2i) -> int:
	var d := maxi(absi(c.x - centre.x), absi(c.y - centre.y))
	for lod in rings.size():
		if d <= rings[lod]:
			return lod
	return -1


func _update(_now: bool) -> void:
	var centre := coord_of(focus)
	var far: int = rings[rings.size() - 1]
	var wanted := {}
	for dz in range(-far, far + 1):
		for dx in range(-far, far + 1):
			var c := centre + Vector2i(dx, dz)
			var lod := _lod_for(c, centre)
			if lod < 0:
				continue
			wanted[c] = lod
			var have = _chunks.get(c)
			if (have == null or have.lod != lod) and _pending.get(c, -1) != lod:
				_pending[c] = lod
				_tasks.append(WorkerThreadPool.add_task(_build_task.bind(c, lod)))
	for c in _chunks.keys():
		if not wanted.has(c):
			_chunks[c].node.queue_free()
			_chunks.erase(c)


## Builds still running on worker threads: waited for on exit so none
## writes into a freed world (that corrupted the heap at quit).
var _tasks: Array[int] = []


## Runs on a worker thread: build one chunk and queue it for the main thread.
func _build_task(c: Vector2i, lod: int) -> void:
	var r := ChunkBuilder.build(gen, c, lod, lod == 0)
	_mutex.lock()
	_results.append(r)
	_mutex.unlock()


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	FoliageLib.release()


func _reap_tasks() -> void:
	var keep: Array[int] = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			keep.append(t)
	_tasks = keep


func _apply(r: Dictionary) -> void:
	var c: Vector2i = r.coord
	var centre := coord_of(focus)
	if _lod_for(c, centre) != r.lod:
		return  # the player moved on while it was building
	if _chunks.has(c):
		_chunks[c].node.queue_free()
	var node := Node3D.new()
	node.position = Vector3(c.x * SIZE, 0, c.y * SIZE)
	add_child(node)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r.arrays)
	var terrain := MeshInstance3D.new()
	terrain.mesh = mesh
	terrain.material_override = _material
	node.add_child(terrain)
	var entry := {"lod": r.lod, "node": node, "flora": r.get("flora", [])}
	_chunks[c] = entry
	if r.lod == 0:
		_add_collider(node, r)
	_build_flora(c, entry)
	if r.has("grass"):
		for kind in r.grass:
			_multimesh(node, kind, r.grass[kind], false)


func _add_collider(node: Node3D, r: Dictionary) -> void:
	var steps: int = r.steps
	var spacing := SIZE / steps
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = steps + 1
	shape.map_depth = steps + 1
	shape.map_data = r.heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# The height map is centred on its node and one unit per cell.
	cs.position = Vector3(SIZE * 0.5, 0, SIZE * 0.5)
	cs.scale = Vector3(spacing, 1, spacing)
	body.add_child(cs)
	node.add_child(body)


## Trees, rocks and plants of one chunk as MultiMeshes, minus what the player
## removed; trunks and boulders of near chunks get colliders.
func _build_flora(c: Vector2i, entry: Dictionary) -> void:
	var node: Node3D = entry.node
	for old in node.get_children():
		if old.has_meta("flora"):
			old.queue_free()
	var by_kind := {}
	var solid := StaticBody3D.new()
	solid.set_meta("flora", true)
	solid.collision_layer = 1
	var flora: Array = entry.flora
	for i in flora.size():
		var rec: Dictionary = flora[i]
		if removed.has(_key(c, i)):
			continue
		var t := Transform3D(Basis(Vector3.UP, rec.yaw).scaled(Vector3.ONE * rec.scale), rec.pos)
		if not by_kind.has(rec.kind):
			by_kind[rec.kind] = []
		by_kind[rec.kind].append(t)
		if entry.lod == 0:
			var cat := FoliageLib.category(rec.kind)
			if cat == "tree" or cat == "rock":
				var cs := CollisionShape3D.new()
				if cat == "tree":
					var cyl := CylinderShape3D.new()
					cyl.radius = 0.35 * rec.scale
					cyl.height = 6.0
					cs.shape = cyl
					cs.position = rec.pos - node.position + Vector3(0, 3.0, 0)
				else:
					var sphere := SphereShape3D.new()
					sphere.radius = 0.75 * rec.scale
					cs.shape = sphere
					cs.position = rec.pos - node.position + Vector3(0, 0.45, 0)
				solid.add_child(cs)
	if solid.get_child_count() > 0:
		node.add_child(solid)
	else:
		solid.free()
	for kind in by_kind:
		_multimesh(node, kind, by_kind[kind], true)


func _multimesh(node: Node3D, kind: String, transforms: Array, flora: bool) -> void:
	for part in FoliageLib.parts(kind):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var world_t: Transform3D = transforms[i]
			mm.set_instance_transform(i, Transform3D(world_t.basis, world_t.origin - node.position) * part[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if flora:
			mmi.set_meta("flora", true)
		# Grass and small plants fade out with distance on weak settings.
		if not flora or FoliageLib.category(kind) == "small":
			mmi.visibility_range_end = 70.0
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


static func _key(c: Vector2i, i: int) -> String:
	return "%d,%d,%d" % [c.x, c.y, i]


## The nearest tree or rock within `reach` of `at`, roughly in front:
## {coord, index, kind, category, pos} or {}.
func nearest_resource(at: Vector3, forward: Vector3, reach := 2.6) -> Dictionary:
	var best := {}
	var best_d := reach
	var centre := coord_of(at)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var c := centre + Vector2i(dx, dz)
			var entry = _chunks.get(c)
			if entry == null:
				continue
			var flora: Array = entry.flora
			for i in flora.size():
				var rec: Dictionary = flora[i]
				var cat := FoliageLib.category(rec.kind)
				if cat != "tree" and cat != "rock":
					continue
				if removed.has(_key(c, i)):
					continue
				var to: Vector3 = rec.pos - at
				to.y = 0
				var d: float = to.length() - (0.35 if cat == "tree" else 0.8) * float(rec.scale)
				if d < best_d and (to.length() < 0.6 or to.normalized().dot(forward) > 0.2):
					best_d = d
					best = {"coord": c, "index": i, "kind": rec.kind, "category": cat, "pos": rec.pos,
						"scale": rec.scale, "yaw": rec.yaw}
	return best


## Strike a resource; returns true when it breaks (and is removed).
func hit_resource(res: Dictionary, damage: float) -> bool:
	var key := _key(res.coord, res.index)
	var health: float = (5.0 if res.category == "tree" else 6.0) * float(res.scale)
	_damage[key] = _damage.get(key, 0.0) + damage
	if _damage[key] < health:
		return false
	removed[key] = true
	_damage.erase(key)
	var entry = _chunks.get(res.coord)
	if entry:
		_build_flora(res.coord, entry)
	resource_broken.emit(res.kind, res.pos)
	return true


func biome_at(p: Vector3) -> int:
	return gen.biome(p.x, p.z)
