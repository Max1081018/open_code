class_name RuneLayer
extends Node2D
## Light-runes: marks cut into the rock over hidden caches. They cannot be
## seen in ordinary light. A flare makes those near it blaze up for a while
## (and the Seer's Eye shows them to you always), so the player learns to
## flare in quiet caves and dig where the rock answers.

const TILE := 128.0
const SHOWN := 24.0        ## seconds a rune stays lit after a flare
const SEER_RANGE := 10.0   ## tiles: the Seer's Eye shows runes this close

var level: Level
## rock cell -> seconds left shown
var _lit := {}
var _glyph: Texture2D
## The Deepsong Shell: ore cells near the player, rescanned twice a second.
var _ore_cells: Array = []
var _ore_scan := 0.0
const ORE_RANGE := 9
const ORE_COLOURS := {
	WorldData.COAL: Color(0.75, 0.75, 0.8), WorldData.COPPER: Color(1.0, 0.6, 0.35),
	WorldData.IRON: Color(0.9, 0.8, 0.75), WorldData.SILVER: Color(0.85, 0.92, 1.0),
	WorldData.GOLD: Color(1.0, 0.85, 0.3), WorldData.GLOWSHARD: Color(0.5, 0.8, 1.0),
	WorldData.RUBY: Color(1.0, 0.3, 0.35), WorldData.EMERALD: Color(0.35, 1.0, 0.5),
}


func setup(the_level: Level) -> void:
	level = the_level
	z_as_relative = false
	z_index = 45
	_glyph = _make_glyph()


## A flare at `centre`: runes within `reach` (pixels) light up.
func flare(centre: Vector2, reach: float) -> int:
	var shown := 0
	for cache in level.data.caches:
		var cell: Vector2i = cache.rune
		if not level.data.is_solid(cell.x, cell.y):
			continue  # already dug open
		if World.centre_of(cell).distance_to(centre) <= reach:
			if not _lit.has(cell):
				shown += 1
			_lit[cell] = SHOWN
	return shown


func is_shown(cell: Vector2i) -> bool:
	return _lit.has(cell)


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	for cell in _lit.keys():
		_lit[cell] -= delta
		if _lit[cell] <= 0.0 or not level.data.is_solid(cell.x, cell.y):
			_lit.erase(cell)
	_ore_scan -= delta
	if _ore_scan <= 0.0:
		_ore_scan = 0.5
		_ore_cells.clear()
		if level.player.has_relic("relic_deepsong"):
			var at := World.cell_of(level.player.global_position + Vector2(0, -90))
			for dy in range(-ORE_RANGE, ORE_RANGE + 1):
				for dx in range(-ORE_RANGE, ORE_RANGE + 1):
					var x := at.x + dx
					var y := at.y + dy
					if dx * dx + dy * dy <= ORE_RANGE * ORE_RANGE and level.data.in_bounds(x, y):
						var ore := level.data.get_ore(x, y)
						if ore != WorldData.ORE_NONE and level.data.is_solid(x, y):
							_ore_cells.append([Vector2i(x, y), ore])
	if level.player.has_relic("relic_seers_eye"):
		var here := World.cell_of(level.player.global_position)
		for cache in level.data.caches:
			var cell: Vector2i = cache.rune
			if Vector2(cell - here).length() <= SEER_RANGE and level.data.is_solid(cell.x, cell.y):
				_lit[cell] = maxf(_lit.get(cell, 0.0), 1.0)
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry in _ore_cells:
		var cell: Vector2i = entry[0]
		var twinkle := 0.5 + 0.5 * sin(t * 4.0 + cell.x * 1.7 + cell.y)
		var colour: Color = ORE_COLOURS.get(entry[1], Color.WHITE)
		var centre := World.centre_of(cell)
		draw_circle(centre, 20.0 + 8.0 * twinkle, Color(colour, 0.18 + 0.2 * twinkle))
		draw_circle(centre, 6.0 + 3.0 * twinkle, Color(colour, 0.85))
	for cell in _lit:
		var left: float = _lit[cell]
		var fade := clampf(left / 2.0, 0.0, 1.0) * (0.75 + 0.25 * sin(t * 3.0 + cell.x))
		var centre := World.centre_of(cell)
		draw_texture_rect(_glyph, Rect2(centre - Vector2(54, 54), Vector2(108, 108)), false,
			Color(1.0, 0.86, 0.45, fade))


## A rune drawn once: a ring with a downward stroke and two arms, "dig here".
static func _make_glyph() -> Texture2D:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length()
			var ring := absf(r - 26.0) < 2.2
			var stem := absf(p.x) < 2.2 and p.y > -18.0 and p.y < 20.0
			var arms := absf(absf(p.x) - (p.y + 4.0) * 0.8) < 2.4 and p.y > -4.0 and p.y < 14.0
			var glow := clampf(1.0 - r / 32.0, 0.0, 1.0) * 0.35
			var a := 1.0 if ring or stem or arms else glow
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)
