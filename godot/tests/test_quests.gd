extends TestCase
## The story's quests, played through the real level.


func _make_level(saved := {}) -> Level:
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(5150, saved)
	return level


func test_every_quest_is_well_formed() -> void:
	var lines: Dictionary = Story.data().lines
	for id in Quests.DEFS:
		var def: Dictionary = Quests.DEFS[id]
		check(Story.speaker(def.giver).size() > 0, "%s giver %s exists" % [id, def.giver])
		for line in def.offer + def.done:
			check(lines.has(line), "%s: line %s exists" % [id, line])
		for step in def.steps:
			if step.has("line"):
				check(lines.has(step.line), "%s: step line %s exists" % [id, step.line])
			var goal: Array = step.goal
			if goal[0] in ["have", "craft"]:
				check(Items.exists(goal[1]), "%s: item %s exists" % [id, goal[1]])
		for item in def.get("reward", {}):
			check(Items.exists(item), "%s: reward %s exists" % [id, item])
		for next in def.next:
			check(Quests.DEFS.has(next), "%s: next quest %s exists" % [id, next])


func test_every_line_is_voiced() -> void:
	for id in Story.data().lines:
		var audio := Story.audio(id)
		check(audio != null, "%s has a recording" % id)
		if audio:
			check(audio.get_length() > 0.8, "%s is real speech (%.1fs)" % [id, audio.get_length()])


func test_the_tutorial_plays_through() -> void:
	var level := _make_level()
	var q := level.quests
	var inv := level.player.inventory
	check(q.quest_for("wren") == "first_light", "Wren offers the first quest")
	var lines: Array = q.talk("wren")
	check(lines.has("wren_wake") and lines.has("wren_task_tree"), "she wakes you and sets the first task")
	check(q.active() == ["first_light"], "the quest is under way")

	q.event("fell")
	check_eq(q.state.first_light.step, 1, "felling a tree completes the first step")
	inv.add("wood", 30)
	check_eq(q.state.first_light.step, 2, "carrying ten wood completes the next")
	q.event("craft", "workbench", 1)
	check_eq(q.state.first_light.step, 3, "crafting the bench")
	q.event("place", "workbench")
	check_eq(q.state.first_light.step, 4, "placing it")
	for i in 5:
		q.event("break", "stone")
	check_eq(q.state.first_light.step, 4, "five stones is not six")
	q.event("break", "soil")
	check_eq(q.state.first_light.step, 4, "soil is not stone")
	q.event("break", "stone")
	check_eq(q.state.first_light.step, 5, "six stones")
	q.event("craft", "wood_axe", 1)
	for i in 6:
		q.event("build")
	check_eq(q.state.first_light.step, 7, "axe made and wall built")
	check(q.quest_for("wren") == "first_light", "Wren is waiting to hear")
	var done: Array = q.talk("wren")
	check(done.has("wren_done_first"), "she thanks you")
	check_eq(q.state.first_light.state, "done", "the quest is done")
	check(inv.count("glow_flask") >= 2 and inv.count("wood_shield") == 1, "the reward is given")
	check(q.quest_for("bram") == "below_the_roots", "Bram has the next main quest")
	check(q.quest_for("mira") == "a_hearty_meal", "Mira has a side quest")
	level.free()


func test_quest_progress_survives_saving() -> void:
	var level := _make_level()
	level.quests.talk("wren")
	level.quests.event("fell")
	var saved := {"world": level.data.to_dict(), "player": level.player.to_dict(),
		"time": 0.4, "quests": level.quests.to_dict()}
	level.free()
	var again := _make_level(saved)
	check_eq(again.quests.state.first_light.state, "active", "still under way")
	check_eq(again.quests.state.first_light.step, 1, "at the same step")
	again.free()


func test_old_saves_without_quests_still_load() -> void:
	var level := _make_level()
	var saved := {"world": level.data.to_dict(), "player": level.player.to_dict(), "time": 0.4}
	level.free()
	var again := _make_level(saved)
	check(again.quests.quest_for("wren") == "first_light", "the story starts fresh")
	again.free()


func test_quest_items_handed_over_are_taken() -> void:
	var level := _make_level()
	var q := level.quests
	q.state["glowcaps"] = {"step": 0, "count": 0, "state": "offered"}
	q.talk("mira")
	level.player.inventory.add("glowshard", 8)
	check(q.quest_for("mira") == "glowcaps", "Mira waits for the shards")
	q.talk("mira")
	check_eq(level.player.inventory.count("glowshard"), 2, "she keeps the six she asked for")
	check(level.player.inventory.count("glow_flask") >= 2, "and pays in flasks")
	level.free()


func test_npcs_stand_on_the_ground_near_the_start() -> void:
	var level := _make_level()
	var ids := []
	for npc in Engine.get_main_loop().get_nodes_in_group("npcs"):
		if not level.is_ancestor_of(npc):
			continue
		ids.append(npc.id)
		var cell := World.cell_of(npc.global_position + Vector2(0, -10))
		check(not level.data.is_solid(cell.x, cell.y), "%s is not inside rock" % npc.id)
		check(level.data.is_solid(cell.x, cell.y + 1), "%s stands on ground" % npc.id)
		check(absf(npc.global_position.x - level.player.global_position.x) < 80 * 128, "%s is near the start" % npc.id)
	ids.sort()
	check_eq(ids, ["bram", "mira", "wren"], "all three are in the world")
	level.free()
