extends Node
## Session-wide state: the save slot, notifications, and the bridge
## between menus and the running world.

signal notify(text: String, icon: Texture2D)
signal item_picked(id: String, count: int)
signal crafted(id: String, amount: int)

const SAVE_PATH := "user://lanternbound.save"
const SAVE_VERSION := 1

## Set by the level while it is running.
var level: Node = null
var world: Node = null
var player: Node = null

var playtime := 0.0
var new_game_seed := 0


func _process(delta: float) -> void:
	if world != null and not get_tree().paused:
		playtime += delta


func world_drop(id: String, count: int, at: Vector2) -> void:
	if level != null:
		level.spawn_drop(id, count, at)


func toast(text: String, icon: Texture2D = null) -> void:
	notify.emit(text, icon)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Write everything the running world reports. Atomic: written to a
## temporary file then renamed, so a crash mid-save never corrupts the
## only copy.
func save_game(state: Dictionary) -> bool:
	state["version"] = SAVE_VERSION
	state["playtime"] = playtime
	var temp := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_var(state, false)
	file.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists(SAVE_PATH.get_file()):
		dir.remove(SAVE_PATH.get_file())
	return dir.rename(temp.get_file(), SAVE_PATH.get_file()) == OK


func load_game() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var data = file.get_var(false)
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) > SAVE_VERSION:
		return {}
	playtime = float(data.get("playtime", 0.0))
	return data
