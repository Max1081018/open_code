class_name ObjectArt
extends RefCounted
## Builds the node that draws one world object: trees, torches, stations.

const TILE := 128

## Object type -> [texture path, height in tiles].
const ART := {
	"workbench": ["res://assets/rendered/workbench.png", 0.95],
	"anvil": ["res://assets/rendered/workbench-anvil.png", 0.95],
	"campfire": ["res://assets/rendered/campfire-pit.png", 0.62],
	"chest": ["res://assets/rendered/chest.png", 0.80],
	"barrel": ["res://assets/rendered/barrel.png", 0.95],
	"altar": ["res://assets/rendered/altar-stone.png", 0.70],
	"wardstone": ["res://assets/rendered/pillar-obelisk.png", 1.9],
	"sign": ["res://assets/rendered/signpost.png", 1.25],
}

## Placed objects that give their item back when broken.
const ITEM_FOR := {
	"torch": "torch", "workbench": "workbench", "anvil": "anvil", "campfire": "campfire",
	"chest": "chest", "wardstone": "wardstone",
}

static var _sway: Shader
static var _textures := {}


static func item_for(object: Dictionary) -> String:
	return ITEM_FOR.get(object.get("type", ""), "")


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## Every object node sits at the bottom-centre of its cell and draws
## relative to that, so halos and effects added later land on it too.
static func make(object: Dictionary, cell: Vector2i) -> Node2D:
	var hash_value := absi(cell.x * 73856093 ^ cell.y * 19349663)
	var node := _build(object, hash_value)
	if node != null:
		_maybe_glow(node, object, cell, hash_value)
		node.position = Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)
		var width: float = SHADOW_WIDTH.get(object.get("type", ""), 0.0)
		if width > 0.0 and Settings.shadows:
			var shadow := SoftShadow.blob(width)
			node.add_child(shadow)
			node.move_child(shadow, 0)
	return node


## Contact-shadow width in tiles for objects that stand on the ground.
const SHADOW_WIDTH := {
	"tree": 1.5, "workbench": 1.0, "anvil": 1.0, "chest": 0.9, "barrel": 0.8,
	"campfire": 0.9, "altar": 1.1, "wardstone": 0.9, "sign": 0.5, "geode": 1.0,
}


static func _build(object: Dictionary, hash_value: int) -> Node2D:
	var foot := Vector2.ZERO
	match object.get("type", ""):
		"tree":
			return _tree(object, foot, hash_value)
		"shrub":
			return _shrub(object, foot, hash_value)
		"torch":
			return _torch(object, foot)
		"wardstone":
			return _wardstone(foot)
		"campfire":
			var node := _prop("campfire", foot)
			node.add_child(Effects.fire(Vector2(0, -TILE * 0.32)))
			return node
		"geode":
			var geode := Node2D.new()
			var crystal := Sprite2D.new()
			crystal.texture = texture("res://assets/props/gem_blue.png")
			crystal.scale = Vector2(1.6, 1.6)
			crystal.modulate = Color(0.8, 0.6, 1.2)
			crystal.position = Vector2(0, -90)
			geode.add_child(crystal)
			geode.add_child(Effects.motes(Vector2(0, -120), Color(0.7, 0.5, 1.0), 2.5))
			return geode
		"spawner":
			return null
	if ART.has(object.get("type", "")):
		return _prop(object.type, foot)
	return null


## Light given off by cave decor: art -> colour. Mushrooms deep enough
## underground glow (decided from the cell, so world generation and saves
## are untouched); crystals always do.
const GLOW_DECOR := {
	"mushroom_brown": Color(0.35, 0.95, 0.85),
	"mushroom_red": Color(0.95, 0.40, 0.85),
	"gem_blue": Color(0.40, 0.70, 1.0),
}


## Marks the node with meta "glow" (a Color) when it should light its cell,
## and gives the sprite a breathing emissive pulse.
static func glows(object: Dictionary, cell: Vector2i) -> bool:
	if object.get("type", "") != "shrub":
		return false
	var art: String = object.get("art", "")
	if not GLOW_DECOR.has(art):
		return false
	if art.begins_with("mushroom"):
		var hash_value := absi(cell.x * 73856093 ^ cell.y * 19349663)
		return cell.y >= WorldData.SURFACE_Y + 20 and hash_value % 3 != 0
	return true


static func _maybe_glow(node: Node2D, object: Dictionary, cell: Vector2i, hash_value: int) -> void:
	if not glows(object, cell):
		return
	var art: String = object.get("art", "")
	var color: Color = GLOW_DECOR[art]
	node.set_meta("glow", color)
	if not art.begins_with("mushroom"):
		for child in node.get_children():
			if child is Sprite2D and child.material == null:
				child.material = emissive_material(color, hash_value)
	else:
		# A cluster: the art only fills the lower half of its canvas, so
		# the main cap is drawn larger, with two smaller ones beside it.
		var tex := texture("res://assets/props/%s.png" % art)
		for child in node.get_children():
			if child is Sprite2D:
				node.remove_child(child)
				child.free()
		var caps := [[Vector2(0, 6), 1.25, false], [Vector2(-34, 6), 0.8, true], [Vector2(30, 6), 0.65, false]]
		for i in caps.size():
			var cap: Array = caps[i]
			var sprite := _sprite_standing(tex, cap[0], cap[1])
			sprite.flip_h = cap[2] != (hash_value % 2 == 0)
			sprite.material = emissive_material(color, hash_value + i * 97)
			node.add_child(sprite)
		node.add_child(Glow.make(color, 1.0))
		if hash_value % 2 == 0:
			node.add_child(Effects.motes(Vector2(0, -50), color, 1.2))


static var _emissive: Shader


## The sprite brightens and tints toward its glow colour on a slow pulse.
## Drawn above the light map's darkening, it reads as the source of light.
static func emissive_material(color: Color, hash_value: int) -> ShaderMaterial:
	if _emissive == null:
		_emissive = Shader.new()
		_emissive.code = """
shader_type canvas_item;
uniform vec3 glow = vec3(0.4, 0.9, 0.9);
uniform float phase = 0.0;
uniform float speed = 1.2;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float pulse = 0.5 + 0.5 * sin(TIME * speed + phase);
	vec3 lit = mix(c.rgb, glow * (0.6 + grey), 0.55) * (1.15 + pulse * 0.45);
	COLOR = vec4(lit, c.a) * COLOR;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _emissive
	material.set_shader_parameter("glow", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("phase", (hash_value % 628) / 100.0)
	material.set_shader_parameter("speed", 0.9 + (hash_value % 9) / 10.0)
	return material


static func _sprite_standing(tex: Texture2D, foot: Vector2, height_tiles: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	var scale := height_tiles * TILE / float(tex.get_height())
	sprite.scale = Vector2(scale, scale)
	sprite.position = foot - Vector2(tex.get_width() * scale * 0.5, tex.get_height() * scale)
	return sprite


static func _prop(type: String, foot: Vector2) -> Node2D:
	var spec: Array = ART[type]
	var tex := texture(spec[0])
	if tex == null:
		return null
	var root := Node2D.new()
	root.add_child(_sprite_standing(tex, foot, spec[1]))
	return root


static func _tree(object: Dictionary, foot: Vector2, hash_value: int) -> Node2D:
	var tex := texture("res://assets/scenery/%s.png" % object.get("art", "tree"))
	if tex == null:
		return null
	var root := Node2D.new()
	var height := 3.4 + (hash_value % 100) / 100.0 * 1.8
	if String(object.art).begins_with("cactus"):
		height = 1.6 + (hash_value % 50) / 100.0
	elif String(object.art).begins_with("treeSmall"):
		height = 2.4
	var sprite := _sprite_standing(tex, foot + Vector2(0, 6), height)
	sprite.material = _sway_material(hash_value)
	root.add_child(sprite)
	return root


static func _shrub(object: Dictionary, foot: Vector2, hash_value: int) -> Node2D:
	var art: String = object.get("art", "bush1")
	var path := "res://assets/scenery/%s.png" % art
	if not ResourceLoader.exists(path):
		path = "res://assets/props/%s.png" % art
	var tex := texture(path)
	if tex == null:
		return null
	var height := 0.62
	if art.begins_with("bush"):
		height = 0.55 + (hash_value % 30) / 100.0
	elif art.begins_with("gem"):
		height = 0.45
	var root := Node2D.new()
	var sprite := _sprite_standing(tex, foot + Vector2(0, 4), height)
	if art.begins_with("bush") or art.begins_with("grass"):
		sprite.material = _sway_material(hash_value)
	if hash_value % 2 == 0:
		sprite.flip_h = true
	root.add_child(sprite)
	if art.begins_with("gem"):
		root.add_child(Glow.make(Color(0.4, 0.75, 1.0), 1.6))
	return root


static func _torch(object: Dictionary, foot: Vector2) -> Node2D:
	var root := Node2D.new()
	if object.get("lit", true):
		var frames := SpriteFrames.new()
		frames.add_animation("burn")
		frames.set_animation_speed("burn", 7.0)
		frames.add_frame("burn", texture("res://assets/props/torch_on_a.png"))
		frames.add_frame("burn", texture("res://assets/props/torch_on_b.png"))
		var flame := AnimatedSprite2D.new()
		flame.sprite_frames = frames
		flame.animation = "burn"
		flame.autoplay = "burn"
		flame.frame = randi() % 2
		flame.scale = Vector2(0.62, 0.62)
		flame.position = foot - Vector2(0, TILE * 0.40)
		flame.play()
		root.add_child(flame)
		root.add_child(Effects.embers(foot - Vector2(0, TILE * 0.62)))
	else:
		root.add_child(_sprite_standing(texture("res://assets/props/torch_off.png"), foot, 0.62))
	return root


static func _wardstone(foot: Vector2) -> Node2D:
	var root := _prop("wardstone", foot)
	var gem := Sprite2D.new()
	gem.texture = texture("res://assets/props/gem_blue.png")
	gem.scale = Vector2(0.5, 0.5)
	gem.position = foot - Vector2(0, TILE * 2.35)
	root.add_child(gem)
	var tween := gem.create_tween().set_loops()
	tween.tween_property(gem, "position:y", gem.position.y - 14, 1.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(gem, "position:y", gem.position.y, 1.4).set_trans(Tween.TRANS_SINE)
	root.add_child(Effects.motes(foot - Vector2(0, TILE * 1.6), Color(0.6, 0.9, 1.0), 2.2))
	return root


static func _sway_material(hash_value: int) -> ShaderMaterial:
	if _sway == null:
		_sway = Shader.new()
		_sway.code = """
shader_type canvas_item;
// Wind: the top of the sprite drifts while its base stays rooted.
uniform float phase = 0.0;
uniform float strength = 9.0;
// Foliage in the world's palette, not Kenney's toy green.
uniform float saturation = 0.72;
uniform vec3 tint = vec3(0.86, 0.92, 0.88);
void vertex() {
	float lift = 1.0 - UV.y;
	float gust = sin(TIME * 1.3 + phase) * 0.7 + sin(TIME * 2.9 + phase * 1.7) * 0.3;
	VERTEX.x += gust * strength * lift * lift;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), c.rgb, saturation) * tint, c.a) * COLOR;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _sway
	material.set_shader_parameter("phase", (hash_value % 628) / 100.0)
	material.set_shader_parameter("strength", 7.0 + (hash_value % 7))
	return material
