class_name Adventure
extends Node
## The first hour on the chosen starting island.
##
## A new journey opens with an arrival: letterbox bars, the camera sweeping
## down from the island's landmark to Lyra, the chapter title (tap to skip).
## Lumi, a star-wisp, joins her and speaks through the dialogue box; she
## floats at Lyra's shoulder for the whole chain.
##
## Then a chain of steps that teach by playing — walk, jump and dodge, reach
## the strange light, strike trees and rocks, open the backpack, craft a
## campfire, find the hidden place, survive the ambush, take the relic,
## return — each with a short contextual tip (dismissable, and off for good
## from the tip's ✕), real objectives, rewards and saved progress. When it
## ends the island's chapter is complete and the road to Starfall Haven opens
## (the townsfolk's quests take over the tracker).
##   setup(game, island, fresh)   to_dict() / from_dict()   tracker()

signal changed

## Per island: landmark ids (RealmFeatures), foes, relic and names.
const ISLANDS := {
	"jungle": {"title": "The Great Jungle", "chapter": "Chapter I  ·  The Fallen Light",
		"light": "jungle_shrine", "hidden": "falls_0", "relic_at": "world_tree", "foes": ["thornling", "thornling", "wisp_caller", "thornling"],
		"relic": "relic_moth_lantern", "light_name": "the Shrine of the First Root", "hidden_name": "Veilwater Falls",
		"relic_name": "the World Tree"},
	"sky": {"title": "Skybound Isle", "chapter": "Chapter I  ·  The Fallen Light",
		"light": "aerie", "hidden": "aerie_edge", "relic_at": "aerie_far", "foes": ["wisp_caller", "rime_shade", "wisp_caller", "rime_shade"],
		"relic": "relic_featherbone", "light_name": "the Aerie's spire", "hidden_name": "the isle's edge",
		"relic_name": "the farthest isle"},
	"coast": {"title": "The Crystal Coast", "chapter": "Chapter I  ·  The Fallen Light",
		"light": "saltmere", "hidden": "grotto", "relic_at": "jetty", "foes": ["rime_shade", "thornling", "rime_shade", "thornling"],
		"relic": "relic_deepsong", "light_name": "Saltmere", "hidden_name": "the Singing Grotto",
		"relic_name": "the end of the jetty"},
}

const LUMI := {"name": "Lumi", "title": "Star-wisp"}

var game: Node
var island := ""
var step := -1          ## index into steps(); -1 = not started, size = done
var progress := 0
var done := false
var tips := true
var _steps: Array = []
var _wisp: Node3D
var _tip: PanelContainer
var _tip_label: Label
var _last_pos := Vector3.INF
var _relic: Node3D
var _cine := false


func setup(the_game: Node, the_island: String, fresh: bool) -> void:
	game = the_game
	# Keeps watching while a menu pauses the game (the backpack step).
	process_mode = Node.PROCESS_MODE_ALWAYS
	island = the_island
	_steps = steps()
	game.play.enemy_killed.connect(_on_kill)
	game.play.resource_struck.connect(func(_c):
		_count("strike"))
	game.play.crafted.connect(func(id):
		if id == "campfire":
			_count("craft"))
	_make_tip()
	if fresh:
		step = 0
		progress = 0
		call_deferred("_arrive")
	elif step >= 0 and not done:
		_make_wisp()


func active() -> bool:
	return step >= 0 and not done and step < _steps.size()


## The chain for this island.
func steps() -> Array:
	var d: Dictionary = ISLANDS.get(island, ISLANDS.jungle)
	return [
		{"id": "walk", "title": "Arrival", "goal": "move", "count": 14,
			"task": "Walk with Lumi and get your bearings.",
			"tip": "Drag the left side of the screen (or use WASD) to walk. Drag the right side to look around.",
			"say": ["You're awake! I'm Lumi — a star-wisp. The light that fell last night woke the whole island.",
				"Something is calling from %s. Walk with me." % d.light_name], "xp": 25},
		{"id": "moves", "title": "Light on Your Feet", "goal": "moves",
			"task": "Jump once and dodge once.",
			"tip": "Jump with the wing button (Space). Dodge with the double arrow (Shift) — it slips through blows.",
			"say": ["The old paths here are broken. Can you still leap? And dodge? You'll need both."], "xp": 25},
		{"id": "light", "title": "The Strange Light", "goal": "goto", "at": d.light,
			"task": "Follow the strange light to %s." % d.light_name,
			"tip": "The gold marker on your minimap shows where to go.",
			"say": ["There — do you see it? A light where there shouldn't be one. Let's go and look."],
			"done": ["It's fading... the light needs feeding. Wood and stone, and a fire to wake it."], "xp": 60},
		{"id": "gather", "title": "Wood and Stone", "goal": "strike", "count": 6,
			"task": "Strike trees and rocks with your blade.",
			"tip": "Face a tree or a rock and attack. Felled trees give wood, broken rocks give stone.",
			"done": ["That's plenty — and here, the island gives freely to those who ask."],
			"items": [["wood", 6], ["stone", 4]], "xp": 50},
		{"id": "bag", "title": "Your Backpack", "goal": "bag",
			"task": "Open your backpack and look at what you gathered.",
			"tip": "Tap the satchel button (or I) to open the backpack. Items are sorted by kind; tap one for details.",
			"xp": 20},
		{"id": "craft", "title": "A Fire to Wake It", "goal": "craft",
			"task": "Craft a campfire (by hand) in the backpack's crafting page.",
			"tip": "In the menu, open Crafting, pick Campfire and press Craft. Some recipes need a workbench or the forge.",
			"done": ["Warm! The light remembers fire. Now — I felt something else, hidden nearby."], "xp": 60},
		{"id": "hidden", "title": "Something Hidden", "goal": "goto", "at": d.hidden,
			"task": "Search %s for what Lumi felt." % d.hidden_name,
			"tip": "Secrets glow. Look for light where there should be none.",
			"done": ["Careful — we're not alone!"], "xp": 60, "ambush": true},
		{"id": "ambush", "title": "Ambush!", "goal": "slay", "count": 4,
			"task": "Defeat the creatures that followed the light.",
			"tip": "Tap to strike, hold to charge a heavy blow. When the ground under a foe glows, dodge.",
			"done": ["You fight like the stories! And look — they were guarding something."], "xp": 120},
		{"id": "relic", "title": "The Fallen Relic", "goal": "relic", "at": d.relic_at,
			"task": "Take the relic that fell at %s." % d.relic_name,
			"tip": "Relics give lasting powers. Equip them from the backpack's relic slots.",
			"done": ["A piece of the fallen star... it chose you, Lyra."],
			"items": [[d.relic, 1], ["gold_coin", 30]], "xp": 100},
		{"id": "return", "title": "Return the Light", "goal": "goto", "at": d.light,
			"task": "Bring the relic's light back to %s." % d.light_name,
			"done": ["The light is whole again! The island will remember you.",
				"There's a haven across the island — Starfall Haven. People there need help too. Shall we go?"],
			"items": [["heart_crystal", 1]], "xp": 150},
	]


func current() -> Dictionary:
	return _steps[step] if active() else {}


# ------------------------------------------------------------ arrival ---

## Letterbox, a sweep from the landmark down to her, the chapter title.
func _arrive() -> void:
	var d: Dictionary = ISLANDS.get(island, ISLANDS.jungle)
	var p: Vector3 = game.player.global_position
	var target := _landmark(String(d.light))
	if target == Vector3.INF:
		target = p + Vector3(40, 0, 40)
	_cine = true
	game.input.blocked = true
	game.hud.cinematic = true  # a clean frame for the arrival
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var bars := []
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0)
		r.size = Vector2(1920, 0)
		r.position = Vector2(0, 0 if top else 1080)
		layer.add_child(r)
		bars.append(r)
	var title := UiKit.label(String(d.title).to_upper(), 64, UiKit.PALE, "title")
	title.position = Vector2(0, 760)
	title.size = Vector2(1920, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	layer.add_child(title)
	var sub := UiKit.label(String(d.chapter), 28, UiKit.GOLD, "italic")
	sub.position = Vector2(0, 850)
	sub.size = Vector2(1920, 50)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.0
	layer.add_child(sub)
	var skip := UiKit.label("Tap to skip", 22, UiKit.DIM, "italic")
	skip.position = Vector2(1700, 1010)
	layer.add_child(skip)
	var cam := Camera3D.new()
	cam.far = 4000.0
	cam.fov = 55.0
	add_child(cam)
	var from := target + Vector3(-60, 55, 70)
	var end_cam: Camera3D = game.cam.camera
	cam.look_at_from_position(from, target + Vector3(0, 20, 0))
	cam.make_current()
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(bars[0], "size:y", 120.0, 0.6)
	t.tween_property(bars[1], "size:y", 120.0, 0.6)
	t.tween_property(bars[1], "position:y", 960.0, 0.6)
	t.tween_property(title, "modulate:a", 1.0, 1.0).set_delay(0.6)
	t.tween_property(sub, "modulate:a", 1.0, 1.0).set_delay(1.1)
	t.set_parallel(false)
	var sweep := func(k: float) -> void:
		if not is_instance_valid(end_cam) or not _cine:
			return
		var e := end_cam.global_transform
		var a := Transform3D(Basis.looking_at((target - from).normalized() + Vector3(0, -0.2, 0)), from)
		var s := k * k * (3.0 - 2.0 * k)
		cam.global_transform = a.interpolate_with(e, s)
	t.tween_method(sweep, 0.0, 1.0, 5.0).set_delay(0.6)
	t.tween_callback(_end_arrival.bind(layer, cam))
	_skip_cb = _end_arrival.bind(layer, cam)


var _skip_cb: Callable


func _unhandled_input(event: InputEvent) -> void:
	if _cine and (event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		get_viewport().set_input_as_handled()
		if _skip_cb.is_valid():
			_skip_cb.call()


func _end_arrival(layer: CanvasLayer, cam: Camera3D) -> void:
	if not _cine:
		return
	_cine = false
	if is_instance_valid(game.cam.camera):
		game.cam.camera.make_current()
	game.input.blocked = false
	game.hud.cinematic = false
	if is_instance_valid(cam):
		cam.queue_free()
	if is_instance_valid(layer):
		var t := layer.create_tween()
		for c in layer.get_children():
			t.parallel().tween_property(c, "modulate:a", 0.0, 0.5)
		t.tween_callback(layer.queue_free)
	_make_wisp()
	_begin_step()


# -------------------------------------------------------------- steps ---

func _begin_step() -> void:
	if not active():
		return
	var s := current()
	progress = 0
	_last_pos = game.player.global_position
	_moves = {}
	game.hud.banner("Lumi", String(s.title))
	if s.has("say"):
		_speak(s.say)
	_show_tip(String(s.get("tip", "")))
	if s.goal == "relic":
		_place_relic(String(s.at))
	changed.emit()


func _complete_step() -> void:
	var s := current()
	_show_tip("")
	var got := []
	for it in s.get("items", []):
		game.play.inventory.add(it[0], int(it[1]))
		got.append(Items.item_name(it[0]) + (" ×%d" % int(it[1]) if int(it[1]) > 1 else ""))
	if s.has("xp"):
		game.play.prog.gain(int(s.xp))
	Sfx.play("pickup")
	game.hud.banner("Objective complete", String(s.title))
	if not got.is_empty():
		game.play.toast.emit("Received  " + ",  ".join(got))
	if s.get("ambush", false):
		_ambush()
	var lines: Array = s.get("done", [])
	step += 1
	if step >= _steps.size():
		done = true
		_finish(lines)
	else:
		if lines.is_empty():
			_begin_step()
		else:
			_speak(lines, _begin_step)
	game.call_deferred("autosave")
	changed.emit()


func _finish(lines: Array) -> void:
	var d: Dictionary = ISLANDS.get(island, ISLANDS.jungle)
	var after := func():
		game.hud.banner("Chapter complete", String(d.title))
		game.play.toast.emit("The road to Starfall Haven is open. Talk to Wren in the Haven.")
		if _wisp:
			var t := _wisp.create_tween()
			t.tween_property(_wisp, "scale", Vector3.ONE * 0.01, 0.6)
			t.tween_callback(_wisp.queue_free)
			_wisp = null
	if lines.is_empty():
		after.call()
	else:
		_speak(lines, after)


func _speak(lines: Array, then := Callable()) -> void:
	game.hud.dialogue.open("lumi", LUMI, lines, then if then.is_valid() else func(): pass)


func _count(what: String) -> void:
	if not active() or current().goal != what:
		return
	progress += 1
	changed.emit()
	if what == "craft" or progress >= int(current().get("count", 1)):
		_complete_step()


func _on_kill(_e: Node) -> void:
	if active() and current().goal == "slay":
		progress += 1
		changed.emit()
		if progress >= int(current().count):
			_complete_step()


var _moves := {}


func _process(delta: float) -> void:
	if game == null or _cine or not active() or game.player == null:
		_follow_wisp(delta)
		return
	var s := current()
	if get_tree().paused:
		if String(s.goal) == "bag" and game.hud.menu and game.hud.menu.visible and String(game.hud.menu.tab) == "bag":
			_complete_step()
		return
	_follow_wisp(delta)
	var p: Vector3 = game.player.global_position
	match String(s.goal):
		"move":
			if _last_pos != Vector3.INF:
				progress += int(Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() * 10.0)
			_last_pos = p
			if progress >= int(s.count) * 10:
				_complete_step()
		"moves":
			if not game.player.is_on_floor() and game.player.velocity.y > 2.0:
				_moves.jump = true
			if game.player.get("_dodge") and float(game.player.get("_dodge")) > 0.0:
				_moves.dodge = true
			if _moves.has("jump") and _moves.has("dodge"):
				_complete_step()
		"goto":
			var at := _landmark(String(s.at))
			if at != Vector3.INF and Vector2(p.x - at.x, p.z - at.z).length() < 14.0:
				_complete_step()
		"bag":
			if game.hud.menu and game.hud.menu.visible and String(game.hud.menu.tab) == "bag":
				_complete_step()
		"relic":
			if _relic and is_instance_valid(_relic):
				_relic.rotation.y += delta * 1.5
				if p.distance_to(_relic.global_position) < 2.2:
					_relic.queue_free()
					_relic = null
					Arcana.sparks(game, p + Vector3(0, 1, 0), Color(0.9, 0.75, 1.0), 40, 4.0, 0.1)
					_complete_step()


## Where a landmark is (with its ground height), or INF.
func _landmark(id: String) -> Vector3:
	var r: RealmFeatures = game.get("realms")
	if r == null:
		return Vector3.INF
	if r.landmarks.has(id):
		var p: Vector3 = r.landmarks[id].pos
		p.y = game.world.height_at(p.x, p.z)
		if id.begins_with("aerie"):
			p.y = (r.landmarks[id].pos as Vector3).y
		return p
	return Vector3.INF


func _ambush() -> void:
	var d: Dictionary = ISLANDS.get(island, ISLANDS.jungle)
	var p: Vector3 = game.player.global_position
	var foes: Array = d.foes
	for i in foes.size():
		var a := TAU * i / foes.size()
		var at := p + Vector3(cos(a), 0, sin(a)) * 9.0
		at.y = game.world.height_at(at.x, at.z)
		if p.y > at.y + 6.0:
			at.y = p.y  # on a sky isle
		game.play.spawn_enemy(String(foes[i]), at)
	Sfx.play("growl", -4.0)


func _place_relic(at_id: String) -> void:
	var at := _landmark(at_id)
	if at == Vector3.INF:
		at = game.player.global_position + Vector3(6, 0, 6)
	_relic = Node3D.new()
	game.add_child(_relic)
	_relic.global_position = at + Vector3(4, 1.2, 4)
	var mi := MeshInstance3D.new()
	mi.mesh = ArchKit.star_crystal()
	mi.scale = Vector3.ONE * 0.18
	_relic.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(0.85, 0.7, 1.0)
	l.light_energy = 2.5
	l.omni_range = 8.0
	_relic.add_child(l)
	Arcana.pillar(game, _relic.global_position - Vector3(0, 1.2, 0), 1.0, 30.0, Color(0.8, 0.6, 1.0), 4.0)


# --------------------------------------------------------------- wisp ---

func _make_wisp() -> void:
	if _wisp or done:
		return
	_wisp = Node3D.new()
	game.add_child(_wisp)
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var core := MeshInstance3D.new()
	core.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Play3D._spark_texture()
	m.albedo_color = Color(0.85, 0.8, 1.0)
	core.material_override = m
	_wisp.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = Color(0.75, 0.7, 1.0)
	l.light_energy = 0.8
	l.omni_range = 4.0
	_wisp.add_child(l)
	_wisp.global_position = game.player.global_position + Vector3(0.6, 1.8, 0)


var _wt := 0.0


func _follow_wisp(delta: float) -> void:
	if _wisp == null or game == null or game.player == null:
		return
	_wt += delta
	var p: Vector3 = game.player.global_position
	var side: Vector3 = game.cam.right_flat() if game.cam else Vector3.RIGHT
	var want := p + side * 0.7 + Vector3(0, 1.75 + sin(_wt * 2.0) * 0.12, 0)
	_wisp.global_position = _wisp.global_position.lerp(want, 1.0 - exp(-3.0 * delta))


# ---------------------------------------------------------------- tip ---

func _make_tip() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_tip = PanelContainer.new()
	var st := UiKit.panel_style()
	st.set_content_margin_all(18)
	_tip.add_theme_stylebox_override("panel", st)
	_tip.position = Vector2(560, 800)
	_tip.custom_minimum_size = Vector2(800, 0)
	_tip.visible = false
	layer.add_child(_tip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_tip.add_child(row)
	_tip_label = UiKit.label("", 22, UiKit.PALE)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(680, 0)
	row.add_child(_tip_label)
	row.add_child(UiKit.button("✕", func():
		tips = false
		_show_tip(""), "quiet", 60, 44))


func _show_tip(text: String) -> void:
	if _tip == null:
		return
	_tip.visible = tips and text != ""
	_tip_label.text = text
	if _tip.visible:
		UiKit.appear(_tip)


# ----------------------------------------------------------- tracking ---

## For the HUD tracker: {title, detail, target}.
func tracker() -> Dictionary:
	var s := current()
	if s.is_empty():
		return {}
	var detail := ""
	match String(s.goal):
		"strike", "slay":
			detail = "%d / %d" % [mini(progress, int(s.count)), int(s.count)]
		"moves":
			detail = ("Jump ✓  " if _moves.has("jump") else "Jump  ") + ("Dodge ✓" if _moves.has("dodge") else "Dodge")
	var target = null
	if s.has("at"):
		var at := _landmark(String(s.at))
		target = at if at != Vector3.INF else null
	if s.goal == "relic" and _relic and is_instance_valid(_relic):
		target = _relic.global_position
	return {"title": String(s.title) + " — " + String(s.task), "detail": detail, "target": target}


func to_dict() -> Dictionary:
	return {"island": island, "step": step, "done": done, "tips": tips}


func from_dict(d: Dictionary) -> void:
	step = int(d.get("step", -1))
	done = bool(d.get("done", false))
	tips = bool(d.get("tips", true))
	if active():
		_make_wisp()
		call_deferred("_begin_step")
