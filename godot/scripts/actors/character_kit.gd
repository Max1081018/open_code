class_name CharacterKit
extends RefCounted
## Builds the cast from Quaternius' Universal Base Characters, Modular
## Character Outfits (Fantasy) and Universal Animation Library (all CC0).
##
## Every humanoid shares one 65-bone skeleton, so a character is a base body
## (face, eyes, skin) with outfit parts and hair moved onto its skeleton, a
## few texture variants and tints, and the one shared animation library.
## Recipes below are the art direction: each person reads differently in
## silhouette (hood, beard, buns, pauldrons, long hair) as well as colour.

const Q := "res://assets/models/quaternius/"
const ANIMS := Q + "anim/humanoid_anims.res"

## name -> recipe
const RECIPES := {
	# The wanderer: hooded ranger, pauldron and bracers, a cloak gone the
	# colour of dusk. Only the lower face shows under the hood.
	"player": {"body": "male", "outfit": "Male_Ranger", "hair": ["Eyebrows_Regular"],
		"textures": {"MI_Ranger": "variants/ranger_dusk.png"}},
	# Wren, the keeper's apprentice: young, quick, lavender wool, hair up.
	"wren": {"body": "female", "outfit": "Female_Peasant", "hair": ["Hair_Buns", "Eyebrows_Female"],
		"hair_tint": Color(0.22, 0.14, 0.1), "textures": {"MI_Peasant": "variants/peasant_lavender.png"}},
	# Old Bram, the miner: big, grey-bearded, in dark work clothes.
	"bram": {"body": "male", "outfit": "Male_Peasant", "hair": ["Hair_Buzzed", "Hair_Beard", "Eyebrows_Regular"],
		"hair_tint": Color(0.78, 0.76, 0.74), "textures": {"MI_Peasant": "outfits/T_Peasant_2_BaseColor.png"}},
	# Mira, the herbalist: a ranger's coat, no hood, long auburn hair.
	"mira": {"body": "female", "parts": ["Female_Ranger_Arms", "Female_Ranger_Body", "Female_Ranger_Feet",
		"Female_Ranger_Legs"], "hair": ["Hair_Long", "Eyebrows_Female"], "hair_tint": Color(0.55, 0.22, 0.12),
		"textures": {"MI_Ranger": "outfits/T_Ranger_3_BaseColor.png"}},
	# Tobin, the travelling smith: ginger beard, parted hair, leathers.
	"tobin": {"body": "male", "outfit": "Male_Peasant", "hair": ["Hair_SimpleParted", "Hair_Beard",
		"Eyebrows_Regular"], "hair_tint": Color(0.72, 0.32, 0.12)},
	# Sir Aldous, last of the Lightwardens: steel, a pauldron, grey hair.
	"aldous": {"body": "male", "parts": ["Male_Ranger_Arms", "Male_Ranger_Body", "Male_Ranger_Feet_Boots",
		"Male_Ranger_Legs", "Male_Ranger_Acc_Pauldron"], "hair": ["Hair_Long", "Hair_Beard",
		"Eyebrows_Regular"], "hair_tint": Color(0.62, 0.6, 0.58), "textures": {"MI_Ranger": "variants/ranger_steel.png"}},
	# The risen dead: the people they were, ash-grey, in rags, eyes alight.
	"zombie": {"body": "male", "outfit": "Male_Peasant", "hair": ["Hair_Buzzed"], "hair_tint": Color(0.3, 0.3, 0.28),
		"textures": {"MI_Superhero_Male": "variants/skin_ash_male.png", "MI_Peasant": "variants/peasant_rags.png"},
		"eyes": Color(0.6, 1.0, 0.7), "undead": true},
	"robot": {"body": "male", "parts": ["Male_Ranger_Arms", "Male_Ranger_Body", "Male_Ranger_Feet_Boots",
		"Male_Ranger_Legs", "Male_Ranger_Acc_Pauldron"], "textures": {"MI_Superhero_Male": "variants/skin_ash_male.png",
		"MI_Ranger": "variants/ranger_rust.png"}, "eyes": Color(1.0, 0.5, 0.3), "undead": true},
	"shade": {"body": "female", "outfit": "Female_Peasant", "hair": ["Hair_Long"], "hair_tint": Color(0.12, 0.1, 0.14),
		"textures": {"MI_Superhero_Female": "variants/skin_ash_female.png", "MI_Peasant": "variants/peasant_gloam.png"},
		"eyes": Color(0.75, 0.55, 1.0), "undead": true},
	# The Rusted Warden: a giant in rusted Lightwarden plate, hood up.
	"warden": {"body": "male", "outfit": "Male_Ranger", "textures": {"MI_Superhero_Male": "variants/skin_ash_male.png",
		"MI_Ranger": "variants/ranger_rust.png"}, "eyes": Color(1.0, 0.35, 0.2), "undead": true},
	# The Gloam: what the dark made of a Lightwarden: violet rags, long hair.
	"gloam": {"body": "female", "parts": ["Female_Ranger_Arms", "Female_Ranger_Body", "Female_Ranger_Feet",
		"Female_Ranger_Legs", "Female_Ranger_Head_Hood", "Female_Ranger_Acc_Pauldrons"],
		"textures": {"MI_Superhero_Female": "variants/skin_ash_female.png", "MI_Ranger": "variants/peasant_gloam.png"},
		"eyes": Color(0.8, 0.5, 1.0), "undead": true},
}

## The downloaded cast (Sketchfab, CC-BY; see ASSET_CATALOG.md), packed by
## tools/pack_characters.gd onto one retargeted humanoid rig and driven by
## one shared animation library. name -> [packed scene, tint or null].
const HEROES := {
	"player": ["player", null],          # hooded assassin: hood, leathers, cloak
	"wren": ["wren", null],
	"mira": ["mira", null],
	"bram": ["bram", null],
	"tobin": ["tobin", null],
	"aldous": ["aldous", null],          # bearded knight in blue plate
	"zombie": ["skeleton", Color(0.6, 0.56, 0.7)],     # the Risen: ashen, violet-cold bone
	"shade": ["skeleton", Color(0.62, 0.5, 0.85)],
	"robot": ["knight", Color(0.8, 0.62, 0.5)],  # rust-eaten plate
	"warden": ["warden", null],          # the cursed knight
	# Zone foes on the same rigs, in their region's colours.
	"thornling": ["skeleton", Color(0.55, 0.78, 0.5)],   # Gloomwood
	"wisp_caller": ["skeleton", Color(0.45, 0.85, 0.82)],
	"frost_knight": ["knight", Color(0.7, 0.85, 1.05)],   # Frostpeaks
	"rime_shade": ["skeleton", Color(0.75, 0.88, 1.1)],
	"dune_raider": ["knight", Color(1.05, 0.86, 0.6)],    # Sunscar
	"sand_thrower": ["skeleton", Color(1.0, 0.85, 0.62)],
	"cinder_knight": ["knight", Color(0.75, 0.4, 0.32)],  # Ashlands
	"ember_caller": ["skeleton", Color(1.0, 0.6, 0.42)],
	"void_shade": ["skeleton", Color(0.58, 0.42, 0.9)],   # Blight
	"void_caller": ["skeleton", Color(0.7, 0.45, 1.0)],
	# The starting islands' guardians.
	"thornmother": ["knight", null],     # Great Jungle (costumed: HERO_STYLE)
	"stormwing": ["skeleton", Color(0.78, 0.92, 1.2)],   # Skybound Isle
	"tidewarden": ["knight", null],      # Crystal Coast (costumed: HERO_STYLE)
	# The islands' own creatures.
	"vine_stalker": ["skeleton", Color(0.42, 0.7, 0.32)],
	"root_guardian": ["knight", Color(0.62, 0.72, 0.42)],
	"gale_sprite": ["skeleton", Color(0.85, 0.95, 1.2)],
	"aerie_sentinel": ["knight", Color(0.9, 0.95, 1.1)],
	"crystal_husk": ["skeleton", Color(0.55, 0.9, 1.1)],
	"tide_caller": ["skeleton", Color(0.4, 0.7, 1.05)],
	"coral_knight": ["knight", Color(0.95, 0.62, 0.6)],
}
## Per-character presence: height in metres and their own way of moving
## (clip overrides on the shared library, playback speed). Anime heroines
## are small and light on their feet; knights heavy; the dead shamble.
const HERO_STYLE := {
	# Her own clips, but the even stride of the shared jog for running; her
	# own bounding run, arms flying, becomes the sprint.
	# Her own idle clutches her hands at her chest; the shared relaxed idle
	# (arms easy at her sides, weight settled) reads far more natural.
	"player": {"height": 1.56, "library": "anim/heroine.res", "speed": 1.0, "clips": {"Jog_Fwd": "ual/Jog_Fwd", "Idle": "ual/Idle", "Idle_Own": "Idle"}, "add_hands": true,
		# No wings: their root bones collapse to nothing (the rest follows).
		"hide_bones": ["Wing02_"]},
	"wren": {"height": 1.6, "clips": {"Idle": "Idle_Talking"}, "speed": 1.05},
	# Mira's model is all pastel white; dye it a herbalist's sage coat and
	# deeper rose hair so she reads at a distance (tints by texture file).
	"mira": {"height": 1.58, "clips": {"Walk": "Walk_Formal"}, "speed": 1.0,
		"tex_tints": {"albedo_3": Color(0.58, 0.74, 0.58), "albedo_2": Color(0.9, 0.6, 0.74)}},
	"tobin": {"height": 1.72, "clips": {"Idle": "Idle_FoldArms"}, "speed": 0.95, "turn": PI},
	"aldous": {"height": 1.64, "clips": {"Idle": "Sword_Idle"}, "speed": 1.0},
	"warden": {"height": 2.0, "speed": 0.85},
	"robot": {"height": 1.85, "speed": 0.9},
	"zombie": {"height": 1.8, "speed": 0.9},
	"shade": {"height": 1.75, "speed": 1.15},
	"thornling": {"height": 1.55, "speed": 1.3},
	"wisp_caller": {"height": 1.75, "speed": 1.0},
	"frost_knight": {"height": 2.05, "speed": 0.8},
	"rime_shade": {"height": 1.75, "speed": 1.1},
	"dune_raider": {"height": 1.85, "speed": 1.1},
	"sand_thrower": {"height": 1.7, "speed": 1.0},
	"cinder_knight": {"height": 2.1, "speed": 0.8},
	# Guardians are costumed part by part (one tint over everything turned
	# the Thornmother into a lime mannequin): weathered bark-bronze plate
	# over moss cloth; the Tidewarden in steel-blue plate over sea teal.
	"thornmother": {"height": 2.0, "speed": 0.85, "tex_tints": {
		"albedo_0": Color(0.58, 0.52, 0.38), "albedo_30": Color(0.52, 0.47, 0.33),
		"albedo_15": Color(0.46, 0.5, 0.38), "albedo_18": Color(0.4, 0.6, 0.3),
		"albedo_33": Color(0.38, 0.54, 0.28), "albedo_36": Color(0.34, 0.42, 0.24),
		"albedo_3": Color(0.55, 0.42, 0.3), "albedo_27": Color(0.5, 0.4, 0.3), "albedo_12": Color(0.45, 0.36, 0.27)}},
	"stormwing": {"height": 1.8, "speed": 1.1},
	"tidewarden": {"height": 2.05, "speed": 0.8, "tex_tints": {
		"albedo_0": Color(0.48, 0.6, 0.76), "albedo_30": Color(0.46, 0.58, 0.74),
		"albedo_15": Color(0.46, 0.56, 0.68), "albedo_18": Color(0.28, 0.55, 0.62),
		"albedo_33": Color(0.3, 0.55, 0.62), "albedo_36": Color(0.24, 0.36, 0.5),
		"albedo_3": Color(0.44, 0.44, 0.5), "albedo_27": Color(0.42, 0.42, 0.48), "albedo_12": Color(0.38, 0.38, 0.44)}},
	"vine_stalker": {"height": 1.6, "speed": 1.35},
	"root_guardian": {"height": 2.0, "speed": 0.8},
	"gale_sprite": {"height": 1.5, "speed": 1.2},
	"aerie_sentinel": {"height": 2.0, "speed": 0.85},
	"crystal_husk": {"height": 1.65, "speed": 1.25},
	"tide_caller": {"height": 1.75, "speed": 1.0},
	"coral_knight": {"height": 2.0, "speed": 0.85},
	"ember_caller": {"height": 1.75, "speed": 1.0},
	"void_shade": {"height": 1.8, "speed": 1.25},
	"void_caller": {"height": 1.8, "speed": 1.0},
}
const HERO_DIR := "res://assets/models/heroes/"
const HERO_ANIMS := HERO_DIR + "anim/humanoid.res"
static var _hero_library: AnimationLibrary

const BODIES := {"male": "bodies/Superhero_Male_FullBody.gltf", "female": "bodies/Superhero_Female_FullBody.gltf"}

## Metres the clothing is pushed out over the body.
const OUTFIT_GROW := 0.022

static var _library: AnimationLibrary


## Add a pose modifier (sitting, floating) so it runs BEFORE the soft-bone
## simulator: the skirt, hair and tails then collide with the legs where the
## pose puts them, not where the animation had them.
static func add_pose_modifier(skeleton: Skeleton3D, modifier: SkeletonModifier3D) -> void:
	skeleton.add_child(modifier)
	for after in ["SkirtSolver", "SoftBones"]:
		var n := skeleton.get_node_or_null(after)
		if n:
			skeleton.move_child(modifier, n.get_index())
			return


static func has(name: String) -> bool:
	return RECIPES.has(name) or HEROES.has(name)


static func library() -> AnimationLibrary:
	if _library == null:
		_library = load(ANIMS)
	return _library


## A ready character: Node3D root with Armature/Skeleton3D and an
## AnimationPlayer holding the shared clips.
static func build(name: String) -> Node3D:
	if HEROES.has(name) and ResourceLoader.exists(HERO_DIR + String(HEROES[name][0]) + ".scn"):
		return _build_hero(name)
	var recipe: Dictionary = RECIPES[name]
	var root: Node3D = load(Q + BODIES[recipe.body]).instantiate()
	root.name = name
	var skeleton: Skeleton3D = root.get_node("Armature/Skeleton3D")
	var parts: Array = []
	if recipe.has("outfit"):
		parts.append("outfits/%s.gltf" % recipe.outfit)
	for part in recipe.get("parts", []):
		parts.append("outfits/%s.gltf" % part)
	for hair in recipe.get("hair", []):
		parts.append("hair/%s.gltf" % hair)
	# The base body's own eyebrows give way to the recipe's.
	if recipe.get("hair", []).any(func(h): return String(h).begins_with("Eyebrows")):
		var brows := skeleton.get_node_or_null("Eyebrows")
		if brows:
			brows.queue_free()
	for path in parts:
		var scene: Node = load(Q + path).instantiate()
		for mesh in scene.find_children("*", "MeshInstance3D", true, false):
			mesh.owner = null
			mesh.get_parent().remove_child(mesh)
			skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
			if path.begins_with("hair/") and recipe.has("hair_tint"):
				_tint(mesh, recipe.hair_tint)
		scene.free()
	for mesh in skeleton.find_children("*", "MeshInstance3D", true, false):
		_dress(mesh, recipe)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.add_animation_library("", library())
	return root


## Texture variants by material name, glowing eyes for the dead, and a
## gentler, less plastic finish on everything.
static func _dress(mesh: MeshInstance3D, recipe: Dictionary) -> void:
	var textures: Dictionary = recipe.get("textures", {})
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(i) as BaseMaterial3D
		if material == null:
			continue
		var copy: BaseMaterial3D = material.duplicate()
		var key := String(material.resource_name)
		if textures.has(key):
			copy.albedo_texture = load(Q + String(textures[key]))
		if key == "MI_Eyes" and recipe.has("eyes"):
			copy.emission_enabled = true
			copy.emission = recipe.eyes
			copy.emission_energy_multiplier = 2.2
		copy.metallic_specular = 0.35
		# Outfits were cut for a slimmer body than the base one: grown a
		# little along their normals they cover it instead of being pierced.
		if key in ["MI_Ranger", "MI_Peasant"]:
			copy.grow = true
			copy.grow_amount = OUTFIT_GROW
		mesh.set_surface_override_material(i, copy)


static func _tint(mesh: MeshInstance3D, colour: Color) -> void:
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(i) as BaseMaterial3D
		if material:
			var copy: BaseMaterial3D = material.duplicate()
			copy.albedo_color = colour
			mesh.set_surface_override_material(i, copy)


## A downloaded character: the packed model, stood 1.8 m tall with its feet
## at the origin, and an AnimationPlayer with the shared retargeted clips.
static func _build_hero(name: String) -> Node3D:
	var spec: Array = HEROES[name]
	var model: Node3D = load(HERO_DIR + String(spec[0]) + ".scn").instantiate()
	var root := Node3D.new()
	root.name = name
	root.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	# Measure head over feet in the root's space (rigs come in metres or
	# centimetres under scaled nodes), then scale and seat the model.
	var to_root := _transform_to(skeleton, root)
	var head := (to_root * skeleton.get_bone_global_rest(skeleton.find_bone("Head"))).origin
	var foot_l := (to_root * skeleton.get_bone_global_rest(skeleton.find_bone("LeftFoot"))).origin
	var foot_r := (to_root * skeleton.get_bone_global_rest(skeleton.find_bone("RightFoot"))).origin
	var floor_y := minf(foot_l.y, foot_r.y)
	var span := maxf(head.y - floor_y, 0.0001)
	# Head bone to crown is about an eighth of a person; ankle to sole ~4 %.
	var k: float = float(HERO_STYLE.get(name, {}).get("height", 1.8)) / (span * 1.17)
	model.scale = Vector3.ONE * k
	model.position = Vector3(0, -(floor_y - span * 0.05) * k, 0)
	# Face +Z like everyone else: some rigs come facing backwards (the
	# toes point the way a body faces).
	var toes := skeleton.find_bone("LeftToes")
	var foot := skeleton.find_bone("LeftFoot")
	if toes >= 0 and foot >= 0:
		var t2r := _transform_to(skeleton, root)
		var ahead := (t2r * skeleton.get_bone_global_rest(toes)).origin - (t2r * skeleton.get_bone_global_rest(foot)).origin
		if ahead.z < -0.01:
			model.rotation.y = PI
	# A rig whose bones were re-aimed on import can still need a half turn.
	model.rotation.y += float(HERO_STYLE.get(name, {}).get("turn", 0.0))
	# Seat by the soles: the lowest point of the skinned meshes in rest
	# pose. (A mesh's own box is in its bind space, which for some rigs is
	# centimetres lying on its back; it says nothing about where feet are.)
	var sole := INF
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		sole = minf(sole, _rest_floor(mesh as MeshInstance3D, root))
	if sole < INF:
		model.position.y -= sole
	# Ankle height above the sole, for runtime foot grounding.
	var foot_y := (_transform_to(skeleton, root) * skeleton.get_bone_global_rest(skeleton.find_bone("LeftFoot"))).origin.y
	root.set_meta("ankle", foot_y)
	root.set_meta("model_y", model.position.y)
	hide_covered_skin(root, float(HERO_STYLE.get(name, {}).get("height", 1.8)))
	_add_leg_collider(root, model, skeleton, float(HERO_STYLE.get(name, {}).get("height", 1.8)))
	for prefix in HERO_STYLE.get(name, {}).get("hide_bones", []):
		for i in skeleton.get_bone_count():
			if skeleton.get_bone_name(i).begins_with(prefix):
				var rest := skeleton.get_bone_rest(i)
				skeleton.set_bone_rest(i, Transform3D(rest.basis.scaled(Vector3.ONE * 0.001), rest.origin))
				skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)
	if spec[1] != null:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			_tint_all(mesh, spec[1])
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = NodePath("../" + String(root.get_path_to(model)))
	if _hero_library == null:
		_hero_library = load(HERO_ANIMS)
	var own: String = HERO_STYLE.get(name, {}).get("library", "")
	if own != "" and ResourceLoader.exists(HERO_DIR + own):
		player.add_animation_library("", load(HERO_DIR + own))
		# The shared library too, as "ual/...", for clips a style borrows.
		player.add_animation_library("ual", _hero_library)
	else:
		player.add_animation_library("", _hero_library)
	root.set_meta("style", HERO_STYLE.get(name, {}))
	var tints: Dictionary = HERO_STYLE.get(name, {}).get("tex_tints", {})
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		_toon(mesh as MeshInstance3D, tints)
	SecondaryMotion.setup(skeleton)
	if bool(HERO_STYLE.get(name, {}).get("add_hands", false)):
		for m in model.find_children("*", "MeshInstance3D", true, false):
			_open_sleeves(m as MeshInstance3D, skeleton, root)
		_add_hands(skeleton)
	# Skirts: solved after the pose, colliding with the legs, every frame.
	var skirt := SkirtSolver.new()
	skirt.name = "SkirtSolver"
	skeleton.add_child(skirt)
	var soft := skeleton.get_node_or_null("SoftBones")
	if soft:
		skeleton.move_child(skirt, soft.get_index())
	return root


## Thighs as capsules that clothing is pushed out of (LegCollider; the
## toon shaders' leg_collide). Radii measured from the skin around them.
static func _add_leg_collider(root: Node3D, model: Node3D, skeleton: Skeleton3D, height: float) -> void:
	var ids := []
	for pair in [["LeftUpperLeg", "LeftLowerLeg"], ["RightUpperLeg", "RightLowerLeg"]]:
		var u := skeleton.find_bone(pair[0])
		var l := skeleton.find_bone(pair[1])
		if u < 0 or l < 0:
			return
		ids.append([u, l])
	var to_root := _transform_to(skeleton, root)
	var a: Vector3 = to_root * skeleton.get_bone_global_rest(ids[0][0]).origin
	var b: Vector3 = to_root * skeleton.get_bone_global_rest(ids[0][1]).origin
	# Thigh radius near the hip and the knee from the skin around the bone.
	var near_hip := []
	var near_knee := []
	var cloth: Array = []
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var base := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var skin := base != null and _looks_like_skin(base.albedo_texture)
		if not skin:
			cloth.append(mi)
			continue
		for si in mi.mesh.get_surface_count():
			for p: Vector3 in _rest_points(mi, si, root)[0]:
				var ab := b - a
				var t: float = (p - a).dot(ab) / ab.length_squared()
				if t < 0.3 or t > 0.92:
					continue
				var d: float = (p - (a + ab * t)).length()
				if d > height * 0.09:
					continue
				(near_hip if t < 0.55 else near_knee).append(d)
	if near_hip.size() < 8 or near_knee.size() < 8 or cloth.is_empty():
		return
	near_hip.sort()
	near_knee.sort()
	var r := Vector2(near_hip[int(near_hip.size() * 0.9)], near_knee[int(near_knee.size() * 0.9)]) + Vector2.ONE * height * 0.004
	for c in cloth:
		_mask_arms(c as MeshInstance3D, skeleton)
	var lc := LegCollider.new()
	lc.name = "LegCollider"
	lc.skeleton = skeleton
	lc.bones = ids
	lc.radius = r
	lc.meshes = cloth
	root.add_child(lc)


## Vertex colour red = how much a clothing vertex may be pushed by the legs:
## 1 - its weight on arm, hand and shoulder bones. Cached per mesh.
static var _masked := {}


static func _mask_arms(mi: MeshInstance3D, skeleton: Skeleton3D) -> void:
	if _masked.has(mi.mesh):
		mi.mesh = _masked[mi.mesh]
		return
	if mi.skin == null or mi.mesh.get_blend_shape_count() > 0:
		return
	var arm_bones := {}
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n.contains("Arm") or n.contains("Hand") or n.contains("Shoulder") or n.contains("Thumb") \
				or n.contains("Index") or n.contains("Middle") or n.contains("Ring") or n.contains("Little"):
			arm_bones[i] = true
	var out := ArrayMesh.new()
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		var per: int = (bones as PackedInt32Array).size() / maxi(verts.size(), 1) if bones != null else 0
		for i in verts.size():
			var arm := 0.0
			for k in per:
				var bind: int = bones[i * per + k]
				var bone := mi.skin.get_bind_bone(bind)
				if bone < 0:
					bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
				if arm_bones.has(bone):
					arm += float(weights[i * per + k])
			var m := clampf(1.0 - arm * 1.5, 0.0, 1.0)
			cols[i] = Color(m, m, m, 1.0)
		arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(arrays))
		out.surface_set_material(si, mi.mesh.surface_get_material(si))
	_masked[mi.mesh] = out
	mi.mesh = out


## The lowest point of a mesh in rest pose, in `root`'s space: skinned
## vertices are carried through their bind pose and the bone's rest (first
## weight only, sampled), so it is right whatever space the mesh data is in.
static func _rest_floor(mesh: MeshInstance3D, root: Node3D) -> float:
	var skel: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if mesh.mesh == null or mesh.skin == null or skel == null:
		return (_transform_to(mesh, root) * mesh.get_aabb()).position.y
	var to_root := _transform_to(skel, root)
	var lowest := INF
	for sfc in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(sfc)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		if verts.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		for i in range(0, verts.size(), maxi(1, verts.size() / 600)):
			var bind := bones[i * per]
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skel.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0:
				continue
			var p := to_root * skel.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind) * verts[i]
			lowest = minf(lowest, p.y)
	return lowest if lowest < INF else (_transform_to(mesh, root) * mesh.get_aabb()).position.y


## Pale pinkish-peach on average: a skin and face atlas.
static func _looks_like_skin(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	img = img.duplicate()
	img.resize(16, 16)
	var sum := Color(0, 0, 0)
	var n := 0
	for y in 16:
		for x in 16:
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.3:
				sum += c
				n += 1
	if n == 0:
		return false
	sum /= n
	return sum.r > 0.6 and sum.r > sum.g * 1.08 and sum.g > sum.b * 0.9 and sum.r - sum.b < 0.35


## Skin hidden under clothing: the body's triangles that some clothing
## covers (lies just outside along the skin's normal) are dropped, so legs
## and arms cannot poke through skirts and sleeves as they move. Faces,
## necks and hands are never touched. Cached per mesh.
static var _culled := {}


static func hide_covered_skin(root: Node3D, height: float) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	var skin: Array = []
	var cloth: Array = []
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var base := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var name := (String(mi.name) + " " + (String(base.resource_name) if base else "")).to_lower()
		if name.contains("eye") or name.contains("hair") or name.contains("lash") or name.contains("brow"):
			continue
		var is_skin := name.contains("body") or name.contains("skin") or (base != null and _looks_like_skin(base.albedo_texture))
		(skin if is_skin else cloth).append(mi)
	if skin.is_empty() or cloth.is_empty():
		return
	var sk_nodes := root.find_children("*", "Skeleton3D", true, false)
	var head_y := INF
	if not sk_nodes.is_empty():
		var sk := sk_nodes[0] as Skeleton3D
		var hb := sk.find_bone("Neck")
		if hb < 0:
			hb = sk.find_bone("Head")
		if hb >= 0:
			head_y = (_transform_to(sk, root) * sk.get_bone_global_rest(hb).origin).y
	var hip_y := -INF
	var knee_y := -INF
	if not sk_nodes.is_empty():
		var sk := sk_nodes[0] as Skeleton3D
		var to_root := _transform_to(sk, root)
		for pair in [["LeftUpperLeg", "LeftLowerLeg"], ["RightUpperLeg", "RightLowerLeg"]]:
			var u := sk.find_bone(pair[0])
			var l := sk.find_bone(pair[1])
			if u >= 0 and l >= 0:
				hip_y = maxf(hip_y, (to_root * sk.get_bone_global_rest(u).origin).y + height * 0.04)
				knee_y = maxf(knee_y, (to_root * sk.get_bone_global_rest(l).origin).y)
	# Only skin under clothing that hugs it is hidden (sleeves, bodice,
	# socks, boots): loose skirts are handled by leg collision instead, so
	# the thighs are never cut.
	var reach := height * 0.05
	# Clothing vertices hashed in a grid of `reach`-sized cells.
	var grid := {}
	for c in cloth:
		var mi := c as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			for w in _rest_points(mi, si, root)[0]:
				var key := Vector3i((w / reach).floor())
				if not grid.has(key):
					grid[key] = PackedVector3Array()
				grid[key].append(w)
	for sm in skin:
		var mi := sm as MeshInstance3D
		if _culled.has(mi.mesh):
			mi.mesh = _culled[mi.mesh]
			continue
		if mi.mesh.get_blend_shape_count() > 0:
			continue  # faces with expressions are left whole
		var out := ArrayMesh.new()
		var dropped := 0
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			var rest := _rest_points(mi, si, root)
			var verts: PackedVector3Array = rest[0]
			var norms: PackedVector3Array = rest[1]
			var covered := PackedByteArray()
			covered.resize(verts.size())
			for i in verts.size():
				var w: Vector3 = verts[i]
				if w.y > head_y - height * 0.02 or norms.is_empty():
					continue
				if w.y < hip_y and w.y > knee_y - height * 0.03:
					continue   # the thighs
				var lim := reach if w.y >= hip_y else reach * 0.6
				var n: Vector3 = norms[i]
				var cell := Vector3i((w / reach).floor())
				var hit := false
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						for dz in range(-1, 2):
							var bucket = grid.get(cell + Vector3i(dx, dy, dz))
							if bucket == null:
								continue
							for cpos in bucket:
								var d: Vector3 = cpos - w
								var len := d.length()
								if len < lim and len > 0.0005 and d.dot(n) > len * 0.35:
									hit = true
									break
							if hit:
								break
						if hit:
							break
					if hit:
						break
				covered[i] = 1 if hit else 0
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(arrays))
			else:
				var keep := PackedInt32Array()
				for k in range(0, idx.size(), 3):
					if covered[idx[k]] and covered[idx[k + 1]] and covered[idx[k + 2]]:
						dropped += 1
						continue
					keep.append(idx[k])
					keep.append(idx[k + 1])
					keep.append(idx[k + 2])
				arrays[Mesh.ARRAY_INDEX] = keep
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(arrays))
			out.surface_set_material(si, mi.mesh.surface_get_material(si))
		_culled[mi.mesh] = out
		mi.mesh = out


## A surface's vertices and normals in `root`'s space in rest pose: each
## carried through its first bone's bind pose and rest (whatever space the
## mesh data is in: some rigs store centimetres lying on their back).
static func _rest_points(mi: MeshInstance3D, si: int, root: Node3D) -> Array:
	var arrays: Array = mi.mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(verts.size())
	out_n.resize(verts.size())
	var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var plain := _transform_to(mi, root)
	if mi.skin == null or skel == null or bones.is_empty():
		for i in verts.size():
			out_v[i] = plain * verts[i]
			out_n[i] = (plain.basis * norms[i]).normalized() if not norms.is_empty() else Vector3.UP
		return [out_v, out_n]
	var to_root := _transform_to(skel, root)
	var per := bones.size() / verts.size()
	var cache := {}
	for i in verts.size():
		var bind := bones[i * per]
		var t: Transform3D
		if cache.has(bind):
			t = cache[bind]
		else:
			var bone := mi.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skel.find_bone(mi.skin.get_bind_name(bind))
			t = to_root * skel.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bind) if bone >= 0 else plain
			cache[bind] = t
		out_v[i] = t * verts[i]
		out_n[i] = (t.basis * norms[i]).normalized() if not norms.is_empty() else Vector3.UP
	return [out_v, out_n]


static var _toon_shader: Shader
static var _line_shader: Shader


## Anime shading on every surface: two-tone light, cool shade, rim light,
## and an ink outline pass (not on eyes, brows, lashes or mouths).
static func _toon(mesh: MeshInstance3D, tints := {}) -> void:
	if _toon_shader == null:
		_toon_shader = load("res://scripts/shaders/toon_character.gdshader")
		_line_shader = load("res://scripts/shaders/toon_outline.gdshader")
	for i in mesh.mesh.get_surface_count():
		var base := mesh.get_active_material(i) as BaseMaterial3D
		if base == null:
			continue
		var name := (String(base.resource_name) + " " + String(mesh.name)).to_lower()
		var m := ShaderMaterial.new()
		m.shader = _toon_shader
		m.set_shader_parameter("albedo_tex", base.albedo_texture)
		var colour := base.albedo_color
		if base.albedo_texture and not tints.is_empty():
			var file := base.albedo_texture.resource_path.get_file().get_basename()
			if tints.has(file):
				colour *= tints[file]
		m.set_shader_parameter("albedo", colour)
		var cut := 0.0
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			cut = 0.5
		m.set_shader_parameter("alpha_cut", cut)
		# Only truly glowing parts glow (many exports switch emission on empty).
		if base.emission_enabled and (base.emission_texture != null or base.emission.get_luminance() * base.emission_energy_multiplier > 0.15):
			m.set_shader_parameter("emission_boost", 0.4)
		var soft_face := false
		for word in ["eye", "brow", "lash", "mouth", "teeth", "tongue", "highlight", "face", "skin", "body"]:
			if name.contains(word):
				soft_face = true
		if not soft_face and _looks_like_skin(base.albedo_texture):
			soft_face = true
		if soft_face:
			# Skin and faces: lit almost flat (anime faces barely shade),
			# warm soft shade, little rim, a touch darker so they never clip.
			m.set_shader_parameter("shade_color", Color(0.95, 0.84, 0.84))
			m.set_shader_parameter("shade_threshold", 0.25)
			m.set_shader_parameter("rim_strength", 0.08)
			m.set_shader_parameter("spec_strength", 0.0)
			m.set_shader_parameter("light_scale", 0.62)
			m.set_shader_parameter("fill", 0.2)
		if name.contains("hair") and not name.contains("shadow"):
			# Anime hair: a cool lilac shade side, a little more of it, and
			# the glossy ring of light across the crown.
			m.set_shader_parameter("shade_color", Color(0.62, 0.54, 0.86))
			m.set_shader_parameter("shade_threshold", 0.56)
			m.set_shader_parameter("rim_strength", 0.22)
			m.set_shader_parameter("hair_ring", 0.22)
			# Pale hair must not clip to white in full sun: a touch darker,
			# a touch cooler, so its strands and lilac still read.
			m.set_shader_parameter("albedo", colour * Color(0.86, 0.84, 0.94))
			m.set_shader_parameter("light_scale", 0.52)
			m.set_shader_parameter("fill", 0.14)
		if name.contains("shadow"):
			# A VRoid-style shade layer (under the fringe): multiplied over.
			var mul := StandardMaterial3D.new()
			mul.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			mul.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mul.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mul.albedo_texture = base.albedo_texture
			mul.albedo_color = Color(1, 1, 1, 0.6)
			mesh.set_surface_override_material(i, mul)
			continue
		var skip_line := false
		for word in ["eye", "brow", "lash", "mouth", "teeth", "tongue", "highlight"]:
			if name.contains(word):
				skip_line = true
		if not skip_line:
			var line := ShaderMaterial.new()
			line.shader = _line_shader
			line.set_shader_parameter("albedo_tex", base.albedo_texture)
			line.set_shader_parameter("alpha_cut", cut)
			m.next_pass = line
		mesh.set_surface_override_material(i, m)


static func _transform_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _tint_all(mesh: MeshInstance3D, colour: Color) -> void:
	for i in mesh.mesh.get_surface_count():
		var material := mesh.get_active_material(i) as BaseMaterial3D
		if material:
			var copy: BaseMaterial3D = material.duplicate()
			copy.albedo_color = copy.albedo_color * colour
			mesh.set_surface_override_material(i, copy)


## Hands for a model whose rig has finger bones but whose mesh has none (the
## heroine's sleeves were modelled closed). A palm rides the Hand bone and a
## rounded segment rides every finger bone, each sized from the rig, so the
## fingers move with every animation. Toon-shaded in the model's skin tone.
static func _add_hands(skeleton: Skeleton3D) -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.86, 0.66, 0.6)
	skin.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	skin.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	skin.roughness = 1.0
	for side in ["Left", "Right"]:
		var hand := skeleton.find_bone(side + "Hand")
		if hand < 0:
			continue
		var tips := []
		for f in ["Index", "Middle", "Ring", "Little", "Thumb"]:
			var chain := []
			for seg in ["Metacarpal", "Proximal", "Intermediate", "Distal"]:
				var b := skeleton.find_bone(side + f + seg)
				if b >= 0:
					chain.append(b)
			if chain.is_empty():
				continue
			if f != "Thumb":
				tips.append(skeleton.get_bone_rest(chain[0]).origin)
			var radius := 0.0085 if f != "Thumb" else 0.0095
			if f == "Little":
				radius = 0.0072
			for i in chain.size():
				var bone: int = chain[i]
				var to: Vector3
				if i + 1 < chain.size():
					to = skeleton.get_bone_rest(chain[i + 1]).origin
				else:
					var prev: Vector3 = skeleton.get_bone_rest(bone).origin
					to = prev.normalized() * prev.length() * 0.8 if prev.length() > 0.001 else Vector3(0, 0.018, 0)
				_bone_capsule(skeleton, bone, to, radius * (1.0 - i * 0.08), skin)
		# The palm: from the wrist to the knuckles, as wide as the knuckle row.
		if tips.size() >= 2:
			var mid := Vector3.ZERO
			for t: Vector3 in tips:
				mid += t
			mid /= tips.size()
			var width: float = (tips[0] as Vector3).distance_to(tips[tips.size() - 1]) + 0.018
			var palm := MeshInstance3D.new()
			var box := CapsuleMesh.new()
			box.radius = width * 0.5
			box.height = maxf(mid.length() + width * 0.3, width)
			box.radial_segments = 12
			box.rings = 4
			palm.mesh = box
			palm.material_override = skin
			var att := BoneAttachment3D.new()
			att.bone_idx = hand
			skeleton.add_child(att)
			att.add_child(palm)
			palm.basis = Basis(Quaternion(Vector3.UP, mid.normalized())) * Basis.from_scale(Vector3(1.0, 1.0, 0.36))
			palm.position = mid * 0.55


static func _bone_capsule(skeleton: Skeleton3D, bone: int, to: Vector3, radius: float, mat: Material) -> void:
	var length := to.length()
	if length < 0.002:
		return
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length + radius * 2.0
	cap.radial_segments = 8
	cap.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = mat
	var att := BoneAttachment3D.new()
	att.bone_idx = bone
	skeleton.add_child(att)
	att.add_child(mi)
	mi.basis = Basis(Quaternion(Vector3.UP, to.normalized()))
	mi.position = to * 0.5


static var _opened := {}


## Shorten sleeves that cover the hands: every vertex past a wrist (along the
## forearm, in rest pose) is drawn back to just short of the wrist, so the
## cuff ends there and the hand shows. Done once per mesh in its own data.
static func _open_sleeves(mi: MeshInstance3D, skeleton: Skeleton3D, root: Node3D) -> void:
	if mi.mesh == null or mi.skin == null:
		return
	if _opened.has(mi.mesh):
		mi.mesh = _opened[mi.mesh]
		return
	var to_root := _transform_to(skeleton, root)
	var sides := []
	for side in ["Left", "Right"]:
		var h := skeleton.find_bone(side + "Hand")
		var e := skeleton.find_bone(side + "LowerArm")
		if h < 0 or e < 0:
			return
		var w: Vector3 = to_root * skeleton.get_bone_global_rest(h).origin
		var el: Vector3 = to_root * skeleton.get_bone_global_rest(e).origin
		sides.append([w, (w - el).normalized(), (w - el).length()])
	var out := ArrayMesh.new()
	var changed := false
	for si in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var rest: PackedVector3Array = _rest_points(mi, si, root)[0]
		var per: int = (bones as PackedInt32Array).size() / maxi(verts.size(), 1) if bones != null else 0
		var plain := _transform_to(mi, root)
		for i in verts.size():
			var p: Vector3 = rest[i]
			for sd in sides:
				var w: Vector3 = sd[0]
				var d: Vector3 = sd[1]
				var t := (p - w).dot(d)
				var radial := (p - w) - d * t
				# Only the sleeve round this forearm, past the wrist.
				if t <= 0.0 or t > 0.3 or radial.length() > 0.12:
					continue
				# Keep the cuff's shape, a third as long past the wrist.
				var back := maxf(t, 0.0) * 0.66
				var q := p - d * back
				# Undo the vertex's rest transform (its first bone's bind).
				var tr := plain
				if per > 0:
					var bind: int = bones[i * per]
					var bone := mi.skin.get_bind_bone(bind)
					if bone < 0:
						bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
					if bone >= 0:
						tr = to_root * skeleton.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bind)
				verts[i] = tr.affine_inverse() * q
				changed = true
				break
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(arrays))
		out.surface_set_material(si, mi.mesh.surface_get_material(si))
	if not changed:
		_opened[mi.mesh] = mi.mesh
		return
	_opened[mi.mesh] = out
	mi.mesh = out


## Surface arrays without the custom channels: read back from an imported
## mesh they come unpacked, and handing them over again without their
## packing flags makes the whole surface fail to build (it vanishes).
static func _plain(arrays: Array) -> Array:
	for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		if c < arrays.size():
			arrays[c] = null
	return arrays
