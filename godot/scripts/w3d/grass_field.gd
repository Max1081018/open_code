class_name GrassField
extends Node3D
## A dense field of grass that follows the heroine: square tiles of blade
## clumps (one MultiMesh each), recycled as she moves and built on worker
## threads. Clumps take the ground's height from a coarse grid per tile,
## keep off roads, water, steep slopes and biomes without grass, and are
## tinted to the biome. The look is in grass_blades.gdshader.

const TILE := 12.0

var gen: TerrainGen
var radius_tiles := 3          ## tiles out from the centre one
var density := 2.0             ## clumps per square metre
var focus := Vector3.ZERO
var _tiles := {}               ## Vector2i -> MultiMeshInstance3D (meta "level")
## Density by ring from the centre tile: full near, thinner toward the edge.
const LEVELS := [1.0, 1.0, 0.6, 0.35]
var _pending := {}
var _results: Array = []
var _tasks: Array[int] = []
var _mutex := Mutex.new()
var _material: ShaderMaterial
var _clump: ArrayMesh
var _flower: ArrayMesh
var _flower_mat: ShaderMaterial
## Wildflower colours: white, buttercup, rose, sky blue, lilac.
const PETALS := [Color(0.92, 0.92, 0.88), Color(1.0, 0.72, 0.08), Color(0.95, 0.32, 0.55), Color(0.3, 0.52, 1.0), Color(0.62, 0.38, 0.95)]
var _timer := 0.0


func setup(the_gen: TerrainGen, quality: int) -> void:
	gen = the_gen
	radius_tiles = 3 if quality >= 2 else 2
	density = 3.2 if quality >= 2 else 2.0
	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/shaders/grass_blades.gdshader")
	_material.set_shader_parameter("field_radius", TILE * (radius_tiles + 0.5))
	_clump = _make_clump()
	_clump.surface_set_material(0, _material)
	_flower_mat = _material.duplicate() as ShaderMaterial
	_flower_mat.set_shader_parameter("flower_mode", true)
	_flower = _make_flower()
	_flower.surface_set_material(0, _flower_mat)


## Five tapered, slightly curved blades round a point; UV.y is 0 at the
## root and 1 at the tip.
static func _make_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 7:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.14)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face)) * 0.024
		var lean := Vector3(-sin(face), 0, cos(face)) * rng.randf_range(0.05, 0.16)
		var h := rng.randf_range(0.32, 0.6)
		var p0 := off - side
		var p1 := off + side
		var m0 := off - side * 0.65 + lean * 0.35 + Vector3(0, h * 0.55, 0)
		var m1 := off + side * 0.65 + lean * 0.35 + Vector3(0, h * 0.55, 0)
		var t := off + lean + Vector3(0, h, 0)
		var quads := [[p0, 0.0], [p1, 0.0], [m1, 0.55], [m0, 0.55]]
		# Lower quad as two triangles, then the tip.
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for i in tri:
				st.set_uv(Vector2(0.0, quads[i][1]))
				st.add_vertex(quads[i][0])
		st.set_uv(Vector2(0, 0.55))
		st.add_vertex(m0)
		st.set_uv(Vector2(0, 0.55))
		st.add_vertex(m1)
		st.set_uv(Vector2(0, 1.0))
		st.add_vertex(t)
	st.generate_normals()
	return st.commit()


## A wildflower: a thin curved stem and a six-petal head facing up-ish.
static func _make_flower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.62
	var w := Vector3(0.014, 0, 0)
	var bend := Vector3(0, 0, 0.05)
	for tri in [[-w, 0.0, w, 0.0, bend + Vector3(0, h, 0), 0.92]]:
		st.set_uv(Vector2(0, tri[1]))
		st.add_vertex(tri[0])
		st.set_uv(Vector2(0, tri[3]))
		st.add_vertex(tri[2])
		st.set_uv(Vector2(0, tri[5]))
		st.add_vertex(tri[4])
	var c := bend + Vector3(0, h, 0)
	var r := 0.1
	# A five-petal star: tips at r, notches at 0.45 r; the centre vertex
	# is marked (UV.y 1) so the shader can paint a golden eye.
	var ring: Array = []
	for k in 10:
		var a := TAU * k / 10.0
		var rr := r if k % 2 == 0 else r * 0.45
		ring.append(c + Vector3(cos(a) * rr, 0.012, sin(a) * rr * 0.9))
	for k in 10:
		st.set_uv(Vector2(1, 1.0))
		st.add_vertex(c + Vector3(0, 0.02, 0))
		st.set_uv(Vector2(1, 0.9))
		st.add_vertex(ring[k])
		st.set_uv(Vector2(1, 0.9))
		st.add_vertex(ring[(k + 1) % 10])
	st.generate_normals()
	return st.commit()


func _process(delta: float) -> void:
	_material.set_shader_parameter("field_centre", focus)
	_flower_mat.set_shader_parameter("field_centre", focus)
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.2
		_reap()
		_update()
	for i in 3:
		_mutex.lock()
		var r = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if r == null:
			break
		_apply(r)


func set_player(p: Vector3) -> void:
	focus = p
	if _material:
		_material.set_shader_parameter("player_pos", p)
		_flower_mat.set_shader_parameter("player_pos", p)


func _coord(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))


func _update() -> void:
	var c := _coord(focus)
	var wanted := {}
	for dz in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			var t := c + Vector2i(dx, dz)
			var level := mini(maxi(absi(dx), absi(dz)), LEVELS.size() - 1)
			wanted[t] = true
			var have: int = (_tiles[t] as Node).get_meta("level", -1) if _tiles.has(t) else -1
			if have != level and _pending.get(t, -1) != level:
				_pending[t] = level
				_tasks.append(WorkerThreadPool.add_task(_build_task.bind(t, level)))
	for t in _tiles.keys():
		if not wanted.has(t):
			(_tiles[t] as Node).queue_free()
			_tiles.erase(t)


## Worker thread: the clump transforms and colours of one tile.
func _build_task(t: Vector2i, level: int) -> void:
	var r := build_tile(gen, t, density * LEVELS[level])
	r.level = level
	_mutex.lock()
	_results.append(r)
	_mutex.unlock()


static func build_tile(g: TerrainGen, t: Vector2i, per_m2: float) -> Dictionary:
	var origin := Vector2(t.x * TILE, t.y * TILE)
	# Heights on a 7x7 grid, interpolated for each clump.
	var n := 7
	var step := TILE / (n - 1)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = g.height(origin.x + i * step, origin.y + j * step)
	var biome := g.biome(origin.x + TILE * 0.5, origin.y + TILE * 0.5)
	var root := _root_colour(biome)
	var xforms: Array = []
	var colours: Array = []
	var flowers: Array = []
	var petals: Array = []
	# Open meadows bloom more than the woods.
	var bloom := 0.2 - g.forest(origin.x + TILE * 0.5, origin.y + TILE * 0.5) * 0.14
	if root.a > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([t.x, t.y, "blades"])
		var count := int(TILE * TILE * per_m2)
		for k in count:
			var fx := rng.randf()
			var fz := rng.randf()
			var gx := fx * (n - 1)
			var gz := fz * (n - 1)
			var i := mini(int(gx), n - 2)
			var j := mini(int(gz), n - 2)
			var ax := gx - i
			var az := gz - j
			var h00 := hs[j * n + i]
			var h10 := hs[j * n + i + 1]
			var h01 := hs[(j + 1) * n + i]
			var h11 := hs[(j + 1) * n + i + 1]
			var h := lerpf(lerpf(h00, h10, ax), lerpf(h01, h11, ax), az)
			if h < TerrainGen.WATER + 0.6:
				continue
			var slope := maxf(absf(h10 - h00), absf(h01 - h00)) / step
			if slope > 0.55:
				continue
			var x := origin.x + fx * TILE
			var z := origin.y + fz * TILE
			if g.paved(x, z) > 0.05:
				continue
			var s := rng.randf_range(0.75, 1.35)
			xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s)),
				Vector3(x, h - 0.03, z)))
			var v := rng.randf_range(-0.06, 0.06)
			colours.append(Color(root.r + v, root.g + v, root.b + v * 0.5))
			if biome == TerrainGen.Biome.FOREST and rng.randf() < bloom:
				# Wildflowers come in little patches of one colour.
				var pick: int = absi(hash([floori(x / 3.0), floori(z / 3.0)])) % PETALS.size()
				var fs := rng.randf_range(0.8, 1.25)
				flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)),
					Vector3(x + 0.1, h - 0.03, z)))
				petals.append(PETALS[pick])
	return {"tile": t, "xforms": xforms, "colours": colours, "flowers": flowers, "petals": petals}


## Root colour by biome; alpha 0 where no meadow grass grows.
static func _root_colour(b: int) -> Color:
	match b:
		TerrainGen.Biome.FOREST:
			return Color(0.36, 0.56, 0.22, 1)
		TerrainGen.Biome.DARK_FOREST:
			return Color(0.22, 0.38, 0.22, 1)
		TerrainGen.Biome.CORRUPTED:
			return Color(0.36, 0.32, 0.4, 1)
	return Color(0, 0, 0, 0)


func _apply(r: Dictionary) -> void:
	var t: Vector2i = r.tile
	if _pending.get(t, -1) == r.get("level", -2):
		_pending.erase(t)
	if _coord(focus).distance_to(t) > radius_tiles + 1.5:
		return
	var xforms: Array = r.xforms
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _clump
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, r.colours[i])
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("level", r.get("level", 0))
	add_child(mmi)
	var fl: Array = r.get("flowers", [])
	if not fl.is_empty():
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.use_colors = true
		fm.mesh = _flower
		fm.instance_count = fl.size()
		for i in fl.size():
			fm.set_instance_transform(i, fl[i])
			fm.set_instance_color(i, r.petals[i])
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_child(fmi)
	if _tiles.has(t):
		(_tiles[t] as Node).queue_free()
	_tiles[t] = mmi


func _reap() -> void:
	var keep: Array[int] = []
	for id in _tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			keep.append(id)
	_tasks = keep


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


## Build every tile around `at` now (start of the game, captures).
func warm(at: Vector3) -> void:
	focus = at
	var c := _coord(at)
	for dz in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			var level := mini(maxi(absi(dx), absi(dz)), LEVELS.size() - 1)
			var r := build_tile(gen, c + Vector2i(dx, dz), density * LEVELS[level])
			r.level = level
			_apply(r)
	set_player(at)
