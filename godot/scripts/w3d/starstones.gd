class_name Starstones
extends Node3D
## Starstones: waystones of the fallen star, one in Starfall Haven and one
## in the heart of every region. Walking up to one attunes it (saved);
## from the map she can travel to any attuned stone.
##   build(game)        place them
##   attuned            ids she has woken
##   travel(id)         go there (veiled while the land streams in)

signal attuned_changed

var game: Node
## [{id, name, pos}]
var stones: Array = []
var attuned := {}
var _nodes := {}     ## id -> {crystal, light}
var _spin := 0.0


func build(the_game: Node) -> void:
	game = the_game
	var gen: TerrainGen = game.world.gen
	# The town's own stone stands at the plaza's south edge.
	var town := Vector3(0, 0, 16)
	stones.append({"id": "haven", "name": "Starfall Haven", "pos": town})
	for r in heartlands(gen):
		stones.append({"id": String(r[0]).to_lower().replace(" ", "_"), "name": r[0], "pos": r[1]})
	for s in stones:
		var p: Vector3 = s.pos
		p.y = gen.height(p.x, p.z)
		s.pos = p
		_make(s)


## Each region's heartland on dry, gentle ground: [name, position].
static func heartlands(gen: TerrainGen) -> Array:
	var span := (TerrainGen.HALF + 120.0) * 2.0
	var n := 48
	var cell := span / n
	var grid := []
	for j in n:
		for i in n:
			var x := -span * 0.5 + (i + 0.5) * cell
			var z := -span * 0.5 + (j + 0.5) * cell
			var ok := gen.height(x, z) > TerrainGen.WATER + 1.0 and gen.normal(x, z).y > 0.85
			grid.append(gen.biome(x, z) if ok else -1)
	var best := {}
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var b: int = grid[j * n + i]
			if b < 0 or b == TerrainGen.Biome.BEACH or b == TerrainGen.Biome.FOREST:
				continue
			var score := 0
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var jj := clampi(j + dj, 0, n - 1)
					var ii := clampi(i + di, 0, n - 1)
					if grid[jj * n + ii] == b:
						score += 1
			if not best.has(b) or score > best[b][0]:
				best[b] = [score, Vector3(-span * 0.5 + (i + 0.5) * cell, 0, -span * 0.5 + (j + 0.5) * cell)]
	var out := []
	for b in best:
		out.append([gen.biome_name(b), best[b][1]])
	return out


func _make(s: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = s.pos
	# A tapered four-sided obelisk of pale stone with a gold band.
	var stone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.55
	cyl.height = 3.0
	cyl.radial_segments = 4
	cyl.rings = 1
	stone.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.86, 0.84, 0.92)
	sm.roughness = 0.8
	stone.material_override = sm
	root.add_child(stone)
	stone.position = Vector3(0, 1.4, 0)
	stone.rotation.y = PI * 0.25
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.47
	bc.bottom_radius = 0.49
	bc.height = 0.16
	bc.radial_segments = 4
	band.mesh = bc
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.95, 0.78, 0.4)
	gm.metallic = 0.8
	gm.roughness = 0.35
	band.material_override = gm
	root.add_child(band)
	band.position = Vector3(0, 0.55, 0)
	band.rotation.y = PI * 0.25
	# The star crystal floating above it.
	var crystal := MeshInstance3D.new()
	crystal.mesh = ArchKit.star_crystal()
	crystal.scale = Vector3.ONE * 0.32
	root.add_child(crystal)
	crystal.position = Vector3(0, 3.6, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(0.72, 0.5, 1.0)
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	light.position = Vector3(0, 3.4, 0)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.5
	cs.height = 3.0
	shape.shape = cs
	shape.position = Vector3(0, 1.5, 0)
	body.add_child(shape)
	root.add_child(body)
	_nodes[s.id] = {"crystal": crystal, "light": light}
	_refresh(s.id)


func _refresh(id: String) -> void:
	var n: Dictionary = _nodes[id]
	var on := attuned.has(id)
	(n.light as OmniLight3D).light_energy = 2.2 if on else 0.5
	(n.crystal as MeshInstance3D).transparency = 0.0 if on else 0.45


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_spin += delta
	var p: Vector3 = game.player.global_position
	for s in stones:
		var n: Dictionary = _nodes[s.id]
		var c := n.crystal as Node3D
		c.rotation.y = _spin * 0.8
		c.position.y = 3.6 + sin(_spin * 1.6 + float(s.pos.x)) * 0.12
		if not attuned.has(s.id) and p.distance_to(s.pos) < 4.5:
			attune(s.id)


func attune(id: String) -> void:
	if attuned.has(id):
		return
	attuned[id] = true
	_refresh(id)
	var s := stone(id)
	Arcana.circle(game, s.pos, 2.4, Color(0.8, 0.6, 1.0), 0.9, 0.8)
	Arcana.sparks(game, s.pos + Vector3(0, 3.4, 0), Color(0.85, 0.65, 1.0), 40, 5.0, 0.12)
	Sfx.play("magic_cast", -4.0)
	game.hud.banner("Starstone attuned", String(s.name))
	attuned_changed.emit()
	game.call_deferred("autosave")


func stone(id: String) -> Dictionary:
	for s in stones:
		if s.id == id:
			return s
	return {}


## Travel to an attuned stone: the screen dims, she arrives beside it.
func travel(id: String) -> void:
	var s := stone(id)
	if s.is_empty() or not attuned.has(id):
		return
	var to: Vector3 = s.pos + Vector3(2.2, 0, 2.2)
	to.y = game.world.height_at(to.x, to.z) + 0.3
	await game.hud.veil(1.0, 0.45).finished
	game.player.global_position = to
	game.player.velocity = Vector3.ZERO
	game.world.warm(to)
	if game.grass:
		game.grass.warm(to)
	game.cam.global_position = to + Vector3(0, 2, 4)
	Sfx.play("magic_cast", -6.0)
	await get_tree().create_timer(0.2).timeout
	game.hud.veil(0.0, 0.6)
	Arcana.circle(game, Vector3(to.x, game.world.height_at(to.x, to.z), to.z), 1.8, Color(0.8, 0.6, 1.0), 0.6, 1.0)
