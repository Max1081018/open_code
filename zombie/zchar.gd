extends Node3D
## A skinned character with a state machine driving it.
##
## One of these sits inside every zombie (and later every animal and survivor):
## it owns the model, the AnimationTree, and the look of that particular
## individual. The AI above it never touches an animation by name - it sets a
## speed and asks for an action, and this decides what plays and how it blends.
##
## Locomotion is a 1D blend space on ground speed rather than four separate
## clips, so a zombie that speeds up from a shamble to a run slides between
## them instead of popping. Everything else - swinging, being shot, falling
## over, crawling, getting back up - is a state in a machine with proper
## transitions, and one-shots return to locomotion on their own at the end of
## the clip.
##
## Every zombie also gets its own look: skin tone, shirt, trousers and build
## are rolled per individual from the one model, so a street full of them
## doesn't read as a street full of clones.

const MODEL := "res://assets/chars/AtlasZombieLite_Walker.fbx"
const LIB := "res://assets/chars/zombie_anims.res"

# Ground speed each locomotion clip is authored for (m/s).
const SPEED_WALK := 1.15
const SPEED_RUN := 2.9
const SPEED_CHASE := 5.0

# Skin, shirt, trousers and shoes, rolled per zombie. The model paints each of
# those in its own material, so a variant is a recolour, not a new mesh.
const SKINS := [Color(0.63, 0.72, 0.52), Color(0.55, 0.66, 0.50), Color(0.72, 0.74, 0.58),
	Color(0.47, 0.57, 0.45), Color(0.68, 0.64, 0.52)]
const SHIRTS := [Color(0.62, 0.33, 0.28), Color(0.30, 0.36, 0.44), Color(0.42, 0.44, 0.33),
	Color(0.55, 0.50, 0.38), Color(0.33, 0.30, 0.32), Color(0.58, 0.45, 0.25),
	Color(0.25, 0.40, 0.36), Color(0.48, 0.24, 0.24)]
const PANTS := [Color(0.33, 0.38, 0.48), Color(0.28, 0.28, 0.31), Color(0.42, 0.37, 0.28),
	Color(0.24, 0.30, 0.36), Color(0.38, 0.33, 0.30)]
const SHOES := [Color(0.26, 0.20, 0.15), Color(0.18, 0.17, 0.17), Color(0.33, 0.26, 0.18)]
const HAIRS := [Color(0.18, 0.15, 0.13), Color(0.31, 0.26, 0.20), Color(0.42, 0.38, 0.34),
	Color(0.24, 0.19, 0.17), Color(0.50, 0.44, 0.33)]
# The survivor you play is the same model, in better health.
const HUMAN_SKINS := [Color(0.80, 0.63, 0.49), Color(0.68, 0.50, 0.37), Color(0.88, 0.73, 0.60),
	Color(0.50, 0.36, 0.27), Color(0.76, 0.58, 0.44)]

var speed := 0.0                  # ground speed, drives the locomotion blend
var crawling := false
var dead := false

var _model: Node3D
var _skel: Skeleton3D
var _ap: AnimationPlayer
var _tree: AnimationTree
var _pb: AnimationNodeStateMachinePlayback
var _busy := 0.0                  # seconds left of a one-shot
var _mats: Array[StandardMaterial3D] = []
var _flash := 0.0
var _tint := Color(1, 1, 1)
var _blend := 0.0


func _ready() -> void:
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.add_animation_library("z", load(LIB))
	_build_tree()


## The state machine. Built in code so every character shares one definition
## and there is no scene to keep in step with the script.
func _build_tree() -> void:
	var sm := AnimationNodeStateMachine.new()

	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = SPEED_CHASE
	move.add_blend_point(_clip("idle"), 0.0)
	move.add_blend_point(_clip("walk"), SPEED_WALK)
	move.add_blend_point(_clip("run"), SPEED_RUN)
	move.add_blend_point(_clip("chase"), SPEED_CHASE)
	sm.add_node("move", move, Vector2(200, 0))

	var crawl := AnimationNodeBlendSpace1D.new()
	crawl.min_space = 0.0
	crawl.max_space = 1.0
	crawl.add_blend_point(_clip("crawl_idle"), 0.0)
	crawl.add_blend_point(_clip("crawl"), 1.0)
	sm.add_node("crawl", crawl, Vector2(200, 160))

	var row := 0
	for one in ["attack", "bite", "hit", "stagger", "death", "getup", "feed", "reach"]:
		sm.add_node(one, _clip(one), Vector2(440, 60 * row))
		row += 1

	# Auto, or a character sits on the state machine's Start node until
	# something else happens to move it on.
	sm.add_transition("Start", "move", _link(0.0, false, true))
	# Into an action from wherever you are, and back out when the clip ends.
	for one in ["attack", "bite", "hit", "stagger", "feed", "reach"]:
		sm.add_transition("move", one, _link(0.10, false))
		sm.add_transition(one, "move", _link(0.14, true, true))
	sm.add_transition("crawl", "bite", _link(0.10, false))
	sm.add_transition("bite", "crawl", _link(0.14, false))
	# Falling over and getting back up.
	sm.add_transition("move", "crawl", _link(0.25, false))
	sm.add_transition("crawl", "getup", _link(0.12, false))
	sm.add_transition("getup", "move", _link(0.18, true, true))
	# Dying is one way.
	for from in ["move", "crawl", "attack", "bite", "hit", "stagger", "getup"]:
		sm.add_transition(from, "death", _link(0.08, false))

	_tree = AnimationTree.new()
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_ap)
	_tree.tree_root = sm
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_tree.active = true
	_pb = _tree.get("parameters/playback")


func _clip(name: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = "z/" + name
	return n


func _link(xfade: float, at_end: bool, auto := false) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END if at_end \
		else AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO if auto \
		else AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	return t


## Called every frame the character is close enough to be worth animating.
func tick(delta: float) -> void:
	if _tree == null:
		return
	_busy = maxf(_busy - delta, 0.0)
	# Ease the blend so a sudden change of pace doesn't snap the legs.
	_blend = lerpf(_blend, speed, clampf(delta * 6.0, 0.0, 1.0))
	if crawling:
		_tree.set("parameters/crawl/blend_position", clampf(speed / SPEED_WALK, 0.0, 1.0))
	else:
		_tree.set("parameters/move/blend_position", _blend)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		_apply_flash()


## Play a one-shot. Returns false if the character is dead or still mid-action.
func act(what: String, force := false) -> bool:
	if dead or _pb == null:
		return false
	if _busy > 0.0 and not force:
		return false
	_pb.travel(what)
	_busy = _length(what) * 0.92
	return true


func busy() -> bool:
	return _busy > 0.0


func go_down() -> void:
	if dead or crawling:
		return
	crawling = true
	_pb.travel("crawl")


func get_up() -> void:
	if dead or not crawling:
		return
	crawling = false
	_pb.travel("getup")
	_busy = _length("getup") * 0.9


func die() -> void:
	if dead:
		return
	dead = true
	_pb.travel("death")
	_busy = _length("death")


func _length(what: String) -> float:
	var n := "z/" + what
	return _ap.get_animation(n).length if _ap.has_animation(n) else 0.5


## Shot or hit: a quick white flash over the whole body.
func flash() -> void:
	_flash = 1.0
	_apply_flash()


func _apply_flash() -> void:
	for m in _mats:
		m.emission_enabled = _flash > 0.01
		m.emission = Color(1, 0.75, 0.7)
		m.emission_energy_multiplier = _flash * 0.9


## Rolls this individual's build and clothes.
##
## The model paints each part of the body with its own named material - skin,
## shirt, pants, boots, hair, eyes, wound - so a variant is a recolour of the
## one mesh. Matching on those names rather than on the colours themselves
## means a dark shirt is never mistaken for a boot.
func randomize_look(rng: RandomNumberGenerator, human := false) -> void:
	var pick := func(list: Array) -> Color:
		return list[rng.randi() % list.size()]
	var skin: Color = pick.call(HUMAN_SKINS if human else SKINS)
	var shirt: Color = pick.call(SHIRTS)
	var pants: Color = pick.call(PANTS)
	var shoe: Color = pick.call(SHOES)
	var hair: Color = pick.call(HAIRS)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		if m3.mesh == null:
			continue
		for si in m3.mesh.get_surface_count():
			var src := m3.mesh.surface_get_material(si) as BaseMaterial3D
			var mat := (src.duplicate() if src else StandardMaterial3D.new()) as StandardMaterial3D
			var who := str(src.resource_name) if src else ""
			if "Skin" in who:
				mat.albedo_color = skin
			elif "Shirt" in who:
				mat.albedo_color = shirt
			elif "Pants" in who:
				mat.albedo_color = pants
			elif "Boots" in who:
				mat.albedo_color = shoe
			elif "Hair" in who:
				mat.albedo_color = hair
			elif "Wound" in who:
				# healthy people are not walking about with these on show
				mat.albedo_color = skin.darkened(0.12) if human else \
					Color(0.52, 0.17, 0.16).lerp(Color(0.33, 0.10, 0.12), rng.randf())
			elif "Eyes" in who and not human:
				mat.albedo_color = Color(0.86, 0.84, 0.62).lerp(Color(0.74, 0.78, 0.52), rng.randf())
			mat.roughness = 0.95
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m3.set_surface_override_material(si, mat)
			_mats.append(mat)
		m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Build: these are heavy, blocky things, and no two are quite the same.
	if human:
		return
	var wide: float = rng.randf_range(1.10, 1.26)
	var tall: float = rng.randf_range(0.94, 1.06)
	_model.scale = Vector3(wide, tall, wide * rng.randf_range(0.92, 1.0))


## How tall this one ended up, for colliders and head shots.
func height() -> float:
	return 1.64 * _model.scale.y if _model else 1.64
