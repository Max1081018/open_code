class_name Npc3D
extends Node3D
## A townsperson: their character, a little routine of idles that suits them
## (Mira tidies her stall, Tobin works kneeling, Aldous stands guard), a
## name plate and a quest marker ("!" / "?") over their head. They turn to
## look at the heroine when she comes near and face her while talking.

var id := ""
var game: Node
var model: Node3D
var anim: AnimationPlayer
var talking := false
var home_yaw := 0.0
## [[clip, seconds], ...] played in turn while idle.
var routine: Array = []
var _step := 0
var _time := 0.0
var _clip := ""
var _marker: Label3D
var _plates: Array = []
var _height := 1.6
var _look: LookAtModifier3D
var _look_target: Node3D
## Waypoints (x, z) walked in a loop, pausing at each for the idle routine.
var route: Array = []
var _leg := 0
var _pause := 3.0
const WALK_SPEED := 1.15


func setup(the_game: Node, npc_id: String, at: Vector3, yaw: float, idle_routine: Array) -> void:
	game = the_game
	id = npc_id
	routine = idle_routine
	home_yaw = yaw
	model = CharacterKit.build(npc_id)
	add_child(model)
	model.rotation.y = yaw
	_height = float(model.get_meta("style", {}).get("height", 1.6))
	anim = model.find_child("AnimationPlayer", true, false)
	if anim:
		for clip in anim.get_animation_list():
			if clip.begins_with("Idle") or clip in ["Sword_Idle", "Fixing_Kneeling", "Spell_Simple_Idle", "Zombie_Idle"]:
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	global_position = at
	# Solid, so the heroine walks round rather than through.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = _height
	cs.shape = cap
	cs.position.y = _height * 0.5
	body.add_child(cs)
	add_child(body)
	# Name plate and marker.
	var who: Dictionary = game.quests.speakers.get(npc_id, {})
	var plate := Label3D.new()
	plate.text = String(who.get("name", npc_id))
	plate.font = load("res://assets/fonts/Cinzel.ttf")
	plate.font_size = 40
	plate.pixel_size = 0.004
	plate.outline_size = 10
	plate.modulate = Color(1.0, 0.95, 0.85)
	plate.outline_modulate = Color(0.06, 0.06, 0.16, 0.8)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = false
	plate.fixed_size = false
	plate.position.y = _height + 0.32
	plate.visibility_range_end = 16.0
	add_child(plate)
	_plates.append(plate)
	var title := Label3D.new()
	title.text = String(who.get("title", ""))
	title.font = plate.font
	title.font_size = 26
	title.pixel_size = 0.004
	title.outline_size = 8
	title.modulate = Color(0.96, 0.84, 0.56)
	title.outline_modulate = plate.outline_modulate
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position.y = _height + 0.2
	title.visibility_range_end = 12.0
	add_child(title)
	_plates.append(title)
	_marker = Label3D.new()
	_marker.font = load("res://assets/fonts/CinzelDecorative-Bold.ttf")
	_marker.font_size = 110
	_marker.pixel_size = 0.004
	_marker.outline_size = 18
	_marker.modulate = Color(1.0, 0.84, 0.35)
	_marker.outline_modulate = Color(0.25, 0.12, 0.02, 0.9)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.position.y = _height + 0.75
	_marker.visibility_range_end = 90.0
	add_child(_marker)
	_play(routine[0][0] if not routine.is_empty() else "Idle")
	# The head follows the heroine (within a natural range).
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	_look_target = Node3D.new()
	add_child(_look_target)
	var look := LookAtModifier3D.new()
	look.bone_name = "Head"
	look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	look.primary_rotation_axis = Vector3.AXIS_Y
	look.use_angle_limitation = true
	look.primary_limit_angle = deg_to_rad(130.0)
	look.secondary_limit_angle = deg_to_rad(60.0)
	look.duration = 0.5
	look.transition_type = Tween.TRANS_SINE
	skel.add_child(look)
	look.target_node = look.get_path_to(_look_target)
	_look = look


func _play(clip: String) -> void:
	if anim == null:
		return
	var style: Dictionary = model.get_meta("style", {})
	clip = style.get("clips", {}).get(clip, clip)
	if not anim.has_animation(clip) or clip == _clip:
		return
	_clip = clip
	anim.play(clip, 0.3)
	anim.speed_scale = float(style.get("speed", 1.0))


func say_gesture() -> void:
	_play("Idle_Talking")


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	_marker.text = "" if talking else game.quests.marker_for(id)
	for pl in _plates:
		(pl as Label3D).visible = not talking
	_marker.position.y = _height + 0.75 + sin(t * 2.4) * 0.06
	var to: Vector3 = game.player.global_position - global_position
	to.y = 0.0
	var near := to.length() < 6.0
	if _look:
		_look_target.global_position = game.player.global_position + Vector3(0, 1.35, 0)
		_look.influence = move_toward(_look.influence, 1.0 if (near or talking) else 0.0, delta * 2.0)
	# Strolling: walk the route unless talking or the heroine is close.
	if not route.is_empty() and not talking and to.length() > 3.5:
		if _pause > 0.0:
			_pause -= delta
		else:
			var goal: Vector2 = route[_leg]
			var here := Vector2(global_position.x, global_position.z)
			var step := goal - here
			if step.length() < 0.25:
				_leg = (_leg + 1) % route.size()
				_pause = randf_range(4.0, 8.0)
			else:
				here += step.normalized() * minf(step.length(), WALK_SPEED * delta)
				global_position = Vector3(here.x, game.world.height_at(here.x, here.y), here.y)
				home_yaw = atan2(step.x, step.y)
				model.rotation.y = lerp_angle(model.rotation.y, home_yaw, minf(1.0, delta * 6.0))
				_play("Walk")
				return
	if talking:
		_play("Idle_Talking")
	elif not routine.is_empty():
		_time += delta
		var step: Array = routine[_step % routine.size()]
		# Kneeling work and the like stop when someone comes to chat.
		if near and step[0] in ["Fixing_Kneeling", "PickUp_Table", "Interact"]:
			_play("Idle")
		else:
			_play(step[0])
		if _time > float(step[1]):
			_time = 0.0
			_step += 1
	# Turn to the heroine when she is close, back to their post otherwise.
	var want := home_yaw
	if near or talking:
		want = atan2(to.x, to.z)
	model.rotation.y = lerp_angle(model.rotation.y, want, minf(1.0, delta * 4.0))


## The heroine is close enough to talk.
func in_reach() -> bool:
	return game.player.global_position.distance_to(global_position) < 2.6
