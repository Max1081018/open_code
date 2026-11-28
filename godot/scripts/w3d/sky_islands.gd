class_name SkyIslands
extends Node3D
## The floating isles of the Starfall: rock bodies hanging in the sky with
## grassy crowns, trees and crystal clusters, waterfalls pouring off their
## edges into mist, and the Starspire — a white crystal spire on the largest
## isle with a pillar of starlight rising from it. Their tops are solid, so a
## glider can land on them.

const ISLANDS := [
	# [x, z, altitude above ground, radius, is the Starspire]
	[260.0, -340.0, 120.0, 46.0, true],
	[-180.0, -260.0, 95.0, 22.0, false],
	[-60.0, -420.0, 140.0, 16.0, false],
	[420.0, -120.0, 105.0, 26.0, false],
	[120.0, 380.0, 110.0, 30.0, false],
	[-380.0, 160.0, 125.0, 24.0, false],
	[-520.0, -480.0, 150.0, 34.0, false],
	[620.0, 360.0, 130.0, 28.0, false],
	[-700.0, 520.0, 140.0, 20.0, false],
	[40.0, -180.0, 80.0, 12.0, false],
]

var gen: TerrainGen
var tops: Array = []   ## [centre Vector3, radius] for gameplay (updrafts, landing)
var _material: ShaderMaterial
var _fall_mat: ShaderMaterial
var _crystal_mat: StandardMaterial3D


func build(the_gen: TerrainGen) -> void:
	gen = the_gen
	_materials()
	_build_all()


## One isle on its own (the title screen's perch): returns its crown centre.
func build_one(centre: Vector3, radius: float, seed_i: int) -> Vector3:
	_materials()
	_island(centre, radius, seed_i, false)
	tops.append([centre, radius])
	return centre


func _materials() -> void:
	if _material:
		return
	_material = ShaderMaterial.new()
	_material.shader = load("res://scripts/shaders/sky_island.gdshader")
	_material.set_shader_parameter("grass_tex", load("res://assets/textures/terrain/grass.jpg"))
	_material.set_shader_parameter("rock_tex", load("res://assets/textures/terrain/rock.jpg"))
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = load("res://scripts/shaders/waterfall.gdshader")
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.82)
	_crystal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(0.4, 0.7, 1.0)
	_crystal_mat.emission_energy_multiplier = 1.2
	_crystal_mat.metallic = 0.2
	_crystal_mat.roughness = 0.1
	_crystal_mat.rim_enabled = true
	_crystal_mat.rim = 0.8
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://scripts/shaders/cloud_puff.gdshader")


func _build_all() -> void:
	var i := 0
	for spec in ISLANDS:
		var ground := maxf(gen.height(spec[0], spec[1]), TerrainGen.WATER)
		var centre := Vector3(spec[0], ground + spec[2], spec[1])
		_island(centre, spec[3], i, spec[4])
		tops.append([centre, float(spec[3])])
		_cloud_ring(centre, float(spec[3]), i)
		i += 1
	# Skybound Isle: its own archipelago in the north-west (see Realms).
	for isle in Realms.sky_isles(gen):
		_island(isle[0], isle[1], i, isle[2])
		tops.append([isle[0], float(isle[1])])
		_cloud_ring(isle[0], float(isle[1]), i)
		i += 1
	# A drifting layer of cloud banks across the sky.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	for k in 46:
		var a := rng.randf() * TAU
		var d := rng.randf_range(150.0, 1500.0)
		var p := Vector3(cos(a) * d, rng.randf_range(150.0, 230.0), sin(a) * d)
		_cloud(p, rng.randf_range(60.0, 130.0), rng.randf_range(22.0, 40.0))


## One island: a noisy disc crown and a long jagged cone of rock beneath.
func _island(centre: Vector3, radius: float, seed_i: int, spire: bool) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 991 + seed_i * 17
	noise.frequency = 0.08
	var rng0 := RandomNumberGenerator.new()
	rng0.seed = 4100 + seed_i
	var lobes := 2 + seed_i % 3
	var phase := rng0.randf() * TAU
	var segs := 48 if radius < 30.0 else 72
	var depth := radius * 1.25
	# The rim: lobed and ragged, not a disc.
	var rim := PackedFloat32Array()
	for s in segs:
		var a := TAU * s / segs
		rim.append(radius * (1.0 + noise.get_noise_1d(a * 9.0) * 0.18 + sin(a * lobes + phase) * 0.14))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Profile rings: [kind, t]: crown rings run centre -> rim, then a grassy
	# lip overhanging the edge, then the cliff body bulging and narrowing.
	var profile := []
	for k in 8:
		profile.append(["crown", float(k) / 7.0])
	profile.append(["lip", 0.0])
	for k in 13:
		profile.append(["body", float(k + 1) / 13.0])
	var pts := []
	for ring in profile:
		var row := []
		for s in segs:
			var a := TAU * s / segs
			var dir := Vector2(cos(a), sin(a))
			var r: float = rim[s]
			var p: Vector3
			match ring[0]:
				"crown":
					var t: float = ring[1]
					var rr := t * r
					var y := (1.0 - t * t) * radius * 0.07 + noise.get_noise_2d(dir.x * rr * 1.3, dir.y * rr * 1.3) * 1.1
					p = Vector3(dir.x * rr, y, dir.y * rr)
				"lip":
					p = Vector3(dir.x * r * 1.04, -1.3, dir.y * r * 1.04)
				_:
					var u: float = ring[1]
					var bulge := 1.0 + sin(u * PI) * 0.12
					# Bigger isles get proportionally more crags, not bigger ones.
					var f := 12.0 + radius * 0.55
					var jag := 1.0 + noise.get_noise_3d(dir.x * f, u * (8.0 + radius * 0.2), dir.y * f) * 0.3
					var rr := r * pow(1.0 - u, 1.15) * bulge * jag + 0.4
					p = Vector3(dir.x * rr, -1.3 - u * depth * (0.85 + 0.15 * jag), dir.y * rr)
			row.append(p)
		pts.append(row)
	for r in pts.size() - 1:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Vector3 = pts[r][s]
			var b: Vector3 = pts[r][s2]
			var c: Vector3 = pts[r + 1][s]
			var d: Vector3 = pts[r + 1][s2]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(d)
	# Hanging spurs: stalactites of rock under the body.
	var spurs := 2 + seed_i % 3
	for k in spurs:
		var a := rng0.randf() * TAU
		var off := Vector2(cos(a), sin(a)) * radius * rng0.randf_range(0.25, 0.55)
		var top_y := -1.3 - depth * rng0.randf_range(0.15, 0.35)
		_spur(st, Vector3(off.x, top_y, off.y), radius * rng0.randf_range(0.18, 0.32), depth * rng0.randf_range(0.45, 0.8), noise, k)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("top_y", centre.y)
	mi.material_override = mat
	mi.position = centre
	add_child(mi)
	# Walkable crown.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	# Solid from both sides: the crown's triangles wind downward, and a
	# one-sided shape let her fall straight through the isle.
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	mi.add_child(body)
	# Trees and flowers on top.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + seed_i
	var kinds := ["CommonTree_1", "CommonTree_3", "Pine_2", "Bush_Common_Flowers", "Flower_3_Group", "Flower_4_Group", "Fern_1"]
	var batches := {}   ## mesh -> [Transform3D]: one MultiMesh per mesh on this isle
	for k in int(radius * 0.6):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius * 0.75
		if spire and rr < radius * 0.35:
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		if FoliageLib.category(kind) == "tree" and rng.randf() < 0.5:
			kind = "Flower_4_Group"
		var at := Vector3(cos(a) * rr, (1.0 - rr / radius) * radius * 0.08, sin(a) * rr)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), at)
		for part in FoliageLib.parts(kind):
			_batch(batches, part[0], t * part[1])
	# Crystal clusters on the rim.
	for k in 3 + seed_i % 3:
		var a := rng.randf() * TAU
		_crystals(batches, Vector3(cos(a) * radius * 0.7, 0.5, sin(a) * radius * 0.7), rng, 1.0)
	# Vines hanging over the rim, and rocks drifting round the isle.
	if _vine == null:
		_vine = _make_vine()
	for k in int(radius * 1.8):
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.94, 1.04)
		var len := rng.randf_range(3.0, 4.0 + radius * 0.35)
		_batch(batches, _vine, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, len, 1.0)),
			Vector3(cos(a) * r, -0.6, sin(a) * r)))
	for k in 3 + seed_i % 4:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(1.15, 1.7)
		var kind: String = ["X:rocks_1", "X:rocks_3", "X:rocks_4"][rng.randi() % 3]
		var sc := rng.randf_range(1.2, 2.6) * (radius / 24.0 + 0.5)
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
		var t := Transform3D(rot.scaled(Vector3.ONE * sc), Vector3(cos(a) * r, rng.randf_range(-depth * 0.5, 3.0), sin(a) * r))
		for part in FoliageLib.parts(kind):
			_batch(batches, part[0], t * part[1])
	for part_mesh in batches:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part_mesh
		var list: Array = batches[part_mesh]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if part_mesh == _prism:
			mmi.material_override = _crystal_mat
		elif part_mesh == _vine:
			mmi.material_override = _vine_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(mmi)
	# Waterfalls off one or two edges.
	for k in 1 + seed_i % 2:
		var a := rng.randf() * TAU
		_waterfall(mi, Vector3(cos(a), 0, sin(a)) * radius * 0.98, a, radius * 0.25, depth * 1.6)
	if spire:
		_starspire(mi, rng)


var _prism: PrismMesh
var _vine: ArrayMesh
var _vine_mat: ShaderMaterial


## A hanging vine: two crossed tapering strips 1 m long (scaled to length),
## UV.y 0 at the top.
func _make_vine() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var side := Vector3(0.36, 0, 0) if k == 0 else Vector3(0, 0, 0.36)
		var steps := 6
		for i in steps:
			var v0 := float(i) / steps
			var v1 := float(i + 1) / steps
			var w0 := 1.0 - v0 * 0.8
			var w1 := 1.0 - v1 * 0.8
			var a := -side * w0 + Vector3(0, -v0, 0)
			var b := side * w0 + Vector3(0, -v0, 0)
			var c := -side * w1 + Vector3(0, -v1, 0)
			var d := side * w1 + Vector3(0, -v1, 0)
			for q in [[a, v0], [b, v0], [c, v1], [b, v0], [d, v1], [c, v1]]:
				st.set_uv(Vector2(0, q[1]))
				st.add_vertex(q[0])
	st.generate_normals()
	if _vine_mat == null:
		_vine_mat = ShaderMaterial.new()
		_vine_mat.shader = load("res://scripts/shaders/vine.gdshader")
	return st.commit()


## A jagged downward cone of rock (a stalactite under an isle).
func _spur(st: SurfaceTool, top: Vector3, radius: float, length: float, noise: FastNoiseLite, k: int) -> void:
	var segs := 12
	var rings := 6
	var pts := []
	for r in rings + 1:
		var u := float(r) / rings
		var row := []
		for s in segs:
			var a := TAU * s / segs
			var jag := 1.0 + noise.get_noise_3d(cos(a) * 9.0 + k * 13.0, u * 6.0, sin(a) * 9.0) * 0.3
			var rr := radius * pow(1.0 - u, 1.3) * jag + 0.05
			row.append(top + Vector3(cos(a) * rr, -u * length, sin(a) * rr))
		pts.append(row)
	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			st.add_vertex(pts[r][s])
			st.add_vertex(pts[r + 1][s])
			st.add_vertex(pts[r][s2])
			st.add_vertex(pts[r][s2])
			st.add_vertex(pts[r + 1][s])
			st.add_vertex(pts[r + 1][s2])


var _cloud_mat: ShaderMaterial
var _quad: QuadMesh


## A cloud puff billboard, `w` wide and `h` tall.
func _cloud(at: Vector3, w: float, h: float) -> void:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _cloud_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = maxf(w, h)
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(w, h, 1.0)


## Clouds hugging an isle: a few puffs round its waist and under its tip.
func _cloud_ring(centre: Vector3, radius: float, seed_i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_i
	for k in 3 + seed_i % 3:
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.7, 1.3)
		var y := -radius * rng.randf_range(0.3, 1.1)
		_cloud(centre + Vector3(cos(a) * r, y, sin(a) * r), radius * rng.randf_range(1.0, 1.8), radius * rng.randf_range(0.45, 0.7))


func set_night(night: float) -> void:
	if _cloud_mat:
		_cloud_mat.set_shader_parameter("night", night)
	if _fall_mat:
		_fall_mat.set_shader_parameter("night", night)


func _batch(batches: Dictionary, mesh: Mesh, t: Transform3D) -> void:
	if not batches.has(mesh):
		batches[mesh] = []
	batches[mesh].append(t)


## A cluster of crystal prisms, batched with the isle's other plants.
func _crystals(batches: Dictionary, at: Vector3, rng: RandomNumberGenerator, scale: float) -> void:
	if _prism == null:
		_prism = PrismMesh.new()
		_prism.size = Vector3(0.6, 2.4, 0.6)
	for k in 5:
		var s := scale * rng.randf_range(0.6, 1.4)
		var pos := at + Vector3(rng.randf_range(-1, 1), 2.4 * s * 0.4, rng.randf_range(-1, 1))
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
		_batch(batches, _prism, Transform3D(basis.scaled(Vector3.ONE * s), pos))


func _waterfall(parent: Node3D, at: Vector3, angle: float, width: float, height: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var w := MeshInstance3D.new()
	w.mesh = quad
	w.material_override = _fall_mat
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.position = at + Vector3(0, -height * 0.5 + 0.5, 0)
	w.rotation.y = -angle + PI * 0.5
	parent.add_child(w)
	# Mist where it thins out.
	var mist := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(3, 3)
	mist.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_texture = Play3D._spark_texture()
	mm.albedo_color = Color(1, 1, 1, 0.18)
	mist.material_override = mm
	mist.amount = 24
	mist.lifetime = 4.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(width * 0.4, 1, 1)
	mist.gravity = Vector3(0, -1.5, 0)
	mist.scale_amount_max = 2.5
	mist.position = at + Vector3(0, -height * 0.85, 0)
	parent.add_child(mist)


## The Starspire: a tall cluster of white-blue crystal and a pillar of light.
func _starspire(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var spire_mat := _crystal_mat.duplicate() as StandardMaterial3D
	spire_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.9)
	for k in 7:
		var prism := PrismMesh.new()
		var h := 10.0 + rng.randf() * 24.0 if k > 0 else 46.0
		prism.size = Vector3(h * 0.12, h, h * 0.12)
		var c := MeshInstance3D.new()
		c.mesh = prism
		c.material_override = spire_mat
		var a := rng.randf() * TAU
		var off := 0.0 if k == 0 else rng.randf_range(2.5, 6.0)
		c.position = Vector3(cos(a) * off, h * 0.45, sin(a) * off)
		c.rotation = Vector3(0, rng.randf() * TAU, 0) if k == 0 else Vector3(cos(a) * 0.25, 0, sin(a) * 0.25)
		parent.add_child(c)
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 2.2
	cyl.height = 900.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	pillar.mesh = cyl
	var pm := ShaderMaterial.new()
	pm.shader = load("res://scripts/shaders/light_pillar.gdshader")
	pillar.material_override = pm
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = Vector3(0, 450.0, 0)
	parent.add_child(pillar)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.8, 1.0)
	glow.light_energy = 2.0
	glow.omni_range = 30.0
	glow.position = Vector3(0, 30, 0)
	parent.add_child(glow)
