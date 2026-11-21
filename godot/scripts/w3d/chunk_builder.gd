class_name ChunkBuilder
extends RefCounted
## Builds one terrain chunk's data off the main thread: the terrain mesh
## arrays (heights, normals, splat weights, biome tint), the height grid for
## its collider, and where its trees, rocks, bushes and grass stand.
## Placement is seeded by the chunk's coordinates, so the world is the same
## every visit; what the player changed (felled trees, mined rocks) is
## applied on top by World3D.

const SIZE := 64.0
## Vertices per side for each level of detail (near, mid, far).
const LOD_STEPS := [32, 16, 8]
const SKIRT := 4.0

## Foliage per biome: [kind, density per chunk, scale range]. Kinds are
## FoliageLib names; "tree" kinds can be felled, "rock" kinds mined.
const FLORA := {
	TerrainGen.Biome.FOREST: [["CommonTree_1", 7], ["CommonTree_2", 6], ["CommonTree_3", 6], ["CommonTree_4", 4],
		["CommonTree_5", 5], ["Pine_1", 3], ["Pine_2", 3], ["Bush_Common", 10], ["Bush_Common_Flowers", 5],
		["Fern_1", 10], ["Plant_1", 6], ["Rock_Medium_1", 2], ["Rock_Medium_2", 2], ["Flower_3_Group", 8],
		["Flower_4_Group", 6], ["Mushroom_Common", 3]],
	TerrainGen.Biome.DARK_FOREST: [["TwistedTree_1", 6], ["TwistedTree_2", 6], ["TwistedTree_3", 5], ["Pine_4", 6],
		["Pine_5", 6], ["DeadTree_1", 3], ["Fern_1", 16], ["Mushroom_Laetiporus", 5], ["Mushroom_Common", 6],
		["Rock_Medium_3", 3], ["Plant_7", 8]],
	TerrainGen.Biome.SNOW: [["Pine_1", 6], ["Pine_2", 6], ["Pine_3", 6], ["Pine_4", 4], ["Rock_Medium_1", 5],
		["Rock_Medium_2", 4], ["Rock_Medium_3", 4], ["DeadTree_4", 2]],
	TerrainGen.Biome.DRY: [["DeadTree_1", 3], ["DeadTree_2", 3], ["DeadTree_5", 2], ["Rock_Medium_1", 7],
		["Rock_Medium_2", 6], ["Rock_Medium_3", 6], ["Plant_7", 5], ["Grass_Wispy_Tall", 14]],
	TerrainGen.Biome.VOLCANIC: [["DeadTree_2", 3], ["DeadTree_3", 3], ["Rock_Medium_1", 9], ["Rock_Medium_2", 9],
		["Rock_Medium_3", 8]],
	TerrainGen.Biome.CORRUPTED: [["TwistedTree_4", 6], ["TwistedTree_5", 6], ["DeadTree_3", 4], ["DeadTree_4", 4],
		["Mushroom_Laetiporus", 8], ["Mushroom_Common", 8], ["Rock_Medium_3", 4], ["Plant_7", 6]],
	TerrainGen.Biome.BEACH: [["Rock_Medium_1", 2], ["Rock_Medium_2", 2], ["Grass_Wispy_Short", 10], ["Pebble_Round_2", 8]],
}
const GRASS := {
	TerrainGen.Biome.FOREST: "Grass_Common_Short", TerrainGen.Biome.DARK_FOREST: "Grass_Common_Tall",
	TerrainGen.Biome.CORRUPTED: "Grass_Wispy_Short", TerrainGen.Biome.DRY: "Grass_Wispy_Short",
}


## Everything about chunk `coord` at detail level `lod`.
static func build(gen: TerrainGen, coord: Vector2i, lod: int, with_grass: bool) -> Dictionary:
	var steps: int = LOD_STEPS[lod]
	var spacing := SIZE / steps
	var origin := Vector2(coord.x * SIZE, coord.y * SIZE)
	var n := steps + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var tints := PackedVector2Array()
	var uv := PackedVector2Array()
	for j in n:
		for i in n:
			var x := origin.x + i * spacing
			var z := origin.y + j * spacing
			var h := gen.height(x, z)
			heights[j * n + i] = h
			var nor := gen.normal(x, z, spacing * 0.75)
			var b := gen.biome(x, z)
			verts.append(Vector3(i * spacing, h, j * spacing))
			normals.append(nor)
			colours.append(gen.splat(x, z, h, nor, b))
			var t := gen.tint(b)
			# Tint packed in UV2: x = hue darkening (green channel), y = ash.
			tints.append(Vector2((t.r + t.g + t.b) / 3.0, t.a))
			uv.append(Vector2(x, z))
	var indices := PackedInt32Array()
	for j in steps:
		for i in steps:
			var a := j * n + i
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# Skirts: a strip hanging down from each edge hides cracks between
	# chunks drawn at different detail.
	var edges := [[], [], [], []]
	for k in n:
		edges[0].append(k)
		edges[1].append(steps * n + k)
		edges[2].append(k * n)
		edges[3].append(k * n + steps)
	for e in edges:
		var base := verts.size()
		for k in e:
			verts.append(verts[k] - Vector3(0, SKIRT, 0))
			normals.append(normals[k])
			colours.append(colours[k])
			tints.append(tints[k])
			uv.append(uv[k])
		for k in range(e.size() - 1):
			var t0: int = e[k]
			var t1: int = e[k + 1]
			indices.append_array([t0, t1, base + k, t1, base + k + 1, base + k])
			indices.append_array([t0, base + k, t1, t1, base + k, base + k + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = tints
	arrays[Mesh.ARRAY_INDEX] = indices

	var result := {"coord": coord, "lod": lod, "arrays": arrays, "heights": heights, "steps": steps}
	if lod <= 1:
		result.flora = _flora(gen, coord, origin)
	if with_grass:
		result.grass = _grass(gen, coord, origin)
	return result


static func _flora(gen: TerrainGen, coord: Vector2i, origin: Vector2) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.seed_value, coord.x, coord.y, "flora"])
	var placed: Array = []
	# Candidate points on a jittered grid; each takes the biome where it lands.
	var cells := 9
	var cell := SIZE / cells
	for cj in cells:
		for ci in cells:
			for k in 3:
				var x := origin.x + (ci + rng.randf()) * cell
				var z := origin.y + (cj + rng.randf()) * cell
				var h := gen.height(x, z)
				if h < TerrainGen.WATER + 0.4:
					continue
				var nor := gen.normal(x, z)
				if nor.y < 0.78:
					continue
				if Vector2(x, z).distance_to(TerrainGen.VILLAGE) < TerrainGen.VILLAGE_RADIUS * 0.9:
					continue  # the village square stays clear
				if gen.paved(x, z) > 0.0 or gen.paved(x + 2.5, z) > 0.0 or gen.paved(x - 2.5, z) > 0.0:
					continue  # and so do the roads
				var b := gen.biome(x, z)
				var table: Array = FLORA.get(b, [])
				var total := 0
				for e in table:
					total += e[1]
				# Density: about one thing in three candidate points.
				if total == 0 or rng.randf() > 0.42:
					continue
				var pick := rng.randi() % total
				for e in table:
					pick -= e[1]
					if pick < 0:
						var kind: String = e[0]
						# Trees gather in groves; open meadows get flowers instead.
						if FoliageLib.category(kind) == "tree" and rng.randf() > gen.forest(x, z) * 0.75:
							if b != TerrainGen.Biome.FOREST or rng.randf() < 0.5:
								break
							kind = ["Flower_3_Group", "Flower_4_Group", "Bush_Common_Flowers"][rng.randi() % 3]
						placed.append({"kind": kind, "pos": Vector3(x, h - 0.05, z), "yaw": rng.randf() * TAU,
							"scale": rng.randf_range(0.8, 1.25)})
						break
	return placed


static func _grass(gen: TerrainGen, coord: Vector2i, origin: Vector2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen.seed_value, coord.x, coord.y, "grass"])
	var by_kind := {}
	for k in 700:
		var x := origin.x + rng.randf() * SIZE
		var z := origin.y + rng.randf() * SIZE
		var b := gen.biome(x, z)
		if not GRASS.has(b):
			continue
		var h := gen.height(x, z)
		if h < TerrainGen.WATER + 0.5 or gen.normal(x, z).y < 0.8:
			continue
		if gen.paved(x, z) > 0.2:
			continue
		var kind: String = GRASS[b]
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)),
			Vector3(x, h - 0.05, z)))
	return by_kind
