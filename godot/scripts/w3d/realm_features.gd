class_name RealmFeatures
extends Node3D
## The landmarks of the designed lands (see Realms):
##   Great Jungle  — the World Tree on its mesa (glowing crown, fireflies),
##                   three waterfalls into misty pools, root-ramp gate ruins,
##                   crystal shards round the tree, a shrine at its foot.
##   Sunscar Sea   — the Sun Gate, a ring of colossal broken pillars round a
##                   sunken plaza, giant sandstone stacks, palm-ringed oases.
##   Crystal Coast — Saltmere village (houses, a jetty into the sea,
##                   lanterns) and the Singing Grotto of giant crystals.
##   Skybound Isle — plank bridges between the floating isles.
## Solid things get colliders. `landmarks` lists named places for the map,
## titles and quests: id -> {name, pos}.

var game: Node
var gen: TerrainGen
var landmarks := {}
var _stone: StandardMaterial3D
var _sand_stone: StandardMaterial3D
var _wood: StandardMaterial3D


func build(the_game: Node) -> void:
	game = the_game
	gen = game.world.gen
	_stone = _mat(Color(0.62, 0.64, 0.6), 0.9)
	_sand_stone = _mat(Color(0.86, 0.68, 0.48), 0.92)
	_wood = _mat(Color(0.46, 0.33, 0.22), 0.95)
	_jungle()
	_desert()
	_coast()
	_sky()


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _ground(x: float, z: float) -> float:
	return gen.height(x, z)


func _mark(id: String, name: String, pos: Vector3) -> void:
	landmarks[id] = {"name": name, "pos": pos}


# ------------------------------------------------------------- jungle ---

func _jungle() -> void:
	var c := Realms.JUNGLE
	var top := _ground(c.x, c.y)
	var root := Node3D.new()
	add_child(root)
	# The World Tree: the pack's broadleaf, sixty metres tall.
	var tree := Node3D.new()
	root.add_child(tree)
	tree.position = Vector3(c.x, top - 1.0, c.y)
	for part in FoliageLib.parts("CommonTree_5"):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 5.6), Vector3.ZERO) * (part[1] as Transform3D)
		tree.add_child(mi)
	_cylinder_body(tree.position + Vector3(0, 12, 0), 3.4, 26.0)
	var crown := OmniLight3D.new()
	crown.light_color = Color(0.5, 1.0, 0.8)
	crown.light_energy = 2.0
	crown.omni_range = 40.0
	crown.shadow_enabled = false
	crown.position = tree.position + Vector3(0, 40, 0)
	root.add_child(crown)
	root.add_child(_motes(tree.position + Vector3(0, 32, 0), Vector3(22, 12, 22), Color(0.7, 1.0, 0.6), 90))
	_mark("world_tree", "The World Tree", tree.position)
	# Waterfalls from the mesa rim into the pools.
	for fa in Realms.FALLS:
		var dir := Vector2(cos(fa), sin(fa))
		var rim := c + dir * (Realms.MESA_R + 3.0)
		var rim_h := _ground(c.x + dir.x * (Realms.MESA_R - 8.0), c.y + dir.y * (Realms.MESA_R - 8.0))
		var at := Vector3(rim.x, rim_h + 0.5, rim.y)
		game.islands._waterfall(root, at, fa, 14.0, rim_h - TerrainGen.WATER + 1.0)
		var pool := c + dir * Realms.POOL_R
		root.add_child(_motes(Vector3(pool.x, 1.5, pool.y), Vector3(10, 2, 10), Color(0.9, 1.0, 1.0), 40, 0.15, 3.0))
		_mark("falls_%d" % Realms.FALLS.find(fa), "Veilwater Falls", Vector3(pool.x, 0.5, pool.y))
	# Gate ruins at the foot and the head of the root ramp.
	var rd := Vector2(cos(Realms.RAMP_ANGLE), sin(Realms.RAMP_ANGLE))
	for d: float in [Realms.MESA_R + 140.0, Realms.MESA_R - 6.0]:
		var p := c + rd * d
		var gate := MeshInstance3D.new()
		gate.mesh = ArchKit.gate(9.0)
		gate.position = Vector3(p.x, _ground(p.x, p.y) - 0.3, p.y)
		gate.rotation.y = atan2(rd.x, rd.y)
		root.add_child(gate)
	_mark("root_ramp", "The Root Stair", Vector3((c + rd * (Realms.MESA_R + 140.0)).x, 0, (c + rd * (Realms.MESA_R + 140.0)).y))
	# Crystal shards round the tree and a shrine at its foot.
	for k in 6:
		var a := TAU * k / 6.0 + 0.4
		var p := c + Vector2(cos(a), sin(a)) * 34.0
		_crystal(root, Vector3(p.x, _ground(p.x, p.y) - 0.2, p.y), randf_range(1.2, 2.2), Color(0.5, 1.0, 0.75))
	var shrine_at := c + Vector2(cos(Realms.RAMP_ANGLE + 0.5), sin(Realms.RAMP_ANGLE + 0.5)) * 22.0
	var shrine := MeshInstance3D.new()
	shrine.mesh = ArchKit.star_fountain()
	shrine.position = Vector3(shrine_at.x, _ground(shrine_at.x, shrine_at.y) - 0.2, shrine_at.y)
	root.add_child(shrine)
	_mark("jungle_shrine", "Shrine of the First Root", shrine.position)


# ------------------------------------------------------------- desert ---

func _desert() -> void:
	var c := Realms.DESERT
	var root := Node3D.new()
	add_child(root)
	# The Sun Gate on a dune crest near the heart of the sands.
	var g := c + Vector2(-80, 60)
	var gate := MeshInstance3D.new()
	gate.mesh = ArchKit.gate(16.0)
	gate.scale = Vector3.ONE * 2.2
	gate.position = Vector3(g.x, _ground(g.x, g.y) - 1.0, g.y)
	gate.rotation.y = 0.35
	root.add_child(gate)
	_sun_tint(gate)
	_mark("sun_gate", "The Sun Gate", gate.position)
	# The Colonnade of Kings: a ring of colossal pillars, some fallen short.
	var ring := c + Vector2(260, -180)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for k in 11:
		var a := TAU * k / 11.0
		var p := ring + Vector2(cos(a), sin(a)) * 46.0
		var hgt := rng.randf_range(8.0, 30.0) if k % 3 != 0 else rng.randf_range(26.0, 34.0)
		var base := _ground(p.x, p.y) - 2.0
		var pil := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.0
		cyl.bottom_radius = 2.4
		cyl.height = hgt
		cyl.radial_segments = 10
		pil.mesh = cyl
		pil.material_override = _sand_stone
		pil.position = Vector3(p.x, base + hgt * 0.5, p.y)
		pil.rotation = Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		root.add_child(pil)
		_cylinder_body(pil.position, 2.3, hgt)
		# A capital block on the tall ones.
		if hgt > 24.0:
			var cap := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(5.6, 1.6, 5.6)
			cap.mesh = bx
			cap.material_override = _sand_stone
			cap.position = pil.position + Vector3(0, hgt * 0.5 + 0.8, 0)
			root.add_child(cap)
	_mark("colonnade", "Colonnade of Kings", Vector3(ring.x, _ground(ring.x, ring.y), ring.y))
	# Giant sandstone stacks: the pack's formations at four times their size.
	for k in 7:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(180.0, 560.0)
		var kind: String = ["X:sandstone_0", "X:sandstone_2", "X:sandstone_4"][k % 3]
		var s := rng.randf_range(3.0, 4.5)
		var holder := Node3D.new()
		holder.position = Vector3(p.x, _ground(p.x, p.y) - 2.0, p.y)
		holder.rotation.y = rng.randf() * TAU
		root.add_child(holder)
		for part in FoliageLib.parts(kind):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO) * (part[1] as Transform3D)
			holder.add_child(mi)
		_cylinder_body(holder.position + Vector3(0, 10, 0), FoliageLib.solid_radius(kind) * s * 0.8, 20.0)
	# Oases: palms round the water, glowing flowers at the edge.
	for o in Realms.OASES:
		var oc: Vector2 = o[0]
		var r: float = o[1]
		for k in 10:
			var a := TAU * k / 10.0 + rng.randf() * 0.3
			var p := oc + Vector2(cos(a), sin(a)) * (r * 1.5 + rng.randf_range(0, 10))
			_prop(root, "P:palm", Vector3(p.x, _ground(p.x, p.y) - 0.2, p.y), rng.randf_range(0.9, 1.3), rng.randf() * TAU)
		_mark("oasis_%d" % Realms.OASES.find(o), "Oasis", Vector3(oc.x, 0.5, oc.y))


func _sun_tint(node: MeshInstance3D) -> void:
	for s in node.mesh.get_surface_count():
		var m := node.mesh.surface_get_material(s) as BaseMaterial3D
		if m:
			m = m.duplicate()
			m.albedo_color = m.albedo_color * Color(1.15, 0.92, 0.72)
			node.set_surface_override_material(s, m)


# -------------------------------------------------------------- coast ---

func _coast() -> void:
	var root := Node3D.new()
	add_child(root)
	var v := Realms.COAST + Vector2(-260.0, -230.0)
	var seaward := Vector2(1, 1).normalized()
	var houses := [
		[Vector2(-18, -6), 7.0, 6.0, 2, "teal"], [Vector2(10, -16), 6.5, 6.0, 1, "cobalt"],
		[Vector2(22, 8), 8.0, 6.5, 2, "teal"], [Vector2(-8, 18), 6.0, 5.5, 1, "rose"],
		[Vector2(-30, 14), 7.0, 6.0, 2, "cobalt"],
	]
	var i := 0
	for h in houses:
		var p: Vector2 = v + h[0]
		var mesh := ArchKit.house(h[1], h[2], h[3], h[4], {"seed": 40 + i, "roof_style": "gable" if i % 2 else "hip"})
		var lo := INF
		for d in [Vector2(-3, -3), Vector2(3, -3), Vector2(-3, 3), Vector2(3, 3)]:
			lo = minf(lo, _ground(p.x + d.x, p.y + d.y))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(p.x, lo, p.y)
		mi.rotation.y = atan2(seaward.x, seaward.y) + (i % 2) * PI * 0.5
		root.add_child(mi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(h[1], h[3] * 3.2, h[2])
		cs.shape = box
		cs.position = Vector3(0, h[3] * 1.6, 0)
		body.add_child(cs)
		mi.add_child(body)
		i += 1
	_mark("saltmere", "Saltmere", Vector3(v.x, _ground(v.x, v.y), v.y))
	# A jetty: plank deck on posts from the shore out over the water.
	var shore := v
	for k in 80:
		var p := v + seaward * (k * 4.0)
		if _ground(p.x, p.y) < TerrainGen.WATER + 0.6:
			shore = p
			break
	var jetty_len := 26.0
	var mid := shore + seaward * (jetty_len * 0.5 - 3.0)
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 0.3, jetty_len)
	deck.mesh = bm
	deck.material_override = _wood
	deck.position = Vector3(mid.x, TerrainGen.WATER + 0.9, mid.y)
	deck.rotation.y = atan2(seaward.x, seaward.y)
	root.add_child(deck)
	var dbody := StaticBody3D.new()
	var dcs := CollisionShape3D.new()
	var dbox := BoxShape3D.new()
	dbox.size = bm.size
	dcs.shape = dbox
	dbody.add_child(dcs)
	deck.add_child(dbody)
	for k in 6:
		for sx in [-1.4, 1.4]:
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.14
			pc.bottom_radius = 0.16
			pc.height = 3.0
			post.mesh = pc
			post.material_override = _wood
			post.position = Vector3(sx, -1.2, -jetty_len * 0.5 + 2.0 + k * (jetty_len - 4.0) / 5.0)
			deck.add_child(post)
	_mark("jetty", "Saltmere Jetty", deck.position)
	# The Singing Grotto: giant crystals on a headland along the shore.
	var gr := Realms.COAST + Vector2(120.0, -260.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var gy := _ground(gr.x, gr.y)
	for k in 14:
		var a := rng.randf() * TAU
		var p := gr + Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 26.0)
		_crystal(root, Vector3(p.x, _ground(p.x, p.y) - 0.4, p.y), rng.randf_range(1.5, 4.5), Color(0.5, 0.95, 1.0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.9, 1.0)
	glow.light_energy = 2.5
	glow.omni_range = 30.0
	glow.shadow_enabled = false
	glow.position = Vector3(gr.x, gy + 6.0, gr.y)
	root.add_child(glow)
	_mark("grotto", "The Singing Grotto", Vector3(gr.x, gy, gr.y))


# ---------------------------------------------------------------- sky ---

func _sky() -> void:
	var isles := Realms.sky_isles(gen)
	for pair in Realms.SKY_BRIDGES:
		var a: Array = isles[pair[0]]
		var b: Array = isles[pair[1]]
		var ca: Vector3 = a[0]
		var cb: Vector3 = b[0]
		var dir := Vector3(cb.x - ca.x, 0, cb.z - ca.z).normalized()
		var from := ca + dir * (float(a[1]) * 0.8)
		var to := cb - dir * (float(b[1]) * 0.8)
		from.y = ca.y + 0.3
		to.y = cb.y + 0.3
		_bridge(from, to)
	_mark("aerie", "The Aerie", (isles[0][0] as Vector3))
	# The isle's far edge (a hidden overlook) and the farthest, highest isle.
	var c0: Vector3 = isles[0][0]
	_mark("aerie_edge", "The Aerie's edge", c0 + Vector3(-float(isles[0][1]) * 0.8, 0.5, -float(isles[0][1]) * 0.35))
	_mark("aerie_far", "The farthest isle", (isles[6][0] as Vector3) + Vector3(0, 0.5, 0))


## A rope-and-plank bridge with a walkable deck.
func _bridge(from: Vector3, to: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = (from + to) * 0.5
	holder.look_at_from_position(holder.global_position, to, Vector3.UP)
	var length := from.distance_to(to)
	var deck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 0.22, length)
	deck.mesh = bm
	deck.material_override = _wood
	holder.add_child(deck)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 0.4, length)
	cs.shape = box
	body.add_child(cs)
	holder.add_child(body)
	# Rails: thin ropes on posts.
	var posts := int(length / 4.0)
	for k in posts + 1:
		for sx in [-1.25, 1.25]:
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.06
			pc.bottom_radius = 0.07
			pc.height = 1.1
			post.mesh = pc
			post.material_override = _wood
			post.position = Vector3(sx, 0.55, -length * 0.5 + k * length / maxf(posts, 1))
			holder.add_child(post)
	# The rails hold: an invisible rail-high wall each side, so a step off
	# the edge of a bridge over open sky is never an accident (jumping over
	# is still a choice, to glide).
	for sx in [-1.3, 1.3]:
		Solid.box(holder, Vector3(0.12, 1.15, length), Vector3(sx, 0.575, 0))
	for sx in [-1.25, 1.25]:
		var rope := MeshInstance3D.new()
		var rc := BoxMesh.new()
		rc.size = Vector3(0.05, 0.05, length)
		rope.mesh = rc
		rope.material_override = _mat(Color(0.75, 0.66, 0.5), 1.0)
		rope.position = Vector3(sx, 1.05, 0)
		holder.add_child(rope)


# ------------------------------------------------------------- shared ---

func _crystal(parent: Node3D, at: Vector3, s: float, tint: Color) -> void:
	for part in FoliageLib.parts("P:crystal"):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * s), at) * (part[1] as Transform3D)
		var m := (part[0] as Mesh).surface_get_material(0).duplicate() as StandardMaterial3D
		m.albedo_color = Color(tint.r * 0.5, tint.g * 0.62, tint.b * 0.7, 0.9)
		m.emission = tint * 0.45
		mi.material_override = m
		parent.add_child(mi)
	_cylinder_body(at + Vector3(0, s * 1.4, 0), s * 0.6, s * 2.8)


func _prop(parent: Node3D, kind: String, at: Vector3, s: float, yaw: float) -> void:
	for part in FoliageLib.parts(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), at) * (part[1] as Transform3D)
		parent.add_child(mi)
	if FoliageLib.category(kind) == "tree":
		_cylinder_body(at + Vector3(0, 3, 0), 0.4 * s, 6.0)


func _cylinder_body(centre: Vector3, r: float, h: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	cs.shape = cyl
	body.add_child(cs)
	add_child(body)
	body.global_position = centre


func _motes(at: Vector3, extents: Vector3, col: Color, amount: int, size := 0.08, life := 5.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = col
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.gravity = Vector3(0, 0.15, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.spread = 180.0
	p.position = at
	p.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	return p
