class_name Director
extends Node
## Decides what lives where. Spawns just off-screen, by biome, depth,
## time of day and — the heart of the game — how dark it is.
##
## Shades are the dark's answer to the player: they appear only where
## there is no light, burn in strong light, and close in when the
## lantern runs dry. Torches and wardstones are therefore not decoration
## but territory, and lighting a path is how the depths are claimed.

const TILE := 128.0
const INTERVAL := 1.5
const DESPAWN := 28.0  ## tiles

var level: Level
var _timer := 2.0
var _spawner_cooldown := {}  ## cell index -> seconds


func cap() -> int:
	var base: int = Settings.enemy_cap()
	return 3 if level.boss != null else base


func _process(delta: float) -> void:
	var player := level.player
	if player == null or player.is_dead():
		return
	_cull()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	_wake_spawners()
	if level.actors.get_tree().get_nodes_in_group("enemies").size() >= cap():
		return
	_try_spawn()


func _cull() -> void:
	var origin := level.player.global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_boss:
			continue
		if enemy.global_position.distance_to(origin) > DESPAWN * TILE:
			enemy.queue_free()


func _try_spawn() -> void:
	var world := level.world
	var data := level.data
	var player := level.player
	# The meadow is safe while Wren is teaching: nothing hunts the player on
	# the surface until the first quest is done. Below ground is another matter.
	if level.quests and level.quests.state.get("first_light", {}).get("state", "") != "done":
		var at := World.cell_of(player.global_position)
		if at.y <= data.surface[clampi(at.x, 0, data.width - 1)] + 6:
			return
	var view := world.visible_cells()
	var pcell := World.cell_of(player.global_position - Vector2(0, 60))
	var desperate := player.glow <= 0.0 and pcell.y > data.surface[clampi(pcell.x, 0, data.width - 1)] + 6

	for attempt in 12:
		var side := 1 if randf() < 0.5 else -1
		var x := pcell.x + side * (view.size.x / 2 + randi_range(1, 6))
		var y := pcell.y + randi_range(-6, 4)
		if desperate and randf() < 0.6:
			# When the lantern is out the dark does not wait off-screen.
			x = pcell.x + side * randi_range(4, 7)
		if not data.in_bounds(x, y) or not world.is_loaded(Vector2i(x, y)):
			continue
		var kind := _choose(x, y, desperate)
		if kind == "":
			continue
		var cell := Vector2i(x, y)
		var mode: int = Enemy.KINDS[kind].mode
		if mode == Enemy.Mode.WALK or mode == Enemy.Mode.HOP:
			cell = _ground_below(x, y)
			if cell.x < 0:
				continue
		elif data.is_solid(x, y) and mode != Enemy.Mode.PHASE:
			continue
		if world.near_placed_light(cell, 7.0) and kind != "robot":
			continue
		level.spawn_enemy(kind, World.foot_of(cell))
		return


func _ground_below(x: int, y: int) -> Vector2i:
	var data := level.data
	for dy in range(0, 10):
		var c := Vector2i(x, y + dy)
		if not data.is_solid(c.x, c.y) and not data.is_solid(c.x, c.y - 1) \
				and data.is_solid(c.x, c.y + 1) and data.get_liquid(c.x, c.y) == WorldData.DRY:
			return c
	return Vector2i(-1, -1)


func _choose(x: int, y: int, desperate: bool) -> String:
	var world := level.world
	var data := level.data
	var surface := data.surface[x]
	var dark := world.brightness_at(World.centre_of(Vector2i(x, y))) < 0.18
	if desperate:
		return "shade"
	if y <= surface + 3:
		if world.is_night():
			return ["zombie", "zombie", "slime"].pick_random()
		match data.biome_columns[x]:
			WorldData.Biome.DESERT:
				return ["worm", "worm", "slime"].pick_random()
			WorldData.Biome.TUNDRA:
				return ["frog", "frog", "slime"].pick_random()
			_:
				return ["slime", "slime", "snail", "bee"].pick_random()
	# Robots come only from the ruins' own spawners: any brick wall was
	# tried first, and the cottage by spawn is brick.
	match data.biome_at(x, y):
		WorldData.Biome.CRYSTAL:
			return (["fly", "spike_slime", "shade"] if dark else ["fly", "spike_slime"]).pick_random()
		WorldData.Biome.DEPTHS:
			return (["fire_slime", "shade", "shade"] if dark else ["fire_slime", "robot"]).pick_random()
	return (["mouse", "spike_slime", "zombie", "shade"] if dark else ["mouse", "spike_slime"]).pick_random()


## Ruin spawners wake as the player approaches, each guarding its hall.
func _wake_spawners() -> void:
	var data := level.data
	var pcell := World.cell_of(level.player.global_position)
	for key in _spawner_cooldown.keys():
		_spawner_cooldown[key] -= INTERVAL
		if _spawner_cooldown[key] <= 0.0:
			_spawner_cooldown.erase(key)
	for dy in range(-8, 9):
		for dx in range(-14, 15):
			var cell := pcell + Vector2i(dx, dy)
			if not data.in_bounds(cell.x, cell.y):
				continue
			var key := data.idx(cell.x, cell.y)
			var object: Dictionary = data.objects.get(key, {})
			if object.get("type", "") != "spawner" or _spawner_cooldown.has(key):
				continue
			if absi(dx) < 4:
				continue  # not on top of the player
			_spawner_cooldown[key] = 40.0
			level.spawn_enemy(object.get("enemy", "robot"), World.foot_of(cell))
