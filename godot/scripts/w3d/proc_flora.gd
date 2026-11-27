class_name ProcFlora
extends RefCounted
## Plants and crystals built in code, for the kinds no model pack provides.
## Kinds (FoliageLib "P:<name>"):
##   palm        curved ringed trunk, nine drooping two-sided fronds
##   glowflower  a slim stem and a cup of petals that glow at night
##   crystal     a cluster of tilted hexagonal crystals with pointed tips
##   cactus      a ribbed column with two raised arms
##   giant_root  an arching buttress root (jungle floor)
## Each mesh is built at unit height; FoliageLib scales it to the kind's size.

const KINDS := {
	"palm": [11.0, "tree"], "glowflower": [0.7, "small"], "crystal": [3.2, "formation"],
	"cactus": [3.0, "tree"], "giant_root": [3.5, "formation"],
}


static func mesh(name: String) -> ArrayMesh:
	match name:
		"palm":
			return _palm()
		"glowflower":
			return _glowflower()
		"crystal":
			return _crystal()
		"cactus":
			return _cactus()
		"giant_root":
			return _root()
	return ArrayMesh.new()


static func _mat(col: Color, rough := 0.85, double := false, glow := Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 1.4
	return m


## A tube along `spine` with radii `radii`, `sides` round.
static func _tube(st: SurfaceTool, spine: Array, radii: Array, sides: int, cols: Array) -> void:
	for i in spine.size() - 1:
		var a: Vector3 = spine[i]
		var b: Vector3 = spine[i + 1]
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(axis).normalized()
		for k in sides:
			var t0 := TAU * k / sides
			var t1 := TAU * (k + 1) / sides
			var d0 := side * cos(t0) + up * sin(t0)
			var d1 := side * cos(t1) + up * sin(t1)
			var p00: Vector3 = a + d0 * float(radii[i])
			var p01: Vector3 = a + d1 * float(radii[i])
			var p10: Vector3 = b + d0 * float(radii[i + 1])
			var p11: Vector3 = b + d1 * float(radii[i + 1])
			var c0: Color = cols[i]
			var c1: Color = cols[i + 1]
			for v in [[p00, d0, c0], [p10, d0, c1], [p11, d1, c1], [p00, d0, c0], [p11, d1, c1], [p01, d1, c0]]:
				st.set_color(v[2])
				st.set_normal(v[1])
				st.add_vertex(v[0])


static func _palm() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine := []
	var radii := []
	var cols := []
	var n := 12
	for i in n + 1:
		var t := float(i) / n
		spine.append(Vector3(0.16 * t * t, t, 0.0))
		radii.append(lerpf(0.032, 0.02, t) * (1.0 + (0.12 if i % 2 == 0 else 0.0)))
		cols.append(Color(0.52, 0.4, 0.28).lerp(Color(0.66, 0.54, 0.38), float(i % 2)))
	_tube(st, spine, radii, 7, cols)
	st.commit(am)
	am.surface_set_material(0, _mat(Color.WHITE, 0.95))
	# Fronds.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Vector3 = spine[n]
	for f in 9:
		var a := TAU * f / 9.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP).normalized()
		var lift := 0.08 + (f % 3) * 0.04
		var seg := 8
		var prev := []
		for s in seg + 1:
			var u := float(s) / seg
			var c := top + dir * u * 0.48 + Vector3.UP * (lift * u - 0.34 * u * u)
			var w := 0.085 * sin(PI * minf(u * 1.1, 1.0)) + 0.008
			var vein := c + Vector3.UP * 0.012
			var col := Color(0.2, 0.42, 0.16).lerp(Color(0.42, 0.66, 0.24), u)
			var row := [c - side * w - Vector3.UP * 0.02 * u, vein, c + side * w - Vector3.UP * 0.02 * u, col]
			if s > 0:
				for k in 2:
					var a0: Vector3 = prev[k]
					var a1: Vector3 = prev[k + 1]
					var b0: Vector3 = row[k]
					var b1: Vector3 = row[k + 1]
					var nrm := (b0 - a0).cross(a1 - a0).normalized()
					if nrm.y < 0.0:
						nrm = -nrm
					for v in [[a0, prev[3]], [b0, col], [b1, col], [a0, prev[3]], [b1, col], [a1, prev[3]]]:
						st.set_color(v[1])
						st.set_normal(nrm)
						st.add_vertex(v[0])
			prev = row
	st.commit(am)
	am.surface_set_material(1, _mat(Color.WHITE, 0.7, true))
	return am


static func _glowflower() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, [Vector3.ZERO, Vector3(0.03, 0.5, 0), Vector3(0.0, 0.82, 0.02)], [0.025, 0.02, 0.015], 5,
		[Color(0.2, 0.45, 0.25), Color(0.25, 0.5, 0.3), Color(0.3, 0.55, 0.35)])
	st.commit(am)
	am.surface_set_material(0, _mat(Color.WHITE))
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0.0, 0.82, 0.02)
	for p in 6:
		var a := TAU * p / 6.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP)
		var tip := c + dir * 0.2 + Vector3.UP * 0.12
		var l := c + dir * 0.09 + side * 0.07 + Vector3.UP * 0.02
		var r := c + dir * 0.09 - side * 0.07 + Vector3.UP * 0.02
		for v in [[c, Color(1, 1, 1)], [l, Color(0.6, 0.9, 1.0)], [tip, Color(0.75, 0.55, 1.0)], [c, Color(1, 1, 1)], [tip, Color(0.75, 0.55, 1.0)], [r, Color(0.6, 0.9, 1.0)]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	st.commit(am)
	am.surface_set_material(1, _mat(Color.WHITE, 0.5, true, Color(0.45, 0.6, 1.0)))
	return am


static func _crystal() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf() * 0.5
		var tilt := 0.0 if k == 0 else rng.randf_range(0.25, 0.6)
		var axis := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt)).normalized()
		var base := Vector3(cos(a), 0, sin(a)) * (0.0 if k == 0 else 0.12)
		var length := 1.0 if k == 0 else rng.randf_range(0.45, 0.8)
		var r := 0.11 if k == 0 else rng.randf_range(0.05, 0.08)
		var side := axis.cross(Vector3.FORWARD).normalized()
		var up := side.cross(axis)
		var top := base + axis * length * 0.82
		var tip := base + axis * length
		for s in 6:
			var t0 := TAU * s / 6.0
			var t1 := TAU * (s + 1) / 6.0
			var d0 := side * cos(t0) + up * sin(t0)
			var d1 := side * cos(t1) + up * sin(t1)
			var col := Color(0.55, 0.95, 1.0).lerp(Color(0.85, 0.7, 1.0), float(s % 2) * 0.5)
			for v in [[base + d0 * r, d0], [top + d0 * r, d0], [top + d1 * r, d1], [base + d0 * r, d0], [top + d1 * r, d1], [base + d1 * r, d1]]:
				st.set_color(col)
				st.set_normal(v[1])
				st.add_vertex(v[0])
			var nt := (d0 + d1).normalized().lerp(axis, 0.5).normalized()
			for v in [top + d0 * r, tip, top + d1 * r]:
				st.set_color(Color(0.95, 1.0, 1.0))
				st.set_normal(nt)
				st.add_vertex(v)
	st.commit(am)
	var m := _mat(Color(1, 1, 1, 0.88), 0.08, false, Color(0.3, 0.75, 1.0))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.3
	m.rim_enabled = true
	m.rim = 0.9
	am.surface_set_material(0, m)
	return am


static func _cactus() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := Color(0.36, 0.52, 0.3)
	_tube(st, [Vector3.ZERO, Vector3(0, 0.5, 0), Vector3(0, 0.92, 0), Vector3(0, 1.0, 0)], [0.09, 0.09, 0.085, 0.04], 8, [g, g, g.lightened(0.1), g.lightened(0.15)])
	_tube(st, [Vector3(0, 0.42, 0), Vector3(0.2, 0.44, 0), Vector3(0.22, 0.7, 0), Vector3(0.22, 0.75, 0)], [0.055, 0.055, 0.05, 0.02], 7, [g, g, g, g.lightened(0.1)])
	_tube(st, [Vector3(0, 0.56, 0), Vector3(-0.17, 0.58, 0), Vector3(-0.19, 0.8, 0), Vector3(-0.19, 0.84, 0)], [0.05, 0.05, 0.045, 0.02], 7, [g, g, g, g.lightened(0.1)])
	st.commit(am)
	am.surface_set_material(0, _mat(Color.WHITE, 0.8))
	return am


static func _root() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spine := []
	var radii := []
	var cols := []
	for i in 13:
		var t := float(i) / 12.0
		spine.append(Vector3(t * 2.2 - 1.1, sin(t * PI) * 0.9, 0.18 * sin(t * 5.0)))
		radii.append(lerpf(0.32, 0.12, absf(t - 0.25) * 1.2))
		cols.append(Color(0.34, 0.26, 0.2).lerp(Color(0.3, 0.42, 0.24), 0.25 + 0.25 * sin(t * 9.0)))
	_tube(st, spine, radii, 8, cols)
	st.commit(am)
	am.surface_set_material(0, _mat(Color.WHITE, 0.95))
	return am
