class_name Level
extends Node2D
## The running game: builds the world, the player and everything around
## them, and routes interactions between systems.

signal opened_panel(name: String)

const TILE := 128.0
## Tiles of world height that fill the screen vertically. Close enough
## that the hero is a fifth of the screen, as on a phone they must be.
const VIEW_TILES := 9.5

var data: WorldData
var world: World
var player: Player
var camera: Camera2D
var foreground: Foreground
var quests: Quests
var guide: QuestGuide
var _saved_quests := {}
var collision_debug: CollisionDebug
var atmosphere: Atmosphere
var fx_layer: Node2D
var drop_layer: Node2D
var actors: Node2D
var hud: Node
var controls: Node
var director: Director
var life: WorldLife
var boss: Enemy = null

var _shake := 0.0
var _look_ahead := 0.0
var _autosave := 60.0


## Build from a fresh seed, or from a saved game when `saved` is not empty.
func start(seed_value: int, saved := {}) -> void:
	Game.level = self
	if saved.is_empty():
		data = WorldData.new()
		data.generate(seed_value)
		_raise_outcrop(data)
	else:
		data = WorldData.from_dict(saved.world)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = -int(TILE * 40)
	camera.limit_right = int(data.width * TILE)
	camera.limit_bottom = int(data.height * TILE)
	add_child(camera)

	world = World.new()
	add_child(world)
	world.setup(data, camera)

	actors = Node2D.new()
	actors.z_index = 10
	world.add_child(actors)
	drop_layer = Node2D.new()
	world.add_child(drop_layer)
	fx_layer = Node2D.new()
	world.add_child(fx_layer)
	foreground = Foreground.new()
	world.add_child(foreground)
	foreground.setup(self)
	collision_debug = CollisionDebug.new()
	world.add_child(collision_debug)
	collision_debug.setup(self)

	player = Player.new()
	player.world = world
	player.level = self
	actors.add_child(player)
	Game.player = player

	if saved.is_empty():
		player.global_position = World.foot_of(data.spawn)
		player.spawn_point = player.global_position
		_starting_kit()
	else:
		player.from_dict(saved.player)
		world.time_of_day = saved.get("time", 0.3)
	_saved_quests = saved.get("quests", {})

	camera.global_position = player.global_position + Vector2(0, -120)
	camera.reset_smoothing()
	_fit_zoom()
	get_viewport().size_changed.connect(_fit_zoom)
	Settings.changed.connect(_fit_zoom)
	world.load_area(World.cell_of(player.global_position), 2)

	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	atmosphere.setup(world, camera)

	player.died.connect(_on_player_died)

	life = WorldLife.new()
	add_child(life)
	life.setup(self)

	director = Director.new()
	director.level = self
	add_child(director)

	# The story: quests, the people who give them, and what points the way.
	quests = Quests.new()
	add_child(quests)
	quests.setup(self, _saved_quests)
	player.inventory.changed.connect(quests.inventory_changed)
	Game.crafted.connect(func(id, amount): quests.event("craft", id, amount))
	_place_npcs()
	guide = QuestGuide.new()
	world.add_child(guide)
	guide.setup(self)
	Sfx.play_music("explore")


func _starting_kit() -> void:
	# A wooden pickaxe and sword, and the lantern — the game's premise —
	# already lit. Everything else is found or made.
	player.inventory.add("wood_pickaxe", 1)
	player.inventory.add("wood_sword", 1)
	player.inventory.add("torch", 6)
	player.inventory.add("apple", 2)


## New worlds get a small rock outcrop a short walk from the start, so the
## tutorial's "mine stone" is a few swings on the surface, not a dig through
## ten tiles of soil. Clear of the cottage, the NPCs and any object.
static func _raise_outcrop(data: WorldData) -> void:
	var start := data.spawn.x + 8
	for x0 in range(start, start + 40):
		# Plants make way; built things (the cottage, chests, signs) do not.
		var clear := true
		for dx in 3:
			var x := x0 + dx
			var y: int = data.surface[x]
			for dy in range(-4, 1):
				var object: Dictionary = data.objects.get(data.idx(x, y + dy), {})
				if not object.is_empty() and not (object.get("type", "") in ["tree", "shrub"]):
					clear = false
			if data.get_liquid(x, y - 1) != WorldData.DRY or absf(data.surface[x] - data.surface[x0]) > 1:
				clear = false
		if not clear:
			continue
		for dx in 3:
			var x := x0 + dx
			var y: int = data.surface[x]
			for dy in range(-4, 1):
				data.objects.erase(data.idx(x, y + dy))
		# A low mound: 2-3-2 rocks, sitting on the ground.
		for dx in 3:
			var x := x0 + dx
			var ground: int = data.surface[x]
			var height := 2 if dx == 1 else 1
			for h in height:
				data.set_tile(x, ground - 1 - h, WorldData.ROCK)
			data.set_tile(x, ground, WorldData.ROCK)
			data.surface[x] = ground - height
		return


## The people of the meadow: Wren by the spawn, Mira at the cottage, Bram
## at the mouth of the nearest mine shaft, Tobin the smith camped out past
## Mira's.
func _place_npcs() -> void:
	var spawn := data.spawn
	_spawn_npc("wren", spawn.x + 4)
	_spawn_npc("mira", spawn.x - 16)
	_spawn_npc("tobin", spawn.x - 34)
	var shaft := spawn.x + 26
	for dx in range(14, 70):
		for side in [1, -1]:
			var x: int = spawn.x + dx * side
			if x > 2 and x < data.width - 3 and data.sky_depth[x] - data.surface[x] > 14:
				shaft = x - 3 * side
				break
		if shaft != spawn.x + 26:
			break
	_spawn_npc("bram", shaft)


func _spawn_npc(npc_id: String, column: int) -> void:
	column = clampi(column, 3, data.width - 4)
	var y: int = data.surface[column] - 1
	# Stand on the first open cell above solid ground.
	while y > 2 and data.is_solid(column, y):
		y -= 1
	var npc := Npc.new()
	npc.position = World.foot_of(Vector2i(column, y))
	actors.add_child(npc)
	npc.setup(self, npc_id)


## The HUD exists: steps that begin speak their line, and a new game
## opens with Wren calling out.
func story_ready(new_game: bool) -> void:
	quests.step_started.connect(func(_quest, line): hud.dialogue.say([line]))
	if new_game:
		await get_tree().create_timer(1.5).timeout
		for npc in get_tree().get_nodes_in_group("npcs"):
			if npc.id == "wren":
				talk_to(npc)


## Talk to an NPC: their lines for whatever quest they have, or a word in
## passing.
func talk_to(npc: Npc) -> void:
	if hud == null or hud.dialogue.is_talking():
		return
	npc.greet()
	var lines: Array = quests.talk(npc.id)
	hud.dialogue.say(lines)


func npc_near() -> Npc:
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.near_player():
			return npc
	return null


func _fit_zoom() -> void:
	var height := get_viewport().get_visible_rect().size.y
	var zoom := height / (VIEW_TILES * TILE) * Settings.camera_zoom
	camera.zoom = Vector2(zoom, zoom)


func _process(delta: float) -> void:
	if player == null:
		return
	# Lead the camera a little in the direction of travel, so the player
	# sees where they are going rather than where they have been.
	_look_ahead = lerpf(_look_ahead, player.velocity.x * 0.22, 2.5 * delta)
	camera.global_position = player.global_position + Vector2(_look_ahead, -150)

	if _shake > 0.0 and Settings.screen_shake:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, 60.0 * delta)
	else:
		camera.offset = Vector2.ZERO

	# Music follows the player: open air, underground, or a fight.
	if boss == null or not is_instance_valid(boss):
		var cell := World.cell_of(player.global_position)
		var below := cell.y - data.surface[clampi(cell.x, 0, data.width - 1)]
		Sfx.play_music("cave" if below > 12 else "explore")

	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = 90.0
		save()


## Hit-stop: the world all but freezes for a few hundredths of a second
## when a blow lands, which is most of what makes a hit feel heavy.
var _stop_until := 0


func hit_stop(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _stop_until:
		return
	_stop_until = until
	Engine.time_scale = 0.08
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		if Time.get_ticks_msec() >= _stop_until - 2:
			Engine.time_scale = 1.0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


# =============================================================================
# Hooks from the player
# =============================================================================

func spawn_drop(id: String, count: int, at: Vector2) -> void:
	if not Items.exists(id) or count <= 0:
		return
	var drop := ItemDrop.new()
	drop.id = id
	drop.count = count
	drop.world = world
	drop.player = player
	drop.position = at
	drop_layer.add_child(drop)


func on_tile_broken(_cell: Vector2i, _material: int, ore: int) -> void:
	if quests:
		quests.event("break", Items.drop_for_tile(_material))
	if ore == WorldData.GLOWSHARD:
		Effects.burst(fx_layer, World.centre_of(_cell), "glow", UITheme.GLOW)


func on_placed(cell: Vector2i, id: String) -> void:
	if quests:
		if Items.kind(id) == Items.Kind.BLOCK:
			quests.event("build")
		else:
			quests.event("place", String(Items.def(id).get("object", id)))
	if id == "wardstone":
		player.spawn_point = World.foot_of(cell) + Vector2(TILE, 0)
		Game.toast("Wardstone planted — you will return here", Items.icon(id))


func interact_with(cell: Vector2i, object: Dictionary) -> void:
	match object.type:
		"chest":
			opened_panel.emit("chest")
			if hud and hud.has_method("open_chest"):
				hud.open_chest(cell, object)
		"workbench", "anvil", "campfire":
			if hud and hud.has_method("open_crafting"):
				hud.open_crafting()
		"sign":
			if hud and hud.has_method("show_message"):
				hud.show_message(object.get("text", ""))
		"wardstone":
			player.spawn_point = World.foot_of(cell) + Vector2(TILE, 0)
			player.add_glow(player.max_glow())
			Game.toast("Your lantern drinks the wardstone's light")
		"torch":
			object["lit"] = not object.get("lit", true)
			world.remove_object(cell)
			world.add_object(cell, object)
		"altar", "geode":
			if hud and hud.has_method("summon_at_altar"):
				hud.summon_at_altar(cell)


func spawn_enemy(kind: String, at: Vector2) -> Enemy:
	var enemy := Enemy.new()
	enemy.setup(kind)
	enemy.world = world
	enemy.level = self
	enemy.player = player
	enemy.position = at
	actors.add_child(enemy)
	enemy.died_at.connect(func(_p): if quests: quests.event("kill", kind))
	return enemy


## The altar wakes the Warden, if you carry the key; the geode wakes the
## Gloam. Each guards a Lumen Core, and each core loosens the deep dark.
func summon_boss(cell: Vector2i) -> void:
	if boss != null and is_instance_valid(boss) and boss.is_alive():
		Game.toast("Something is already awake")
		return
	var object := world.object_at(cell)
	var kind := "warden"
	if object.get("type", "") == "geode":
		kind = "gloam"
	elif not player.inventory.remove("vault_key", 1):
		Game.toast("The altar is cold. It wants a key.", Items.icon("vault_key"))
		return
	var at := World.foot_of(cell) + Vector2(5 * TILE * (1 if randf() < 0.5 else -1), -TILE)
	boss = spawn_enemy(kind, at)
	boss.died_at.connect(_on_boss_died)
	Sfx.play("roar", 4.0)
	shake(26.0)
	Sfx.play_music("boss")
	Game.toast("%s awakens" % Enemy.KINDS[kind].boss)


func boss_phase(enemy: Enemy) -> void:
	Game.toast("%s is enraged!" % enemy.spec.boss)
	shake(18.0)


func _on_boss_died(_at: Vector2) -> void:
	Game.toast("%s is defeated" % boss.spec.boss, Items.icon("lumen_core"))
	boss = null
	Sfx.play_music("explore")


func _on_player_died() -> void:
	await get_tree().create_timer(1.0).timeout
	if hud and hud.has_method("show_death"):
		hud.show_death()
		await hud.respawn_requested
	else:
		await get_tree().create_timer(2.2).timeout
	player.revive(player.spawn_point)
	camera.global_position = player.global_position
	camera.reset_smoothing()
	world.load_area(World.cell_of(player.global_position), 2)


# =============================================================================
# Saving
# =============================================================================

func save() -> bool:
	if player == null or player.is_dead():
		return false
	return Game.save_game({
		"world": data.to_dict(),
		"player": player.to_dict(),
		"quests": quests.to_dict() if quests else {},
		"time": world.time_of_day,
	})
