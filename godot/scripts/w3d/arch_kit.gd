class_name ArchKit
extends RefCounted
## Starfall Haven architecture, built from code so every building shares one
## design language (ART_BIBLE.md §5): warm white plaster walls on a sandstone
## plinth with sandstone quoins and string courses; glazed cobalt, teal or
## violet roofs with gold ridges and finials; tall arched windows of blue
## glass that glow at night; arched doors; balconies with railings and
## flower boxes; round towers with conical spires. Buildings are one mesh,
## a surface per material, origin at the ground centre, front facing +Z.

const TEX := "res://assets/textures/arch/"
const STOREY := 3.4
const ROOFS := {"cobalt": Color(0.17, 0.28, 0.56), "teal": Color(0.13, 0.38, 0.42), "violet": Color(0.3, 0.26, 0.48),
	"rose": Color(0.56, 0.3, 0.3)}

static var _mats := {}
## Window glass; its glow is set by the time of day (set_night).
static var glass: StandardMaterial3D


static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	if name.begins_with("roof_"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://scripts/shaders/arch_roof.gdshader")
		sm.set_shader_parameter("tiles", load(TEX + "roof.jpg"))
		sm.set_shader_parameter("tiles_n", load(TEX + "roof_n.jpg"))
		sm.set_shader_parameter("tint", ROOFS.get(name.substr(5), ROOFS.cobalt))
		m = sm
	else:
		var s := StandardMaterial3D.new()
		s.uv1_triplanar = true
		s.uv1_world_triplanar = true
		match name:
			"wall":
				s.albedo_texture = load(TEX + "plaster.jpg")
				s.normal_enabled = true
				s.normal_texture = load(TEX + "plaster_n.jpg")
				s.normal_scale = 0.5
				s.albedo_color = Color(0.93, 0.89, 0.83)
				s.uv1_scale = Vector3.ONE * 0.4
				s.roughness = 0.9
			"stone":
				s.albedo_texture = load(TEX + "sandstone.jpg")
				s.normal_enabled = true
				s.normal_texture = load(TEX + "sandstone_n.jpg")
				s.albedo_color = Color(1.05, 0.94, 0.78)
				s.uv1_scale = Vector3.ONE * 0.28
				s.roughness = 0.85
			"marble":
				s.albedo_texture = load(TEX + "marble.jpg")
				s.normal_enabled = true
				s.normal_texture = load(TEX + "marble_n.jpg")
				s.albedo_color = Color(1.05, 1.05, 1.08)
				s.uv1_scale = Vector3.ONE * 0.5
				s.roughness = 0.35
			"wood":
				s.albedo_texture = load(TEX + "wood.jpg")
				s.normal_enabled = true
				s.normal_texture = load(TEX + "wood_n.jpg")
				s.albedo_color = Color(0.78, 0.6, 0.52)
				s.uv1_scale = Vector3.ONE * 0.7
				s.roughness = 0.7
			"gold":
				s.uv1_triplanar = false
				s.albedo_color = Color(0.96, 0.76, 0.36)
				s.metallic = 0.85
				s.roughness = 0.28
			"slate":
				s.uv1_triplanar = false
				s.albedo_color = Color(0.3, 0.34, 0.44)
				s.roughness = 0.6
			"glass":
				s.uv1_triplanar = false
				s.albedo_color = Color(0.16, 0.24, 0.42)
				s.metallic = 0.3
				s.roughness = 0.12
				s.emission_enabled = true
				s.emission = Color(1.0, 0.74, 0.42)
				s.emission_energy_multiplier = 0.0
				glass = s
			"crystal":
				s.uv1_triplanar = false
				s.albedo_color = Color(0.62, 0.86, 1.0, 0.85)
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				s.emission_enabled = true
				s.emission = Color(0.4, 0.78, 1.0)
				s.emission_energy_multiplier = 1.4
				s.rim_enabled = true
				s.rim = 0.8
				s.roughness = 0.08
			"water":
				s.uv1_triplanar = false
				s.albedo_color = Color(0.3, 0.72, 0.85, 0.75)
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				s.roughness = 0.05
				s.metallic = 0.2
			"flowers":
				s.uv1_triplanar = false
				s.vertex_color_use_as_albedo = true
				s.roughness = 0.9
		m = s
	_mats[name] = m
	return m


## Windows glow warm after dark (0 day .. 1 night).
static func set_night(night: float) -> void:
	if glass:
		glass.emission_energy_multiplier = lerpf(0.15, 2.4, night)


# ------------------------------------------------------------ builder ---

## Accumulates geometry per material, then commits one mesh.
class Builder:
	var tools := {}

	func _st(m: String) -> SurfaceTool:
		if not tools.has(m):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[m] = st
		return tools[m]

	## One triangle facing `n` (wound to Godot's front face whatever the order).
	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, col := Color.WHITE) -> void:
		var st := _st(m)
		if (c - a).cross(b - a).dot(n) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		for p in [[a, ua], [b, ub], [c, uc]]:
			st.set_normal(n)
			st.set_uv(p[1])
			st.set_color(col)
			st.add_vertex(p[0])

	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col := Color.WHITE) -> void:
		tri(m, a, b, c, n, uv[0], uv[1], uv[2], col)
		tri(m, a, c, d, n, uv[0], uv[2], uv[3], col)

	## An oriented box: transform `t` (origin at the box's centre), `size`.
	func box(m: String, t: Transform3D, size: Vector3, col := Color.WHITE) -> void:
		var h := size * 0.5
		for axis in 3:
			for sgn in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var a := (axis + 1) % 3
				var b := (axis + 2) % 3
				var u := Vector3.ZERO
				u[a] = h[a]
				var v := Vector3.ZERO
				v[b] = h[b]
				var c := n * h[axis]
				quad(m, t * (c - u - v), t * (c + u - v), t * (c + u + v), t * (c - u + v),
					(t.basis * n).normalized(), [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col)

	## An upright frustum (cylinder when r0 == r1) from y0 to y1 about `at`.
	func frustum(m: String, at: Vector3, r0: float, r1: float, y0: float, y1: float, segs := 16, caps := true) -> void:
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var p0 := at + d0 * r0 + Vector3(0, y0, 0)
			var p1 := at + d1 * r0 + Vector3(0, y0, 0)
			var q0 := at + d0 * r1 + Vector3(0, y1, 0)
			var q1 := at + d1 * r1 + Vector3(0, y1, 0)
			var slope := (r0 - r1) / maxf(y1 - y0, 0.001)
			var n := ((d0 + d1) * 0.5 + Vector3(0, slope, 0)).normalized()
			var u0 := float(i) / segs * TAU * r0 / 3.6
			var u1 := float(i + 1) / segs * TAU * r0 / 3.6
			var sl := Vector2(r0 - r1, y1 - y0).length() / 3.6
			quad(m, p0, p1, q1, q0, n, [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, sl), Vector2(u0, sl)])
			if caps:
				if r1 > 0.001:
					tri(m, at + Vector3(0, y1, 0), q0, q1, Vector3.UP)
				if r0 > 0.001:
					tri(m, at + Vector3(0, y0, 0), p0, p1, Vector3.DOWN)

	## A flat arch-topped panel (a window or door shape) in the XY plane of
	## `t`, width w, straight height h, half-round top; facing t's +Z.
	func arch_panel(m: String, t: Transform3D, w: float, h: float, segs := 8) -> void:
		var n := (t.basis * Vector3.BACK).normalized()
		var r := w * 0.5
		quad(m, t * Vector3(-r, 0, 0), t * Vector3(r, 0, 0), t * Vector3(r, h, 0), t * Vector3(-r, h, 0), n)
		for i in segs:
			var a0 := PI * i / segs
			var a1 := PI * (i + 1) / segs
			tri(m, t * Vector3(0, h, 0), t * Vector3(cos(a0) * r, h + sin(a0) * r, 0), t * Vector3(cos(a1) * r, h + sin(a1) * r, 0), n)

	## A raised arched frame (stone surround) round an arch_panel opening.
	func arch_frame(m: String, t: Transform3D, w: float, h: float, thick := 0.14, depth := 0.12, segs := 8) -> void:
		var r := w * 0.5 + thick * 0.5
		for sx in [-1.0, 1.0]:
			box(m, t * Transform3D(Basis.IDENTITY, Vector3(sx * r, h * 0.5, depth * 0.5)), Vector3(thick, h, depth))
		for i in segs:
			var a := PI * (i + 0.5) / segs
			var seg := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * r, h + sin(a) * r, depth * 0.5))
			box(m, t * seg, Vector3(thick, PI * r / segs + 0.02, depth))
		# Sill and keystone.
		box(m, t * Transform3D(Basis.IDENTITY, Vector3(0, -0.06, depth * 0.6)), Vector3(w + thick * 2.4, 0.12, depth * 1.4))
		box(m, t * Transform3D(Basis.IDENTITY, Vector3(0, h + r, depth * 0.6)), Vector3(0.2, 0.28, depth * 1.3))

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for k in tools:
			(tools[k] as SurfaceTool).commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, ArchKit.material(k))
		return mesh


# ---------------------------------------------------------- buildings ---

## A town house: `w` wide (x), `d` deep (z), `floors` storeys, a hipped or
## gabled roof in `roof` colour; optional balcony, round corner tower,
## chimney. `seed` varies the details.
static func house(w: float, d: float, floors: int, roof: String, opts := {}) -> ArrayMesh:
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var wall_h := floors * STOREY
	var plinth := 0.7
	# Plinth, walls, string courses, quoins.
	b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, plinth * 0.5 - 0.3, 0)), Vector3(w + 0.3, plinth + 0.6, d + 0.3))
	b.box("wall", Transform3D(Basis.IDENTITY, Vector3(0, plinth + (wall_h - plinth) * 0.5, 0)), Vector3(w, wall_h - plinth, d))
	for f in range(1, floors):
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, f * STOREY, 0)), Vector3(w + 0.16, 0.22, d + 0.16))
	b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, wall_h - 0.12, 0)), Vector3(w + 0.24, 0.28, d + 0.24))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var y := plinth + 0.25
			var k := 0
			while y < wall_h - 0.3:
				var big := k % 2 == 0
				var qx := 0.62 if big else 0.4
				b.box("stone", Transform3D(Basis.IDENTITY, Vector3(cx * (w * 0.5 - qx * 0.5 + 0.06), y, cz * (d * 0.5 - (0.4 if big else 0.62) * 0.5 + 0.06))),
					Vector3(qx, 0.42, 0.4 if big else 0.62))
				y += 0.46
				k += 1
	# Windows on every face; the front's ground floor gets the door.
	var faces := [[Vector3.BACK, w, d], [Vector3.FORWARD, w, d], [Vector3.RIGHT, d, w], [Vector3.LEFT, d, w]]
	for fc in faces:
		var n: Vector3 = fc[0]
		var span: float = fc[1]
		var depth: float = fc[2]
		var basis := Basis.looking_at(-n, Vector3.UP)
		var count := maxi(1, int(span / 2.6))
		for f in floors:
			for i in count:
				var x := (i - (count - 1) * 0.5) * (span / count)
				var door := n == Vector3.BACK and f == 0 and i == count / 2
				var wdt := 1.5 if door else 0.95
				var hgt := 2.1 if door else 1.6
				var y0 := plinth + 0.05 if door else f * STOREY + plinth + 0.55
				var t := Transform3D(basis, n * (depth * 0.5 + 0.01) + basis * Vector3(x, y0, 0))
				b.arch_panel("wood" if door else "glass", t, wdt, hgt)
				b.arch_frame("stone", t, wdt, hgt)
				if not door and f > 0 and rng.randf() < 0.45:
					# A flower box under the window.
					b.box("wood", t * Transform3D(Basis.IDENTITY, Vector3(0, -0.22, 0.2)), Vector3(wdt + 0.3, 0.26, 0.34))
					for p in 6:
						var hue: Color = [Color(1.0, 0.5, 0.65), Color(1.0, 0.86, 0.3), Color(0.7, 0.55, 1.0), Color(1, 1, 1)][rng.randi() % 4]
						b.box("flowers", t * Transform3D(Basis.IDENTITY, Vector3((p - 2.5) * (wdt + 0.1) / 6.0, -0.02, 0.22)), Vector3(0.16, 0.16, 0.16), hue)
				if door:
					# Steps and a little canopy over the door.
					b.box("stone", t * Transform3D(Basis.IDENTITY, Vector3(0, -0.4, 0.45)), Vector3(wdt + 1.0, 0.3, 0.9))
					b.box("stone", t * Transform3D(Basis.IDENTITY, Vector3(0, -0.6, 0.85)), Vector3(wdt + 1.4, 0.3, 0.9))
					b.box("gold", t * Transform3D(Basis.IDENTITY, Vector3(0, hgt + wdt * 0.5 + 0.35, 0.12)), Vector3(0.18, 0.18, 0.1))
	# Balcony on the upper front.
	if floors >= 2 and opts.get("balcony", true):
		var by := STOREY + 0.05
		var bw := minf(w * 0.55, 4.2)
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, by, d * 0.5 + 0.55)), Vector3(bw, 0.2, 1.1))
		for i in 9:
			var x := (i - 4) * bw / 8.5
			b.box("gold", Transform3D(Basis.IDENTITY, Vector3(x, by + 0.5, d * 0.5 + 1.05)), Vector3(0.06, 0.85, 0.06))
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, by + 0.95, d * 0.5 + 1.05)), Vector3(bw, 0.1, 0.12))
		for sx in [-1.0, 1.0]:
			b.box("stone", Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(sx * bw * 0.35, by - 0.45, d * 0.5 + 0.3)), Vector3(0.18, 0.18, 1.0))
	# Roof.
	var ov := 0.45
	var rw := w * 0.5 + ov
	var rd := d * 0.5 + ov
	var rh := minf(w, d) * 0.55 + 0.6
	var top := wall_h
	var rm := "roof_" + roof
	if opts.get("roof_style", "hip") == "hip":
		var ridge := maxf(rw - rd, 0.0) if rw > rd else 0.0
		var ridge_z := maxf(rd - rw, 0.0)
		var A := Vector3(-rw, top, rd)
		var B := Vector3(rw, top, rd)
		var C := Vector3(rw, top, -rd)
		var D := Vector3(-rw, top, -rd)
		var R0 := Vector3(-ridge, top + rh, -ridge_z) if rw > rd else Vector3(0, top + rh, -ridge_z)
		var R1 := Vector3(ridge, top + rh, ridge_z) if rw > rd else Vector3(0, top + rh, ridge_z)
		if rw > rd:
			R0 = Vector3(-ridge, top + rh, 0)
			R1 = Vector3(ridge, top + rh, 0)
		_roof_quad(b, rm, A, B, R1, R0, Vector3(0, rw, rh).normalized())
		_roof_quad(b, rm, C, D, R0, R1, Vector3(0, rw, -rh).normalized())
		_roof_tri(b, rm, B, C, R1, Vector3(rh, rd, 0).normalized())
		_roof_tri(b, rm, D, A, R0, Vector3(-rh, rd, 0).normalized())
		b.box("gold", Transform3D(Basis.IDENTITY, (R0 + R1) * 0.5 + Vector3(0, 0.08, 0)), Vector3(maxf((R1 - R0).length(), 0.3) + 0.2, 0.16, 0.16))
		for rp in [R0, R1]:
			_finial(b, rp)
	else:
		var R0 := Vector3(-rw, top + rh, 0)
		var R1 := Vector3(rw, top + rh, 0)
		_roof_quad(b, rm, Vector3(-rw, top, rd), Vector3(rw, top, rd), R1, R0, Vector3(0, rd, rh).normalized())
		_roof_quad(b, rm, Vector3(rw, top, -rd), Vector3(-rw, top, -rd), R0, R1, Vector3(0, rd, -rh).normalized())
		for sx in [-1.0, 1.0]:
			var x: float = sx * w * 0.5
			b.tri("wall", Vector3(x, top, d * 0.5), Vector3(x, top, -d * 0.5), Vector3(x, top + rh - 0.3, 0), Vector3(sx, 0, 0))
			# A round window in the gable.
			var t := Transform3D(Basis.looking_at(Vector3(-sx, 0, 0), Vector3.UP), Vector3(x + sx * 0.02, top + rh * 0.35, 0))
			b.arch_panel("glass", t, 0.7, 0.01)
		b.box("gold", Transform3D(Basis.IDENTITY, Vector3(0, top + rh + 0.08, 0)), Vector3(rw * 2.0 + 0.2, 0.16, 0.16))
		_finial(b, R0)
		_finial(b, R1)
	# A round corner tower with a spire.
	if opts.get("tower", false):
		var tr := minf(w, d) * 0.26
		var tc := Vector3(w * 0.5, 0, d * 0.5)
		var th := wall_h + STOREY * 1.2
		b.frustum("stone", tc, tr + 0.2, tr + 0.2, -0.3, plinth, 20)
		b.frustum("wall", tc, tr, tr, plinth, th, 20, false)
		b.frustum("stone", tc, tr + 0.14, tr + 0.14, th - 0.3, th, 20)
		b.frustum(rm, tc, tr + 0.5, 0.06, th, th + tr * 3.0, 20)
		_finial(b, tc + Vector3(0, th + tr * 3.0, 0))
		for i in 3:
			var a := PI * 0.25 + i * PI * 0.5
			var dir := Vector3(cos(a), 0, sin(a))
			var t := Transform3D(Basis.looking_at(-dir, Vector3.UP), tc + dir * (tr + 0.01) + Vector3(0, th - STOREY * 0.9, 0))
			b.arch_panel("glass", t, 0.7, 1.2)
			b.arch_frame("stone", t, 0.7, 1.2, 0.12, 0.1)
	if opts.get("chimney", true):
		var cx := -w * 0.25
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(cx, top + rh * 0.7, -d * 0.15)), Vector3(0.7, rh * 1.2, 0.7))
		b.box("slate", Transform3D(Basis.IDENTITY, Vector3(cx, top + rh * 1.3 + 0.05, -d * 0.15)), Vector3(0.9, 0.14, 0.9))
	return b.commit()


static func _roof_quad(b: Builder, m: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	var along := (p1 - p0).normalized()
	var up_s := (p3 - p0)
	var uv := func(p: Vector3) -> Vector2: return Vector2((p - p0).dot(along), (p - p0).dot(up_s.normalized())) / 3.6
	b.quad(m, p0, p1, p2, p3, n, [uv.call(p0), uv.call(p1), uv.call(p2), uv.call(p3)])
	# Thickness: an eave fascia below the edge.
	b.quad("slate", p0, p1, p1 + Vector3(0, -0.18, 0), p0 + Vector3(0, -0.18, 0), Vector3(n.x, 0, n.z).normalized())


static func _roof_tri(b: Builder, m: String, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3) -> void:
	var along := (p1 - p0).normalized()
	var mid := (p0 + p1) * 0.5
	var up_s := (p2 - mid).normalized()
	var uv := func(p: Vector3) -> Vector2: return Vector2((p - p0).dot(along), (p - mid).dot(up_s)) / 3.6
	b.tri(m, p0, p1, p2, n, uv.call(p0), uv.call(p1), uv.call(p2))
	b.quad("slate", p0, p1, p1 + Vector3(0, -0.18, 0), p0 + Vector3(0, -0.18, 0), Vector3(n.x, 0, n.z).normalized())


## A gold spike with a ball.
static func _finial(b: Builder, at: Vector3) -> void:
	b.frustum("gold", at, 0.1, 0.02, 0.0, 0.9, 8)
	b.frustum("gold", at + Vector3(0, 0.45, 0), 0.14, 0.14, 0.0, 0.2, 8)


## A tall round watchtower / bell tower (landmark), `h` metres.
static func tower(r: float, h: float, roof: String) -> ArrayMesh:
	var b := Builder.new()
	b.frustum("stone", Vector3.ZERO, r + 0.5, r + 0.3, -0.4, 1.2, 24)
	b.frustum("wall", Vector3.ZERO, r, r * 0.9, 1.2, h, 24, false)
	var y := 1.2
	while y < h - 1.0:
		b.frustum("stone", Vector3.ZERO, r * lerpf(1.0, 0.9, y / h) + 0.1, r * lerpf(1.0, 0.9, y / h) + 0.1, y, y + 0.22, 24)
		for i in 4:
			var a := TAU * i / 4.0 + y
			var rr := r * lerpf(1.0, 0.9, (y + 1.5) / h)
			var dir := Vector3(cos(a), 0, sin(a))
			var t := Transform3D(Basis.looking_at(-dir, Vector3.UP), dir * (rr + 0.01) + Vector3(0, y + 0.8, 0))
			b.arch_panel("glass", t, 0.8, 1.4)
			b.arch_frame("stone", t, 0.8, 1.4, 0.12, 0.1)
		y += 4.2
	# Belvedere: an open ring of columns under the spire.
	var rt := r * 0.9
	b.frustum("stone", Vector3.ZERO, rt + 0.4, rt + 0.4, h, h + 0.4, 24)
	for i in 8:
		var a := TAU * i / 8.0
		b.frustum("marble", Vector3(cos(a), 0, sin(a)) * rt, 0.22, 0.22, h + 0.4, h + 3.2, 10)
	b.frustum("stone", Vector3.ZERO, rt + 0.5, rt + 0.5, h + 3.2, h + 3.6, 24)
	b.frustum("crystal", Vector3(0, h + 0.4, 0), 0.0, 0.7, 0.0, 1.4, 6)
	b.frustum("crystal", Vector3(0, h + 1.8, 0), 0.7, 0.0, 0.0, 1.4, 6)
	b.frustum("roof_" + roof, Vector3.ZERO, rt + 1.0, 0.08, h + 3.6, h + 3.6 + rt * 3.4, 24)
	_finial(b, Vector3(0, h + 3.6 + rt * 3.4, 0))
	return b.commit()


## The plaza's centrepiece: a tiered marble fountain with a floating star
## crystal turning above it, water in its basins.
static func star_fountain() -> ArrayMesh:
	var b := Builder.new()
	b.frustum("stone", Vector3.ZERO, 5.4, 5.4, -0.3, 0.25, 32)
	b.frustum("marble", Vector3.ZERO, 5.0, 5.0, 0.25, 0.9, 32, false)
	b.frustum("marble", Vector3.ZERO, 5.2, 5.2, 0.9, 1.05, 32)
	b.frustum("water", Vector3.ZERO, 4.8, 4.8, 0.3, 0.75, 32)
	b.frustum("marble", Vector3.ZERO, 0.9, 0.7, 0.25, 2.6, 16)
	b.frustum("marble", Vector3.ZERO, 0.5, 2.3, 2.6, 3.0, 24)
	b.frustum("marble", Vector3.ZERO, 2.3, 2.4, 3.0, 3.25, 24)
	b.frustum("water", Vector3.ZERO, 2.1, 2.1, 2.9, 3.15, 24)
	b.frustum("marble", Vector3.ZERO, 0.45, 0.3, 3.25, 4.6, 12)
	b.frustum("gold", Vector3.ZERO, 0.3, 0.9, 4.6, 4.9, 12)
	for i in 8:
		var a := TAU * i / 8.0
		b.frustum("gold", Vector3(cos(a), 0, sin(a)) * 5.1, 0.12, 0.12, 1.05, 1.3, 8)
	return b.commit()


## The floating crystal over the fountain (a separate mesh so it can turn).
static func star_crystal() -> ArrayMesh:
	var b := Builder.new()
	b.frustum("crystal", Vector3.ZERO, 0.0, 0.9, -1.6, 0.0, 6)
	b.frustum("crystal", Vector3.ZERO, 0.9, 0.0, 0.0, 2.2, 6)
	for i in 4:
		var a := TAU * i / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 1.9
		b.frustum("crystal", p, 0.0, 0.25, -0.5, 0.0, 5)
		b.frustum("crystal", p, 0.25, 0.0, 0.0, 0.7, 5)
	return b.commit()


## The town gate: two stone pylons with spires and an arch between them.
static func gate(span: float) -> ArrayMesh:
	var b := Builder.new()
	var h := 6.5
	for sx in [-1.0, 1.0]:
		var x: float = sx * (span * 0.5 + 0.8)
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(x, 0.4, 0)), Vector3(2.0, 1.2, 2.0))
		b.box("wall", Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5 + 0.4, 0)), Vector3(1.6, h, 1.6))
		b.box("stone", Transform3D(Basis.IDENTITY, Vector3(x, h + 0.55, 0)), Vector3(1.9, 0.3, 1.9))
		b.frustum("roof_cobalt", Vector3(x, 0, 0), 1.3, 0.05, h + 0.7, h + 3.6, 4)
		_finial(b, Vector3(x, h + 3.6, 0))
	var r := span * 0.5 + 0.35
	var spring := h - r - 0.4
	for i in 16:
		var a := PI * (i + 0.5) / 16.0
		var t := Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * r, spring + sin(a) * r, 0))
		b.box("stone", t, Vector3(0.55, PI * r / 16.0 + 0.06, 1.3))
	# A lintel band over the arch, and the star emblem on its keystone.
	b.box("stone", Transform3D(Basis.IDENTITY, Vector3(0, h + 0.05, 0)), Vector3(span + 1.6, 0.6, 1.3))
	b.box("gold", Transform3D(Basis(Vector3.BACK, PI * 0.25), Vector3(0, h - 0.5, 0.68)), Vector3(0.7, 0.7, 0.08))
	return b.commit()
