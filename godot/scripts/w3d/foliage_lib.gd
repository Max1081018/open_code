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

## Downloaded pieces (Sketchfab CC BY, split by tools/split_nature.gd into
## assets/models/nature_ext). Kind "X:<piece>"; [height m, category].
## Category "formation": solid landmark rock, not mineable.
const EXT_DIR := "res://assets/models/nature_ext/"
const EXT := {
	"pines_0": [13.0, "tree"], "pines_1": [11.0, "tree"], "pines_4": [12.0, "tree"], "pines_6": [14.0, "tree"],
	"sakura_0": [8.0, "tree"],
	"rocks_0": [1.6, "rock"], "rocks_1": [1.8, "rock"], "rocks_2": [1.4, "rock"], "rocks_3": [1.5, "rock"],
	"rocks_4": [1.9, "rock"], "rocks_5": [1.4, "rock"], "rocks_6": [1.6, "rock"],
	"rocks_7": [3.4, "formation"], "rocks_8": [3.0, "formation"], "rocks_9": [0.5, "small"], "rocks_10": [0.45, "small"],
	"sandstone_0": [7.0, "formation"], "sandstone_2": [5.0, "formation"], "sandstone_4": [5.5, "formation"],
	"sandstone_1": [1.8, "rock"], "sandstone_3": [2.0, "rock"],
	"volcanic_0": [9.0, "formation"], "volcanic_1": [9.0, "formation"], "volcanic_2": [8.0, "formation"],
	"volcanic_3": [9.0, "formation"], "volcanic_5": [8.0, "formation"], "volcanic_6": [7.0, "formation"],
	"volcanic_7": [9.0, "formation"], "volcanic_8": [12.0, "formation"], "volcanic_10": [8.0, "formation"],
	"volcanic_12": [7.0, "formation"], "volcanic_14": [6.0, "formation"],
	"volcanic_18": [7.0, "formation"], "volcanic_19": [7.0, "formation"],
	"volcanic_16": [2.0, "rock"], "volcanic_17": [2.0, "rock"], "volcanic_22": [1.8, "rock"], "volcanic_23": [1.8, "rock"],
	"volcanic_24": [1.8, "rock"], "volcanic_26": [1.8, "rock"], "volcanic_27": [1.8, "rock"],
	"volcanic_28": [1.8, "rock"], "volcanic_29": [1.8, "rock"], "volcanic_25": [0.8, "small"],
}

## Measured mean brightness of each rock piece's texture at its own UVs
## (tools: the uvcol probe in the QA notes), for toning them evenly.
const ROCK_LUM := {"rocks_0": 0.56, "rocks_1": 0.60, "rocks_2": 0.59, "rocks_3": 0.60, "rocks_4": 0.64,
	"rocks_5": 0.46, "rocks_6": 0.44, "rocks_7": 0.47, "rocks_8": 0.46, "rocks_9": 0.37, "rocks_10": 0.51}

static var _cache := {}
static var _wind: Shader


## [[mesh, transform in the kind's frame], ...], already scaled to size.
static func parts(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	if kind.begins_with("X:"):
		return _ext_parts(kind)
	if kind.begins_with("P:"):
		var pm := ProcFlora.mesh(kind.substr(2))
		var pk: float = float(spec_for(kind)[0]) / maxf(pm.get_aabb().size.y, 0.01)
		_cache[kind] = [[pm, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * pk), Vector3.ZERO)]]
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
	_white_tex = null


static var _white_tex: Texture2D


static func _white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


static func _tinted(mesh: Mesh, colour: Color) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var m := copy.surface_get_material(s) as BaseMaterial3D
		if m:
			m = m.duplicate()
			m.albedo_color = m.albedo_color * colour
			copy.surface_set_material(s, m)
	return copy


static func _ext_parts(kind: String) -> Array:
	var piece := kind.substr(2)
	var mesh: Mesh = load(EXT_DIR + piece + ".res")
	var spec: Array = spec_for(kind)
	var k: float = float(spec[0]) / maxf(mesh.get_aabb().size.y, 0.01)
	var m: Mesh = _windy(mesh, spec[1], piece) if spec[1] == "tree" else mesh
	# The rock pack's stone is pale (0.56-0.64 where its UVs land, twice the
	# ground's brightness): in full sun the exposure and grade clipped every
	# boulder to a flat white blob. Toned down to weathered grey stone (0.26), a
	# shade warmer on the lighter pieces.
	if piece.begins_with("rocks_"):
		var lum: float = ROCK_LUM.get(piece, 0.55)
		var tone := clampf(0.26 / lum, 0.4, 0.9)
		m = _tinted(m, Color(tone * 1.02, tone, tone * 0.96))
	# Lava vents and veined rocks glow.
	if piece in ["volcanic_18", "volcanic_19", "volcanic_24", "volcanic_26", "volcanic_27", "volcanic_28", "volcanic_29"]:
		m = _glowing(m)
	var out := [[m, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * k), Vector3.ZERO)]]
	_cache[kind] = out
	return out


## The palette's bright lava colours become emissive (vents, veins).
static func _glowing(mesh: Mesh) -> Mesh:
	var copy: Mesh = mesh.duplicate()
	for s in copy.get_surface_count():
		var m := copy.surface_get_material(s) as BaseMaterial3D
		if m == null:
			continue
		m = m.duplicate()
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color(0, 0, 0)
		m.emission_energy_multiplier = 1.0
		m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		copy.surface_set_material(s, m)
	return copy


## Footprint radius of a solid kind, for its collider (metres, unscaled).
static func solid_radius(kind: String) -> float:
	var spec := spec_for(kind)
	match spec[1]:
		"tree":
			return 0.35
		"formation":
			return float(spec[0]) * 0.4
	return float(spec[0]) * 0.44


static func spec_for(kind: String) -> Array:
	if kind.begins_with("P:"):
		return ProcFlora.KINDS.get(kind.substr(2), [1.0, "small"])
	if kind.begins_with("X:"):
		return EXT.get(kind.substr(2), [1.5, "rock"])
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


## The bounds of one surface (a tree's leaves without its trunk).
static func _surface_box(mesh: Mesh, s: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return mesh.get_aabb()
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


## The pines are deep blue-green conifers, not the pack's lime.
static func _shade(kind_hint: String) -> Color:
	return Color(0.58, 0.7, 0.66) if kind_hint.begins_with("pines") else Color(1, 1, 1)


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
			if cat == "tree":
				# Trunks and solid boughs share the leaf shader (no cut-out, no
				# sway) so they too thin out near the camera and in front of
				# the heroine.
				if _wind == null:
					_wind = load("res://scripts/shaders/foliage3d.gdshader")
				var solid := ShaderMaterial.new()
				solid.shader = _wind
				solid.set_shader_parameter("albedo_tex", material.albedo_texture if material.albedo_texture else _white())
				solid.set_shader_parameter("albedo", material.albedo_color * _shade(kind_hint) * Color(0.86, 0.86, 0.86))
				solid.set_shader_parameter("saturation", 0.82)
				solid.set_shader_parameter("alpha_cut", -1.0)
				solid.set_shader_parameter("sway", 0.0)
				solid.set_shader_parameter("near_fade", 5.5)
				copy.surface_set_material(s, solid)
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
		var colour := material.albedo_color * _shade(kind_hint)
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
		sm.set_shader_parameter("near_fade", 5.5 if cat == "tree" else 0.0)
		if cat == "tree" or (cat == "small" and kind_hint.begins_with("Bush")):
			var box := _surface_box(copy, s)
			sm.set_shader_parameter("canopy_center", box.get_center() + Vector3(0, box.size.y * 0.08, 0))
			sm.set_shader_parameter("canopy_radius", maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5)
			sm.set_shader_parameter("translucency", 0.35)
		copy.surface_set_material(s, sm)
	return copy
