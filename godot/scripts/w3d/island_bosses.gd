class_name IslandBosses
extends Node3D
## The guardian of each starting island, waiting in its arena:
##   Great Jungle  — the Thornmother, on the World Tree's mesa
##   Skybound Isle — the Stormwing, on the isle west of the Aerie, over its
##                   own bridge (never on the Aerie, where a journey starts)
##   Crystal Coast — the Tidewarden, on the open ground by the grotto
## A ring of standing runes marks each arena from afar. Walking in wakes the
## guardian (its name and title, the boss bar); it fights in three phases
## (Enemy3D.BOSS_SPECS). Beating it gives rich loot, a lot of experience and
## a heart crystal, and is saved: it never returns. After the island's first
## chapter the quest tracker points to the arena.

const ARENAS := {
	"jungle": {"kind": "thornmother", "near": "world_tree", "dist": 42.0, "flat": true},
	"sky": {"kind": "stormwing", "isle": 3, "flat": false},
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
		if a.has("isle"):
			# A floating isle of its own, on its grassy crown.
			c = (Realms.sky_isles(game.world.gen)[int(a.isle)] as Array)[0]
			var top := _crown(c.x, c.z)
			if not is_nan(top):
				c.y = top
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


## Open level ground about `dist` from `c`: the flattest arena floor found
## going round in widening rings (judged over the whole floor, not one
## point), dry and clear of falls and oases.
func _flat_near(c: Vector3, dist: float) -> Vector3:
	var gen: TerrainGen = game.world.gen
	var best := Vector3(c.x + dist, gen.height(c.x + dist, c.z), c.z)
	var best_score := -1.0
	for r: float in [dist, dist * 0.7, dist * 1.3, dist * 0.45, dist * 1.8, dist * 2.4, dist * 3.2]:
		for k in 24:
			var a := k * TAU / 24.0 + 0.3
			var x := c.x + cos(a) * r
			var z := c.z + sin(a) * r
			var h := gen.height(x, z)
			if h < TerrainGen.WATER + 1.5 or _near_water(x, z):
				continue
			var score := _floor_flatness(gen, x, z, h)
			if score > best_score:
				best_score = score
				best = Vector3(x, h, z)
		if best_score > 0.95:
			break   # flat enough this close in: no need to wander further
	return best


## How level the floor of an arena centred here is: the least upright ground
## normal under it, less any drop or rise across it.
func _floor_flatness(gen: TerrainGen, x: float, z: float, h: float) -> float:
	var worst := gen.normal(x, z, 5.0).y
	for k in 8:
		var a := k * TAU / 8.0
		var px := x + cos(a) * 11.0
		var pz := z + sin(a) * 11.0
		worst = minf(worst, gen.normal(px, pz, 5.0).y - absf(gen.height(px, pz) - h) * 0.02)
	return worst


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


## Eight standing runestones round the arena, each with a rune cut into its
## face that glows in the guardian's colour.
func _ring(at: Vector3, colour: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_texture = load("res://assets/textures/terrain/rock.jpg")
	stone_mat.albedo_color = Color(0.66, 0.66, 0.72)
	stone_mat.uv1_triplanar = true
	stone_mat.uv1_scale = Vector3.ONE * 0.7
	stone_mat.roughness = 0.92
	if _rune_shader == null:
		_rune_shader = load("res://scripts/shaders/rune_glyph.gdshader")
	for k in 8:
		var a := k * TAU / 8.0
		var ground := NAN
		var p := Vector3.ZERO
		if not is_nan(_crown(at.x, at.z)):
			# On a floating isle: each stone stands on the crown, drawn in
			# from the ragged rim so none hangs over the drop.
			for rr: float in [RING_R, 16.0, 14.0, 12.0, 10.0]:
				p = Vector3(cos(a), 0, sin(a)) * rr
				ground = _crown(at.x + p.x, at.z + p.z, 0.15)
				if not is_nan(ground):
					break
			if is_nan(ground):
				continue
		else:
			p = Vector3(cos(a), 0, sin(a)) * RING_R
			ground = game.world.height_at(at.x + p.x, at.z + p.z)
		var h := 3.0 + 0.5 * sin(k * 2.9 + at.x)
		var stone := MeshInstance3D.new()
		stone.mesh = _menhir(h, k + int(absf(at.x)))
		stone.material_override = stone_mat
		root.add_child(stone)
		# Sunk a little into the ground, facing the arena's centre, leaning.
		stone.global_position = Vector3(at.x + p.x, ground - 0.25, at.z + p.z)
		stone.rotation = Vector3(0.06 * sin(k * 1.7), PI * 0.5 - a, 0.05 * cos(k * 2.3))
		var rune := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.34, 1.1)
		rune.mesh = q
		var rm := ShaderMaterial.new()
		rm.shader = _rune_shader
		rm.set_shader_parameter("tint", colour)
		rm.set_shader_parameter("seed", float(k))
		rune.material_override = rm
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stone.add_child(rune)
		# On the face toward the centre (the stone's +Z), just proud of it.
		rune.position = Vector3(0, h * 0.5, _face_z(h * 0.5) + 0.02)


static var _rune_shader: Shader
const _MENHIR_DEPTH := 0.34   ## half-thickness of the slab at its foot


## A rough standing stone `h` tall: a flat slab of seven sides tapering and
## twisting a little as it rises, its top broken at a slant. Flat-shaded.
static func _menhir(h: float, seed_i: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 300 + seed_i
	noise.frequency = 1.4
	var sides := 7
	var rings := 5
	var rows := []
	for r in rings + 1:
		var t := float(r) / rings
		var y := t * h
		var width := lerpf(0.55, 0.36, t)
		var depth := lerpf(_MENHIR_DEPTH, 0.22, t)
		var twist := t * 0.18
		var row := []
		for s in sides:
			var a := TAU * s / sides + twist
			var j := 1.0 + noise.get_noise_2d(s * 3.1, y * 2.0) * 0.16
			var v := Vector3(cos(a) * width * j, y, sin(a) * depth * j)
			if r == rings:
				# The broken top: higher on one side.
				v.y -= (0.5 + 0.5 * cos(a + seed_i)) * 0.45
			row.append(v)
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for r in rings:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0: Vector3 = rows[r][s]
			var a1: Vector3 = rows[r][s2]
			var b0: Vector3 = rows[r + 1][s]
			var b1: Vector3 = rows[r + 1][s2]
			for v in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(v)
	var top: Array = rows[rings]
	var c := Vector3.ZERO
	for v: Vector3 in top:
		c += v
	c /= top.size()
	for s in sides:
		st.add_vertex(c)
		st.add_vertex(top[(s + 1) % sides])
		st.add_vertex(top[s])
	st.generate_normals()
	return st.commit()


## How far the stone's face stands out (+Z) at height y (for the rune).
static func _face_z(_y: float) -> float:
	return _MENHIR_DEPTH * 0.86


## A sky isle's crown height here (NAN where there is none).
func _crown(x: float, z: float, inset := 0.0) -> float:
	if game.islands == null:
		return NAN
	return (game.islands as SkyIslands).crown_y(x, z, inset)


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
	if ARENAS[id].has("isle"):
		# On the isle's real (collision) crown, not inside it.
		var y = game.surface_y(at)
		if y != null:
			at.y = float(y)
			arenas[id] = at
	var kind: String = ARENAS[id].kind
	var colour: Color = Enemy3D.BOSS_SPECS[kind].element
	Arcana.pillar(game, at, 1.6, 18.0, colour, 0.7)
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
