class_name QuestTracker
extends VBoxContainer
## The current objectives, top right: quest title, what to do now, and how
## far along it is. Pulses when something changes; a banner when a quest
## is completed.

var level: Level
var _rows := {}


func setup(the_level: Level) -> void:
	level = the_level
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -500
	offset_right = -24
	offset_top = 250
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	level.quests.changed.connect(_refresh)
	level.quests.completed.connect(_on_completed)
	level.player.inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for child in get_children():
		child.queue_free()
	var shown := 0
	for id in level.quests.active():
		if shown >= 2:
			break
		shown += 1
		var def: Dictionary = Quests.DEFS[id]
		var p: Array = level.quests.progress(id)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UITheme.flat(Color(0.07, 0.06, 0.10, 0.72), 18,
			UITheme.GOLD if def.main else Color(0.5, 0.75, 0.55), 3))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(column)
		column.add_child(UITheme.title(("★ " if def.main else "◆ ") + def.title, 30,
			UITheme.GOLD if def.main else Color(0.6, 0.9, 0.65)))
		var step := Label.new()
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step.custom_minimum_size = Vector2(440, 0)
		step.add_theme_font_size_override("font_size", 26)
		step.add_theme_color_override("font_color", UITheme.PAPER)
		step.text = p[0] + ("  %d/%d" % [p[1], p[2]] if p[2] > 1 else "")
		column.add_child(step)
		add_child(box)
		if _rows.get(id, "") != step.text:
			# Changed: a quick pulse so the eye catches it.
			box.pivot_offset = Vector2(235, 40)
			box.scale = Vector2(1.06, 1.06)
			box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
		_rows[id] = step.text


func _on_completed(id: String) -> void:
	Game.toast("Quest complete: %s" % Quests.DEFS[id].title)
	Sfx.play("craft", 2.0, 0.0)
