class_name Play3D
extends Node
## The rules of the open world: the inventory and hotbar, what a swing does
## when it lands (strike foes in an arc, fell a tree, break a rock), pickups,
## enemies spawned by region and time of day, the Warden's arena and fight,
## and feedback (hit-stop, shake, debris, damage numbers, toasts).

signal toast(text: String)
signal inventory_changed

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


func setup(the_game: Node) -> void:
	game = the_game
	for start in [["wood_sword", 1], ["wood_axe", 1], ["wood_pickaxe", 1], ["apple", 3], ["torch", 4]]:
		inventory.add(start[0], start[1])
	inventory.changed.connect(func(): inventory_changed.emit())
	game.player.swung.connect(_on_swing)
	select(0)
	_debris_mesh = BoxMesh.new()
	_debris_mesh.size = Vector3(0.12, 0.08, 0.1)
	boss_site = _find_boss_site()


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


func _process(delta: float) -> void:
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
		debris(spark_at, Color(0.42, 0.3, 0.2) if wants == "tree" else Color(0.55, 0.55, 0.58), 10)
		Sfx.play("chop" if wants == "tree" else "dig")
		_shake = maxf(_shake, 0.25)
		if game.world.hit_resource(res, power):
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
		return
	# A weapon strike: every foe in a frontal arc within reach.
	var damage: float = float(Items.def(id).get("damage", 4)) if id != "" else 4.0
	if heavy:
		damage *= 2.2
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
		var crit := randf() < 0.12
		var amount := damage * (2.0 if crit else 1.0) * randf_range(0.9, 1.1)
		enemy.take_hit(amount, at, heavy)
		damage_number(enemy.global_position + Vector3(0, 2.0 * (1.5 if enemy.is_boss else 1.0), 0), amount, crit)
		debris(enemy.global_position + Vector3(0, 1.1, 0), Color(0.85, 0.82, 0.75), 6)
		struck += 1
	if struck > 0:
		Sfx.play("hit")
		_shake = maxf(_shake, 0.35 if heavy else 0.2)
		_hitstop(0.06 if heavy else 0.035)


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


func on_player_hit(_amount: float) -> void:
	_shake = maxf(_shake, 0.45)


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
	if at.y < TerrainGen.WATER + 0.5 or Vector2(at.x, at.z).distance_to(TerrainGen.VILLAGE) < TerrainGen.VILLAGE_RADIUS * 1.6:
		return
	var b: int = game.world.biome_at(at)
	var kinds := ["zombie"]
	match b:
		TerrainGen.Biome.DARK_FOREST, TerrainGen.Biome.CORRUPTED:
			kinds = ["shade", "zombie", "shade"]
		TerrainGen.Biome.SNOW, TerrainGen.Biome.VOLCANIC:
			kinds = ["robot", "zombie"]
		TerrainGen.Biome.DRY:
			kinds = ["robot", "zombie", "zombie"]
		_:
			kinds = ["zombie", "zombie", "robot"] if night else ["zombie"]
	if not night and b == TerrainGen.Biome.FOREST and randf() < 0.6:
		return  # the green woods are mostly safe by day
	spawn_enemy(kinds.pick_random(), at)


func spawn_enemy(kind: String, at: Vector3) -> Enemy3D:
	var e := Enemy3D.new()
	e.setup(kind, self)
	game.add_child(e)
	e.global_position = at + Vector3(0, 0.3, 0)
	e.died.connect(_on_enemy_died)
	return e


func _on_enemy_died(e: Enemy3D) -> void:
	for drop in e.spec.get("loot", []):
		if randf() < drop[1]:
			spawn_pickup(drop[0], randi_range(1, drop[2]), e.global_position + Vector3(0, 1, 0),
				Vector3(randf_range(-2, 2), 4.5, randf_range(-2, 2)))
	if e == boss:
		boss = null
		toast.emit("The Rusted Warden falls!")
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


func _spawn_boss() -> void:
	_boss_spawned = true
	boss = spawn_enemy("warden", boss_site)


# Called by the Warden.
func boss_started(e: Enemy3D) -> void:
	boss = e
	game.hud.boss_bar(e)
	toast.emit("The Rusted Warden wakes")


func boss_phase(e: Enemy3D, phase: int) -> void:
	_shake = 0.8
	toast.emit(["", "", "The Warden charges!", "The Warden calls the dead!"][phase])
	if phase == 3:
		for i in 2:
			var a := randf() * TAU
			spawn_enemy("zombie", e.global_position + Vector3(cos(a), 0, sin(a)) * 6.0)


func boss_slam(e: Enemy3D) -> void:
	_shake = 0.9
	debris(e.global_position + e.model.global_transform.basis.z * 2.0, Color(0.45, 0.4, 0.35), 40)
	var d: float = game.player.global_position.distance_to(e.global_position)
	if d < 5.5:
		game.player.hurt(14.0, e.global_position)
