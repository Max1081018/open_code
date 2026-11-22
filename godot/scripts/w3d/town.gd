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
## Which way each model's front (door, seat) faces in its own frame: the
## yaw added after turning +Z toward the plaza.
const FRONT_OFFSET := {"bench": -PI * 0.5}
## [model, x, z, height m, solid] — fronts turned to the plaza.
const TOWN := [
	["fountain_small", 0.0, 0.0, 3.6, true],
	["magic_tower", 0.0, -52.0, 22.0, true],
	["statue", -7.5, -38.0, 3.8, true],
	["house_blue", -24.0, -16.0, 11.0, true],
	["house_med", 24.0, -18.0, 10.0, true],
	["house_wood", -27.0, 14.0, 8.5, true],
	["house_tower", 25.0, 17.0, 14.0, true],
	["house_blue", -7.0, 45.0, 10.0, true],
	["shrine_stone", 18.0, -5.0, 4.2, true],
	["fountain", -16.5, -4.5, 3.2, true],
	["market_stall", 5.8, -11.5, 3.6, true],
	["market_stall", -5.8, -11.5, 3.6, true],
	["crates", 9.0, -14.5, 1.1, false],
	["crates", -9.5, -14.0, 1.1, false],
	["bench", 8.0, 2.9, 1.0, false],
	["bench", -1.2, 8.4, 1.0, false],
	["bench", -8.3, 1.5, 1.0, false],
	["bench", 7.4, -4.2, 1.0, false],
]
## Shade trees between the houses: [kind, x, z].
const TREES := [["CommonTree_3", -12.0, -27.0], ["CommonTree_1", 12.0, -30.0], ["CommonTree_2", 38.0, -4.0],
	["CommonTree_4", -40.0, 6.0], ["CommonTree_5", 22.0, 40.0], ["CommonTree_1", -30.0, 36.0],
	["CommonTree_3", 40.0, -30.0], ["CommonTree_2", -38.0, -34.0]]
## Isle props: [model, island index, height, offset from centre].
const ISLES := [["ruin_arch", 1, 10.0, Vector2(0, 0)], ["ruin_arch", 6, 14.0, Vector2(6, 0)]]
## Free-floating mini isles: [model, x, z, altitude above ground, height].
const FLOATERS := [["sky_house", -150.0, 130.0, 70.0, 30.0], ["shrine_sky", 190.0, 60.0, 55.0, 20.0]]

var game: Node
var chests: Array = []   ## [Node3D, opened: bool, loot, magic: bool]


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	for spec in TOWN:
		var at := Vector3(spec[1], 0, spec[2])
		at.y = gen.height(at.x, at.z)
		var yaw := atan2(-at.x, -at.z) if Vector2(at.x, at.z).length() > 1.0 else 0.0
		yaw += FRONT_OFFSET.get(spec[0], 0.0)
		place(spec[0], at, spec[3], yaw, "box" if spec[4] else "")
	_garden_flowers(gen)
	# A ring of flowers round the fountain.
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector2(cos(a), sin(a)) * 5.2
		place("flower_pot", Vector3(p.x, gen.height(p.x, p.y), p.y), 0.75, a)
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
		(m as MeshInstance3D).visibility_range_end = 900.0
	var k := height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
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
			place("flower_pot", Vector3(p.x, gen.height(p.x, p.y), p.y), 0.75, randf() * TAU)


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
			place("lantern", at, 3.6, atan2(-side.x * s, -side.y * s))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.78, 0.48)
			l.light_energy = 1.3
			l.omni_range = 9.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 70.0
			l.distance_fade_length = 20.0
			l.position = at + Vector3(0, 3.1, 0)
			add_child(l)
			d += 14.0
			n += 1


func _tree(kind: String, at: Vector3) -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at
	holder.rotation.y = randf() * TAU
	for part in FoliageLib.parts(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
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
	var c := place("chest_magic" if magic else "chest", at, 1.4 if magic else 0.8, randf() * TAU)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.85, 1.0) if magic else Color(1.0, 0.85, 0.5)
	glow.light_energy = 0.9
	glow.omni_range = 4.0
	glow.position = Vector3(0, 1.0, 0)
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 50.0
	c.add_child(glow)
	var loot: Array = [["gold_coin", randi_range(6, 20)]]
	if magic:
		loot.append([["heart_crystal", "lumen_core", "glowshard", "ruby", "emerald"].pick_random(), 1])
		loot.append(["glowshard", randi_range(2, 5)])
	else:
		loot.append([["apple", "cooked_meat", "glowshard", "copper_ore", "iron_ore"].pick_random(), randi_range(1, 4)])
	chests.append([c, false, loot, magic])


func _process(_delta: float) -> void:
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
	Sfx.play("chest")
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector3(1.15, 0.85, 1.15), 0.12)
	t.tween_property(node, "scale", Vector3.ONE, 0.2)
	t.tween_interval(2.0)
	t.tween_property(node, "scale", Vector3.ZERO, 0.4)
	t.tween_callback(node.queue_free)
