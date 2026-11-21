class_name CaveForeground
extends Node2D
## The near layer underground: dark rock silhouettes between the camera and
## the cave. Stalactite clusters hang from the top of the view and
## stalagmite mounds rise from the bottom, scrolling faster than the world
## (parallax above 1). They frame the scene like the near edge of a diorama,
## which is what makes a cave read as a space with depth rather than a
## flat wall behind the player. Drawn as polygons: no art, nothing per tile.

const PARALLAX := 1.5
const PERIOD := 6400.0
const TILE := 128.0

var level: Level
## [x along the strip, polygon (local), from the top?]
var _pieces: Array = []
var _shown := 0.0
var _scroll := 0.0
var _view := Vector2.ZERO
var _left := 0.0
var _top := 0.0


func setup(the_level: Level) -> void:
	level = the_level
	z_as_relative = false
	z_index = 46
	visible = Settings.background >= 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 4177
	var x := 0.0
	var from_top := true
	while x < PERIOD:
		_pieces.append([x, _cluster(rng, from_top), from_top])
		x += rng.randf_range(360.0, 720.0)
		from_top = not from_top if rng.randf() < 0.8 else from_top


## A clump of spikes on a rough base, pointing down (top) or up (bottom).
static func _cluster(rng: RandomNumberGenerator, hanging: bool) -> PackedVector2Array:
	var width := rng.randf_range(300.0, 620.0)
	var points := PackedVector2Array()
	var sign := 1.0 if hanging else -1.0
	points.append(Vector2(-60.0, -40.0 * sign))
	var spikes := rng.randi_range(3, 5)
	for i in spikes:
		var cx := width * (i + 0.5) / spikes + rng.randf_range(-30.0, 30.0)
		var half := width / spikes * rng.randf_range(0.32, 0.5)
		var length := TILE * rng.randf_range(0.7, 2.3) * (1.25 if i == spikes / 2 else 1.0)
		var base := TILE * rng.randf_range(0.15, 0.45)
		points.append(Vector2(cx - half, base * sign))
		points.append(Vector2(cx - half * 0.25, length * 0.7 * sign))
		points.append(Vector2(cx, length * sign))
		points.append(Vector2(cx + half * 0.3, length * 0.6 * sign))
		points.append(Vector2(cx + half, base * sign))
	points.append(Vector2(width + 60.0, -40.0 * sign))
	return points


func _process(delta: float) -> void:
	if not visible or level.player == null:
		return
	var camera := level.camera
	_view = get_viewport_rect().size / camera.zoom
	var centre := camera.get_screen_center_position()
	var data := level.data
	var cell := World.cell_of(level.player.global_position)
	var column := clampi(cell.x, 0, data.width - 1)
	var underground := clampf(float(cell.y - data.surface[column] - 6) / 6.0, 0.0, 1.0)
	_shown = move_toward(_shown, underground, delta * 1.2)
	if _shown <= 0.0:
		queue_redraw()
		return
	_scroll = fposmod(centre.x * PARALLAX, PERIOD)
	_left = centre.x - _view.x * 0.5
	_top = centre.y - _view.y * 0.5
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.0:
		return
	var ink := Color(0.02, 0.018, 0.03, 0.96 * _shown)
	var rim := Color(0.20, 0.17, 0.24, 0.5 * _shown)
	for piece in _pieces:
		var x := fposmod(float(piece[0]) - _scroll, PERIOD) - 400.0
		if x > _view.x + 200.0:
			continue
		var hanging: bool = piece[2]
		var origin := Vector2(_left + x, _top if hanging else _top + _view.y)
		var poly: PackedVector2Array = piece[1]
		var placed := PackedVector2Array()
		for p in poly:
			placed.append(origin + p)
		draw_colored_polygon(placed, ink)
		# A faint lit edge: the lantern catching the near rock.
		draw_polyline(placed, rim, 3.0)
