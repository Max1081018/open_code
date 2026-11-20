class_name LightMap
extends RefCounted
## Coloured tile lighting for a window of the world.
##
## Sources seed cells, then four directional sweeps spread light with a
## falloff that is gentle through air and steep through rock. The result
## is one RGB value per tile, uploaded as a tiny texture and drawn over the
## world with a multiply blend, filtered so tile centres blend smoothly.
## This is how the deep gets genuinely dark while torches, lava and
## crystal throw coloured pools of light — at a cost proportional to the
## visible tiles, not to the number of lights.

## How much light survives one tile of travel.
const AIR_FALLOFF := 0.88
const SOLID_FALLOFF := 0.74
const WATER_FALLOFF := 0.80
## Floor so the darkest cave is deep indigo, never flat black.
const AMBIENT := Color(0.025, 0.022, 0.045)

var region := Rect2i()
var r := PackedFloat32Array()
var g := PackedFloat32Array()
var b := PackedFloat32Array()
var image: Image


func resize(rect: Rect2i) -> void:
	region = rect
	var n := rect.size.x * rect.size.y
	r.resize(n)
	g.resize(n)
	b.resize(n)
	if image == null or image.get_size() != rect.size:
		image = Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGB8)


func clear() -> void:
	r.fill(0.0)
	g.fill(0.0)
	b.fill(0.0)


## Raise the light at world cell (x, y) to at least `color`.
func seed_cell(x: int, y: int, color: Color) -> void:
	var lx := x - region.position.x
	var ly := y - region.position.y
	if lx < 0 or ly < 0 or lx >= region.size.x or ly >= region.size.y:
		return
	var i := ly * region.size.x + lx
	r[i] = maxf(r[i], color.r)
	g[i] = maxf(g[i], color.g)
	b[i] = maxf(b[i], color.b)


## A soft round light centred on a world position in tiles. Drawn directly
## rather than propagated, so a moving lantern glides instead of stepping
## from tile to tile; solid cells take only a fraction, so it does not
## shine through rock.
func seed_radial(centre: Vector2, radius: float, color: Color, data: WorldData) -> void:
	var x0 := int(floor(centre.x - radius))
	var x1 := int(ceil(centre.x + radius))
	var y0 := int(floor(centre.y - radius))
	var y1 := int(ceil(centre.y + radius))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
			if d > radius:
				continue
			var t := 1.0 - d / radius
			var strength := t * t * (3.0 - 2.0 * t)  # smoothstep
			if data.is_solid(x, y):
				strength *= 0.45
			seed_cell(x, y, color * strength)


## Spread the seeded light. `data` supplies what blocks it.
##
## Written for speed rather than elegance: this runs up to twenty times a
## second on a phone. Per-cell helper calls were ~45,000 function calls an
## update and the single biggest cost, so the pull is inlined and the
## world is read straight from its byte arrays.
func propagate(data: WorldData) -> void:
	var w := region.size.x
	var h := region.size.y
	var falloff := PackedFloat32Array()
	falloff.resize(w * h)
	var tiles := data.tiles
	var liquids := data.liquids
	var dw := data.width
	var dh := data.height
	for ly in h:
		var y := ly + region.position.y
		for lx in w:
			var x := lx + region.position.x
			var f := SOLID_FALLOFF
			if x >= 0 and y >= 0 and x < dw and y < dh:
				var i := y * dw + x
				if tiles[i] == WorldData.AIR:
					f = WATER_FALLOFF if liquids[i] == WorldData.WATER else AIR_FALLOFF
			falloff[ly * w + lx] = f

	_sweep_forward(w, h, falloff)
	_sweep_backward(w, h, falloff)
	# A second forward pass lets light turn corners it reached only on the
	# backward sweep.
	_sweep_forward(w, h, falloff)


func _sweep_forward(w: int, h: int, falloff: PackedFloat32Array) -> void:
	for ly in h:
		var row := ly * w
		for lx in w:
			var i := row + lx
			var f := falloff[i]
			var best_r := r[i]
			var best_g := g[i]
			var best_b := b[i]
			if lx > 0:
				best_r = maxf(best_r, r[i - 1] * f)
				best_g = maxf(best_g, g[i - 1] * f)
				best_b = maxf(best_b, b[i - 1] * f)
			if ly > 0:
				best_r = maxf(best_r, r[i - w] * f)
				best_g = maxf(best_g, g[i - w] * f)
				best_b = maxf(best_b, b[i - w] * f)
			r[i] = best_r
			g[i] = best_g
			b[i] = best_b


func _sweep_backward(w: int, h: int, falloff: PackedFloat32Array) -> void:
	for ly in range(h - 1, -1, -1):
		var row := ly * w
		for lx in range(w - 1, -1, -1):
			var i := row + lx
			var f := falloff[i]
			var best_r := r[i]
			var best_g := g[i]
			var best_b := b[i]
			if lx < w - 1:
				best_r = maxf(best_r, r[i + 1] * f)
				best_g = maxf(best_g, g[i + 1] * f)
				best_b = maxf(best_b, b[i + 1] * f)
			if ly < h - 1:
				best_r = maxf(best_r, r[i + w] * f)
				best_g = maxf(best_g, g[i + w] * f)
				best_b = maxf(best_b, b[i + w] * f)
			r[i] = best_r
			g[i] = best_g
			b[i] = best_b


func at(x: int, y: int) -> Color:
	var lx := x - region.position.x
	var ly := y - region.position.y
	if lx < 0 or ly < 0 or lx >= region.size.x or ly >= region.size.y:
		return AMBIENT
	var i := ly * region.size.x + lx
	return Color(maxf(r[i], AMBIENT.r), maxf(g[i], AMBIENT.g), maxf(b[i], AMBIENT.b))


## Brightness 0..1 at a cell: the strongest channel.
func brightness(x: int, y: int) -> float:
	var c := at(x, y)
	return maxf(c.r, maxf(c.g, c.b))


func write_image() -> Image:
	var w := region.size.x
	var bytes := PackedByteArray()
	bytes.resize(r.size() * 3)
	for i in r.size():
		bytes[i * 3] = int(clampf(maxf(r[i], AMBIENT.r), 0.0, 1.0) * 255.0)
		bytes[i * 3 + 1] = int(clampf(maxf(g[i], AMBIENT.g), 0.0, 1.0) * 255.0)
		bytes[i * 3 + 2] = int(clampf(maxf(b[i], AMBIENT.b), 0.0, 1.0) * 255.0)
	image.set_data(w, region.size.y, false, Image.FORMAT_RGB8, bytes)
	return image
