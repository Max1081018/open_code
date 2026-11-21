class_name Town
extends Node3D
## Starfall Haven, the town on the central plateau, and the props of the wider
## world: stylized houses around a plaza with a mage statue, the magic tower
## as the town's landmark, a waypoint shrine and street lanterns; on the sky
## isles a dwelling, a shrine and a ruined arch; treasure chests scattered
## across the land and isles that open with F (or the hand button).

const DIR := "res://assets/models/world/"
## [model, x, z, height m, solid]
const TOWN := [
	["statue", 0.0, 0.0, 3.6, true],
	["magic_tower", 0.0, -52.0, 22.0, true],
	["house_blue", -32.0, -20.0, 10.0, true],
	["house_med", 30.0, -24.0, 9.0, true],
	["house_wood", -36.0, 22.0, 10.0, true],
	["house_tower", 32.0, 30.0, 14.0, true],
	["house_blue", -10.0, 44.0, 10.0, true],
	["shrine_stone", 16.0, 8.0, 4.2, true],
	["lantern", 10.0, -10.0, 3.6, false], ["lantern", -10.0, -10.0, 3.6, false],
	["lantern", 10.0, 12.0, 3.6, false], ["lantern", -12.0, 12.0, 3.6, false],
	["lantern", 0.0, -30.0, 3.6, false],
]
## Isle props: [model, island index, height, offset from centre]
const ISLES := [["sky_house", 4, 22.0, Vector2(0, 0)], ["ruin_arch", 1, 10.0, Vector2(0, 0)],
	["shrine_sky", 3, 12.0, Vector2(0, 0)], ["ruin_arch", 6, 14.0, Vector2(6, 0)]]

var game: Node
var chests: Array = []   ## [Node3D, opened: bool, loot]


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	for spec in TOWN:
		var at := Vector3(spec[1], 0, spec[2])
		at.y = gen.height(at.x, at.z)
		var yaw := atan2(-at.x, -at.z) if Vector2(at.x, at.z).length() > 1.0 else 0.0
		place(spec[0], at, spec[3], yaw, spec[4])
		if spec[0] == "lantern":
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.5)
			l.light_energy = 1.2
			l.omni_range = 9.0
			l.position = at + Vector3(0, 3.0, 0)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 60.0
			add_child(l)
	var tops: Array = game.islands.tops
	for spec in ISLES:
		var top: Array = tops[spec[1]]
		var c: Vector3 = top[0]
		var off: Vector2 = spec[3]
		place(spec[0], c + Vector3(off.x, 0.3, off.y), spec[2], randf() * TAU, true)
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


## Put a model in the world, `height` metres tall, base on `at`.
func place(model: String, at: Vector3, height: float, yaw: float, solid: bool) -> Node3D:
	var scene: PackedScene = load(DIR + model + ".glb")
	var holder := Node3D.new()
	add_child(holder)
	var inst: Node3D = scene.instantiate()
	holder.add_child(inst)
	var box := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
		(m as MeshInstance3D).visibility_range_end = 900.0
	var k := height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	holder.global_position = at
	holder.rotation.y = yaw
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(box.size.x * k * 0.8, height, box.size.z * k * 0.8)
		cs.shape = shape
		cs.position = Vector3(0, height * 0.5, 0)
		body.add_child(cs)
		holder.add_child(body)
	return holder


func _chest(at: Vector3, magic: bool) -> void:
	var c := place("chest_magic" if magic else "chest", at, 1.4 if magic else 0.8, randf() * TAU, false)
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
