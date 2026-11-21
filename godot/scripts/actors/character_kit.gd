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
	"zombie": ["skeleton", null],
	"shade": ["skeleton", Color(0.62, 0.5, 0.85)],
	"robot": ["knight", Color(0.8, 0.62, 0.5)],  # rust-eaten plate
	"warden": ["warden", null],          # the cursed knight
}
## Per-character presence: height in metres and their own way of moving
## (clip overrides on the shared library, playback speed). Anime heroines
## are small and light on their feet; knights heavy; the dead shamble.
const HERO_STYLE := {
	"player": {"height": 1.56, "clips": {"Walk": "Walk_Formal"}, "speed": 1.12},
	"wren": {"height": 1.6, "clips": {"Idle": "Idle_Talking"}, "speed": 1.05},
	"mira": {"height": 1.58, "clips": {"Walk": "Walk_Formal"}, "speed": 1.0},
	"tobin": {"height": 1.72, "clips": {"Idle": "Idle_FoldArms"}, "speed": 0.95},
	"aldous": {"height": 1.64, "clips": {"Idle": "Sword_Idle"}, "speed": 1.0},
	"warden": {"height": 2.0, "speed": 0.85},
	"robot": {"height": 1.85, "speed": 0.9},
	"zombie": {"height": 1.8, "speed": 0.9},
	"shade": {"height": 1.75, "speed": 1.15},
}
const HERO_DIR := "res://assets/models/heroes/"
const HERO_ANIMS := HERO_DIR + "anim/humanoid.res"
static var _hero_library: AnimationLibrary

const BODIES := {"male": "bodies/Superhero_Male_FullBody.gltf", "female": "bodies/Superhero_Female_FullBody.gltf"}

## Metres the clothing is pushed out over the body.
const OUTFIT_GROW := 0.022

static var _library: AnimationLibrary


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
	if spec[1] != null:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			_tint_all(mesh, spec[1])
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.root_node = NodePath("../" + String(root.get_path_to(model)))
	if _hero_library == null:
		_hero_library = load(HERO_ANIMS)
	player.add_animation_library("", _hero_library)
	root.set_meta("style", HERO_STYLE.get(name, {}))
	return root


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
