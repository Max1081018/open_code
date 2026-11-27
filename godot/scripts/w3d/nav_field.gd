class_name NavField
extends Node3D
## Recast navigation around the heroine. The open world is far too large to
## bake whole, so a SPAN-wide window of ground is baked on a worker thread
## wherever she is and re-baked when she has moved REBAKE metres:
##   - ground triangles come straight from the height field (no scene parsing)
##   - water and lava lakes (below the waterline) are left out
##   - tree trunks, boulders and stone formations are carved out as obstacles
## Foes ask it for a path (`path_dir`) and fall back to walking straight when
## they are outside the window or no bake has finished yet.

const SPAN := 112.0
const STEP := 2.0
const REBAKE := 28.0

var world: OpenWorld
var region: NavigationRegion3D
var centre := Vector3(INF, 0, INF)
var bakes := 0
var last_bake_ms := 0.0
var _busy := false
var _started := 0
var _task := -1


func setup(the_world: OpenWorld) -> void:
	world = the_world
	region = NavigationRegion3D.new()
	add_child(region)


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if world == null or _busy:
		return
	var p: Vector3 = world.focus
	if Vector2(p.x - centre.x, p.z - centre.z).length() > REBAKE:
		bake_at(p)


func ready_near(p: Vector3) -> bool:
	return bakes > 0 and absf(p.x - centre.x) < SPAN * 0.5 - 2.0 and absf(p.z - centre.z) < SPAN * 0.5 - 2.0


func bake_at(p: Vector3) -> void:
	centre = Vector3(snappedf(p.x, STEP), 0, snappedf(p.z, STEP))
	_busy = true
	_started = Time.get_ticks_usec()
	var obstacles := _obstacles(centre)
	_task = WorkerThreadPool.add_task(_build.bind(world.gen, centre, obstacles), false, "navfield")


## [x, y, z, radius, height] of every solid trunk and stone in the window.
func _obstacles(c: Vector3) -> Array:
	var out := []
	var half := SPAN * 0.5 + 4.0
	var cc := world.coord_of(c)
	var reach := int(ceil(half / OpenWorld.SIZE)) + 1
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := Vector2i(cc.x + dx, cc.y + dz)
			if not world._chunks.has(key):
				continue
			var flora: Array = world._chunks[key].flora
			for i in flora.size():
				var rec: Dictionary = flora[i]
				var pos: Vector3 = rec.pos
				if absf(pos.x - c.x) > half or absf(pos.z - c.z) > half:
					continue
				var cat := FoliageLib.category(rec.kind)
				if cat != "tree" and cat != "rock" and cat != "formation":
					continue
				if world.removed.has("%d,%d,%d" % [key.x, key.y, i]):
					continue
				var r: float = FoliageLib.solid_radius(rec.kind) * float(rec.scale)
				if r < 0.25:
					continue
				out.append([pos.x, pos.y, pos.z, r, 6.0])
	return out


## Worker thread: ground faces + obstacles -> source geometry.
func _build(gen: TerrainGen, c: Vector3, obstacles: Array) -> void:
	var n := int(SPAN / STEP)
	var x0 := c.x - SPAN * 0.5
	var z0 := c.z - SPAN * 0.5
	var h := PackedFloat32Array()
	h.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			h[j * (n + 1) + i] = gen.height(x0 + i * STEP, z0 + j * STEP)
	var faces := PackedVector3Array()
	var dry := TerrainGen.WATER + 0.15
	for j in n:
		for i in n:
			var ha := h[j * (n + 1) + i]
			var hb := h[j * (n + 1) + i + 1]
			var hc := h[(j + 1) * (n + 1) + i]
			var hd := h[(j + 1) * (n + 1) + i + 1]
			if minf(minf(ha, hb), minf(hc, hd)) < dry:
				continue  # the sea, rivers and lava lakes are no place to walk
			var a := Vector3(x0 + i * STEP, ha, z0 + j * STEP)
			var b := Vector3(a.x + STEP, hb, a.z)
			var cc := Vector3(a.x, hc, a.z + STEP)
			var d := Vector3(a.x + STEP, hd, a.z + STEP)
			# Clockwise seen from above: Godot's front faces, normal up.
			faces.append_array([a, b, cc, b, d, cc])
	var src := NavigationMeshSourceGeometryData3D.new()
	src.add_faces(faces, Transform3D.IDENTITY)
	for o in obstacles:
		var ring := PackedVector3Array()
		var r: float = o[3] + 0.15
		for k in 8:
			var t := TAU * k / 8.0
			ring.append(Vector3(o[0] + cos(t) * r, 0, o[2] + sin(t) * r))
		src.add_projected_obstruction(ring, float(o[1]) - 1.0, float(o[4]), true)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.75
	nm.agent_max_slope = 42.0
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.6
	nm.detail_sample_distance = 8.0
	nm.filter_baking_aabb = AABB(Vector3(x0, -200, z0), Vector3(SPAN, 600, SPAN))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	call_deferred("_done", nm)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _done(nm: NavigationMesh) -> void:
	if not is_inside_tree():
		return
	region.navigation_mesh = nm
	bakes += 1
	last_bake_ms = (Time.get_ticks_usec() - _started) / 1000.0
	_busy = false


## Direction to walk from `from` toward `to` along the navmesh (flat, unit),
## or the straight line when there is no usable path.
func path_dir(from: Vector3, to: Vector3, cache: Dictionary) -> Vector3:
	var straight := Vector3(to.x - from.x, 0, to.z - from.z)
	if not ready_near(from):
		return straight.normalized()
	var now := Time.get_ticks_msec()
	if now >= int(cache.get("next", 0)) or not cache.has("path"):
		cache.next = now + 350 + randi() % 150
		var map := get_world_3d().navigation_map
		cache.path = NavigationServer3D.map_get_path(map, from, to, true)
		cache.i = 1
	var path: PackedVector3Array = cache.path
	var i: int = cache.get("i", 1)
	while i < path.size() and Vector2(path[i].x - from.x, path[i].z - from.z).length() < 0.9:
		i += 1
	cache.i = i
	if path.size() < 2 or i >= path.size():
		return straight.normalized()
	var d := Vector3(path[i].x - from.x, 0, path[i].z - from.z)
	return d.normalized() if d.length() > 0.05 else straight.normalized()
