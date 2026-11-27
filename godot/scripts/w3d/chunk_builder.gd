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
	# Greenwood: round broadleaf groves, sakura here and there, clean pale
	# stone, standing stones, flowers.
	TerrainGen.Biome.FOREST: [["CommonTree_1", 7], ["CommonTree_2", 6], ["CommonTree_3", 6], ["CommonTree_4", 4],
		["CommonTree_5", 5], ["X:sakura_0", 3], ["X:pines_4", 2], ["Bush_Common", 9], ["Bush_Common_Flowers", 6],
		["Fern_1", 8], ["Plant_1", 5], ["X:rocks_0", 2], ["X:rocks_3", 1], ["X:rocks_5", 1], ["X:rocks_7", 1],
		["Flower_3_Group", 8], ["Flower_4_Group", 6], ["Mushroom_Common", 2]],
	# The Gloomwood: tall dark pines, twisted trunks, ferns, mushrooms,
	# rocks threaded with teal light.
	TerrainGen.Biome.DARK_FOREST: [["X:pines_6", 7], ["X:pines_0", 5], ["X:pines_4", 5], ["TwistedTree_1", 4],
		["TwistedTree_2", 3], ["Fern_1", 16], ["Mushroom_Laetiporus", 5], ["Mushroom_Common", 7],
		["X:volcanic_29", 2], ["X:rocks_8", 1], ["Plant_7", 8]],
	# The Frostpeaks: pines, pale boulders, standing stones.
	TerrainGen.Biome.SNOW: [["X:pines_1", 6], ["X:pines_4", 6], ["X:pines_6", 4], ["X:rocks_1", 4],
		["X:rocks_4", 3], ["X:rocks_2", 3], ["X:rocks_7", 1], ["DeadTree_4", 1]],
	# The Sunscar: red sandstone stacks and arches, dry trees, wispy tufts.
	TerrainGen.Biome.DRY: [["DeadTree_1", 1], ["DeadTree_5", 1], ["X:sandstone_0", 1], ["X:sandstone_2", 1],
		["X:sandstone_4", 1], ["X:sandstone_1", 2], ["X:sandstone_3", 2], ["P:cactus", 2], ["Grass_Wispy_Tall", 3]],
	# The Ashlands: basalt pillars and cliffs, lava vents, ember-veined rock.
	TerrainGen.Biome.VOLCANIC: [["DeadTree_2", 2], ["X:volcanic_7", 2], ["X:volcanic_8", 2], ["X:volcanic_10", 2],
		["X:volcanic_14", 2], ["X:volcanic_0", 1], ["X:volcanic_3", 1], ["X:volcanic_18", 1], ["X:volcanic_19", 1],
		["X:volcanic_24", 4], ["X:volcanic_28", 4], ["X:volcanic_16", 4], ["X:volcanic_22", 4], ["X:volcanic_25", 12]],
	# The Blight: twisted trees, dead wood, mushrooms, Void-veined rock.
	TerrainGen.Biome.CORRUPTED: [["TwistedTree_4", 6], ["TwistedTree_5", 6], ["DeadTree_3", 3], ["DeadTree_4", 3],
		["Mushroom_Laetiporus", 7], ["Mushroom_Common", 7], ["X:volcanic_27", 5], ["X:volcanic_12", 1], ["Plant_7", 6]],
	# The Great Jungle: giant broadleaf and twisted trees, palms, buttress
	# roots, ferns and big-leaf plants, glowing flowers, mossy rocks.
	TerrainGen.Biome.JUNGLE: [["CommonTree_1", 5], ["CommonTree_2", 4], ["CommonTree_4", 4],
		["P:palm", 7], ["P:giant_root", 3], ["Fern_1", 16], ["Plant_1_Big", 5],
		["Bush_Common", 7], ["P:glowflower", 7], ["Mushroom_Laetiporus", 2], ["X:rocks_8", 1]],
	# The Crystal Coast: palms, pale rock, crystal clusters, beach grass.
	TerrainGen.Biome.CRYSTAL: [["P:palm", 8], ["X:rocks_6", 3], ["X:rocks_2", 3], ["P:crystal", 3], ["X:sakura_0", 1],
		["Grass_Wispy_Tall", 10], ["Bush_Common_Flowers", 4], ["Flower_4_Group", 4]],
	TerrainGen.Biome.BEACH: [["X:rocks_6", 2], ["X:rocks_2", 2], ["Grass_Wispy_Short", 10], ["X:rocks_9", 6], ["X:rocks_10", 6]],
}
const GRASS := {
	TerrainGen.Biome.FOREST: "Grass_Common_Short", TerrainGen.Biome.DARK_FOREST: "Grass_Common_Tall",
	TerrainGen.Biome.CORRUPTED: "Grass_Wispy_Short", TerrainGen.Biome.JUNGLE: "Grass_Common_Tall",
	TerrainGen.Biome.CRYSTAL: "Grass_Wispy_Short",
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
			var t := gen.blended_tint(x, z, b)
			# Tint packed in UV2: x = hue darkening (green channel), y = ash.
			tints.append(Vector2((t.r + t.g + t.b) / 3.0, maxf(0.0 if b == TerrainGen.Biome.VOLCANIC else t.a, gen.volcanic(x, z))))
			# UV: the tint's hue (red and blue share of its brightness).
			var avg := maxf((t.r + t.g + t.b) / 3.0, 0.01)
			uv.append(Vector2(t.r / avg, t.b / avg))
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
				var in_town := Vector2(x, z).distance_to(TerrainGen.VILLAGE) < TerrainGen.VILLAGE_RADIUS * 0.9
				if in_town and (Vector2(x, z).length() < 20.0 or _near_building(x, z)):
					continue  # the plaza and the buildings stay clear
				if gen.paved(x, z) > 0.0 or gen.paved(x + 2.5, z) > 0.0 or gen.paved(x - 2.5, z) > 0.0:
					continue  # and so do the roads
				var b := gen.biome(x, z)
				var table: Array = FLORA.get(b, [])
				var total := 0
				for e in table:
					total += e[1]
				# Density: about one thing in three candidate points (the jungle
				# is thick, the open sand sparse).
				var density := 0.5 if b == TerrainGen.Biome.JUNGLE else (0.1 if b == TerrainGen.Biome.DRY else 0.42)
				if total == 0 or rng.randf() > density:
					continue
				var pick := rng.randi() % total
				for e in table:
					pick -= e[1]
					if pick < 0:
						var kind: String = e[0]
						# In town only garden plants grow (bushes, flowers, ferns).
						if in_town and FoliageLib.category(kind) != "small":
							break
						# Trees gather in groves; open meadows get flowers instead.
						if FoliageLib.category(kind) == "tree" and b != TerrainGen.Biome.DARK_FOREST and b != TerrainGen.Biome.JUNGLE and rng.randf() > gen.forest(x, z) * 0.75:
							if b != TerrainGen.Biome.FOREST or rng.randf() < 0.5:
								break
							kind = ["Flower_3_Group", "Flower_4_Group", "Bush_Common_Flowers"][rng.randi() % 3]
						var sink := 0.05
						if FoliageLib.category(kind) == "formation":
							# Big formations are landmarks: a few per square kilometre.
							if rng.randf() > 0.18:
								break
							sink = float(FoliageLib.spec_for(kind)[0]) * 0.08  # bedded into slopes
						# The drawn mesh is coarser than the height field: on a slope
						# it can sit below the true surface, so bed things deeper there.
						sink += (1.0 - nor.y) * 3.0
						var sc := rng.randf_range(0.8, 1.25)
						if b == TerrainGen.Biome.JUNGLE and (kind.begins_with("CommonTree") or kind.begins_with("TwistedTree")):
							sc *= rng.randf_range(1.4, 2.2)  # the jungle's giants
						placed.append({"kind": kind, "pos": Vector3(x, h - sink, z), "yaw": rng.randf() * TAU,
							"scale": sc})
						break
	return placed


## Within a town building's footprint (plus a garden margin).
static func _near_building(x: float, z: float) -> bool:
	for k in Town.KIT:
		var o: Dictionary = k[3]
		var r: float = maxf(float(o.get("w", 7.0)), float(o.get("d", 7.0))) * 0.75 + 2.5
		if k[0] == "tower":
			r = float(o.r) + 3.0
		if Vector2(x - k[1], z - k[2]).length() < r:
			return true
	return false


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
		var ny := gen.normal(x, z).y
		if h < TerrainGen.WATER + 0.5 or ny < 0.8:
			continue
		if gen.paved(x, z) > 0.2:
			continue
		var kind: String = GRASS[b]
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3)),
			Vector3(x, h - 0.05 - (1.0 - ny) * 2.0, z)))
	return by_kind
