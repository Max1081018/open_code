class_name Foreground
extends Node2D
## The near layer: large, dark plant silhouettes passing in front of the
## world, between the scene and the camera. They move faster than the
## ground (parallax above 1), which is what sells the depth, and they stay
## along the bottom edge so they frame the view without hiding play.
##
## A handful of sprites recycled along a repeating strip; nothing per tile.

const PARALLAX := 1.45
const PERIOD := 7200.0
## [x along the strip, art, height in tiles, flipped]
const PIECES := [
	[0.0, "bushAlt1", 2.6, false],
	[620.0, "grass_b", 2.2, true],
	[1900.0, "bush2", 3.0, true],
	[2650.0, "grass_a", 2.4, false],
	[3800.0, "bushAlt3", 2.4, false],
	[4300.0, "grass_c", 2.0, true],
	[5600.0, "bush1", 2.8, false],
	[6400.0, "grass_b", 2.3, false],
]

var level: Level
var _sprites: Array[Sprite2D] = []
var _shown := 0.0


func setup(the_level: Level) -> void:
	level = the_level
	z_as_relative = false
	z_index = 45
	visible = Settings.background >= 2
	for piece in PIECES:
		var path := "res://assets/scenery/%s.png" % piece[1]
		if not ResourceLoader.exists(path):
			path = "res://assets/scenery/foliage/%s.png" % piece[1]
		var sprite := Sprite2D.new()
		sprite.texture = load(path)
		sprite.centered = false
		var k: float = piece[2] * 128.0 / float(sprite.texture.get_height())
		sprite.scale = Vector2(k, k)
		sprite.flip_h = piece[3]
		sprite.material = Visuals.sway()
		add_child(sprite)
		_sprites.append(sprite)


func _process(delta: float) -> void:
	if not visible or level.player == null:
		return
	var camera := level.camera
	var view := get_viewport_rect().size / camera.zoom
	var centre := camera.get_screen_center_position()
	var data := level.data
	# Only near the surface: underground there is nothing to stand in front of.
	var cell := World.cell_of(level.player.global_position)
	var column := clampi(cell.x, 0, data.width - 1)
	var outdoors := clampf(1.0 - float(cell.y - data.surface[column]) / 8.0, 0.0, 1.0)
	_shown = move_toward(_shown, outdoors, delta * 1.5)
	modulate = Color(0.10, 0.13, 0.12, 0.94 * _shown)
	if _shown <= 0.0:
		return
	var scroll := fposmod(centre.x * PARALLAX, PERIOD)
	var left := centre.x - view.x * 0.5
	var bottom := centre.y + view.y * 0.5
	for i in _sprites.size():
		var sprite := _sprites[i]
		var width := sprite.texture.get_width() * sprite.scale.x
		var height := sprite.texture.get_height() * sprite.scale.y
		# Position along the strip relative to the scrolled window.
		var x := fposmod(float(PIECES[i][0]) - scroll, PERIOD) - width
		sprite.visible = x < view.x + width
		sprite.position = Vector2(left + x, bottom - height * 0.62)
