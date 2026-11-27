class_name Secrets
extends Node3D
## What the world hides, and what it remembers once found.
##   Discovery   — every named landmark (RealmFeatures) and Starstone is
##                 "discovered" when Lyra comes near: a banner, XP, and its name
##                 on the world map from then on.
##   Starlit chests — tucked behind waterfalls, among roots, inside ruins, at
##                 the far ends of things; given away only by drifting motes.
##   Rune shrines — three rune stones round a shrine, marked with one, two and
##                 three glyph rings: strike them in that order to open it.
##   Starsilver veins — rare glowing crystal nodes; three strikes break one
##                 for Starsilver, a crafting material found nowhere else.
##   The Colossus of Kings — wakes at the Colonnade only at night.
## All of it is saved (to_dict / from_dict).

const DISCOVER_R := 28.0
const CHEST_XP := 40
const SHRINE_XP := 120

var game: Node
var discovered := {}         ## id -> name
var opened := {}             ## chest id -> true
var solved := {}             ## shrine id -> true
var mined := {}              ## vein id -> true
var colossus_down := false
var _chests: Array = []      ## [id, node, loot]
var _shrines: Array = []     ## [id, centre, [pillar nodes], order progress, reward]
var _veins: Array = []       ## [id, node, hits]
var _check := 0.0
var _colossus: Enemy3D
var _night := 0.0


func build(the_game: Node) -> void:
	game = the_game
	var r: RealmFeatures = game.realms
	var lm: Dictionary = r.landmarks
	# Starlit chests at the hidden places.
	var spots := [
		["falls_chest_0", _near(lm, "falls_0", 6.0, 0.6), [["heart_crystal", 1], ["gold_coin", 40]]],
		["falls_chest_2", _near(lm, "falls_2", 6.0, 3.6), [["lumen_core", 1], ["glowshard", 6]]],
		["root_chest", _near(lm, "world_tree", 9.0, 2.0), [["relic_luckstone", 1], ["gold_coin", 60]]],
		["colonnade_chest", _near(lm, "colonnade", 4.0, 1.0), [["ruby", 3], ["gold_coin", 80]]],
		["oasis_chest", _near(lm, "oasis_1", 40.0, 4.2), [["glow_flask", 2], ["emerald", 2]]],
		["grotto_chest", _near(lm, "grotto", 8.0, 5.0), [["heart_crystal", 1], ["glowshard", 8]]],
		["jetty_chest", _near(lm, "jetty", 3.0, 0.0), [["gold_coin", 50], ["stew", 3]]],
		["far_isle_chest", _near(lm, "aerie_far", 4.0, 1.0), [["lumen_core", 1], ["heart_crystal", 1]]],
	]
	for s in spots:
		if s[1] != Vector3.INF:
			_make_chest(s[0], s[1], s[2])
	# Rune shrines.
	for sh in [["jungle_runes", "jungle_shrine", [["relic_moth_lantern", 0], ["glowshard", 10], ["gold_coin", 60]]],
			["sun_runes", "sun_gate", [["lumen_core", 1], ["ruby", 2]]],
			["coast_runes", "saltmere", [["emerald", 3], ["heart_crystal", 1]]]]:
		var at := _near(lm, sh[1], 14.0, 2.5)
		if at != Vector3.INF:
			_make_shrine(sh[0], at, sh[2])
	# Starsilver veins: a few near each realm's heart.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var k := 0
	for c: Vector2 in [Realms.JUNGLE, Realms.DESERT, Realms.COAST]:
		for i in 4:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(160.0, 420.0)
			var h: float = game.world.height_at(p.x, p.y)
			if h > TerrainGen.WATER + 1.0:
				_make_vein("vein_%d" % k, Vector3(p.x, h, p.y))
			k += 1
	game.play.enemy_killed.connect(func(e):
		if e != null and e == _colossus:
			colossus_down = true
			_colossus = null
			game.hud.banner("Hidden foe defeated", "The Colossus of Kings")
			var at: Vector3 = e.global_position
			for it in [["lumen_sword", 1], ["heart_crystal", 2], ["gold_coin", 150]]:
				game.play.spawn_pickup(it[0], it[1], at + Vector3(0, 1.5, 0), Vector3(randf_range(-2, 2), 5, randf_range(-2, 2)))
			game.call_deferred("autosave"))


func _near(lm: Dictionary, id: String, dist: float, angle: float) -> Vector3:
	if not lm.has(id):
		return Vector3.INF
	var c: Vector3 = lm[id].pos
	var p := c + Vector3(cos(angle), 0, sin(angle)) * dist
	if id.begins_with("aerie"):
		return Vector3(p.x, c.y, p.z)
	p.y = game.world.height_at(p.x, p.z)
	return p


# ------------------------------------------------------------- chests ---

func _make_chest(id: String, at: Vector3, loot: Array) -> void:
	var node: Node3D = game.town.place("chest_magic", at, 1.3, randf() * TAU)
	# The clue: a slow drift of motes over the lid, seen from afar.
	var motes := _motes(Color(0.75, 0.9, 1.0), 14, 1.2)
	motes.position = Vector3(0, 1.4, 0)
	node.add_child(motes)
	_chests.append([id, node, loot])


func _open_chest(c: Array) -> void:
	opened[c[0]] = true
	var node: Node3D = c[1]
	var loot: Array = (c[2] as Array).duplicate()
	if game.play.wearing("relic_luckstone"):
		loot.append(["glowshard", 4])   # the Luckstone's extra find
	for it in loot:
		if int(it[1]) > 0:
			game.play.spawn_pickup(it[0], it[1], node.global_position + Vector3(0, 1.2, 0), Vector3(randf_range(-2, 2), 5, randf_range(-2, 2)))
	game.play._star_ring(node.global_position, 2.5, Color(0.6, 0.9, 1.0))
	game.play.prog.gain(CHEST_XP)
	game.play.toast.emit("A hidden starlit chest!")
	Sfx.play("chest")
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector3(1.15, 0.85, 1.15), 0.12)
	t.tween_property(node, "scale", Vector3.ONE, 0.2)
	t.tween_interval(2.0)
	t.tween_property(node, "scale", Vector3.ZERO, 0.4)
	t.tween_callback(node.queue_free)
	game.call_deferred("autosave")


# ------------------------------------------------------------ shrines ---

func _make_shrine(id: String, centre: Vector3, reward: Array) -> void:
	var pillars := []
	var order := [2, 0, 1]   # which pillar carries one, two, three rings
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var at := centre + Vector3(cos(a), 0, sin(a)) * 4.0
		at.y = game.world.height_at(at.x, at.z)
		var root := Node3D.new()
		add_child(root)
		root.global_position = at
		var stone := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.32
		cyl.bottom_radius = 0.42
		cyl.height = 2.2
		cyl.radial_segments = 6
		stone.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.58, 0.58, 0.62)
		m.roughness = 0.9
		stone.material_override = m
		stone.position.y = 1.1
		root.add_child(stone)
		# Glyph rings: how many marks this stone carries (its place in order).
		var marks: int = order.find(i) + 1
		for r in marks:
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.36
			tor.outer_radius = 0.42
			ring.mesh = tor
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.5, 0.45, 0.6)
			gm.emission_enabled = true
			gm.emission = Color(0.35, 0.25, 0.6)
			ring.material_override = gm
			ring.position.y = 1.5 + r * 0.22
			root.add_child(ring)
		root.set_meta("place", marks)
		root.set_meta("mat", m)
		pillars.append(root)
	_shrines.append([id, centre, pillars, 0, reward])


func strike_near(at: Vector3) -> void:
	# Rune stones answer the blade.
	for sh in _shrines:
		if solved.has(sh[0]):
			continue
		for p: Node3D in sh[2]:
			if p.global_position.distance_to(at) > 2.6:
				continue
			var want: int = int(sh[3]) + 1
			if int(p.get_meta("place")) == want:
				sh[3] = want
				(p.get_meta("mat") as StandardMaterial3D).emission_enabled = true
				(p.get_meta("mat") as StandardMaterial3D).emission = Color(0.6, 0.45, 1.0)
				Sfx.play("magic_cast", -6.0)
				Arcana.sparks(game, p.global_position + Vector3(0, 2.0, 0), Color(0.8, 0.65, 1.0), 20, 3.0, 0.08)
				if want == 3:
					_solve(sh)
			else:
				sh[3] = 0
				for q: Node3D in sh[2]:
					(q.get_meta("mat") as StandardMaterial3D).emission_enabled = false
				Sfx.play("hit", -8.0)
				game.play.toast.emit("The runes go dark. Count the marks...")
			return
	# Starsilver veins.
	for v in _veins:
		if mined.has(v[0]) or (v[1] as Node3D).global_position.distance_to(at) > 2.4:
			continue
		v[2] = int(v[2]) + 1
		Arcana.sparks(game, (v[1] as Node3D).global_position + Vector3(0, 0.8, 0), Color(0.8, 0.9, 1.0), 14, 3.0, 0.06)
		Sfx.play("dig", -4.0)
		if int(v[2]) >= 3:
			mined[v[0]] = true
			game.play.inventory.add("starsilver", 2)
			game.play.prog.gain(30)
			game.play.toast.emit("Starsilver ×2")
			(v[1] as Node3D).queue_free()
			game.call_deferred("autosave")
		return


func _solve(sh: Array) -> void:
	solved[sh[0]] = true
	var c: Vector3 = sh[1]
	Arcana.circle(game, c, 4.5, Color(0.75, 0.6, 1.0), 1.2, 1.5)
	Arcana.pillar(game, c, 1.4, 30.0, Color(0.8, 0.6, 1.0), 2.5)
	Sfx.play("magic_burst", -2.0)
	game.hud.banner("Shrine awakened", "The runes remember")
	for it in sh[4]:
		if int(it[1]) > 0:
			game.play.spawn_pickup(it[0], it[1], c + Vector3(0, 1.5, 0), Vector3(randf_range(-2, 2), 5, randf_range(-2, 2)))
	game.play.prog.gain(SHRINE_XP)
	game.call_deferred("autosave")


# -------------------------------------------------------------- veins ---

func _make_vein(id: String, at: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	for part in FoliageLib.parts("P:crystal"):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.45), Vector3.ZERO) * (part[1] as Transform3D)
		var m := (part[0] as Mesh).surface_get_material(0).duplicate() as StandardMaterial3D
		m.albedo_color = Color(0.85, 0.92, 1.0, 0.9)
		m.emission = Color(0.7, 0.85, 1.0)
		mi.material_override = m
		root.add_child(mi)
	var motes := _motes(Color(0.85, 0.95, 1.0), 8, 0.6)
	motes.position.y = 0.8
	root.add_child(motes)
	_veins.append([id, root, 0])


func _motes(col: Color, amount: int, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = col
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread
	p.amount = amount
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	return p


# ------------------------------------------------------------ process ---

## Seer's Eye and Deepsong: hidden chests' and veins' motes carry farther.
func set_sight(seer: bool, deepsong: bool) -> void:
	for c in _chests:
		if is_instance_valid(c[1]):
			for m in (c[1] as Node3D).find_children("*", "CPUParticles3D", true, false):
				(m as CPUParticles3D).visibility_range_end = 220.0 if seer else 60.0
	for v in _veins:
		if is_instance_valid(v[1]):
			for m in (v[1] as Node3D).find_children("*", "CPUParticles3D", true, false):
				(m as CPUParticles3D).scale_amount_max = 4.0 if deepsong else 1.0
				(m as CPUParticles3D).visibility_range_end = 260.0 if deepsong else 60.0


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p: Vector3 = game.player.global_position
	# Chests: open with the interact button.
	for c in _chests:
		if opened.has(c[0]) or not is_instance_valid(c[1]):
			continue
		if (c[1] as Node3D).global_position.distance_to(p) < 2.4:
			game.hud.prompt("Open the starlit chest")
			if game.input.interact:
				game.input.interact = false
				_open_chest(c)
	# Rune stones and veins answer her attacks.
	if game.input.attack:
		strike_near(p + game.player.model.global_transform.basis.z * 1.0)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_discover(p)
		_colossus_watch(p)


func _discover(p: Vector3) -> void:
	var lm: Dictionary = game.realms.landmarks
	for id in lm:
		if discovered.has(id):
			continue
		var c: Vector3 = lm[id].pos
		if Vector2(p.x - c.x, p.z - c.z).length() < DISCOVER_R and absf(p.y - c.y) < 60.0:
			discovered[id] = String(lm[id].name)
			game.hud.banner("Discovered", String(lm[id].name))
			game.play.prog.gain(20)
			Sfx.play("magic_cast", -10.0)
			game.call_deferred("autosave")


## The Colossus of Kings walks the Colonnade at night, once.
func _colossus_watch(p: Vector3) -> void:
	if colossus_down or _colossus != null:
		return
	var lm: Dictionary = game.realms.landmarks
	if not lm.has("colonnade"):
		return
	var c: Vector3 = lm.colonnade.pos
	var night: bool = game.time_of_day < 0.22 or game.time_of_day > 0.8
	if not night or Vector2(p.x - c.x, p.z - c.z).length() > 70.0:
		return
	c.y = game.world.height_at(c.x, c.z)
	_colossus = game.play.spawn_enemy("cinder_knight", c)
	_colossus.max_health *= 10.0
	_colossus.health = _colossus.max_health
	_colossus.scale = Vector3.ONE * 2.2
	_colossus.is_boss = true
	game.hud.banner("A giant stirs", "The Colossus of Kings")
	Sfx.play("roar", -2.0)


func to_dict() -> Dictionary:
	return {"discovered": discovered.duplicate(), "opened": opened.keys(), "solved": solved.keys(),
		"mined": mined.keys(), "colossus": colossus_down}


func from_dict(d: Dictionary) -> void:
	discovered = (d.get("discovered", {}) as Dictionary).duplicate()
	for id in d.get("opened", []):
		opened[String(id)] = true
	for id in d.get("solved", []):
		solved[String(id)] = true
	for id in d.get("mined", []):
		mined[String(id)] = true
	colossus_down = bool(d.get("colossus", false))
	for c in _chests:
		if opened.has(c[0]) and is_instance_valid(c[1]):
			(c[1] as Node3D).queue_free()
	for v in _veins:
		if mined.has(v[0]) and is_instance_valid(v[1]):
			(v[1] as Node3D).queue_free()
	for sh in _shrines:
		if solved.has(sh[0]):
			for q: Node3D in sh[2]:
				(q.get_meta("mat") as StandardMaterial3D).emission_enabled = true
