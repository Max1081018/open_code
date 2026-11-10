class_name UIDraw
extends RefCounted
## Shared drawing kit for every in-game HUD, so buttons, pills, cards and bars
## look the same everywhere. All functions draw onto a CanvasItem from inside its
## _draw(). Icons are simple vector shapes, so there are no image files and no
## missing-glyph boxes.

const BTN_FILL := Color(0.035, 0.075, 0.14, 0.58)
const BTN_RING := Color(1, 1, 1, 0.55)
const INK := Color(0.12, 0.07, 0.03)          # dark text on the coral accent


static var _boxes := {}


## Style boxes are cached by look, so HUDs that redraw every frame don't
## allocate new ones each time.
static func pill(ci: CanvasItem, rect: Rect2, color: Color, radius := 22.0,
		border := Color(1, 1, 1, 0.12), border_w := 2) -> void:
	var key := "%s|%d|%s|%d" % [color.to_html(), int(radius), border.to_html(), border_w]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		if _boxes.size() > 256:
			_boxes.clear()
		sb = StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(int(radius))
		sb.set_border_width_all(border_w)
		sb.border_color = border
		sb.anti_aliasing = true
		_boxes[key] = sb
	ci.draw_style_box(sb, rect)


static func text_c(ci: CanvasItem, font: Font, text: String, centre: Vector2, size: int,
		color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, Vector2(centre.x - w * 0.5, centre.y + size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_w(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A rounded progress bar. `value` 0..1.
static func bar(ci: CanvasItem, rect: Rect2, value: float, fill: Color,
		back := Color(0, 0, 0, 0.45)) -> void:
	var r := rect.size.y * 0.5
	pill(ci, rect, back, r, Color(1, 1, 1, 0.10), 1)
	var v := clampf(value, 0.0, 1.0)
	if v > 0.001:
		var w := maxf(rect.size.y, rect.size.x * v)
		pill(ci, Rect2(rect.position, Vector2(w, rect.size.y)), fill, r, Color(0, 0, 0, 0), 0)


## A circular touch button with an icon and a short label under it.
## `primary` paints it in the coral accent (the thing you'll want to press).
static func round_button(ci: CanvasItem, font: Font, centre: Vector2, r: float,
		label: String, icon_kind: String, primary := false, pressed := false,
		opacity := 1.0) -> void:
	var fill := UITheme.ACCENT if primary else BTN_FILL
	if pressed:
		fill = UITheme.ACCENT_LO if primary else Color(0.10, 0.18, 0.28, 0.75)
	fill.a *= opacity
	# soft drop shadow
	ci.draw_circle(centre + Vector2(0, 4), r, Color(0, 0, 0, 0.22 * opacity))
	ci.draw_circle(centre, r, fill)
	var ring := Color(1, 1, 1, 0.85 if primary else 0.55)
	ring.a *= opacity
	ci.draw_arc(centre, r - 1.5, 0, TAU, 64, ring, 3.0, true)
	var ink := INK if primary else Color(1, 1, 1, 0.95)
	ink.a *= opacity
	var has_label := label != ""
	var icon_c := centre + Vector2(0, -r * 0.16 if has_label else 0.0)
	icon(ci, icon_kind, icon_c, r * (0.40 if has_label else 0.52), ink)
	if has_label:
		var fs := int(clampf(r * 0.24, 14.0, 24.0))
		while fs > 12 and text_w(font, label, fs) > r * 1.55:
			fs -= 1
		text_c(ci, font, label, centre + Vector2(0, r * 0.47), fs, ink)


## Small vector icons. `s` is roughly the half-size.
static func icon(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.0, s * 0.16)
	match kind:
		"fish":
			_ellipse(ci, c + Vector2(-s * 0.12, 0), s * 0.62, s * 0.36, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.42, 0), c + Vector2(s * 0.85, -s * 0.38), c + Vector2(s * 0.85, s * 0.38)]), col)
		"cast":   # rod arc with a hook
			ci.draw_arc(c + Vector2(-s * 0.2, s * 0.5), s * 0.9, -PI * 0.5, -PI * 0.05, 18, col, w, true)
			ci.draw_line(c + Vector2(s * 0.68, s * 0.35), c + Vector2(s * 0.68, s * 0.75), col, w * 0.7, true)
			ci.draw_arc(c + Vector2(s * 0.52, s * 0.75), s * 0.16, 0, PI, 10, col, w * 0.7, true)
		"reel":
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, col, w, true)
			ci.draw_circle(c, s * 0.18, col)
			ci.draw_line(c, c + Vector2(s * 0.55, -s * 0.55), col, w, true)
			ci.draw_circle(c + Vector2(s * 0.62, -s * 0.62), s * 0.16, col)
		"whack":  # mallet
			var head := Rect2(c + Vector2(-s * 0.75, -s * 0.72), Vector2(s * 1.0, s * 0.55))
			ci.draw_rect(head, col)
			ci.draw_line(c + Vector2(-s * 0.25, -s * 0.2), c + Vector2(s * 0.55, s * 0.75), col, w * 1.2, true)
		"hand":   # grab
			ci.draw_circle(c + Vector2(0, s * 0.18), s * 0.42, col)
			for i in 4:
				var x := -s * 0.36 + i * s * 0.24
				ci.draw_line(c + Vector2(x, 0), c + Vector2(x, -s * 0.62 + absf(i - 1.5) * s * 0.1), col, w * 1.1, true)
			ci.draw_line(c + Vector2(-s * 0.42, s * 0.12), c + Vector2(-s * 0.72, -s * 0.15), col, w * 1.1, true)
		"drop":
			ci.draw_line(c + Vector2(0, -s * 0.7), c + Vector2(0, s * 0.45), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.45, s * 0.15), c + Vector2(s * 0.45, s * 0.15), c + Vector2(0, s * 0.7)]), col)
		"coin":
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, col, w * 1.1, true)
			ci.draw_arc(c, s * 0.34, PI * 0.25, PI * 1.75, 16, col, w, true)
		"boat":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.85, s * 0.22), c + Vector2(s * 0.85, s * 0.22),
				c + Vector2(s * 0.55, s * 0.62), c + Vector2(-s * 0.55, s * 0.62)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.05, -s * 0.75), c + Vector2(-s * 0.05, s * 0.12), c + Vector2(s * 0.6, s * 0.12)]), col)
		"run":    # double chevron
			for k in 2:
				var o := Vector2(-s * 0.32 + k * s * 0.5, 0)
				ci.draw_polyline(PackedVector2Array([
					c + o + Vector2(-s * 0.22, -s * 0.5), c + o + Vector2(s * 0.22, 0), c + o + Vector2(-s * 0.22, s * 0.5)]),
					col, w * 1.2, true)
		"back":
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(s * 0.15, -s * 0.55), c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.15, s * 0.55)]),
				col, w * 1.2, true)
			ci.draw_line(c + Vector2(-s * 0.35, 0), c + Vector2(s * 0.6, 0), col, w * 1.2, true)
		"buy":    # bag
			ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.25), Vector2(s * 1.1, s * 0.9)), col)
			ci.draw_arc(c + Vector2(0, -s * 0.25), s * 0.32, PI, TAU, 14, col, w, true)
		"equip":  # check mark
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-s * 0.55, 0), c + Vector2(-s * 0.12, s * 0.45), c + Vector2(s * 0.6, -s * 0.45)]),
				col, w * 1.4, true)
		"lock":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.05), Vector2(s * 1.0, s * 0.75)), col)
			ci.draw_arc(c + Vector2(0, -s * 0.05), s * 0.32, PI, TAU, 14, col, w, true)
		"heart":
			ci.draw_circle(c + Vector2(-s * 0.3, -s * 0.15), s * 0.36, col)
			ci.draw_circle(c + Vector2(s * 0.3, -s * 0.15), s * 0.36, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.64, -s * 0.02), c + Vector2(s * 0.64, -s * 0.02), c + Vector2(0, s * 0.7)]), col)
		"bubble":
			ci.draw_arc(c, s * 0.55, 0, TAU, 20, col, w, true)
			ci.draw_arc(c + Vector2(-s * 0.18, -s * 0.18), s * 0.18, PI, PI * 1.6, 8, col, w * 0.8, true)
		"fist":   # knuckles from the front
			ci.draw_rect(Rect2(c + Vector2(-s * 0.55, -s * 0.30), Vector2(s * 1.1, s * 0.75)), col)
			for i in 4:
				ci.draw_circle(c + Vector2(-s * 0.41 + i * s * 0.275, -s * 0.30), s * 0.15, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.62, s * 0.05), Vector2(s * 0.42, s * 0.20)), col)
		"rod":    # rod with a reel and a hanging hook
			ci.draw_line(c + Vector2(-s * 0.70, s * 0.70), c + Vector2(s * 0.62, -s * 0.70), col, w, true)
			ci.draw_arc(c + Vector2(-s * 0.30, s * 0.42), s * 0.20, 0, TAU, 14, col, w * 0.8, true)
			ci.draw_line(c + Vector2(s * 0.62, -s * 0.70), c + Vector2(s * 0.62, -s * 0.05), col, maxf(1.0, w * 0.4), true)
			ci.draw_arc(c + Vector2(s * 0.52, -s * 0.05), s * 0.10, 0, PI, 8, col, maxf(1.0, w * 0.5), true)
		"dagger":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-s * 0.08, s * 0.10), c + Vector2(s * 0.08, s * 0.10), c + Vector2(0, -s * 0.78)]), col)
			ci.draw_line(c + Vector2(-s * 0.32, s * 0.16), c + Vector2(s * 0.32, s * 0.16), col, w, true)
			ci.draw_line(c + Vector2(0, s * 0.16), c + Vector2(0, s * 0.70), col, w * 1.3, true)
		"axe":
			ci.draw_line(c + Vector2(-s * 0.45, s * 0.72), c + Vector2(s * 0.30, -s * 0.62), col, w * 1.1, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(s * 0.12, -s * 0.70), c + Vector2(s * 0.70, -s * 0.52),
				c + Vector2(s * 0.62, -s * 0.05), c + Vector2(s * 0.26, -s * 0.22)]), col)
		"grips":  # knuckle duster rings
			for i in 3:
				ci.draw_arc(c + Vector2(-s * 0.42 + i * s * 0.42, -s * 0.05), s * 0.20, 0, TAU, 14, col, w * 0.8, true)
			ci.draw_line(c + Vector2(-s * 0.62, s * 0.28), c + Vector2(s * 0.62, s * 0.28), col, w * 1.2, true)
		"clam":   # scallop fan with ridges
			var pts := PackedVector2Array([c + Vector2(0, s * 0.55)])
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				pts.append(c + Vector2(cos(a) * s * 0.66, sin(a) * s * 0.62 + s * 0.12))
			ci.draw_colored_polygon(pts, col)
			var ink := Color(0, 0, 0, 0.35 * col.a)
			for i in 4:
				var a := PI + PI * (float(i) + 1.0) / 5.0
				ci.draw_line(c + Vector2(0, s * 0.50), c + Vector2(cos(a) * s * 0.58, sin(a) * s * 0.55 + s * 0.12), ink, maxf(1.0, w * 0.45), true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.16, s * 0.48), Vector2(s * 0.32, s * 0.16)), col)
		"jump":   # chevron up over a bar
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-s * 0.5, s * 0.05), c + Vector2(0, -s * 0.5), c + Vector2(s * 0.5, s * 0.05)]),
				col, w * 1.3, true)
			ci.draw_line(c + Vector2(-s * 0.45, s * 0.5), c + Vector2(s * 0.45, s * 0.5), col, w * 1.1, true)
		"hook":
			ci.draw_line(c + Vector2(s * 0.18, -s * 0.72), c + Vector2(s * 0.18, s * 0.20), col, w, true)
			ci.draw_arc(c + Vector2(-s * 0.08, s * 0.20), s * 0.26, 0, PI, 12, col, w, true)
			ci.draw_line(c + Vector2(-s * 0.34, s * 0.20), c + Vector2(-s * 0.34, -s * 0.05), col, w, true)
		_:
			ci.draw_circle(c, s * 0.3, col)


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)
