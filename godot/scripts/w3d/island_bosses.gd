class_name IslandBosses
extends Node3D
## The guardian of each starting island, waiting in its arena:
##   Great Jungle  — the Thornmother, on the World Tree's mesa
##   Skybound Isle — the Stormwing, over the Aerie
##   Crystal Coast — the Tidewarden, on the open ground by the grotto
## A ring of standing runes marks each arena from afar. Walking in wakes the
## guardian (its name and title, the boss bar); it fights in three phases
## (Enemy3D.BOSS_SPECS). Beating it gives rich loot, a lot of experience and
## a heart crystal, and is saved: it never returns. After the island's first
## chapter the quest tracker points to the arena.

const ARENAS := {
	"jungle": {"kind": "thornmother", "near": "world_tree", "dist": 42.0, "flat": true},
	"sky": {"kind": "stormwing", "near": "aerie", "dist": 0.0, "flat": false},
	"coast": {"kind": "tidewarden", "near": "grotto", "dist": 36.0, "flat": true},
}
const WAKE_R := 26.0
const RING_R := 18.0

var game: Node
var defeated := {}      ## island id -> true
var arenas := {}        ## island id -> Vector3 (arena centre)
var _live := {}         ## island id -> Enemy3D
var _check := 0.0


func build(the_game: Node) -> void:
	game = the_game
	var lm: Dictionary = game.realms.landmarks
	for id in ARENAS:
		var a: Dictionary = ARENAS[id]
		var c: Vector3
		if id == "sky":
			# The Aerie's own walkable top (where a Skybound journey starts).
			c = Realms.spawn_point(game.world.gen, "sky")
		elif lm.has(a.near):
			c = lm[a.near].pos
		else:
			continue
		var at := c
		if a.flat:
			at = _flat_near(c, float(a.dist))
		arenas[id] = at
		_ring(at, Enemy3D.BOSS_SPECS[a.kind].element)
	game.play.enemy_killed.connect(_on_killed)


## Open level ground about `dist` from `c` (the first found going round).
func _flat_near(c: Vector3, dist: float) -> Vector3:
	var gen: TerrainGen = game.world.gen
	for r: float in [dist, dist * 0.7, dist * 1.3, dist * 0.45]:
		for k in 16:
			var a := k * TAU / 16.0 + 0.3
			var x := c.x + cos(a) * r
			var z := c.z + sin(a) * r
			var h := gen.height(x, z)
			if h > TerrainGen.WATER + 1.5 and gen.normal(x, z, 5.0).y > 0.94 and gen.normal(x + 7.0, z, 5.0).y > 0.9 \
					and not _near_water(x, z):
				return Vector3(x, h, z)
	var y := gen.height(c.x + dist, c.z)
	return Vector3(c.x + dist, y, c.z)


## Waterfall pools and oases sit above sea level: keep arenas out of them.
func _near_water(x: float, z: float) -> bool:
	var lm: Dictionary = game.realms.landmarks
	for id in lm:
		var s := String(id)
		if s.begins_with("falls_") or s.begins_with("oasis"):
			var p: Vector3 = lm[id].pos
			if Vector2(p.x - x, p.z - z).length() < 34.0:
				return true
	return false


## Eight standing runestones round the arena, glowing in the guardian's colour.
func _ring(at: Vector3, colour: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.5, 0.5, 0.56)
	stone_mat.roughness = 0.85
	var glow := StandardMaterial3D.new()
	glow.albedo_color = colour
	glow.emission_enabled = true
	glow.emission = colour
	glow.emission_energy_multiplier = 1.6
	for k in 8:
		var a := k * TAU / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * RING_R
		var ground: float = game.world.height_at(at.x + p.x, at.z + p.z)
		if absf(ground - at.y) > 6.0:
			ground = at.y   # over a sky isle's edge: keep to its height
		var stone := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 3.4, 0.6)
		stone.mesh = box
		stone.material_override = stone_mat
		root.add_child(stone)
		stone.global_position = Vector3(at.x + p.x, ground + 1.5, at.z + p.z)
		stone.rotation = Vector3(0.05 * sin(k * 1.7), -a, 0.04 * cos(k * 2.3))
		var rune := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(0.3, 0.9, 0.05)
		rune.mesh = q
		rune.material_override = glow
		stone.add_child(rune)
		rune.position = Vector3(0, 0.5, 0.31)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.4
	var p: Vector3 = game.player.global_position
	for id in arenas:
		if defeated.has(id) or (_live.has(id) and is_instance_valid(_live[id])):
			continue
		var at: Vector3 = arenas[id]
		if Vector2(p.x - at.x, p.z - at.z).length() < WAKE_R and absf(p.y - at.y) < 20.0:
			wake(id)


## The guardian rises in its arena.
func wake(id: String) -> Enemy3D:
	var at: Vector3 = arenas[id]
	if id == "sky":
		# On the isle's real crown, not inside it.
		var y = game.surface_y(at)
		if y != null:
			at.y = float(y)
			arenas[id] = at
	var kind: String = ARENAS[id].kind
	var colour: Color = Enemy3D.BOSS_SPECS[kind].element
	Arcana.pillar(game, at, 2.0, 18.0, colour, 1.2)
	Arcana.circle(game, at, 6.0, colour, 1.5, 1.0)
	var e: Enemy3D = game.play.spawn_enemy(kind, at + Vector3(0, 0.2, 0))
	_live[id] = e
	return e


func _on_killed(e: Node) -> void:
	for id in _live:
		if _live[id] == e:
			defeated[id] = true
			_live.erase(id)
			game.hud.banner("Guardian defeated", String((e as Enemy3D).spec.boss))
			game.call_deferred("autosave")
			return


## For the quest tracker: the arena of this island's guardian, if it waits.
func pending(island: String) -> Dictionary:
	if not arenas.has(island) or defeated.has(island):
		return {}
	var kind: String = ARENAS[island].kind
	return {"title": "Guardian — Defeat %s" % String(Enemy3D.BOSS_SPECS[kind].boss), "detail": "Optional",
		"target": arenas[island]}


func to_dict() -> Dictionary:
	return {"defeated": defeated.keys()}


func from_dict(d: Dictionary) -> void:
	for id in d.get("defeated", []):
		defeated[String(id)] = true
