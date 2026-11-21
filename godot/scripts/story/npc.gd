class_name Npc
extends Node2D
## A person in the world: a jointed rig like the player's, who turns to
## face you when you come near, idles with a bit of life (shifting weight,
## the odd wave), shows a marker when they have something for you, and
## talks when you interact.

const TILE := 128.0
const TALK_RANGE := 2.6 * TILE

var id := "wren"
var level: Level
var body: Node2D  ## Body3D, or the cut-out rig when 3D characters are off
var _marker: Label
var _name: Label
var _facing := 1
var _fidget := 4.0


func setup(the_level: Level, npc_id: String) -> void:
	level = the_level
	id = npc_id
	add_to_group("npcs")
	z_index = 9
	body = Body3D.new(id) if Settings.characters_3d and Body3D.CAST.has(id) else CutoutBody.new(id)
	add_child(body)
	if Settings.shadows:
		add_child(SoftShadow.under(self, level.world, 0.8))

	_name = Label.new()
	_name.text = Story.speaker(id).get("name", id)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.position = Vector2(-120, -300)
	_name.size = Vector2(240, 40)
	_name.add_theme_font_override("font", UITheme.title_font())
	_name.add_theme_font_size_override("font_size", 30)
	_name.add_theme_color_override("font_color", UITheme.PAPER)
	_name.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12))
	_name.add_theme_constant_override("outline_size", 10)
	add_child(_name)

	# "!" when they have a quest to give, "?" when they are waiting on you.
	_marker = Label.new()
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.position = Vector2(-60, -400)
	_marker.size = Vector2(120, 90)
	_marker.add_theme_font_override("font", UITheme.title_font())
	_marker.add_theme_font_size_override("font_size", 80)
	_marker.add_theme_color_override("font_color", UITheme.GOLD)
	_marker.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	_marker.add_theme_constant_override("outline_size", 14)
	add_child(_marker)


func near_player() -> bool:
	return level.player != null and global_position.distance_to(level.player.global_position) < TALK_RANGE


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	var to_player := level.player.global_position.x - global_position.x
	var close := absf(to_player) < 7.0 * TILE
	if close and absf(to_player) > 30.0:
		_facing = 1 if to_player > 0 else -1
	body.flip_h = _facing < 0
	body.motion = Vector2.ZERO
	body.grounded = true

	# A wave now and then while the player is about.
	_fidget -= delta
	if _fidget <= 0.0:
		_fidget = randf_range(5.0, 11.0)
		if close and body.animation == "idle":
			body.play("cheer")
			get_tree().create_timer(1.1).timeout.connect(func(): body.play("idle"))

	var quest := level.quests.quest_for(id) if level.quests else ""
	if quest == "":
		_marker.text = ""
	else:
		_marker.text = "!" if level.quests.state[quest].state == "offered" else "?"
	_marker.position.y = -400 + sin(Time.get_ticks_msec() / 260.0) * 8.0
	_name.modulate.a = 1.0 if near_player() else 0.6


## Turn to the player and play a talking gesture.
func greet() -> void:
	body.play("interact")
