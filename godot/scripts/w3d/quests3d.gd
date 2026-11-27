class_name Quests3D
extends Node
## The townsfolk's requests and how far along each one is. A quest is offered
## when its giver is spoken to (and the one before it is finished), becomes
## active, turns "ready" when its goal is met, and is handed in to the giver
## for a reward. Goals:
##   reach  — stand on a floating isle (index into SkyIslands.tops)
##   shards — have found this many Starshards
##   item   — carry this many of an item (taken on hand-in)
##   kill   — defeat this many of the risen
##   boss   — defeat the Rusted Warden
## The tracker (top left of the HUD) follows the most recent quest.

signal changed

const QUESTS := [
	{"id": "wings", "task": "Step into the updraft beside the little isle north of town, jump twice to spread your wings, and land on top.",  "giver": "wren", "title": "Wings of the Wind", "goal": "reach", "isle": 9,
		"reward": [["heart_crystal", 1], ["gold_coin", 20]]},
	{"id": "shards", "task": "Find three Starshards: floating blue crystals on hilltops, isles and lonely corners.",  "giver": "mira", "title": "Starshards", "goal": "shards", "count": 3,
		"reward": [["stew", 2], ["glow_flask", 1]]},
	{"id": "ore", "task": "Strike the grey boulders in the hills for iron ore and bring Tobin five pieces.",  "giver": "tobin", "title": "Iron for the Forge", "goal": "item", "item": "iron_ore", "count": 5,
		"reward": [["iron_sword", 1]]},
	{"id": "hunt", "task": "Defeat six of the risen dead. They walk the roads and woods, and grow bold at night.",  "giver": "aldous", "title": "The Night Hunt", "goal": "kill", "count": 6,
		"reward": [["gold_coin", 40]]},
	{"id": "starspire", "task": "Reach the Starspire, the great isle crowned with a pillar of light, and stand upon it.",  "giver": "wren", "after": "wings", "title": "The Starspire", "goal": "reach", "isle": 0,
		"reward": [["lumen_core", 1], ["gold_coin", 50]]},
	{"id": "warden", "task": "Find the ruins beyond the hills and free the Rusted Warden from the dark.",  "giver": "aldous", "after": "hunt", "title": "The Rusted Warden", "goal": "boss",
		"reward": [["silver_sword", 1], ["relic_bulwark", 1]]},
]

var game: Node
var state := {}      ## id -> "active" | "ready" | "done"
var progress := {}   ## id -> int
var met := {}        ## npc id -> true once greeted
var tracked := ""
var boss_down := false
var npcs := {}       ## npc id -> Npc3D
var _talk: Dictionary


func setup(the_game: Node) -> void:
	game = the_game
	var file := FileAccess.open("res://assets/story/dialogue3d.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	_talk = data.get("talk", {})
	speakers = data.get("speakers", {})
	game.play.enemy_killed.connect(_on_kill)


var speakers := {}


func quest(id: String) -> Dictionary:
	for q in QUESTS:
		if q.id == id:
			return q
	return {}


func lines(key: String) -> Array:
	return _talk.get(key, [])


## The quest `npc` would offer now, or {}.
func offer_for(npc: String) -> Dictionary:
	for q in QUESTS:
		if q.giver != npc or state.has(q.id):
			continue
		if q.has("after") and state.get(q.after, "") != "done":
			continue
		return q
	return {}


func _with_state(npc: String, s: String) -> Dictionary:
	for q in QUESTS:
		if q.giver == npc and state.get(q.id, "") == s:
			return q
	return {}


## What floats over a person's head: "!" a request, "?" a request done.
func marker_for(npc: String) -> String:
	if not _with_state(npc, "ready").is_empty():
		return "?"
	if not offer_for(npc).is_empty():
		return "!"
	return ""


## Speak with `npc`: greet, hand in, remind or offer. Returns the lines to
## show and does the bookkeeping when they have been read.
func talk(npc: String) -> void:
	var say: Array = []
	if not met.has(npc):
		met[npc] = true
		say.append_array(lines(npc + "_greet"))
	var ready := _with_state(npc, "ready")
	var active := _with_state(npc, "active")
	var finish := {}
	var start := {}
	if not ready.is_empty():
		say.append_array(lines(ready.id + "_done"))
		finish = ready
		# A new request may follow straight on.
		state[ready.id] = "done"
		start = offer_for(npc)
		state[ready.id] = "ready"
		if not start.is_empty():
			say.append_array(lines(start.id + "_offer"))
	elif not active.is_empty():
		say.append_array(lines(active.id + "_remind"))
	else:
		start = offer_for(npc)
		if not start.is_empty():
			say.append_array(lines(start.id + "_offer"))
		elif say.is_empty():
			say.append(lines(npc + "_idle").pick_random())
	game.hud.dialogue.open(npc, speakers.get(npc, {}), say, _after_talk.bind(finish, start, npc))


func _after_talk(finish: Dictionary, start: Dictionary, npc := "") -> void:
	_end_talk()
	# Tobin keeps a stall: an ordinary chat with him ends at his wares.
	if npc == "tobin" and finish.is_empty() and start.is_empty() and state.get("ore", "") != "active":
		game.hud.menu.call_deferred("open", "shop")
	game.call_deferred("autosave")
	if not finish.is_empty():
		_complete(finish)
	if not start.is_empty():
		_accept(start)
	changed.emit()


func _accept(q: Dictionary) -> void:
	state[q.id] = "active"
	progress[q.id] = 0
	tracked = q.id
	if q.goal == "boss" and boss_down:
		state[q.id] = "ready"
	game.hud.banner("New Quest", q.title)
	Sfx.play("pickup")


func _complete(q: Dictionary) -> void:
	state[q.id] = "done"
	game.play.prog.gain(Progression.XP_QUEST)
	if q.goal == "item":
		game.play.inventory.remove(q.item, int(q.count))
	var got: Array = []
	for r in q.reward:
		game.play.inventory.add(r[0], r[1])
		got.append("%s ×%d" % [Items.item_name(r[0]), r[1]] if r[1] > 1 else Items.item_name(r[0]))
	game.hud.banner("Quest Complete", q.title)
	game.play.toast.emit("Received  " + ",  ".join(got))
	Sfx.play("craft")
	if tracked == q.id:
		tracked = ""
		for other in QUESTS:
			if state.get(other.id, "") in ["active", "ready"]:
				tracked = other.id


func _ready_up(q: Dictionary) -> void:
	if state.get(q.id, "") != "active":
		return
	state[q.id] = "ready"
	var giver: String = speakers.get(q.giver, {}).get("name", q.giver)
	game.play.toast.emit("%s — done!  Return to %s" % [q.title, giver])
	Sfx.play("pickup")
	changed.emit()


func _on_kill(e: Node) -> void:
	if e == game.play.boss or (e.get("spec") and e.spec.has("boss")):
		boss_down = true
		var w := quest("warden")
		_ready_up(w)
		return
	var h := quest("hunt")
	if state.get("hunt", "") == "active":
		progress["hunt"] = int(progress.get("hunt", 0)) + 1
		if progress["hunt"] >= int(h.count):
			_ready_up(h)
		changed.emit()


## The townsperson being spoken to, or null.
var speaking: Npc3D


## Begin a conversation with `npc`: the heroine stops, turns to them and the
## camera comes round over her shoulder.
func start_talk(npc: Npc3D) -> void:
	speaking = npc
	npc.talking = true
	game.input.blocked = true
	var p: Player3D = game.player
	var to: Vector3 = npc.global_position - p.global_position
	p.model.rotation.y = atan2(to.x, to.z)
	_saved_cam = [game.cam.distance, game.cam.yaw_target, game.cam.pitch_target]
	game.cam.distance = 2.9
	game.cam.yaw_target = atan2(-to.x, -to.z) + 0.7
	game.cam.pitch_target = -0.06
	talk(npc.id)


var _saved_cam: Array = []


func _end_talk() -> void:
	if speaking:
		speaking.talking = false
	speaking = null
	game.input.blocked = false
	if not _saved_cam.is_empty():
		game.cam.distance = _saved_cam[0]
		game.cam.pitch_target = _saved_cam[2]


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	var p: Vector3 = game.player.global_position
	# The heroine glances at whoever is close by.
	var glance = null
	var gd := 5.0
	for n in npcs.values():
		var d: float = (n as Node3D).global_position.distance_to(p)
		if d < gd:
			gd = d
			glance = (n as Node3D).global_position + Vector3(0, 1.45, 0)
	if speaking:
		glance = speaking.global_position + Vector3(0, 1.45, 0)
	game.player.look_at_point = glance
	if speaking == null:
		var best: Npc3D = null
		for n in npcs.values():
			if (n as Npc3D).in_reach():
				best = n
		if best:
			game.hud.prompt("Talk to " + String(speakers.get(best.id, {}).get("name", best.id)))
			if game.input.interact:
				game.input.interact = false
				start_talk(best)
	for q in QUESTS:
		if state.get(q.id, "") != "active":
			continue
		match q.goal:
			"reach":
				var top: Array = game.islands.tops[q.isle]
				var c: Vector3 = top[0]
				if Vector2(p.x - c.x, p.z - c.z).length() < float(top[1]) and p.y > c.y - 3.0 and game.player.is_on_floor():
					_ready_up(q)
			"shards":
				progress[q.id] = game.features.found
				if game.features.found >= int(q.count):
					_ready_up(q)
			"item":
				progress[q.id] = game.play.inventory.count(q.item)
				if progress[q.id] >= int(q.count):
					_ready_up(q)


## For the HUD tracker: {title, detail, target (Vector3 or null)}.
func tracker() -> Dictionary:
	if tracked != "":
		var q := quest(tracked)
		var s: String = state.get(tracked, "")
		if s == "ready":
			var npc: Npc3D = npcs.get(q.giver)
			return {"title": q.title, "detail": "Return to " + String(speakers.get(q.giver, {}).get("name", "")),
				"target": npc.global_position if npc else null}
		match q.goal:
			"reach":
				return {"title": q.title, "detail": "", "target": (game.islands.tops[q.isle][0] as Vector3)}
			"boss":
				return {"title": q.title, "detail": "", "target": game.play.boss_site}
			_:
				return {"title": q.title, "detail": "%d / %d" % [mini(int(progress.get(tracked, 0)), int(q.count)), int(q.count)],
					"target": null}
	# Nothing under way: point to whoever has something to ask.
	for npc_id in ["wren", "mira", "tobin", "aldous"]:
		if not offer_for(npc_id).is_empty() and npcs.has(npc_id):
			var who: String = speakers.get(npc_id, {}).get("name", npc_id)
			return {"title": "Talk to " + who, "detail": "", "target": (npcs[npc_id] as Npc3D).global_position}
	return {"title": "Explore the Starfall", "detail": "", "target": null}
