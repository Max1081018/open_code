class_name Town
extends Node3D
## Starfall Haven, the town on the central plateau, and the props of the wider
## world. A cobbled plaza (drawn by the terrain shader from TerrainGen's
## PLAZA_RADIUS and ROADS) with a fountain at its heart; houses around it
## with their doors to the square, each on a garden path lined with flowers;
## market stalls either side of the road up to the magic tower; benches,
## lanterns along every road, shade trees. Two small isles drift above the
## land on their own (a sky dwelling, a waterfall shrine) and ruined arches
## stand on the big isles. Treasure chests on every isle and across the land
## open with F (or the hand button).

const DIR := "res://assets/models/world/"
## Draw distance (m) and whether it casts shadows, per model; small props go
## early and cast none. Others: 900 m with shadows.
const DRAW := {"chest": [110.0, false], "chest_magic": [140.0, false], "flower_pot": [70.0, false],
	"crates": [90.0, false], "bench": [90.0, false], "lantern": [180.0, true], "market_stall": [240.0, true],
	"fountain": [240.0, true], "fountain_small": [320.0, true], "statue": [320.0, true], "shrine_stone": [420.0, true]}
## Which way each model's front (door, seat) faces in its own frame: the
## yaw added after turning +Z toward the plaza.
const FRONT_OFFSET := {"bench": -PI * 0.5}
## [model, x, z, height m, solid] — fronts turned to the plaza.
const TOWN := [
	["statue", -7.5, -38.0, 3.8, true],
	["shrine_stone", 18.0, -5.0, 4.2, true],
	["fountain", -16.5, -4.5, 3.2, true],
	["market_stall", 5.8, -11.5, 3.6, true],
	["market_stall", -5.8, -11.5, 3.6, true],
	["crates", 9.0, -14.5, 1.1, true],
	["crates", -9.5, -14.0, 1.1, true],
	["bench", 8.0, 2.9, 1.0, true],
	["bench", -1.2, 8.4, 1.0, true],
	["bench", -8.3, 1.5, 1.0, true],
	["bench", 7.4, -4.2, 1.0, true],
]
## Starfall Haven's own buildings (ArchKit): [kind, x, z, options]; houses
## face the plaza unless options give a yaw. Kinds: house, tower, gate.
const KIT := [
	["house", -24.0, -16.0, {"w": 9.0, "d": 7.5, "floors": 2, "roof": "cobalt", "seed": 1, "tower": true}],
	["house", 24.0, -18.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "teal", "seed": 2, "roof_style": "gable"}],
	["house", -27.0, 14.0, {"w": 8.5, "d": 7.0, "floors": 2, "roof": "violet", "seed": 3}],
	["house", 25.0, 17.0, {"w": 10.0, "d": 8.0, "floors": 3, "roof": "cobalt", "seed": 4, "tower": true}],
	["house", -7.0, 45.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "rose", "seed": 5, "roof_style": "gable"}],
	["house", 40.0, -9.5, {"w": 9.0, "d": 7.0, "floors": 2, "roof": "teal", "seed": 6, "yaw": 0.0}],
	["house", 47.0, 18.5, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "cobalt", "seed": 7, "yaw": PI, "roof_style": "gable"}],
	["house", -42.0, -16.5, {"w": 8.0, "d": 7.0, "floors": 3, "roof": "rose", "seed": 8, "yaw": 0.0, "tower": true}],
	["house", -47.0, 9.0, {"w": 9.0, "d": 7.0, "floors": 2, "roof": "violet", "seed": 9, "yaw": PI}],
	["house", -22.0, -42.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "teal", "seed": 10, "roof_style": "gable"}],
	["house", 23.0, -44.0, {"w": 8.5, "d": 7.5, "floors": 2, "roof": "violet", "seed": 11, "tower": true}],
	["house", -58.0, -30.0, {"w": 9.0, "d": 7.0, "floors": 2, "roof": "cobalt", "seed": 12}],
	["house", 58.0, -28.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "rose", "seed": 13, "roof_style": "gable"}],
	["house", -30.0, 58.0, {"w": 9.0, "d": 7.5, "floors": 3, "roof": "teal", "seed": 14, "tower": true}],
	["house", 34.0, 52.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "cobalt", "seed": 15}],
	["house", -60.0, 32.0, {"w": 8.0, "d": 7.0, "floors": 2, "roof": "rose", "seed": 16, "roof_style": "gable"}],
	["house", 60.0, 40.0, {"w": 8.5, "d": 7.0, "floors": 2, "roof": "violet", "seed": 17}],
	["tower", 0.0, -52.0, {"r": 3.6, "h": 17.0, "roof": "violet"}],
	["gate", 8.7, 43.4, {"span": 6.6}],
]
## Shade trees between the houses: [kind, x, z] (sakura for colour).
const TREES := [["X:sakura_0", -12.0, -27.0], ["CommonTree_1", 12.0, -30.0], ["X:sakura_0", 33.0, 2.0],
	["CommonTree_4", -36.0, 26.0], ["X:sakura_0", 22.0, 40.0], ["CommonTree_1", -30.0, 36.0],
	["CommonTree_3", 40.0, -30.0], ["X:sakura_0", -36.0, -34.0], ["X:sakura_0", -16.0, 30.0]]
## Isle props: [model, island index, height, offset from centre].
const ISLES := [["ruin_arch", 1, 10.0, Vector2(0, 0)], ["ruin_arch", 6, 14.0, Vector2(6, 0)]]
## Free-floating mini isles: [model, x, z, altitude above ground, height].
const FLOATERS := [["sky_house", -150.0, 130.0, 70.0, 30.0], ["shrine_sky", 190.0, 60.0, 55.0, 20.0]]

var game: Node
var chests: Array = []
var lamps: Array = []    ## [OmniLight3D, glow sprite] per street lantern   ## [Node3D, opened: bool, loot, magic: bool]


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	for spec in TOWN:
		var at := Vector3(spec[1], 0, spec[2])
		at.y = gen.height(at.x, at.z)
		var yaw := atan2(-at.x, -at.z) if Vector2(at.x, at.z).length() > 1.0 else 0.0
		yaw += FRONT_OFFSET.get(spec[0], 0.0)
		place(spec[0], at, spec[3], yaw, "box" if spec[4] else "")
	_build_kit(gen)
	_garden_flowers(gen)
	_banners(gen)
	# A ring of flowers round the fountain.
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2(cos(a), sin(a)) * 6.3
		place("flower_pot", Vector3(p.x, gen.height(p.x, p.y), p.y), 0.75, a, "box")
	_road_lanterns(gen)
	for t in TREES:
		_tree(t[0], Vector3(t[1], gen.height(t[1], t[2]), t[2]))
	var tops: Array = game.islands.tops
	for spec in ISLES:
		var top: Array = tops[spec[1]]
		var c: Vector3 = top[0]
		var off: Vector2 = spec[3]
		place(spec[0], c + Vector3(off.x, 0.3, off.y), spec[2], randf() * TAU, "box")
	for f in FLOATERS:
		var ground := maxf(gen.height(f[1], f[2]), TerrainGen.WATER)
		var at := Vector3(f[1], ground + f[3], f[2])
		var node := place(f[0], at, f[4], 0.6, "mesh")
		# Gentle bob, and an updraft to reach it.
		var t := node.create_tween().set_loops()
		t.tween_property(node, "position:y", at.y + 1.2, 4.0).set_trans(Tween.TRANS_SINE)
		t.tween_property(node, "position:y", at.y, 4.0).set_trans(Tween.TRANS_SINE)
		if game.features:
			var base := at + Vector3(f[4] * 0.9, 0, 0)
			base.y = maxf(gen.height(base.x, base.z), TerrainGen.WATER)
			game.features._updraft(base, 4.5, at.y - base.y + f[4] + 10.0)
	# Chests: on every isle and scattered over the land.
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	for top in tops:
		var c: Vector3 = top[0]
		_chest(c + Vector3(top[1] * 0.45, 0.3, -top[1] * 0.3), true)
	for k in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(80.0, 1200.0)
		var x := cos(a) * d
		var z := sin(a) * d
		var h := gen.height(x, z)
		if h < TerrainGen.WATER + 0.6 or gen.normal(x, z).y < 0.85:
			continue
		_chest(Vector3(x, h, z), rng.randf() < 0.25)


var crystal: Node3D


## The town's buildings from ArchKit, each one mesh with a box collider
## (the gate only on its pylons), and the plaza's star fountain.
func _build_kit(gen: TerrainGen) -> void:
	# All the kit's buildings become one mesh with a surface per material
	# (a handful of draw calls for the whole town instead of hundreds).
	var tools := {}   ## Material -> SurfaceTool
	for spec in KIT:
		var at := Vector3(spec[1], 0, spec[2])
		var o: Dictionary = spec[3]
		var mesh: ArrayMesh
		match spec[0]:
			"house":
				mesh = ArchKit.house(o.w, o.d, o.floors, o.roof, o)
			"tower":
				mesh = ArchKit.tower(o.r, o.h, o.roof)
			"gate":
				mesh = ArchKit.gate(o.span)
		# Seat on the lowest corner so no side floats on a slope.
		var lo := INF
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
			lo = minf(lo, gen.height(at.x + c.x * 4.0, at.z + c.y * 4.0))
		at.y = lo
		var yaw: float = o.get("yaw", atan2(-at.x, -at.z))
		if spec[0] == "gate":
			var road: Array = TerrainGen.ROADS[1]
			var dir: Vector2 = (road[1] - road[0]).normalized()
			yaw = atan2(dir.x, dir.y)
		var holder := Node3D.new()
		add_child(holder)
		holder.position = at
		holder.rotation.y = yaw
		var place := Transform3D(Basis(Vector3.UP, yaw), at)
		for si in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(si)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			(tools[mat] as SurfaceTool).append_from(mesh, si, place)
		var body := StaticBody3D.new()
		holder.add_child(body)
		var box := mesh.get_aabb()
		if spec[0] == "gate":
			for sx in [-1.0, 1.0]:
				_box_shape(body, Vector3(sx * (o.span * 0.5 + 0.8), 3.5, 0), Vector3(2.0, 7.0, 2.0))
		else:
			_box_shape(body, box.get_center(), box.size * Vector3(0.96, 1.0, 0.96))
	var merged := ArrayMesh.new()
	for mat in tools:
		(tools[mat] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, mat)
	var kit := MeshInstance3D.new()
	kit.name = "KitBuildings"
	kit.mesh = merged
	kit.visibility_range_end = 1400.0
	add_child(kit)
	# The plaza's centrepiece: a tiered marble fountain with the star crystal
	# turning above it.
	var c := Vector3(0, gen.height(0, 0), 0)
	var fountain := MeshInstance3D.new()
	fountain.mesh = ArchKit.star_fountain()
	add_child(fountain)
	fountain.position = c
	var fb := StaticBody3D.new()
	fountain.add_child(fb)
	var cyl := CylinderShape3D.new()
	cyl.radius = 5.3
	cyl.height = 1.2
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position.y = 0.5
	fb.add_child(cs)
	crystal = MeshInstance3D.new()
	(crystal as MeshInstance3D).mesh = ArchKit.star_crystal()
	add_child(crystal)
	crystal.position = c + Vector3(0, 6.6, 0)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.82, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 12.0
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 90.0
	crystal.add_child(glow)
	# Water sparkling up from the top basin.
	var spray := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	spray.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_texture = Play3D._spark_texture()
	sm.albedo_color = Color(0.75, 0.92, 1.0, 0.7)
	spray.material_override = sm
	spray.amount = 60
	spray.lifetime = 1.4
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	spray.emission_ring_axis = Vector3.UP
	spray.emission_ring_radius = 0.6
	spray.emission_ring_inner_radius = 0.4
	spray.emission_ring_height = 0.1
	spray.direction = Vector3.UP
	spray.spread = 30
	spray.initial_velocity_min = 2.5
	spray.initial_velocity_max = 3.4
	spray.gravity = Vector3(0, -6, 0)
	add_child(spray)
	spray.position = c + Vector3(0, 4.9, 0)


func _box_shape(body: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = centre
	body.add_child(cs)


## Put a model in the world, `height` metres tall, base on `at`. `collide`
## is "" (none), "box" (a box round the base) or "mesh" (its own surfaces,
## for things to stand on).
func place(model: String, at: Vector3, height: float, yaw: float, collide := "") -> Node3D:
	var scene: PackedScene = load(DIR + model + ".glb")
	var holder := Node3D.new()
	add_child(holder)
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	var box := AABB()
	var first := true
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var k := height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	# One mesh per model, a surface per material (see MeshMerge).
	var merged := MeshMerge.merged(model, inst)
	if merged:
		var one := MeshInstance3D.new()
		one.mesh = merged
		one.transform = inst.transform
		holder.remove_child(inst)
		inst.free()
		holder.add_child(one)
		meshes = [one]
	var draw: Array = DRAW.get(model, [900.0, true])
	for m in meshes:
		var mi := m as MeshInstance3D
		mi.visibility_range_end = draw[0]
		mi.visibility_range_end_margin = 12.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if draw[1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.global_position = at
	holder.rotation.y = yaw
	if collide == "box":
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(box.size.x * k * 0.8, height, box.size.z * k * 0.8)
		cs.shape = shape
		cs.position = Vector3(0, height * 0.5, 0)
		body.add_child(cs)
		holder.add_child(body)
	elif collide == "mesh":
		for m in meshes:
			(m as MeshInstance3D).create_trimesh_collision()
	return holder


## Flower buckets either side of each garden path, near the door.
func _garden_flowers(gen: TerrainGen) -> void:
	for r in TerrainGen.ROADS:
		if float(r[2]) > 2.0:
			continue
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var at := a + (b - a) * 0.62
		for s in [-1.0, 1.0]:
			var p: Vector2 = at + side * s * (float(r[2]) + 0.9)
			place("flower_pot", Vector3(p.x, gen.height(p.x, p.y), p.y), 0.75, randf() * TAU, "box")


## Lanterns along the roads, alternating sides, every 14 m from the plaza.
func _road_lanterns(gen: TerrainGen) -> void:
	var n := 0
	for r in TerrainGen.ROADS:
		if float(r[2]) <= 2.0:
			continue
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var side := Vector2(-dir.y, dir.x)
		var d := 18.0 if a == Vector2.ZERO else 7.0
		while d < length - 3.0:
			var s := 1.0 if n % 2 == 0 else -1.0
			var p := a + dir * d + side * s * (float(r[2]) + 1.3)
			var at := Vector3(p.x, gen.height(p.x, p.y), p.y)
			place("lantern", at, 3.6, atan2(-side.x * s, -side.y * s), "box")
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.74, 0.42)
			l.light_energy = 0.0
			l.omni_range = 12.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 48.0
			l.distance_fade_length = 14.0
			l.position = at + Vector3(0, 3.1, 0)
			l.visible = false
			add_child(l)
			var halo := _glow(at + Vector3(0, 2.95, 0), Color(1.0, 0.72, 0.38), 1.6)
			halo.visible = false
			lamps.append([l, halo])
			d += 14.0
			n += 1


## Banners on tall poles round the plaza, between the roads.
func _banners(gen: TerrainGen) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/banner.gdshader")
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.24, 0.18)
	pole_mat.roughness = 0.7
	var cloth := PlaneMesh.new()
	cloth.size = Vector2(2.6, 0.9)
	cloth.subdivide_width = 16
	cloth.subdivide_depth = 2
	cloth.orientation = PlaneMesh.FACE_Z
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = 7.0
	var cap := SphereMesh.new()
	cap.radius = 0.16
	cap.height = 0.32
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.96, 0.8, 0.4)
	cap_mat.metallic = 0.6
	cap_mat.roughness = 0.3
	for a_deg in [52.0, 124.0, 196.0, 232.0, 300.0, 340.0]:
		var a := deg_to_rad(a_deg)
		var p := Vector2(cos(a), sin(a)) * 15.6
		var base := Vector3(p.x, gen.height(p.x, p.y), p.y)
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = base
		holder.rotation.y = randf() * TAU
		var pm := MeshInstance3D.new()
		pm.mesh = pole
		pm.material_override = pole_mat
		pm.position.y = 3.5
		holder.add_child(pm)
		var cm := MeshInstance3D.new()
		cm.mesh = cap
		cm.material_override = cap_mat
		cm.position.y = 7.05
		holder.add_child(cm)
		var flag := MeshInstance3D.new()
		flag.mesh = cloth
		flag.material_override = mat
		flag.position = Vector3(1.3, 6.35, 0)
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(flag)


static var _glow_mats := {}


## A soft additive halo sprite (lamp flames, chest shimmer): bloom does the rest.
func _glow(at: Vector3, colour: Color, size: float) -> MeshInstance3D:
	var key := colour.to_html()
	if not _glow_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = Play3D._spark_texture()
		m.albedo_color = Color(colour.r * 1.6, colour.g * 1.6, colour.b * 1.6, 0.9)
		m.disable_fog = false
		_glow_mats[key] = m
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _glow_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	add_child(mi)
	mi.global_position = at
	return mi


## Lanterns come on as the light goes (0 day .. 1 night).
func set_night(night: float) -> void:
	ArchKit.set_night(night)
	var on := night > 0.08
	for lamp in lamps:
		var l: OmniLight3D = lamp[0]
		l.visible = on
		l.light_energy = 3.2 * night
		(lamp[1] as Node3D).visible = on
		((lamp[1] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a = 0.9 * night


func _tree(kind: String, at: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at
	holder.rotation.y = randf() * TAU
	for part in FoliageLib.parts(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		mi.visibility_range_end = 500.0
		holder.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 6.0
	cs.shape = cyl
	cs.position.y = 3.0
	body.add_child(cs)
	holder.add_child(body)


func _chest(at: Vector3, magic: bool) -> void:
	var c := place("chest_magic" if magic else "chest", at, 1.4 if magic else 0.8, randf() * TAU, "box")
	# A soft glow over the lid (a sprite, not a light: lights are scarce).
	var halo := _glow(Vector3.ZERO, Color(0.55, 0.85, 1.0) if magic else Color(1.0, 0.82, 0.45), 1.3 if magic else 1.0)
	halo.position = Vector3(0, 1.1 if magic else 0.75, 0)
	halo.get_parent().remove_child(halo)
	c.add_child(halo)
	var loot: Array = [["gold_coin", randi_range(6, 20)]]
	if magic:
		loot.append([["heart_crystal", "lumen_core", "glowshard", "ruby", "emerald"].pick_random(), 1])
		loot.append(["glowshard", randi_range(2, 5)])
	else:
		loot.append([["apple", "cooked_meat", "glowshard", "copper_ore", "iron_ore"].pick_random(), randi_range(1, 4)])
	chests.append([c, false, loot, magic])
	c.set_meta("id", chests.size() - 1)


func opened_ids() -> Array:
	var out: Array = []
	for i in chests.size():
		if chests[i][1]:
			out.append(i)
	return out


## Chests opened in a saved journey stay open (and gone).
func restore_opened(ids: Array) -> void:
	for i in ids:
		if int(i) < chests.size() and not chests[int(i)][1]:
			chests[int(i)][1] = true
			(chests[int(i)][0] as Node).queue_free()


func _process(delta: float) -> void:
	if crystal:
		crystal.rotation.y += delta * 0.6
		crystal.position.y = game.world.height_at(0, 0) + 6.6 + sin(Time.get_ticks_msec() / 900.0) * 0.25
	if game == null or game.player == null:
		return
	var p: Player3D = game.player
	var near := false
	for ch in chests:
		if ch[1]:
			continue
		var node: Node3D = ch[0]
		if node.global_position.distance_to(p.global_position) < 2.4:
			near = true
			if game.input.interact:
				game.input.interact = false
				_open(ch)
	game.hud.prompt("Open chest" if near else "")


func _open(ch: Array) -> void:
	ch[1] = true
	var node: Node3D = ch[0]
	var p: Play3D = game.play
	for l in ch[2]:
		p.spawn_pickup(l[0], l[1], node.global_position + Vector3(0, 1.2, 0), Vector3(randf_range(-2, 2), 5, randf_range(-2, 2)))
	p._star_ring(node.global_position, 2.5, Color(1.0, 0.85, 0.45) if not ch[3] else Color(0.6, 0.9, 1.0))
	p.toast.emit("Treasure!" if not ch[3] else "A starlit chest!")
	game.autosave()
	Sfx.play("chest")
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector3(1.15, 0.85, 1.15), 0.12)
	t.tween_property(node, "scale", Vector3.ONE, 0.2)
	t.tween_interval(2.0)
	t.tween_property(node, "scale", Vector3.ZERO, 0.4)
	t.tween_callback(node.queue_free)
