class_name QuestGuide
extends Node2D
## Points at what the current step is about: the NPC to talk to, a tree to
## fell, rock to mine. A bobbing arrow over the target when it is on
## screen; a compass arrow beside the player when it is not.

const TILE := 128.0

var level: Level
var _target := Vector2.INF
var _search := 0.0


func setup(the_level: Level) -> void:
	level = the_level
	z_as_relative = false
	z_index = 85


func _process(delta: float) -> void:
	_search -= delta
	if _search <= 0.0:
		_search = 0.5
		_target = _find_target()
	queue_redraw()


func _find_target() -> Vector2:
	var quests := level.quests
	for id in quests.active():
		var goal: Array = quests.current_step(id).get("goal", [])
		if goal.is_empty():
			continue
		match goal[0]:
			"talk":
				for npc in get_tree().get_nodes_in_group("npcs"):
					if npc.id == goal[1]:
						return npc.global_position + Vector2(0, -500)
			"fell":
				return _nearest_object("tree", 40)
			"break":
				return _nearest_rock(70)
			"craft":
				# Away from the station this needs: point the way to one.
				for recipe in Items.recipes:
					if recipe[0] == goal[1] and recipe[2] != Items.Station.HAND \
							and not (recipe[2] in level.player.nearby_stations()):
						var station: String = {Items.Station.WORKBENCH: "workbench",
							Items.Station.ANVIL: "anvil", Items.Station.CAMPFIRE: "campfire"}.get(recipe[2], "")
						return _nearest_object(station, 80)
	# Otherwise whoever has a quest to offer.
	for npc in get_tree().get_nodes_in_group("npcs"):
		var quest: String = quests.quest_for(npc.id)
		if quest != "" and quests.state[quest].state == "offered":
			return npc.global_position + Vector2(0, -500)
	return Vector2.INF


func _nearest_object(type: String, radius: int) -> Vector2:
	var data := level.data
	var at := World.cell_of(level.player.global_position)
	var best := Vector2.INF
	var best_d := INF
	for dy in range(-12, 12):
		for dx in range(-radius, radius + 1):
			var cell := at + Vector2i(dx, dy)
			if level.world.object_at(cell).get("type", "") == type:
				var p := World.centre_of(cell) + Vector2(0, -TILE * 2.4)
				var d := p.distance_squared_to(level.player.global_position)
				if d < best_d:
					best_d = d
					best = p
	return best


## The nearest rock with open air above it (somewhere a pick can get at),
## searched in growing square rings so the closest is found first.
func _nearest_rock(radius: int) -> Vector2:
	var data := level.data
	var at := World.cell_of(level.player.global_position)
	for r in range(1, radius):
		for i in range(-r, r + 1):
			for cell in [at + Vector2i(i, -r), at + Vector2i(i, r), at + Vector2i(-r, i), at + Vector2i(r, i)]:
				if data.get_tile(cell.x, cell.y) == WorldData.ROCK and not data.is_solid(cell.x, cell.y - 1):
					return World.centre_of(cell) + Vector2(0, -TILE * 0.9)
	return Vector2.INF


func _draw() -> void:
	if _target == Vector2.INF or level.hud == null:
		return
	var view := get_viewport_rect()
	var to_screen := get_canvas_transform()
	var on_screen := view.grow(-80).has_point(to_screen * _target)
	var bob := sin(Time.get_ticks_msec() / 220.0) * 14.0
	var colour := Color(1.0, 0.82, 0.35, 0.95)
	if on_screen:
		var tip := _target + Vector2(0, bob)
		_arrow(tip, Vector2.DOWN, 46.0, colour)
	else:
		var from := level.player.global_position + Vector2(0, -150)
		var dir := (_target - from).normalized()
		_arrow(from + dir * (210 + bob * 0.5), dir, 34.0, Color(colour, 0.85))


func _arrow(tip: Vector2, dir: Vector2, size: float, colour: Color) -> void:
	var side := dir.orthogonal()
	var base := tip - dir * size * 1.4
	var points := PackedVector2Array([tip, base + side * size, base - side * size])
	draw_colored_polygon(points, Color(0.1, 0.06, 0.02, 0.6))
	var inner := PackedVector2Array([tip - dir * 6, base + side * (size - 9) + dir * 3, base - side * (size - 9) + dir * 3])
	draw_colored_polygon(inner, colour)
