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
	var i := 0
	for spec in ISLANDS:
		var ground := maxf(gen.height(spec[0], spec[1]), TerrainGen.WATER)
		var centre := Vector3(spec[0], ground + spec[2], spec[1])
		_island(centre, spec[3], i, spec[4])
		tops.append([centre, float(spec[3])])
		i += 1


## One island: a noisy disc crown and a long jagged cone of rock beneath.
func _island(centre: Vector3, radius: float, seed_i: int, spire: bool) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 991 + seed_i * 17
	noise.frequency = 0.08
	var rings := 18
	var segs := 40
	var depth := radius * 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []   # ring -> segment -> Vector3
	for r in rings + 1:
		var row := []
		var t := float(r) / rings
		for s in segs:
			var a := TAU * s / segs
			var dir := Vector2(cos(a), sin(a))
			var p: Vector3
			if t <= 0.5:
				# Crown: from centre out to the rim, gently domed and bumpy.
				var rr := t * 2.0 * radius * (1.0 + noise.get_noise_2d(dir.x * 30.0, dir.y * 30.0) * 0.25)
				var y := (1.0 - t * 2.0) * radius * 0.08 + noise.get_noise_2d(dir.x * rr, dir.y * rr) * 1.2
				p = Vector3(dir.x * rr, y, dir.y * rr)
			else:
				# Body: down from the rim, narrowing to a craggy point.
				var u := (t - 0.5) * 2.0
				var shrink := pow(1.0 - u, 1.3)
				var jag := 1.0 + noise.get_noise_3d(dir.x * 20.0, u * 12.0, dir.y * 20.0) * 0.35
				var rr := radius * (1.0 + noise.get_noise_2d(dir.x * 30.0, dir.y * 30.0) * 0.25) * shrink * jag
				p = Vector3(dir.x * rr, -u * depth * (0.8 + 0.2 * jag), dir.y * rr)
			row.append(p)
		pts.append(row)
	for r in rings:
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
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	mi.add_child(body)
	# Trees and flowers on top.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + seed_i
	var kinds := ["CommonTree_1", "CommonTree_3", "Pine_2", "Bush_Common_Flowers", "Flower_3_Group", "Flower_4_Group", "Fern_1"]
	for k in int(radius * 0.6):
		var a := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * radius * 0.75
		if spire and rr < radius * 0.35:
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		if FoliageLib.category(kind) == "tree" and rng.randf() < 0.5:
			kind = "Flower_4_Group"
		var at := Vector3(cos(a) * rr, (1.0 - rr / radius) * radius * 0.08, sin(a) * rr)
		for part in FoliageLib.parts(kind):
			var f := MeshInstance3D.new()
			f.mesh = part[0]
			f.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), at) * part[1]
			mi.add_child(f)
	# Crystal clusters on the rim.
	for k in 3 + seed_i % 3:
		var a := rng.randf() * TAU
		_crystals(mi, Vector3(cos(a) * radius * 0.7, 0.5, sin(a) * radius * 0.7), rng, 1.0)
	# Waterfalls off one or two edges.
	for k in 1 + seed_i % 2:
		var a := rng.randf() * TAU
		_waterfall(mi, Vector3(cos(a), 0, sin(a)) * radius * 0.98, a, radius * 0.25, depth * 1.6)
	if spire:
		_starspire(mi, rng)


func _crystals(parent: Node3D, at: Vector3, rng: RandomNumberGenerator, scale: float) -> void:
	for k in 5:
		var prism := PrismMesh.new()
		prism.size = Vector3(0.6, 2.4, 0.6) * scale * rng.randf_range(0.6, 1.4)
		var c := MeshInstance3D.new()
		c.mesh = prism
		c.material_override = _crystal_mat
		c.position = at + Vector3(rng.randf_range(-1, 1), prism.size.y * 0.4, rng.randf_range(-1, 1)) * Vector3(1, 1, 1)
		c.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
		parent.add_child(c)


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
