extends CanvasLayer
## The map.
##
## Drawn from the world itself rather than from anything hand-made: at
## start-up the whole land mass is sampled on a grid - height, biome, slope -
## and painted into one small image. That is the map. It is correct by
## construction, because it is made by asking the same functions that built
## the ground you are standing on.
##
## A compass rose sits in the top corner all the time, with the land around
## you and an arrow for which way you are facing. Tap it and it opens out to
## the whole island; tap again and it closes.

const PIX := 320                  # samples across the whole map
const MINI := 150.0               # corner map, pixels
const MINI_RANGE := 190.0         # metres shown in the corner

var world_r := 620.0
var sea_y := -11.0
var height_at: Callable           # (x, z) -> float
var biome_at: Callable            # (x, z) -> int
var player_pos := Vector3.ZERO
var player_yaw := 0.0
var marks: Array = []             # [{pos, kind}] - town, ruins, camps
var open := false

var _tex: ImageTexture
var _view: Painter
var _span := 0.0                  # metres across the painted image


func _ready() -> void:
	layer = 6
	_view = Painter.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


## Paints the island once. Costs a few tens of milliseconds and never runs
## again; everything after this is just drawing a texture.
func bake() -> void:
	_span = world_r * 2.4
	var img := Image.create(PIX, PIX, false, Image.FORMAT_RGB8)
	var step := _span / float(PIX)
	var deep := Color(0.05, 0.14, 0.22)
	var shallow := Color(0.12, 0.30, 0.40)
	var sand := Color(0.68, 0.62, 0.44)
	var grass := Color(0.28, 0.40, 0.22)
	var jungle := Color(0.16, 0.33, 0.17)
	var dust := Color(0.42, 0.37, 0.28)
	var rock := Color(0.44, 0.43, 0.42)
	for py in PIX:
		for px in PIX:
			var x := (float(px) - PIX * 0.5) * step
			var z := (float(py) - PIX * 0.5) * step
			var h: float = height_at.call(x, z)
			var c: Color
			if h < sea_y + 0.5:
				c = deep.lerp(shallow, clampf((h - sea_y + 6.0) / 6.0, 0.0, 1.0))
			elif h < sea_y + 3.0:
				c = sand
			else:
				match int(biome_at.call(x, z)):
					1: c = jungle
					2: c = dust
					_: c = grass
				# Hill shading: compare with the ground a step to the west, so
				# ridges and valleys show as light and shade.
				var hw: float = height_at.call(x - step, z)
				var lit: float = clampf((h - hw) * 0.09 + 0.5, 0.0, 1.0)
				c = c.darkened((1.0 - lit) * 0.45).lightened(maxf(lit - 0.5, 0.0) * 0.5)
				if h > 26.0:
					c = c.lerp(rock, clampf((h - 26.0) / 14.0, 0.0, 0.8))
			img.set_pixel(px, py, c)
	_tex = ImageTexture.create_from_image(img)


## World position -> pixel in the map image (0..1 on each axis).
func _uv_of(p: Vector3) -> Vector2:
	return Vector2(p.x / _span + 0.5, p.z / _span + 0.5)


func _input(event: InputEvent) -> void:
	var at := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
		at = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
		at = (event as InputEventMouseButton).position
	else:
		return
	if not pressed:
		return
	if open:
		open = false
		_view.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var vp := _view.size
	var centre := Vector2(vp.x - MINI * 0.5 - 24.0, MINI * 0.5 + 24.0)
	if at.distance_to(centre) <= MINI * 0.5 + 6.0:
		open = true
		_view.queue_redraw()
		get_viewport().set_input_as_handled()


func _process(_d: float) -> void:
	if _view:
		_view.queue_redraw()


class Painter extends Control:
	var ui


	func _draw() -> void:
		if ui._tex == null:
			return
		var vp := size
		var font := ThemeDB.fallback_font
		if ui.open:
			_draw_full(vp, font)
		else:
			_draw_mini(vp)


	## The corner map: a disc of the land round you, turning with you only in
	## so far as the arrow does - north stays up, which is what people read
	## maps by.
	func _draw_mini(vp: Vector2) -> void:
		var r: float = ui.MINI * 0.5
		var centre := Vector2(vp.x - r - 24.0, r + 24.0)
		var uv: Vector2 = ui._uv_of(ui.player_pos)
		var half: float = float(ui.MINI_RANGE) / float(ui._span)          # fraction of the image shown
		var src := Rect2(
			Vector2(uv.x - half, uv.y - half) * float(int(ui.PIX)),
			Vector2(half * 2.0, half * 2.0) * float(int(ui.PIX)))
		draw_circle(centre, r + 4.0, Color(0.05, 0.06, 0.08, 0.85))
		var dest := Rect2(centre - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
		draw_texture_rect_region(ui._tex, dest, src, Color(1, 1, 1, 0.97))
		# Ring, cardinal tick and the player's heading.
		draw_arc(centre, r + 2.0, 0.0, TAU, 48, Color(0.85, 0.85, 0.8, 0.9), 2.5, true)
		draw_string(ThemeDB.fallback_font, centre + Vector2(-5, -r + 14), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))
		_arrow(centre, float(ui.player_yaw), 9.0)
		for m in ui.marks:
			var mp: Vector3 = m["pos"]
			var d := Vector2(mp.x - ui.player_pos.x, mp.z - ui.player_pos.z)
			if d.length() > ui.MINI_RANGE:
				continue
			var at: Vector2 = centre + d / float(ui.MINI_RANGE) * r
			draw_circle(at, 3.0, Color(0.95, 0.80, 0.30, 0.95))


	## The whole island, with where you are on it.
	func _draw_full(vp: Vector2, font: Font) -> void:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.05, 0.86))
		var side: float = minf(vp.x, vp.y) * 0.84
		var dest := Rect2(Vector2((vp.x - side) * 0.5, (vp.y - side) * 0.5), Vector2(side, side))
		draw_texture_rect(ui._tex, dest, false)
		draw_rect(dest, Color(0.85, 0.85, 0.8, 0.9), false, 2.0)
		for m in ui.marks:
			var mp: Vector3 = m["pos"]
			var uv: Vector2 = ui._uv_of(mp)
			var at: Vector2 = dest.position + uv * side
			var kind := str(m.get("kind", "ruin"))
			if kind == "town":
				draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.85, 0.35))
				draw_string(font, at + Vector2(9, 5), "town", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
					Color(1.0, 0.9, 0.6))
			else:
				draw_circle(at, 3.5, Color(0.9, 0.75, 0.3, 0.9))
		var puv: Vector2 = ui._uv_of(ui.player_pos)
		_arrow(dest.position + puv * side, float(ui.player_yaw), 11.0)
		var label := "%d m east  ·  %d m north" % [int(ui.player_pos.x), int(-ui.player_pos.z)]
		draw_string(font, dest.position + Vector2(12, 26), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.92, 0.94, 0.97))
		draw_string(font, Vector2(dest.position.x + 12, dest.end.y - 14), "tap to close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.7, 0.72, 0.75))


	func _arrow(at: Vector2, yaw: float, size: float) -> void:
		# Screen north is -Z, and the camera yaw turns the other way round it.
		var a := -yaw
		var tip := at + Vector2(sin(a), -cos(a)) * size
		var l := at + Vector2(sin(a + 2.5), -cos(a + 2.5)) * size * 0.7
		var r := at + Vector2(sin(a - 2.5), -cos(a - 2.5)) * size * 0.7
		draw_colored_polygon(PackedVector2Array([tip, l, at, r]), Color(1.0, 0.35, 0.25))
		draw_circle(at, 2.0, Color(1, 1, 1, 0.9))
