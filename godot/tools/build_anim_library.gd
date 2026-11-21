extends SceneTree
## Extracts the clips the game plays from Quaternius' Universal Animation
## Library 1 and 2 (CC0) into one AnimationLibrary resource that every
## humanoid character shares (they all use the same 65-bone skeleton):
##   godot --headless --path . -s res://tools/build_anim_library.gd
## The library GLBs themselves need not ship.
## Copy UAL1_Standard.glb and UAL2_Standard.glb into assets/models/quaternius/anim/ to rebuild.
const SOURCES := ["res://assets/models/quaternius/anim/UAL1_Standard.glb", "res://assets/models/quaternius/anim/UAL2_Standard.glb"]
const KEEP := ["Idle_No", "Sword_Dash", "Sword_Regular_Combo", "NinjaJump_Start", "NinjaJump_Idle", "NinjaJump_Land", "Slide", "Dance", "Spell_Simple_Idle", "Idle", "Idle_Talking", "Idle_Torch", "Idle_Lantern", "Idle_FoldArms", "Walk", "Walk_Formal", "Jog_Fwd",
	"Sprint", "Jump", "Jump_Start", "Jump_Land", "Roll", "Hit_Chest", "Hit_Head", "Hit_Knockback", "Death01",
	"Interact", "PickUp_Table", "Chest_Open", "Consume", "Fixing_Kneeling", "Spell_Simple_Shoot", "OverhandThrow",
	"Swim_Fwd", "Swim_Idle", "Sword_Idle", "Sword_Attack", "Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C",
	"Sword_Heavy_Combo", "Sword_Block", "Idle_Shield", "Shield_OneShot", "TreeChopping", "Yes", "Zombie_Idle",
	"Zombie_Walk_Fwd", "Zombie_Scratch", "LayToIdle", "Melee_Hook", "Punch_Jab", "ClimbUp_1m"]

func _initialize() -> void:
	# Optional: "-- <output.res> <source.glb>..." builds a library from other
	# sources (e.g. the UAL files imported with humanoid retargeting).
	var args := OS.get_cmdline_user_args()
	var output := "res://assets/models/quaternius/anim/humanoid_anims.res"
	var sources: Array = SOURCES
	if args.size() >= 2:
		output = args[0]
		sources = args.slice(1)
	var library := AnimationLibrary.new()
	for source in sources:
		var scene: Node = load(source).instantiate()
		var player: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
		for name in player.get_animation_list():
			if name in KEEP and not library.has_animation(name):
				var clip: Animation = player.get_animation(name).duplicate(true)
				# Drop the root bone's motion: the game moves the body itself.
				for t in range(clip.get_track_count() - 1, -1, -1):
					if String(clip.track_get_path(t)).ends_with(":root") or String(clip.track_get_path(t)).ends_with(":Root"):
						clip.remove_track(t)
				clip.compress()
				library.add_animation(name, clip)
		scene.free()
	var missing := []
	for name in KEEP:
		if not library.has_animation(name):
			missing.append(name)
	print("kept ", library.get_animation_list().size(), " missing ", missing)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	ResourceSaver.save(library, output, ResourceSaver.FLAG_COMPRESS)
	quit()
