class_name SoftShadow
extends Sprite2D
## A soft elliptical contact shadow.
##
## Without one, a character standing on flat colour reads as floating a
## few pixels above it. `follow` makes it track the ground beneath a moving
## body, shrinking and fading as the body rises.

const TILE := 128.0

static var _texture: Texture2D

var follow: Node2D = null
var world: World = null
var width_tiles := 1.0


static func shadow_texture() -> Texture2D:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.02, 0.02, 0.05, 0.55))
		gradient.set_color(1, Color(0.02, 0.02, 0.05, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_texture = tex
	return _texture


## A fixed shadow at a parent's origin (its foot).
static func blob(width: float) -> SoftShadow:
	var shadow := SoftShadow.new()
	shadow.texture = shadow_texture()
	shadow.width_tiles = width
	shadow.scale = Vector2(width * TILE / 128.0, width * TILE / 128.0 * 0.22)
	shadow.position = Vector2(0, -4)
	shadow.z_index = -1
	return shadow


## A shadow that finds the ground under `body` every frame.
static func under(body: Node2D, the_world: World, width: float) -> SoftShadow:
	var shadow := blob(width)
	shadow.follow = body
	shadow.world = the_world
	shadow.top_level = true
	shadow.z_as_relative = false
	shadow.z_index = 1
	return shadow


func _process(_delta: float) -> void:
	if follow == null or world == null:
		return
	var foot := follow.global_position
	var cell := World.cell_of(foot + Vector2(0, -8))
	var ground := -1
	for dy in 7:
		if world.data.is_solid(cell.x, cell.y + dy):
			ground = cell.y + dy
			break
	if ground < 0:
		visible = false
		return
	visible = true
	var floor_y := ground * TILE
	var height := clampf((floor_y - foot.y) / (TILE * 5.0), 0.0, 1.0)
	global_position = Vector2(foot.x, floor_y - 4.0)
	var k := (1.0 - height * 0.6) * width_tiles * TILE / 128.0
	scale = Vector2(k, k * 0.22)
	modulate.a = 1.0 - height * 0.85
