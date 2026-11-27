class_name Save3D
extends RefCounted
## The Starfall journey on disk: where the heroine stands, her bag, the
## townsfolk's requests, the Starshards found, the chests opened, the trees
## felled and rocks broken, the Warden's fate and the hour of the day.
## Written atomically (to a temporary file, then renamed) so a crash or a
## phone killing the app mid-write never corrupts the only copy.

## Each account has its own journey (Account.save_path()).
const VERSION := 2


static func path() -> String:
	return Account.save_path()

## Set by the title screen: Continue loads, New Journey starts fresh.
static var load_on_start := false


static func exists() -> bool:
	return FileAccess.file_exists(path())


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(path(), FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var(false)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) > VERSION:
		return {}
	return data


static func write(state: Dictionary) -> bool:
	state["version"] = VERSION
	var target := path()
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var temp := target + ".tmp"
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(state, false)
	f.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(temp, target) == OK


## Everything worth keeping from a running game.
static func capture(game: Node) -> Dictionary:
	var p: Player3D = game.player
	var q: Quests3D = game.quests
	return {
		"pos": p.global_position,
		"yaw": p.model.rotation.y,
		"health": p.health,
		"max_health": p.max_health,
		"max_stamina": p.max_stamina,
		"progress": game.play.prog.to_dict(),
		"bag": game.play.inventory.to_array(),
		"hotbar": game.play.hotbar_index,
		"quest_state": q.state.duplicate(),
		"quest_progress": q.progress.duplicate(),
		"met": q.met.duplicate(),
		"tracked": q.tracked,
		"boss_down": q.boss_down,
		"shards": game.features.found_ids.duplicate(),
		"chests": game.town.opened_ids(),
		"removed": game.world.removed.duplicate(),
		"world_clock": game.world.clock,
		"starstones": game.starstones.attuned.keys() if game.starstones else [],
		"time": game.time_of_day,
		"character": String(game.get("character_id")) if game.get("character_id") else "heroine",
		"start_island": String(game.get("start_island")) if game.get("start_island") else "",
	}


## Put a saved journey back into a freshly built game (after the world,
## town, features and quests exist).
static func restore(game: Node, s: Dictionary) -> void:
	var p: Player3D = game.player
	p.model.rotation.y = float(s.get("yaw", 0.0))
	game.play.prog.from_dict(s.get("progress", {}))
	p.max_health = float(s.get("max_health", Progression.max_health_at(game.play.prog.level)))
	p.health = clampf(float(s.get("health", p.max_health)), 1.0, p.max_health)
	p.max_stamina = float(s.get("max_stamina", p.max_stamina))
	p.stamina = p.max_stamina
	if s.has("bag"):
		game.play.inventory.from_array(s.bag)
		game.play.select(int(s.get("hotbar", 0)))
	var q: Quests3D = game.quests
	q.state = s.get("quest_state", {}).duplicate()
	q.progress = s.get("quest_progress", {}).duplicate()
	q.met = s.get("met", {}).duplicate()
	q.tracked = String(s.get("tracked", ""))
	q.boss_down = bool(s.get("boss_down", false))
	if q.boss_down:
		game.play.skip_boss()
	game.features.restore_found(s.get("shards", []))
	game.town.restore_opened(s.get("chests", []))
	game.world.clock = float(s.get("world_clock", 0.0))
	if game.starstones:
		for id in s.get("starstones", []):
			game.starstones.attuned[String(id)] = true
			game.starstones._refresh(String(id))
	game.world.restore_removed(s.get("removed", {}))
	game.time_of_day = float(s.get("time", game.time_of_day))
