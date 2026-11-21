class_name Minimap
extends Control
## The map in the corner: the world as the player has seen it. Cells are
## revealed in a circle round the player as they go (the fog of war is
## saved with the world), drawn one pixel per tile and shown magnified
## round the player, with dots for the people of the meadow and a mark on
## whatever the current quest step is about.

const REVEAL_RADIUS := 13
const PIXELS_PER_TILE := 3.0
const SIZE := Vector2(330, 190)

const TILE_COLOURS := {
	WorldData.GRASS: Color(0.36, 0.64, 0.30),
	WorldData.SOIL: Color(0.47, 0.32, 0.21),
	WorldData.SAND: Color(0.86, 0.76, 0.50),
	WorldData.SNOW: Color(0.92, 0.95, 1.00),
	WorldData.ROCK: Color(0.46, 0.46, 0.50),
	WorldData.BRICK: Color(0.62, 0.36, 0.30),
	WorldData.CRYSTAL: Color(0.66, 0.46, 0.92),
	WorldData.BASALT: Color(0.30, 0.25, 0.31),
	WorldData.PLANKS: Color(0.72, 0.52, 0.31),
	WorldData.BEDROCK: Color(0.14, 0.14, 0.17),
}
const SKY := Color(0.56, 0.74, 0.92, 0.55)
const CAVE := Color(0.10, 0.10, 0.14, 0.9)
const WATER := Color(0.25, 0.5, 0.95)
const LAVA := Color(1.0, 0.45, 0.12)

var level: Level
var _image: Image
var _texture: ImageTexture
var _dirty := false
var _timer := 0.0
var _upload_timer := 0.0


func setup(the_level: Level) -> void:
	level = the_level
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var data := level.data
	_image = Image.create(data.width, data.height, false, Image.FORMAT_RGBA8)
	# Paint what an earlier visit already saw.
	for y in data.height:
		for x in data.width:
			if data.explored[y * data.width + x]:
				_image.set_pixel(x, y, colour_of(data, x, y))
	_texture = ImageTexture.create_from_image(_image)
	level.world.tile_changed.connect(_on_tile_changed)


## Mark the cells round (cx, cy) as seen; returns how many were new.
static func reveal(data: WorldData, cx: int, cy: int, radius: int, image: Image = null) -> int:
	var fresh := 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := cx + dx
			var y := cy + dy
			if not data.in_bounds(x, y):
				continue
			var i := y * data.width + x
			if data.explored[i]:
				continue
			data.explored[i] = 1
			fresh += 1
			if image:
				image.set_pixel(x, y, colour_of(data, x, y))
	return fresh


static func colour_of(data: WorldData, x: int, y: int) -> Color:
	var tile := data.get_tile(x, y)
	if tile != WorldData.AIR:
		return TILE_COLOURS.get(tile, Color(0.5, 0.5, 0.5))
	match data.get_liquid(x, y):
		WorldData.WATER:
			return WATER
		WorldData.LAVA:
			return LAVA
	return SKY if y < data.surface[x] else CAVE


func _on_tile_changed(cell: Vector2i) -> void:
	var data := level.data
	if data.in_bounds(cell.x, cell.y) and data.explored[cell.y * data.width + cell.x]:
		_image.set_pixel(cell.x, cell.y, colour_of(data, cell.x, cell.y))
		_dirty = true


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		var at := World.cell_of(level.player.global_position + Vector2(0, -60))
		var radius := REVEAL_RADIUS * (2 if level.player.has_relic("relic_seers_eye") else 1)
		if reveal(level.data, at.x, at.y, radius, _image) > 0:
			_dirty = true
	_upload_timer -= delta
	if _dirty and _upload_timer <= 0.0:
		_upload_timer = 0.5
		_dirty = false
		_texture.update(_image)
	queue_redraw()


func _draw() -> void:
	if level == null or level.player == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	draw_style_box(_panel(), frame)
	var inner := frame.grow(-8)
	# The world round the player, magnified.
	var centre := level.player.global_position / World.TILE
	var span := inner.size / PIXELS_PER_TILE
	var source := Rect2(centre - span * 0.5, span)
	draw_texture_rect_region(_texture, inner, source)
	# People: pale dots; the player: gold, with a dark ring.
	for npc in get_tree().get_nodes_in_group("npcs"):
		_dot(_to_map(npc.global_position / World.TILE, source, inner) + Vector2(0, -3), 5.0, UITheme.PAPER, inner)
	if level.guide and level.guide._target != Vector2.INF:
		var mark := _to_map(level.guide._target / World.TILE, source, inner)
		var clamped := Vector2(clampf(mark.x, inner.position.x + 6, inner.end.x - 6),
			clampf(mark.y, inner.position.y + 6, inner.end.y - 6))
		var pulse := 6.0 + sin(Time.get_ticks_msec() / 200.0) * 1.5
		draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -pulse), clamped + Vector2(pulse, 0),
			clamped + Vector2(0, pulse), clamped + Vector2(-pulse, 0)]), UITheme.GOLD)
	var me := inner.get_center() + Vector2(0, -60.0 / World.TILE * PIXELS_PER_TILE)
	draw_circle(me, 7.0, Color(0.1, 0.06, 0.02))
	draw_circle(me, 5.0, UITheme.GOLD)


func _to_map(cell: Vector2, source: Rect2, inner: Rect2) -> Vector2:
	return inner.position + (cell - source.position) * PIXELS_PER_TILE


func _dot(at: Vector2, radius: float, colour: Color, inner: Rect2) -> void:
	if inner.has_point(at):
		draw_circle(at, radius + 1.5, Color(0.08, 0.05, 0.1))
		draw_circle(at, radius, colour)


static var _style: StyleBoxFlat


static func _panel() -> StyleBoxFlat:
	if _style == null:
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.06, 0.05, 0.09, 0.78)
		_style.border_color = Color(0.95, 0.82, 0.5, 0.75)
		_style.set_border_width_all(3)
		_style.set_corner_radius_all(18)
	return _style
