extends SceneTree
## Builds a character's own AnimationLibrary: the shared humanoid clips with
## named ones replaced by real motion from retargeted animation sources
## (assets/models/sf_src/motion, not shipped). The game asks for the same
## clip names (Idle, Walk, Jog_Fwd, Sword_Regular_A...), so the heroine moves
## like herself with no game-code changes.
##   godot --headless --path . -s res://tools/build_hero_library.gd

const BASE := "res://assets/models/heroes/anim/humanoid.res"
const OUT := "res://assets/models/heroes/anim/heroine.res"
const SRC := "res://assets/models/sf_src/motion/"

## game clip name -> [source file, source clip, loops]
const MAP := {
	"Idle": ["fantasygirl", "sold_fem|idle_noweapon02", true],
	"Idle_Talking": ["lowpolygirl", "cycle_talking", true],
	"Idle_FoldArms": ["fantasygirl", "sold_fem|idle_noweapon04", false],
	"Yes": ["fantasygirl", "sold_fem|idle_noweapon03", false],
	"Idle_No": ["fantasygirl", "sold_fem|idle_noweapon05", false],
	"Idle_Rest": ["fantasygirl", "sold_fem|female_resting_01", false],
	"Walk": ["fantasygirl", "sold_fem|Walk_no_weapon", true],
	"Walk_Formal": ["fantasygirl", "sold_fem|Walk_no_weapon", true],
	"Jog_Fwd": ["fantasygirl", "sold_fem|Run-no-Weapon", true],
	"Sprint": ["fantasygirl", "sold_fem|Run_base", true],
	"Sword_Idle": ["fantasygirl", "sold_fem|BattleMode_generic", true],
	"Sword_Regular_A": ["fantasygirl", "sold_fem|Attack_saber01", false],
	"Sword_Regular_B": ["fantasygirl", "sold_fem|Attack_sword_destroyer01", false],
	"Sword_Regular_C": ["fantasygirl", "sold_fem|Attack_sword_destroyer02", false],
	"Sword_Heavy_Combo": ["fantasygirl", "sold_fem|Attack_claymore", false],
	"Sword_Attack": ["fantasygirl", "sold_fem|Attack_jump", false],
	"Roll": ["fantasygirl", "sold_fem|dash_start", false],
	"Sword_Dash": ["fantasygirl", "sold_fem|dash_cons", false],
	"Jump_Start": ["fantasygirl", "sold_fem|jump-2d-start", false],
	"Jump": ["fantasygirl", "sold_fem|Midle_air", true],
	"Jump_Land": ["lowpolygirl", "jump_end", false],
	"Hit_Chest": ["fantasygirl", "sold_fem|Damage_01", false],
	"Hit_Head": ["fantasygirl", "sold_fem|Damage_02", false],
	"Death01": ["fantasygirl", "sold_fem|Dead_generic_weapon01", false],
	"TreeChopping": ["fantasygirl", "sold_fem|Attack_axe_spike_hamer01", false],
	"PickUp_Table": ["lowpolygirl", "inspect_ground", false],
	"Interact": ["lowpolygirl", "action_button_click", false],
	"ClimbUp_1m": ["lowpolygirl", "climb_high", false],
}


func _initialize() -> void:
	var base: AnimationLibrary = load(BASE)
	var lib := AnimationLibrary.new()
	for name in base.get_animation_list():
		lib.add_animation(name, base.get_animation(name))
	var players := {}
	var replaced := 0
	for name in MAP:
		var spec: Array = MAP[name]
		if not players.has(spec[0]):
			var scene: Node = load(SRC + spec[0] + ".glb").instantiate()
			players[spec[0]] = [scene, scene.find_children("*", "AnimationPlayer", true, false)[0]]
		var ap: AnimationPlayer = players[spec[0]][1]
		if not ap.has_animation(spec[1]):
			print("missing ", spec)
			continue
		var clip: Animation = ap.get_animation(spec[1]).duplicate(true)
		# Keep only the humanoid skeleton's tracks; drop root/controller motion
		# (the game moves the body) and the Hips' travel in X/Z.
		for t in range(clip.get_track_count() - 1, -1, -1):
			var path := String(clip.track_get_path(t))
			if not path.begins_with("%GeneralSkeleton:") or path.ends_with(":Root"):
				clip.remove_track(t)
				continue
			if path.ends_with(":Hips") and clip.track_get_type(t) == Animation.TYPE_POSITION_3D:
				for k in clip.track_get_key_count(t):
					var v: Vector3 = clip.track_get_key_value(t, k)
					clip.track_set_key_value(t, k, Vector3(0.0, v.y, 0.0) if not spec[2] else Vector3(0.0, v.y, 0.0))
		clip.loop_mode = Animation.LOOP_LINEAR if spec[2] else Animation.LOOP_NONE
		if lib.has_animation(name):
			lib.remove_animation(name)
		lib.add_animation(name, clip)
		replaced += 1
	for k in players:
		players[k][0].free()
	ResourceSaver.save(lib, OUT, ResourceSaver.FLAG_COMPRESS)
	print("heroine library: ", lib.get_animation_list().size(), " clips, ", replaced, " real female clips")
	quit()
