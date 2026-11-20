class_name Quests
extends Node
## The story's quests. Each is a list of steps; each step is one objective,
## met by events the world reports (a tree felled, a thing crafted, a
## depth reached...). A step can name a voiced line, spoken when it begins,
## so the tutorial teaches by talking the player through play rather than
## by walls of text.
##
## Objectives:
##   ["talk", npc]            speak to an NPC
##   ["fell", count]          trees cut down
##   ["have", item, count]    carry this many (counted, not consumed)
##   ["craft", item, count]   make this many
##   ["place", object]        set down a placeable (workbench, wardstone...)
##   ["build", count]         blocks placed
##   ["break", material, n]   tiles of a material dug out ("stone" = rock)
##   ["depth", metres]        reach this depth below the surface
##   ["kill", kind]           defeat a creature or boss

signal changed
signal completed(quest_id: String)
signal step_started(quest_id: String, line_id: String)

const DEFS := {
	"first_light": {
		"title": "First Light", "giver": "wren", "main": true,
		"offer": ["wren_wake", "wren_premise"],
		"steps": [
			{"goal": ["fell", 1], "text": "Fell a tree", "line": "wren_task_tree"},
			{"goal": ["have", "wood", 10], "text": "Gather wood", "line": "wren_task_wood"},
			{"goal": ["craft", "workbench", 1], "text": "Craft a workbench (open your pack)",
				"line": "wren_task_workbench"},
			{"goal": ["place", "workbench"], "text": "Place the workbench", "line": "wren_task_place"},
			{"goal": ["break", "stone", 6], "text": "Mine stone", "line": "wren_task_stone"},
			{"goal": ["craft", "wood_axe", 1], "text": "Craft a wooden axe at the bench", "line": "wren_task_axe"},
			{"goal": ["build", 6], "text": "Build a wall: place blocks", "line": "wren_task_build"},
			{"goal": ["talk", "wren"], "text": "Return to Wren", "line": "wren_task_return"},
		],
		"done": ["wren_done_first"],
		"reward": {"glow_flask": 2, "wood_shield": 1},
		"next": ["below_the_roots", "a_hearty_meal"],
	},
	"below_the_roots": {
		"title": "Below the Roots", "giver": "bram", "main": true,
		"offer": ["bram_greet", "bram_roots_offer"],
		"steps": [
			{"goal": ["depth", 40], "text": "Descend below the roots (40m)", "line": "bram_roots_depth"},
			{"goal": ["have", "copper_ore", 12], "text": "Mine copper ore"},
			{"goal": ["have", "iron_ore", 6], "text": "Mine iron ore"},
			{"goal": ["craft", "anvil", 1], "text": "Build an anvil at the workbench"},
			{"goal": ["place", "anvil"], "text": "Place the anvil"},
			{"goal": ["craft", "copper_pickaxe", 1], "text": "Forge a copper pickaxe"},
			{"goal": ["talk", "bram"], "text": "Show Bram your pickaxe"},
		],
		"done": ["bram_roots_done"],
		"reward": {"iron_axe": 1, "torch": 10},
		"next": ["ward_the_dark", "glowcaps"],
	},
	"ward_the_dark": {
		"title": "Ward the Dark", "giver": "wren", "main": true,
		"offer": ["wren_ward_offer"],
		"steps": [
			{"goal": ["have", "glowshard", 6], "text": "Gather glowshards"},
			{"goal": ["have", "ruby", 1], "text": "Find a ruby"},
			{"goal": ["craft", "wardstone", 1], "text": "Forge a wardstone"},
			{"goal": ["place", "wardstone"], "text": "Plant the wardstone"},
			{"goal": ["talk", "wren"], "text": "Tell Wren"},
		],
		"done": ["wren_ward_done"],
		"reward": {"heart_crystal": 1},
		"next": ["the_rusted_warden"],
	},
	"the_rusted_warden": {
		"title": "The Rusted Warden", "giver": "bram", "main": true,
		"offer": ["bram_warden_offer"],
		"steps": [
			{"goal": ["have", "vault_key", 1], "text": "Find the vault key in the ruins"},
			{"goal": ["kill", "warden"], "text": "Wake and defeat the Warden at the altar"},
			{"goal": ["talk", "bram"], "text": "Return to Bram"},
		],
		"done": ["bram_warden_done"],
		"reward": {"iron_shield": 1, "glow_flask": 3},
		"next": ["into_the_hollows"],
	},
	"into_the_hollows": {
		"title": "Into the Hollows", "giver": "wren", "main": true,
		"offer": ["wren_gloam_offer"],
		"steps": [
			{"goal": ["kill", "gloam"], "text": "Find the geode in the Crystal Hollows and defeat the Gloam"},
			{"goal": ["talk", "wren"], "text": "Return to Wren"},
		],
		"done": ["wren_gloam_done"],
		"reward": {"heart_crystal": 2},
		"next": [],
	},
	"a_hearty_meal": {
		"title": "A Hearty Meal", "giver": "mira", "main": false,
		"offer": ["mira_greet", "mira_meal_offer"],
		"steps": [
			{"goal": ["craft", "campfire", 1], "text": "Build a campfire"},
			{"goal": ["craft", "cooked_meat", 2], "text": "Cook meat at the campfire"},
			{"goal": ["talk", "mira"], "text": "Bring the meat to Mira"},
		],
		"done": ["mira_meal_done"],
		"take": {"cooked_meat": 2},
		"reward": {"stew": 3},
		"next": [],
	},
	"glowcaps": {
		"title": "Liquid Light", "giver": "mira", "main": false,
		"offer": ["mira_shards_offer"],
		"steps": [
			{"goal": ["have", "glowshard", 6], "text": "Gather glowshards for Mira"},
			{"goal": ["talk", "mira"], "text": "Bring them to Mira"},
		],
		"done": ["mira_shards_done"],
		"take": {"glowshard": 6},
		"reward": {"glow_flask": 2},
		"next": [],
	},
}

var level: Level
## quest id -> {"step": int, "count": int, "state": "offered"|"active"|"done"}
var state := {}
var _depth_timer := 0.0


func setup(the_level: Level, saved := {}) -> void:
	level = the_level
	state = saved.duplicate(true)
	if state.is_empty():
		# The opening quest is offered by Wren the moment the game starts.
		state["first_light"] = {"step": 0, "count": 0, "state": "offered"}


func to_dict() -> Dictionary:
	return state.duplicate(true)


# --- Queries -----------------------------------------------------------------

func active() -> Array:
	var out := []
	for id in state:
		if state[id].state == "active":
			out.append(id)
	# Main quests first.
	out.sort_custom(func(a, b): return DEFS[a].main and not DEFS[b].main)
	return out


## The quest an NPC has for the player right now: one to offer, or one
## waiting on a "talk to" step. "" if none.
func quest_for(npc: String) -> String:
	for id in state:
		var q: Dictionary = state[id]
		if q.state == "offered" and DEFS[id].giver == npc:
			return id
		if q.state == "active":
			var goal: Array = current_step(id).get("goal", [])
			if goal.size() > 1 and goal[0] == "talk" and goal[1] == npc:
				return id
	return ""


func current_step(id: String) -> Dictionary:
	var q: Dictionary = state.get(id, {})
	var steps: Array = DEFS[id].steps
	if q.is_empty() or q.step >= steps.size():
		return {}
	return steps[q.step]


## Text and progress for the tracker, e.g. ["Gather wood", 6, 10].
func progress(id: String) -> Array:
	var step := current_step(id)
	if step.is_empty():
		return ["", 0, 0]
	var goal: Array = step.goal
	var need := _needed(goal)
	var have := _counted(id, goal)
	return [step.text, mini(have, need), need]


func _needed(goal: Array) -> int:
	match goal[0]:
		"fell", "build":
			return int(goal[1])
		"have", "craft", "break":
			return int(goal[2])
	return 1


func _counted(id: String, goal: Array) -> int:
	if goal[0] == "have":
		return level.player.inventory.count(goal[1])
	return int(state[id].count)


# --- Talking -----------------------------------------------------------------

## The player spoke to an NPC. Returns the lines to say, in order.
func talk(npc: String) -> Array:
	var id := quest_for(npc)
	if id == "":
		return ["%s_idle" % npc]
	var q: Dictionary = state[id]
	if q.state == "offered":
		q.state = "active"
		q.step = 0
		q.count = 0
		var lines: Array = DEFS[id].offer.duplicate()
		var first := current_step(id)
		if first.has("line"):
			lines.append(first.line)
		changed.emit()
		_check_have(id)
		return lines
	# A "talk to" step: this conversation completes it. The closing lines
	# are said now; a following step's line comes through step_started.
	var finishing := int(q.step) + 1 >= (DEFS[id].steps as Array).size()
	_advance(id)
	return (DEFS[id].done as Array).duplicate() if finishing else []


# --- Events from the world -----------------------------------------------------

func event(kind: String, what := "", amount := 1) -> void:
	for id in active():
		var goal: Array = current_step(id).get("goal", [])
		if goal.is_empty() or goal[0] != kind:
			continue
		match kind:
			"fell", "build":
				_add(id, amount, int(goal[1]))
			"craft", "break":
				if goal[1] == what:
					_add(id, amount, int(goal[2]))
			"place", "kill":
				if goal[1] == what:
					_advance(id)
			"depth":
				if amount >= int(goal[1]):
					_advance(id)


func _add(id: String, amount: int, need: int) -> void:
	state[id].count = int(state[id].count) + amount
	if state[id].count >= need:
		_advance(id)
	else:
		changed.emit()


## Inventory changed: "have" steps complete as soon as the items are in the bag.
func inventory_changed() -> void:
	for id in active():
		_check_have(id)


func _check_have(id: String) -> void:
	var goal: Array = current_step(id).get("goal", [])
	if goal.size() == 3 and goal[0] == "have" and level.player.inventory.count(goal[1]) >= int(goal[2]):
		_advance(id)


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	_depth_timer -= delta
	if _depth_timer <= 0.0:
		_depth_timer = 0.5
		var cell := World.cell_of(level.player.global_position)
		var surface: int = level.data.surface[clampi(cell.x, 0, level.data.width - 1)]
		event("depth", "", (cell.y - surface) * 2)


func _advance(id: String) -> void:
	var q: Dictionary = state[id]
	q.step = int(q.step) + 1
	q.count = 0
	var steps: Array = DEFS[id].steps
	if q.step >= steps.size():
		_complete(id)
		return
	var step := current_step(id)
	if step.has("line"):
		step_started.emit(id, step.line)
	changed.emit()
	_check_have(id)


func _complete(id: String) -> void:
	var def: Dictionary = DEFS[id]
	state[id].state = "done"
	for item in def.get("take", {}):
		level.player.inventory.remove(item, def.take[item])
	for item in def.get("reward", {}):
		var left := level.player.inventory.add(item, def.reward[item])
		if left > 0:
			level.spawn_drop(item, left, level.player.global_position + Vector2(0, -80))
	for next in def.get("next", []):
		if not state.has(next):
			state[next] = {"step": 0, "count": 0, "state": "offered"}
	completed.emit(id)
	changed.emit()
