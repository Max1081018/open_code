class_name FoliageLib
extends RefCounted
## The Stylized Nature MegaKit (Quaternius, CC0) as instancing material: each
## kind loaded once, scaled to a real-world size, split into its mesh parts
## (bark, leaves...) so chunks can draw thousands with MultiMeshes. Leaves
## sway in the wind (a vertex shader on their material).

const DIR := "res://assets/models/nature3d/"
## kind -> [height in metres, category]
const SIZES := {
	"CommonTree": [11.0, "tree"], "Pine": [12.0, "tree"], "TwistedTree": [8.5, "tree"], "DeadTree": [8.0, "tree"],
	"Bush_Common": [1.6, "small"], "Fern_1": [1.0, "small"], "Plant_1": [1.1, "small"], "Plant_7": [0.9, "small"],
	"Rock_Medium": [1.7, "rock"], "Flower": [0.55, "small"], "Mushroom": [0.55, "small"], "Grass": [0.55, "grass"],
	"Pebble": [0.3, "small"], "Clover": [0.3, "small"],
}

static var _cache := {}
static var _wind: Shader


## [[mesh, transform in the kind's frame], ...], already scaled to size.
static func parts(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	# "<kind>_Basalt": the same model as dark volcanic stone.
	var basalt := kind.ends_with("_Basalt")
	var scene: PackedScene = load(DIR + kind.trim_suffix("_Basalt") + ".gltf")
	var root: Node3D = scene.instantiate()
	var found := []
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var t := _to_root(m, root)
		found.append([m.mesh, t])
		var b: AABB = t * (m as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	var spec: Array = spec_for(kind)
	var k: float = float(spec[0]) / maxf(box.size.y, 0.01)
	var out := []
	for f in found:
		var mesh: Mesh = _windy(f[0], spec[1], kind)
		if basalt:
			mesh = _tinted(mesh, Color(0.36, 0.3, 0.3))
		out.append([mesh, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), Vector3.ZERO) * f[1]])
	_cache[kind] = out
	return out


## Drop the cached meshes and materials. Call before the engine shuts down:
## static variables are cleared after the servers are gone, and freeing
## render resources then corrupts the heap.
static func release() -> void:
	_cache.clear()
	_wind = null


static func _tinted(mesh: Mesh, colour: Color) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var m := copy.surface_get_material(s) as BaseMaterial3D
		if m:
			m = m.duplicate()
			m.albedo_color = m.albedo_color * colour
			copy.surface_set_material(s, m)
	return copy


static func spec_for(kind: String) -> Array:
	for prefix in SIZES:
		if kind.begins_with(prefix):
			return SIZES[prefix]
	return [1.0, "small"]


static func category(kind: String) -> String:
	return spec_for(kind)[1]


static func _to_root(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## A copy of the mesh whose leafy (alpha-tested) surfaces sway in the wind.
static func _windy(mesh: Mesh, cat: String, kind_hint := "") -> Mesh:
	if cat == "rock":
		# The kit's stones are mint-grey; warm them to plain weathered stone.
		var rock: Mesh = mesh.duplicate()
		for s in rock.get_surface_count():
			var m := rock.surface_get_material(s) as BaseMaterial3D
			if m:
				m = m.duplicate()
				m.albedo_color = m.albedo_color * Color(1.0, 0.9, 0.9)
				rock.surface_set_material(s, m)
		return rock
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var material := copy.surface_get_material(s) as BaseMaterial3D
		if material == null:
			continue
		var leafy := material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or cat == "grass"
		if not leafy:
			continue
		if _wind == null:
			_wind = load("res://scripts/shaders/foliage3d.gdshader")
		var sm := ShaderMaterial.new()
		sm.shader = _wind
		var tex := material.albedo_texture
		# The kit's plain bush borrows the twisted tree's purple leaves; give
		# it ordinary green ones (the twisted look is for the dark woods).
		if kind_hint.begins_with("Bush_Common") and String(material.resource_name).contains("Twisted"):
			tex = load(DIR + "Leaves_NormalTree_C.png")
		sm.set_shader_parameter("albedo_tex", tex)
		# The kit's greens are candy-bright; grass is muted toward meadow.
		var colour := material.albedo_color
		var saturation := 0.85
		if cat == "grass":
			colour = colour * Color(0.62, 0.72, 0.5)
			saturation = 0.5
		elif cat == "small":
			colour = colour * Color(0.85, 0.88, 0.8)
			saturation = 0.75
		if kind_hint.begins_with("TwistedTree"):
			colour = colour * Color(0.78, 0.58, 0.52)
			saturation = 0.5
		sm.set_shader_parameter("albedo", colour)
		sm.set_shader_parameter("saturation", saturation)
		sm.set_shader_parameter("sway", 0.06 if cat == "tree" else 0.12)
		copy.surface_set_material(s, sm)
	return copy
