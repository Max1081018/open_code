class_name Play3D
extends Node
## The rules of the open world: the inventory and hotbar, what a swing does
## when it lands (strike foes in an arc, fell a tree, break a rock), pickups,
## enemies spawned by region and time of day, the Warden's arena and fight,
## and feedback (hit-stop, shake, debris, damage numbers, toasts).

signal toast(text: String)
signal enemy_killed(e: Node)
signal inventory_changed
signal resource_struck(category: String)
signal crafted(item: String)

var game: Node
var inventory := Inventory.new(40)
var hotbar_index := 0
var boss: Enemy3D
var boss_site := Vector3.ZERO
var _impacts: Array = []          ## [seconds left, kind, heavy]
var _spawn_timer := 4.0
var _shake := 0.0
var _boss_spawned := false
var _debris_mesh: BoxMesh

## Seconds from the swing starting to the blow landing.
const IMPACT := {"attack": 0.32, "attack_heavy": 0.55, "chop": 0.48, "mine": 0.42}
const ARC_REACH := 2.6
const SKILL_COOLDOWN := 6.0
const BURST_COST := 60.0
var skill_cooldown := 0.0
var energy := 0.0
var prog := Progression.new()
const VIOLET := Color(0.72, 0.45, 1.0)


func setup(the_game: Node) -> void:
	game = the_game
	# Her own Moonblade fights and gathers alike: no starting axe or pickaxe.
	for start in [["moonblade", 1], ["apple", 3], ["torch", 4]]:
		inventory.add(start[0], start[1])
	inventory.changed.connect(func():
		inventory_changed.emit()
		if not relics.is_empty():
			apply_relics())
	game.player.swung.connect(_on_swing)
	game.player.burned.connect(func():
		_shake = maxf(_shake, 0.6)
		Sfx.play("hit")
		toast.emit("The lava burns!"))
	game.player.died.connect(_on_player_died)
	prog.leveled.connect(_on_level_up)
	select(0)
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.12, 0.08, 0.1)
	boss_site = _find_boss_site()


## She falls: the screen dims, and she wakes at the town gate.
func _on_player_died() -> void:
	Sfx.play("hit")
	await get_tree().create_timer(1.8).timeout
	await game.hud.veil(1.0, 1.0).finished
	var home := Vector3(10, 0, 14)
	home.y = game.world.height_at(home.x, home.z) + 0.2
	game.player.revive(home)
	game.cam.global_position = home + Vector3(0, 2, 4)
	await get_tree().create_timer(0.4).timeout
	game.hud.veil(0.0, 1.2)
	game.hud.banner("Fallen", "The light carried you home")


func select(index: int) -> void:
	hotbar_index = clampi(index, 0, Inventory.HOTBAR_SIZE - 1)
	var stack = inventory.get_slot(hotbar_index)
	game.player.hold(stack.id if stack != null else "")
	inventory_changed.emit()


func held_id() -> String:
	var stack = inventory.get_slot(hotbar_index)
	return stack.id if stack != null else ""


func _on_swing(kind: String) -> void:
	_impacts.append([IMPACT.get(kind, 0.4), kind.trim_suffix("_heavy"), kind.ends_with("_heavy")])
	if kind.begins_with("attack") and Items.kind(held_id()) == Items.Kind.SWORD:
		var heavy := kind.ends_with("_heavy")
		get_tree().create_timer(0.08).timeout.connect(_slash.bind(heavy))
		if _arcane():
			Sfx.play("magic_slash", -10.0 if not heavy else -6.0, 0.12)
			if heavy and prog.unlocked("crescent"):
				get_tree().create_timer(0.2).timeout.connect(_crescent_wave)


static var _arc: ArrayMesh
var _slash_flip := false


## A crescent of light swept round the heroine with each sword stroke;
## strokes alternate side to side, heavy ones are larger and golden.
func _slash(heavy: bool) -> void:
	if _arc == null:
		_arc = _make_arc()
	var p: Player3D = game.player
	var mi := MeshInstance3D.new()
	mi.mesh = _arc
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/slash.gdshader")
	var core := Color(1.0, 0.8, 0.4) if heavy else Color(0.55, 0.85, 1.0)
	if _arcane():
		core = Color(0.95, 0.62, 1.0) if heavy else VIOLET
	mat.set_shader_parameter("core", core)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(mi)
	var face := p.model.global_transform.basis.z
	face.y = 0.0
	mi.global_position = p.global_position + Vector3(0, 1.0 if not heavy else 0.9, 0) + face.normalized() * 0.2
	mi.global_basis = Basis.looking_at(-face.normalized(), Vector3.UP)
	_slash_flip = not _slash_flip
	# Diagonal strokes, alternating, so the crescent reads from behind too.
	mi.rotate_object_local(Vector3.FORWARD, (1.0 if _slash_flip else -1.0) * randf_range(0.6, 1.05))
	var k := 1.35 if heavy else 1.0
	mi.scale = Vector3(-k if _slash_flip else k, k, k)
	var t := mi.create_tween()
	t.tween_method(_set_progress.bind(mat), 0.0, 1.0, 0.24 if not heavy else 0.32)
	t.tween_callback(mi.queue_free)


func _set_progress(v: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("progress", v)


## A flat half-ring in front (+Z) from right to left: UV.x along the arc,
## UV.y from the inner to the outer radius.
static func _make_arc() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var inner := 0.55
	var outer := 1.85
	for i in segs:
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var a0 := lerpf(-1.9, 1.9, u0)
		var a1 := lerpf(-1.9, 1.9, u1)
		var p00 := Vector3(sin(a0) * inner, 0, cos(a0) * inner)
		var p01 := Vector3(sin(a0) * outer, 0, cos(a0) * outer)
		var p10 := Vector3(sin(a1) * inner, 0, cos(a1) * inner)
		var p11 := Vector3(sin(a1) * outer, 0, cos(a1) * outer)
		for q in [[p00, u0, 0.0], [p01, u0, 1.0], [p11, u1, 1.0], [p00, u0, 0.0], [p11, u1, 1.0], [p10, u1, 0.0]]:
			st.set_uv(Vector2(q[1], q[2]))
			st.add_vertex(q[0])
	return st.commit()


func _process(delta: float) -> void:
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	for a in cooldowns:
		cooldowns[a] = maxf(0.0, float(cooldowns[a]) - delta)
	_buff_time = maxf(0.0, _buff_time - delta)
	var inp: Input3D = game.input
	if inp.skill:
		inp.skill = false
		use_skill()
	if inp.skill2:
		inp.skill2 = false
		use_phase()
	if inp.skill3:
		inp.skill3 = false
		use_orbit()
	if inp.burst:
		inp.burst = false
		use_burst()
	_update_orbit(delta)
	for i in range(_impacts.size() - 1, -1, -1):
		_impacts[i][0] -= delta
		if _impacts[i][0] <= 0.0:
			var hit: Array = _impacts[i]
			_impacts.remove_at(i)
			_impact(hit[1], hit[2])
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 6.0
		_spawn_enemies()
	if not _boss_spawned and game.player.global_position.distance_to(boss_site) < 70.0:
		_spawn_boss()
	# Camera shake.
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		game.cam.camera.h_offset = randf_range(-1, 1) * _shake * 0.15
		game.cam.camera.v_offset = randf_range(-1, 1) * _shake * 0.15
	else:
		game.cam.camera.h_offset = 0.0
		game.cam.camera.v_offset = 0.0


func _impact(kind: String, heavy: bool) -> void:
	var player: Player3D = game.player
	var forward := player.model.global_transform.basis.z  # the model faces +Z
	var at := player.global_position
	var id := held_id()
	if kind == "chop" or kind == "mine":
		var res: Dictionary = game.world.nearest_resource(at, forward, 2.8)
		if res.is_empty():
			return
		var wants := "tree" if kind == "chop" else "rock"
		var power: float = float(Items.def(id).get("power", 1)) if id != "" else 1.0
		var spark_at: Vector3 = res.pos + Vector3(0, 1.0 if res.category == "tree" else 0.6, 0)
		if res.category != wants:
			debris(spark_at, Color(0.6, 0.6, 0.6), 4)
			toast.emit("Wrong tool")
			return
		_strike_resource(res, power, at, forward)
		return
	_weapon_strike(id, heavy, at, forward)


## A tree or rock struck by a tool or by the Moonblade's arcana.
func _strike_resource(res: Dictionary, power: float, at: Vector3, forward: Vector3) -> void:
	var wants: String = res.category
	resource_struck.emit(wants)
	var spark_at: Vector3 = res.pos + Vector3(0, 1.0 if wants == "tree" else 0.6, 0)
	debris(spark_at, Color(0.42, 0.3, 0.2) if wants == "tree" else Color(0.55, 0.55, 0.58), 10)
	if _arcane():
		Arcana.sparks(game, spark_at, VIOLET, 14, 4.0, 0.1)
	Sfx.play("chop" if wants == "tree" else "dig")
	_shake = maxf(_shake, 0.25)
	if game.world.hit_resource(res, power):
		prog.gain(Progression.XP_TREE if wants == "tree" else Progression.XP_ROCK)
		if wants == "tree":
			var fall := FallingTree.new()
			fall.kind = res.kind
			fall.game = self
			fall.scale_factor = res.scale
			var away: Vector3 = res.pos - at
			away.y = 0
			fall.away = away.normalized() if away.length() > 0.1 else forward
			fall.rotation.y = res.yaw
			game.add_child(fall)
			fall.global_position = res.pos
			fall.rotation = Vector3.ZERO
			toast.emit("Timber!")
		else:
			_break_rock(res)


## A weapon strike: every foe in a frontal arc within reach.
func _weapon_strike(id: String, heavy: bool, at: Vector3, forward: Vector3) -> void:
	var mult := 2.2 if heavy else float([1.0, 1.1, 1.45][game.player.combo_step])  # the finisher hits hardest
	var struck := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead:
			continue
		var to := enemy.global_position - at
		to.y = 0
		var reach := ARC_REACH + (0.6 if enemy.is_boss else 0.0) + (0.4 if heavy else 0.0)
		if to.length() > reach or (to.length() > 0.5 and forward.dot(to.normalized()) < (0.0 if heavy else 0.35)):
			continue
		hit(enemy, mult, at, heavy, "arcane" if _arcane() else "")
		debris(enemy.global_position + Vector3(0, 1.1, 0), Color(0.85, 0.82, 0.75), 6)
		struck += 1
		energy = minf(BURST_COST, energy + (6.0 if heavy else 3.5))
	if struck > 0:
		Sfx.play("hit")
		_shake = maxf(_shake, 0.35 if heavy else 0.2)
		_hitstop(0.06 if heavy else 0.035)
	elif Items.def(id).has("power") and Items.kind(id) == Items.Kind.SWORD:
		# Nothing to fight: the Moonblade's arcana cuts wood and stone.
		var res: Dictionary = game.world.nearest_resource(at, forward, 2.8)
		if not res.is_empty():
			_strike_resource(res, float(Items.def(id).power) * (1.5 if heavy else 1.0), at, forward)


## Is she wielding her arcane Moonblade?
func _arcane() -> bool:
	return held_id() == "moonblade"


## Arcane Comet (E, Lv 3): a homing violet orb launched from her blade;
## it bursts among foes in a ring of runes.
func use_skill() -> void:
	var p: Player3D = game.player
	if skill_cooldown > 0.0 or p.busy() or p.swimming or p.dead:
		return
	if not prog.unlocked("comet"):
		toast.emit("Arcane Comet awakens at Lv. %d" % Progression.UNLOCKS.comet)
		return
	skill_cooldown = prog.art_cooldown("comet")
	p.perform("Spell_Simple_Shoot", 0.55, 1.2)
	var fwd: Vector3 = p.model.global_transform.basis.z
	Arcana.circle(game, p.global_position, 1.3, VIOLET, 0.35, 1.2)
	Sfx.play("magic_cast", -4.0)
	get_tree().create_timer(0.22).timeout.connect(func():
		var orb := Arcana.Orb.new()
		orb.heading = (fwd + Vector3(0, 0.08, 0)).normalized()
		orb.target = _nearest_enemy(p.global_position, fwd, 22.0)
		orb.ground = game.world.height_at
		orb.burst = _comet_burst
		game.add_child(orb)
		orb.global_position = p.global_position + Vector3(0, 1.3, 0) + fwd * 0.8
		Arcana.flash(game, orb.global_position, VIOLET, 3.0, 5.0, 0.25))


func _comet_burst(at: Vector3) -> void:
	var ground := Vector3(at.x, game.world.height_at(at.x, at.z), at.z)
	Arcana.circle(game, ground, 3.6, VIOLET, 0.25, 2.0)
	Arcana.sparks(game, at, VIOLET, 36, 8.0, 0.12)
	Arcana.flash(game, at, VIOLET, 3.0, 9.0, 0.4)
	Sfx.play("magic_impact", -3.0)
	_area_strike(ground, 3.6, prog.art_mult("comet"), VIOLET)
	energy = minf(BURST_COST, energy + 10.0)


## The closest living foe ahead within `reach` (or null).
func _nearest_enemy(at: Vector3, fwd: Vector3, reach: float) -> Enemy3D:
	var best: Enemy3D = null
	var best_d := reach
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead:
			continue
		var to := enemy.global_position - at
		var d := to.length()
		if d < best_d and (d < 3.0 or fwd.dot(to.normalized()) > 0.2):
			best = enemy
			best_d = d
	return best


## Crescent Wave (heavy stroke, Lv 2): a violet crescent flung forward,
## cutting every foe along its path.
func _crescent_wave() -> void:
	var p: Player3D = game.player
	if _arc == null:
		_arc = _make_arc()
	var fwd: Vector3 = p.model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _arc
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/slash.gdshader")
	mat.set_shader_parameter("core", Color(0.85, 0.55, 1.0))
	mat.set_shader_parameter("progress", 0.78)
	mat.set_shader_parameter("strength", 3.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(mi)
	var from := p.global_position + Vector3(0, 0.9, 0) + fwd * 0.6
	mi.global_position = from
	mi.global_basis = Basis.looking_at(-fwd, Vector3.UP).scaled(Vector3(0.8, 0.8, 0.8))
	var reach := 11.0
	var t := mi.create_tween()
	t.tween_property(mi, "global_position", from + fwd * reach, 0.45)
	t.parallel().tween_method(func(v: float): mat.set_shader_parameter("strength", v), 3.0, 0.0, 0.45).set_ease(Tween.EASE_IN)
	t.tween_callback(mi.queue_free)
	# Foes in the corridor are cut as the crescent reaches them.
	var mult := prog.art_mult("crescent")
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead:
			continue
		var to := enemy.global_position - p.global_position
		to.y = 0.0
		var along := to.dot(fwd)
		var side := (to - fwd * along).length()
		if along > 0.0 and along < reach and side < 2.0 + (1.0 if enemy.is_boss else 0.0):
			get_tree().create_timer(along / reach * 0.45).timeout.connect(func():
				if not is_instance_valid(enemy) or enemy.dead:
					return
				hit(enemy, mult, p.global_position, true, "arcane")
				Arcana.sparks(game, enemy.global_position + Vector3(0, 1.1, 0), VIOLET, 16, 5.0, 0.1)
				energy = minf(BURST_COST, energy + 4.0))


## Violet Starfall (Q, Lv 5): a great rune circle opens beneath her, light
## rises, and star lances rain on every foe around her.
func use_burst() -> void:
	var p: Player3D = game.player
	if p.busy() or p.swimming or p.dead:
		return
	if not prog.unlocked("starfall"):
		toast.emit("Violet Starfall awakens at Lv. %d" % Progression.UNLOCKS.starfall)
		return
	if energy < BURST_COST:
		return
	energy = 0.0
	p.perform("Spell_Simple_Shoot", 1.3, 0.8)
	var centre := p.global_position
	Arcana.circle(game, centre, 8.0, VIOLET, 1.4, 0.6)
	Arcana.circle(game, centre, 3.0, Arcana.LILAC, 1.4, -1.4)
	Arcana.pillar(game, centre, 0.8, 12.0, VIOLET, 0.5)
	Arcana.flash(game, centre + Vector3(0, 3, 0), VIOLET, 1.4, 12.0, 1.0)
	Sfx.play("magic_burst", -2.0)
	toast.emit("Violet Starfall!")
	_shake = maxf(_shake, 0.5)
	# One lance on each foe in reach, the rest scattered round the circle.
	var spots: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if not enemy.dead and enemy.global_position.distance_to(centre) < 9.0:
			spots.append(enemy.global_position)
	while spots.size() < 9:
		var a := randf() * TAU
		var r := randf_range(2.5, 7.5)
		var pt := centre + Vector3(cos(a) * r, 0, sin(a) * r)
		pt.y = game.world.height_at(pt.x, pt.z)
		spots.append(pt)
	for i in spots.size():
		var at: Vector3 = spots[i]
		at.y = game.world.height_at(at.x, at.z)
		Arcana.lance(game, at, 0.35 + i * 0.09, _lance_strike)
	get_tree().create_timer(0.35 + spots.size() * 0.09 + 0.35).timeout.connect(func():
		_area_strike(centre, 8.0, prog.art_mult("starfall"), VIOLET)
		Sfx.play("magic_impact", 0.0)
		_shake = 1.0)


func _lance_strike(at: Vector3) -> void:
	Sfx.play("magic_impact", -12.0, 0.2)
	_shake = maxf(_shake, 0.25)
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead or enemy.global_position.distance_to(at) > 2.4:
			continue
		hit(enemy, prog.art_mult("starfall") * 0.57, at, true, "arcane")


## A new level: stronger, healed, and perhaps a new art of the Moonblade.
func _on_level_up(level: int, art: String) -> void:
	var p: Player3D = game.player
	p.max_health = Progression.max_health_at(level)
	p.max_stamina = Progression.max_stamina_at(level)
	p.health = p.max_health
	p.stamina = p.max_stamina
	var at := p.global_position
	Arcana.circle(game, at, 2.6, Color(1.0, 0.85, 0.5), 0.9, 0.8)
	Arcana.pillar(game, at, 0.9, 8.0, Color(1.0, 0.85, 0.55), 0.7)
	Arcana.sparks(game, at + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.5), 50, 6.0, 0.12, 1.5)
	Sfx.play("magic_cast", -2.0)
	if art != "":
		game.hud.banner("Level %d" % level, "New art:  " + String(Progression.ART_NAMES[art]))
	else:
		game.hud.banner("Level %d" % level, "Max HP %d  ·  Power %d  ·  +1 skill point" % [int(p.max_health), int(round(DamageCalc.power(attacker_stats())))])


func _area_strike(at: Vector3, radius: float, mult: float, colour: Color) -> void:
	_star_ring(at, radius, colour)
	var hits := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead or enemy.global_position.distance_to(at) > radius + (1.0 if enemy.is_boss else 0.0):
			continue
		hit(enemy, mult, at, true, "arcane")
		hits += 1
	_shake = maxf(_shake, 0.6)
	if hits > 0:
		_hitstop(0.07)
		Sfx.play("hit")


## A flat ring of light expanding on the ground plus rising sparkles.
func _star_ring(at: Vector3, radius: float, colour: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(colour, 0.9)
	ring.material_override = mat
	game.add_child(ring)
	ring.global_position = at + Vector3(0, 0.3, 0)
	ring.scale = Vector3(0.3, 0.3, 0.3)
	var t := ring.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	t.chain().tween_callback(ring.queue_free)
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	p.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_texture = _spark_texture()
	pm.albedo_color = colour
	p.material_override = pm
	p.amount = 60
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.8
	p.emission_ring_inner_radius = radius * 0.3
	p.emission_ring_height = 0.2
	p.direction = Vector3.UP
	p.spread = 15
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.gravity = Vector3(0, -1, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	game.add_child(p)
	p.global_position = at + Vector3(0, 0.4, 0)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


static var _spark: Texture2D


## A soft round glow with a bright core: the sprite for every spark.
static func _spark_texture() -> Texture2D:
	if _spark == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.8))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_spark = t
	return _spark


func _break_rock(res: Dictionary) -> void:
	var at: Vector3 = res.pos + Vector3(0, 0.6, 0)
	debris(at, Color(0.5, 0.5, 0.52), 26)
	_shake = maxf(_shake, 0.4)
	spawn_pickup("stone", randi_range(3, 5), at, Vector3(0, 4, 0))
	var b: int = game.world.biome_at(res.pos)
	var ore := "coal"
	match b:
		TerrainGen.Biome.SNOW:
			ore = "silver_ore"
		TerrainGen.Biome.VOLCANIC:
			ore = "gold_ore"
		TerrainGen.Biome.DRY:
			ore = "copper_ore"
		TerrainGen.Biome.DARK_FOREST, TerrainGen.Biome.CORRUPTED:
			ore = "iron_ore"
	if randf() < 0.75:
		spawn_pickup(ore, randi_range(1, 3), at, Vector3(randf_range(-2, 2), 4, randf_range(-2, 2)))
	if randf() < 0.08:
		spawn_pickup(["ruby", "emerald", "glowshard"].pick_random(), 1, at, Vector3(0, 5, 0))


func tree_landed(tree: Node3D) -> void:
	if tree.global_position.distance_to(game.player.global_position) < 25.0:
		_shake = maxf(_shake, 0.5)
	debris(tree.global_position + (tree as FallingTree).away * 4.0, Color(0.3, 0.4, 0.22), 24)


func spawn_pickup(id: String, count: int, at: Vector3, impulse: Vector3) -> void:
	var p := Pickup3D.new()
	p.setup(id, count, self, impulse)
	game.add_child(p)
	p.global_position = at


## The player picked something up.
func collect(id: String, count: int, _at: Vector3) -> void:
	inventory.add(id, count)
	Sfx.play("pickup", -6.0)
	toast.emit("+%d %s" % [count, Items.item_name(id)])


## Expose for pickups (they ask for the player and the world).
var player: Player3D:
	get:
		return game.player
var world: OpenWorld:
	get:
		return game.world


func debris(at: Vector3, colour: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _debris_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	p.material_override = m
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.1
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -16, 0)
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	game.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func damage_number(at: Vector3, amount: float, crit: bool) -> void:
	var label := Label3D.new()
	label.text = ("%d!" if crit else "%d") % roundi(amount)
	label.font_size = 96 if crit else 64
	label.outline_size = 18
	label.modulate = Color(1.0, 0.85, 0.3) if crit else Color(1, 1, 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.004
	game.add_child(label)
	label.global_position = at
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "global_position", at + Vector3(randf_range(-0.4, 0.4), 1.2, 0), 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(label.queue_free)


func _hitstop(seconds: float) -> void:
	Engine.time_scale = 0.08
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func on_player_hit(amount: float) -> void:
	_shake = maxf(_shake, 0.45)
	game.hud.hurt_flash(clampf(amount / 30.0, 0.35, 1.0))
	Sfx.play("hurt", -6.0)


## A foe's ground blow: a ring of its element racing outward, dust, a jolt.
func ring_burst(at: Vector3, radius: float, colour: Color) -> void:
	_star_ring(at, radius, colour)
	Arcana.sparks(game, at + Vector3(0, 0.3, 0), colour, 30, 7.0, 0.12, -6.0)
	debris(at + Vector3(0, 0.2, 0), Color(0.5, 0.46, 0.42), 14)
	Sfx.play("land", 0.0, 0.1, 0.7)
	if game.player.global_position.distance_to(at) < radius * 3.0:
		_shake = maxf(_shake, 0.5)


# ---------------------------------------------------------------- enemies ---

func _spawn_enemies() -> void:
	var player: Player3D = game.player
	var near := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(player.global_position) < 70.0:
			near += 1
		elif e.global_position.distance_to(player.global_position) > 140.0 and not (e as Enemy3D).is_boss:
			e.queue_free()
	var night: bool = game.time_of_day < 0.23 or game.time_of_day > 0.8
	var cap := 6 if night else 3
	if near >= cap:
		return
	var angle := randf() * TAU
	var at := player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(32.0, 50.0)
	at.y = game.world.height_at(at.x, at.z)
	var aloft: bool = player.global_position.y > game.world.height_at(player.global_position.x, player.global_position.z) + 12.0
	if aloft:
		# On a sky isle: foes come out on the isle itself, never the land below.
		at = player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(14.0, 26.0)
		var y = game.surface_y(Vector3(at.x, player.global_position.y + 10.0, at.z))
		if y == null or absf(float(y) - player.global_position.y) > 12.0:
			return
		at.y = float(y)
	if at.y < TerrainGen.WATER + 0.5 or Vector2(at.x, at.z).distance_to(TerrainGen.VILLAGE) < TerrainGen.VILLAGE_RADIUS * 1.6:
		return
	var b: int = TerrainGen.Biome.SKY if aloft else game.world.biome_at(at)
	var kinds: Array = ZONE_FOES.get(b, ["zombie"])
	if b == TerrainGen.Biome.FOREST and night:
		kinds = ["zombie", "zombie", "robot"]
	if not night and b == TerrainGen.Biome.FOREST and randf() < 0.6:
		return  # the green woods are mostly safe by day
	# About one in twelve is an elite of its kind.
	spawn_enemy(kinds.pick_random(), at, randf() < ELITE_CHANCE)
	# Away from the meadows foes come in small bands.
	if b != TerrainGen.Biome.FOREST and randf() < 0.45:
		var p2 := at + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		p2.y = at.y if aloft else game.world.height_at(p2.x, p2.z)
		spawn_enemy(kinds.pick_random(), p2)


## Who walks each region (weighted by repeats).
const ZONE_FOES := {
	TerrainGen.Biome.FOREST: ["zombie"],
	TerrainGen.Biome.DARK_FOREST: ["thornling", "thornling", "wisp_caller", "shade"],
	TerrainGen.Biome.SNOW: ["frost_knight", "rime_shade", "rime_shade"],
	TerrainGen.Biome.DRY: ["dune_raider", "sand_thrower", "sand_thrower", "zombie"],
	TerrainGen.Biome.VOLCANIC: ["cinder_knight", "ember_caller", "ember_caller"],
	TerrainGen.Biome.CORRUPTED: ["void_shade", "void_shade", "void_caller"],
	TerrainGen.Biome.BEACH: ["zombie"],
	TerrainGen.Biome.JUNGLE: ["thornling", "vine_stalker", "wisp_caller", "root_guardian", "vine_stalker"],
	TerrainGen.Biome.CRYSTAL: ["crystal_husk", "tide_caller", "coral_knight", "crystal_husk", "rime_shade"],
	TerrainGen.Biome.SKY: ["gale_sprite", "gale_sprite", "aerie_sentinel", "wisp_caller"],
}


const ELITE_CHANCE := 0.08


func spawn_enemy(kind: String, at: Vector3, elite := false) -> Enemy3D:
	var e := Enemy3D.new()
	e.setup(kind, self)
	if elite:
		e.make_elite()
	# Placed before it enters the tree: its home post (_ready) is where it
	# stands, not the world's origin.
	e.position = at + Vector3(0, 0.3, 0)
	game.add_child(e)
	e.died.connect(_on_enemy_died)
	return e


func _on_enemy_died(e: Enemy3D) -> void:
	enemy_killed.emit(e)
	prog.gain(int(float(e.spec.get("health", 30.0)) / 3.0))
	for drop in e.spec.get("loot", []):
		if randf() < minf(1.0, float(drop[1]) * (luck() if float(drop[1]) < 0.5 else 1.0)):
			spawn_pickup(drop[0], randi_range(1, drop[2]), e.global_position + Vector3(0, 1, 0),
				Vector3(randf_range(-2, 2), 4.5, randf_range(-2, 2)))
	if e.is_boss:
		# A great foe: a great deal of experience, and the bar goes.
		prog.gain(150)
		if e == boss:
			boss = null
		toast.emit("%s falls!" % String(e.spec.get("boss", "The guardian")))
		game.hud.boss_bar(null)


## A flat open spot a few hundred metres out for the Warden's ruined arena.
func _find_boss_site() -> Vector3:
	var gen: TerrainGen = game.world.gen
	for r in [320.0, 380.0, 440.0, 260.0]:
		for k in 24:
			var a := k * TAU / 24.0 + 0.4
			var x: float = cos(a) * r
			var z: float = sin(a) * r
			var h := gen.height(x, z)
			if h > TerrainGen.WATER + 3.0 and gen.normal(x, z, 6.0).y > 0.93 and gen.normal(x + 8, z, 6.0).y > 0.9:
				return Vector3(x, h, z)
	return Vector3(300, gen.height(300, 0), 0)


## The Warden was freed in a saved journey: never raise him again.
func skip_boss() -> void:
	_boss_spawned = true


func _spawn_boss() -> void:
	_boss_spawned = true
	boss = spawn_enemy("warden", boss_site)


# Called by the Warden.
func boss_started(e: Enemy3D) -> void:
	boss = e
	game.hud.boss_bar(e)
	if e.spec.has("title"):
		game.hud.banner(String(e.spec.boss), String(e.spec.title))
		Sfx.play("roar", -2.0)
	else:
		toast.emit("%s wakes" % String(e.spec.get("boss", "The guardian")))


func boss_phase(e: Enemy3D, phase: int) -> void:
	_shake = 0.8
	var lines: Array = e.spec.get("phase_lines", ["", "", "The Warden charges!", "The Warden calls the dead!"])
	toast.emit(String(lines[clampi(phase, 0, lines.size() - 1)]))
	Arcana.flash(game, e.global_position + Vector3(0, 2, 0), e.spec.get("element", Color(1, 0.6, 0.4)), 3.0, 10.0, 0.5)
	if phase == 3 and not e.spec.has("patterns"):
		for i in 2:
			var a := randf() * TAU
			spawn_enemy("zombie", e.global_position + Vector3(cos(a), 0, sin(a)) * 6.0)


func boss_slam(e: Enemy3D) -> void:
	_shake = 0.9
	debris(e.global_position + e.model.global_transform.basis.z * 2.0, Color(0.45, 0.4, 0.35), 40)
	var d: float = game.player.global_position.distance_to(e.global_position)
	if d < 5.5:
		game.player.hurt(14.0, e.global_position)


# -------------------------------------------------------- damage & arts ---

## Seconds left on each art's cooldown (the Comet keeps skill_cooldown).
var cooldowns := {"phase": 0.0, "orbit": 0.0}
## A short buff on her power (multiplier) and its time left.
var _buff := 1.0
var _buff_time := 0.0


## Her side of DamageCalc: weapon, level, buffs and what her relics add.
func attacker_stats() -> Dictionary:
	var id := held_id()
	var weapon: float = float(Items.def(id).get("damage", 4)) if id != "" and Items.def(id).has("damage") else 4.0
	var buff := (_buff if _buff_time > 0.0 else 1.0) * relic_damage_mult()
	return {"weapon": weapon, "level": prog.level, "buff": buff,
		"crit_chance": DamageCalc.CRIT_CHANCE, "crit_damage": DamageCalc.CRIT_DAMAGE}


## Every blow on a foe lands here: one DamageCalc result, the same number
## shown and taken. Returns the damage dealt.
func hit(enemy: Enemy3D, mult: float, from: Vector3, heavy: bool, element := "") -> int:
	if enemy == null or enemy.dead:
		return 0
	var stats: Dictionary = enemy.combat_stats(from, heavy)
	var r: Dictionary = DamageCalc.compute(attacker_stats(), stats, mult, element)
	var amount: int = r.amount
	if float(stats.get("reduction", 0.0)) > 0.0:
		# Turned aside on its shield: a clang and blue sparks.
		Arcana.sparks(game, enemy.global_position + Vector3(0, 1.2, 0), Color(0.7, 0.85, 1.0), 12, 4.0, 0.06)
		Sfx.play("anvil", -10.0, 0.1, 1.4)
	enemy.take_hit(float(amount), from, heavy)
	damage_number(enemy.global_position + Vector3(0, 2.0 * (1.5 if enemy.is_boss else 1.0), 0), amount, r.crit)
	return amount


## The art on a control slot, if unlocked ("" otherwise).
func art_for_slot(slot: String) -> String:
	for a in Progression.ARTS:
		if Progression.ARTS[a].slot == slot:
			return a if prog.unlocked(a) else ""
	return ""


func cooldown_left(art: String) -> float:
	if art == "comet":
		return skill_cooldown
	return float(cooldowns.get(art, 0.0))


## Phase Step (Lv 4): she blinks up to 7 m ahead, untouchable, through
## foes; the violet afterimage she leaves cuts everything along the line
## and Marks it (20% more harm for 5 s).
func use_phase() -> void:
	var p: Player3D = game.player
	if not prog.unlocked("phase"):
		toast.emit("Phase Step awakens at Lv. %d" % Progression.UNLOCKS.phase)
		return
	if cooldowns.phase > 0.0 or p.busy() or p.swimming or p.dead:
		return
	cooldowns.phase = prog.art_cooldown("phase")
	var fwd: Vector3 = game.input.move.x * game.cam.right_flat() + game.input.move.y * game.cam.forward_flat()
	if fwd.length() < 0.2:
		fwd = p.model.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var from := p.global_position
	# Stop short of walls: probe along the ground.
	var reach := 7.0
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.9, 0), from + Vector3(0, 0.9, 0) + fwd * reach, 1)
	var ray := space.intersect_ray(q)
	if not ray.is_empty():
		reach = maxf(0.0, from.distance_to(ray.position) - 0.6)
	var to := from + fwd * reach
	to.y = game.world.height_at(to.x, to.z) + 0.05
	_afterimage(p, from)
	Arcana.sparks(game, from + Vector3(0, 1.0, 0), VIOLET, 26, 5.0, 0.1)
	Sfx.play("magic_slash", -4.0, 0.1, 1.3)
	p.blink_to(to, fwd)
	Arcana.flash(game, to + Vector3(0, 1.0, 0), VIOLET, 2.0, 6.0, 0.3)
	var mult := prog.art_mult("phase")
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead:
			continue
		var rel := enemy.global_position - from
		rel.y = 0.0
		var along := rel.dot(fwd)
		var side := (rel - fwd * along).length()
		if along > -0.5 and along < reach + 1.0 and side < 1.8 + (0.8 if enemy.is_boss else 0.0):
			enemy.mark = 5.0
			get_tree().create_timer(0.12 + along / maxf(reach, 1.0) * 0.12).timeout.connect(func():
				if is_instance_valid(enemy) and not enemy.dead:
					hit(enemy, mult, from, true, "arcane")
					Arcana.sparks(game, enemy.global_position + Vector3(0, 1.2, 0), Color(0.95, 0.7, 1.0), 14, 4.0, 0.08)
					energy = minf(BURST_COST, energy + 5.0))


## A violet ghost of her, fading where she stood.
func _afterimage(p: Player3D, at: Vector3) -> void:
	var ghost := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.6
	ghost.mesh = cap
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/magic_energy.gdshader")
	m.set_shader_parameter("energy", 1.2)
	ghost.material_override = m
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(ghost)
	ghost.global_position = at + Vector3(0, 0.85, 0)
	var t := ghost.create_tween()
	t.tween_method(func(v: float): m.set_shader_parameter("energy", v), 1.2, 0.0, 0.6)
	t.tween_callback(ghost.queue_free)


## Blade Orbit (Lv 7): her floating blade leaves her hand and circles her
## for 4 s; each foe it sweeps through is cut, at most every 0.45 s.
const ORBIT_TIME := 4.0
const ORBIT_RADIUS := 2.4
var _orbit := 0.0
var _orbit_hits := {}   ## enemy instance id -> seconds until it can be cut again


func use_orbit() -> void:
	var p: Player3D = game.player
	if not prog.unlocked("orbit"):
		toast.emit("Blade Orbit awakens at Lv. %d" % Progression.UNLOCKS.orbit)
		return
	if cooldowns.orbit > 0.0 or _orbit > 0.0 or p.dead or not MagicHold.floats(held_id()):
		if not MagicHold.floats(held_id()) and prog.unlocked("orbit"):
			toast.emit("Blade Orbit needs a blade or tool to send")
		return
	cooldowns.orbit = prog.art_cooldown("orbit")
	_orbit = ORBIT_TIME
	_orbit_hits.clear()
	p.magic_hold.orbit(ORBIT_TIME, ORBIT_RADIUS)
	Arcana.circle(game, p.global_position, ORBIT_RADIUS, VIOLET, 0.6, 2.4)
	Sfx.play("magic_cast", -3.0, 0.1, 1.2)


func _update_orbit(delta: float) -> void:
	if _orbit <= 0.0:
		return
	_orbit -= delta
	var p: Player3D = game.player
	var blade: Vector3 = p.magic_hold.global_position
	for k in _orbit_hits.keys():
		_orbit_hits[k] = float(_orbit_hits[k]) - delta
	var mult := prog.art_mult("orbit")
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy3D
		if enemy.dead:
			continue
		var id := enemy.get_instance_id()
		if float(_orbit_hits.get(id, 0.0)) > 0.0:
			continue
		var d := Vector2(enemy.global_position.x - blade.x, enemy.global_position.z - blade.z).length()
		if d < 1.3 + (0.8 if enemy.is_boss else 0.0):
			_orbit_hits[id] = 0.45
			hit(enemy, mult, p.global_position, false, "arcane")
			Arcana.sparks(game, blade, VIOLET, 10, 4.0, 0.07)
			energy = minf(BURST_COST, energy + 1.5)


# -------------------------------------------------------------- relics ---

## Worn relics (up to three). Each does what its card says:
##   Bulwark Sigil   a quarter less harm (DamageCalc guard)
##   Swiftroot       12% faster on foot
##   Featherbone     a second jump in the air
##   Ember Heart     her blows burn: +15% damage
##   Luckstone       rare drops twice as likely; chests give one more find
##   Moth Lantern    stamina returns half again as fast
##   Tidecaller      swims 60% faster
##   Seer's Eye      hidden places glimmer from much farther away
##   Deepsong Shell  starsilver veins hum: their light shows from afar
const RELIC_SLOTS := 3
var relics: Array[String] = []
signal relics_changed


func wearing(id: String) -> bool:
	return id in relics


func equip_relic(id: String) -> bool:
	if Items.kind(id) != Items.Kind.RELIC or wearing(id) or relics.size() >= RELIC_SLOTS or inventory.count(id) <= 0:
		return false
	relics.append(id)
	apply_relics()
	return true


func unequip_relic(id: String) -> void:
	relics.erase(id)
	apply_relics()


## Push every worn relic's effect onto the systems it changes.
func apply_relics() -> void:
	# A relic no longer carried cannot be worn.
	relics = relics.filter(func(r): return inventory.count(r) > 0)
	var p: Player3D = game.player
	p.damage_reduction = 0.25 if wearing("relic_bulwark") else 0.0
	p.move_mult = 1.12 if wearing("relic_swiftroot") else 1.0
	p.air_jumps = 1 if wearing("relic_featherbone") else 0
	p.stamina_regen_mult = 1.5 if wearing("relic_moth_lantern") else 1.0
	p.swim_mult = 1.6 if wearing("relic_tidecaller") else 1.0
	if game.get("secrets"):
		game.secrets.set_sight(wearing("relic_seers_eye"), wearing("relic_deepsong"))
	relics_changed.emit()


## Ember Heart's share of her damage.
func relic_damage_mult() -> float:
	return 1.15 if wearing("relic_ember_heart") else 1.0


## Luckstone: how much likelier a rare drop is.
func luck() -> float:
	return 2.0 if wearing("relic_luckstone") else 1.0
