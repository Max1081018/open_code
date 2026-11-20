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
var atmosphere: Atmosphere
var fx_layer: Node2D
var drop_layer: Node2D
var actors: Node2D
var hud: Node
var controls: Node

var _shake := 0.0
var _look_ahead := 0.0
var _autosave := 60.0


## Build from a fresh seed, or from a saved game when `saved` is not empty.
func start(seed_value: int, saved := {}) -> void:
	Game.level = self
	if saved.is_empty():
		data = WorldData.new()
		data.generate(seed_value)
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


func _starting_kit() -> void:
	# A wooden pickaxe and sword, and the lantern — the game's premise —
	# already lit. Everything else is found or made.
	player.inventory.add("wood_pickaxe", 1)
	player.inventory.add("wood_sword", 1)
	player.inventory.add("torch", 6)
	player.inventory.add("apple", 2)


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

	_autosave -= delta
	if _autosave <= 0.0:
		_autosave = 90.0
		save()


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
	if ore == WorldData.GLOWSHARD:
		Effects.burst(fx_layer, World.centre_of(_cell), "glow", UITheme.GLOW)


func on_placed(cell: Vector2i, id: String) -> void:
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
		"altar":
			if hud and hud.has_method("summon_at_altar"):
				hud.summon_at_altar(cell)


func _on_player_died() -> void:
	Game.toast("You fell. The lantern carries you back.")
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
		"time": world.time_of_day,
	})
