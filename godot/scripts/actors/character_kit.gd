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
	# Her own clips, but the even stride of the shared jog for running; her
	# own bounding run, arms flying, becomes the sprint.
	"player": {"height": 1.56, "library": "anim/heroine.res", "speed": 1.0, "clips": {"Jog_Fwd": "ual/Jog_Fwd"}},
	"wren": {"height": 1.6, "clips": {"Idle": "Idle_Talking"}, "speed": 1.05},
	# Mira's model is all pastel white; dye it a herbalist's sage coat and
	# deeper rose hair so she reads at a distance (tints by texture file).
	"mira": {"height": 1.58, "clips": {"Walk": "Walk_Formal"}, "speed": 1.0,
		"tex_tints": {"albedo_3": Color(0.58, 0.74, 0.58), "albedo_2": Color(0.9, 0.6, 0.74)}},
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
	return root


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
