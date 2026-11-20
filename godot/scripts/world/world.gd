class_name World
extends Node2D
## Draws a WorldData and lets the game change it.
##
## Tiles stream in by 16x16 chunks around the camera: the whole world is
## 230,000 cells, far too many to hold as live tiles and collision shapes
## on a phone, but a screen needs only a few thousand.

signal tile_changed(cell: Vector2i)

const TILE := 128
const CHUNK := 16
const LOADS_PER_FRAME := 3

## Seconds in a full day-night cycle.
const DAY_LENGTH := 600.0

const TERRAIN_SOURCE := 0
const OVERLAY_SOURCE := 1
const LIQUID_SOURCE := 2

## Object types that emit light, and their colour and reach in tiles.
const OBJECT_LIGHTS := {
	"torch": [Color(1.0, 0.74, 0.42), 9.0],
	"campfire": [Color(1.0, 0.58, 0.30), 11.0],
	"wardstone": [Color(0.52, 0.88, 1.0), 15.0],
	"altar": [Color(0.85, 0.30, 0.35), 6.0],
}
const GLOWSHARD_LIGHT := Color(0.22, 0.46, 0.80)
const LAVA_LIGHT := Color(1.0, 0.42, 0.12)
const CRYSTAL_AMBIENT := Color(0.16, 0.08, 0.24)

var data: WorldData
var time_of_day := 0.30  ## 0..1; 0.25 is sunrise, 0.75 sunset

var terrain: TileMapLayer
var walls: TileMapLayer
var overlay: TileMapLayer
var liquids: TileMapLayer
var object_root: Node2D
var glow_root: Node2D

var light_map := LightMap.new()
var light_sprite: Sprite2D
var light_texture: ImageTexture
var _light_timer := 0.0
var _light_dirty := true

var _loaded := {}  ## Vector2i chunk -> true
var _object_nodes := {}  ## cell index -> Node2D
var _objects_by_chunk := {}  ## Vector2i chunk -> Array of cell indices
var _lit_objects := {}  ## cell index -> true
var _camera: Camera2D

## Extra light sources outside the tile grid (the lantern, projectiles):
## Callable returning Array of [Vector2 tile position, radius, Color].
var dynamic_lights: Array[Callable] = []


func setup(world_data: WorldData, camera: Camera2D) -> void:
	data = world_data
	_camera = camera
	_index_objects()
	_build_layers()


func _index_objects() -> void:
	_objects_by_chunk.clear()
	for key in data.objects:
		_index_object(key)


func _index_object(key: int) -> void:
	var chunk := Vector2i(key % data.width, key / data.width) / CHUNK
	if not _objects_by_chunk.has(chunk):
		_objects_by_chunk[chunk] = []
	_objects_by_chunk[chunk].append(key)
	if OBJECT_LIGHTS.has(data.objects[key].type):
		_lit_objects[key] = true


func _build_layers() -> void:
	var tileset := _build_tileset()

	walls = TileMapLayer.new()
	walls.tile_set = tileset
	walls.collision_enabled = false
	walls.z_index = -5
	# Background walls are the same rock, set back: darker and cooler, so
	# the eye reads them as depth rather than as more ground.
	walls.modulate = Color(0.40, 0.40, 0.50)
	add_child(walls)

	object_root = Node2D.new()
	object_root.z_index = -2
	add_child(object_root)

	liquids = TileMapLayer.new()
	liquids.tile_set = tileset
	liquids.collision_enabled = false
	liquids.z_index = 3
	liquids.modulate = Color(1, 1, 1, 0.82)
	add_child(liquids)

	terrain = TileMapLayer.new()
	terrain.tile_set = tileset
	terrain.z_index = 0
	add_child(terrain)

	overlay = TileMapLayer.new()
	overlay.tile_set = tileset
	overlay.collision_enabled = false
	overlay.z_index = 1
	add_child(overlay)

	light_texture = ImageTexture.new()
	light_sprite = Sprite2D.new()
	light_sprite.centered = false
	light_sprite.z_index = 50
	light_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	light_sprite.material = multiply
	add_child(light_sprite)

	glow_root = Node2D.new()
	glow_root.z_index = 60
	add_child(glow_root)


func _build_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)

	var terrain_source := TileSetAtlasSource.new()
	terrain_source.texture = load("res://assets/tiles/terrain.png")
	terrain_source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(terrain_source, TERRAIN_SOURCE)
	var half := TILE / 2.0
	var square := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	for row in 9:
		for mask in 16:
			var coords := Vector2i(mask, row)
			terrain_source.create_tile(coords)
			var tile_data := terrain_source.get_tile_data(coords, 0)
			tile_data.add_collision_polygon(0)
			tile_data.set_collision_polygon_points(0, 0, square)

	var overlay_source := TileSetAtlasSource.new()
	overlay_source.texture = load("res://assets/tiles/overlay.png")
	overlay_source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(overlay_source, OVERLAY_SOURCE)
	for column in 11:
		for row in 2:
			overlay_source.create_tile(Vector2i(column, row))

	var liquid_source := TileSetAtlasSource.new()
	liquid_source.texture = load("res://assets/tiles/liquid.png")
	liquid_source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(liquid_source, LIQUID_SOURCE)
	for column in 4:
		liquid_source.create_tile(Vector2i(column, 0))

	return tileset


# =============================================================================
# Coordinates
# =============================================================================

static func cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE), floori(world_position.y / TILE))


static func centre_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


## World position of the bottom-centre of a cell: where things stand.
static func foot_of(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)


func visible_cells() -> Rect2i:
	var view := get_viewport_rect().size / _camera.zoom
	var top_left := _camera.get_screen_center_position() - view * 0.5
	var start := cell_of(top_left)
	var end := cell_of(top_left + view) + Vector2i.ONE
	return Rect2i(start, end - start)


# =============================================================================
# Streaming
# =============================================================================

func _process(delta: float) -> void:
	if data == null:
		return
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH, 1.0)
	_stream_chunks()

	_light_timer -= delta
	if _light_timer <= 0.0:
		_light_timer = 1.0 / Settings.light_rate()
		_update_lighting()


func _stream_chunks() -> void:
	var view := visible_cells().grow(CHUNK / 2)
	var first := Vector2i(floori(view.position.x / float(CHUNK)), floori(view.position.y / float(CHUNK)))
	var last := Vector2i(floori(view.end.x / float(CHUNK)), floori(view.end.y / float(CHUNK)))
	var limit := Vector2i((data.width - 1) / CHUNK, (data.height - 1) / CHUNK)
	first = first.clamp(Vector2i.ZERO, limit)
	last = last.clamp(Vector2i.ZERO, limit)

	var centre := (first + last) / 2
	var wanted := []
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var chunk := Vector2i(cx, cy)
			if not _loaded.has(chunk):
				wanted.append(chunk)
	# Nearest first, a few per frame, so streaming never hitches.
	wanted.sort_custom(func(a, b): return (a - centre).length_squared() < (b - centre).length_squared())
	for i in min(wanted.size(), LOADS_PER_FRAME):
		_load_chunk(wanted[i])

	# Unload with a margin of one chunk, so walking back and forth across a
	# boundary does not thrash.
	for chunk in _loaded.keys():
		if chunk.x < first.x - 1 or chunk.x > last.x + 1 or chunk.y < first.y - 1 or chunk.y > last.y + 1:
			_unload_chunk(chunk)


## Load everything around a point immediately. Used at spawn so the player
## never falls through ground that has not streamed in yet.
func load_area(cell: Vector2i, radius_chunks: int) -> void:
	var centre := cell / CHUNK
	for cy in range(centre.y - radius_chunks, centre.y + radius_chunks + 1):
		for cx in range(centre.x - radius_chunks, centre.x + radius_chunks + 1):
			var chunk := Vector2i(cx, cy)
			if cx >= 0 and cy >= 0 and cx * CHUNK < data.width and cy * CHUNK < data.height \
					and not _loaded.has(chunk):
				_load_chunk(chunk)
	_update_lighting()


func is_loaded(cell: Vector2i) -> bool:
	return _loaded.has(cell / CHUNK)


func _load_chunk(chunk: Vector2i) -> void:
	_loaded[chunk] = true
	var x0 := chunk.x * CHUNK
	var y0 := chunk.y * CHUNK
	for y in range(y0, min(y0 + CHUNK, data.height)):
		for x in range(x0, min(x0 + CHUNK, data.width)):
			_draw_cell(Vector2i(x, y))
	for key in _objects_by_chunk.get(chunk, []):
		_spawn_object_node(key)


func _unload_chunk(chunk: Vector2i) -> void:
	_loaded.erase(chunk)
	var x0 := chunk.x * CHUNK
	var y0 := chunk.y * CHUNK
	for y in range(y0, min(y0 + CHUNK, data.height)):
		for x in range(x0, min(x0 + CHUNK, data.width)):
			var cell := Vector2i(x, y)
			terrain.erase_cell(cell)
			walls.erase_cell(cell)
			overlay.erase_cell(cell)
			liquids.erase_cell(cell)
	for key in _objects_by_chunk.get(chunk, []):
		if _object_nodes.has(key):
			_object_nodes[key].queue_free()
			_object_nodes.erase(key)


static func atlas_row(material: int) -> int:
	return WorldData.BASALT - 1 if material == WorldData.BEDROCK else material - 1


func _draw_cell(cell: Vector2i) -> void:
	var x := cell.x
	var y := cell.y
	var material := data.get_tile(x, y)
	if material == WorldData.AIR:
		terrain.erase_cell(cell)
		overlay.erase_cell(cell)
	else:
		terrain.set_cell(cell, TERRAIN_SOURCE, Vector2i(data.mask(x, y), atlas_row(material)))
		var ore := data.get_ore(x, y)
		if ore != WorldData.ORE_NONE:
			overlay.set_cell(cell, OVERLAY_SOURCE, Vector2i(ore - 1, (x * 7 + y * 13) & 1))
		else:
			overlay.erase_cell(cell)

	var wall := data.get_wall(x, y)
	if wall != WorldData.AIR and material == WorldData.AIR:
		walls.set_cell(cell, TERRAIN_SOURCE, Vector2i(0, atlas_row(wall)))
	else:
		walls.erase_cell(cell)

	var liquid := data.get_liquid(x, y)
	if liquid == WorldData.DRY:
		liquids.erase_cell(cell)
	else:
		var surface := data.get_liquid(x, y - 1) != liquid
		var column := (0 if liquid == WorldData.WATER else 2) + (1 if surface else 0)
		liquids.set_cell(cell, LIQUID_SOURCE, Vector2i(column, 0))


## Redraw a cell and its neighbours, whose edge pieces depend on it.
func refresh(cell: Vector2i) -> void:
	for offset in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var c: Vector2i = cell + offset
		if data.in_bounds(c.x, c.y) and is_loaded(c):
			_draw_cell(c)
	_light_dirty = true
	tile_changed.emit(cell)


# =============================================================================
# Changing the world
# =============================================================================

func set_block(cell: Vector2i, material: int) -> void:
	data.set_tile(cell.x, cell.y, material)
	refresh(cell)
	# A block knocked out from under a tree or torch brings it down too.
	var above := cell + Vector2i.UP
	var key := data.idx(above.x, above.y)
	if material == WorldData.AIR and data.objects.has(key) \
			and data.objects[key].type in ["tree", "shrub", "torch", "workbench", "anvil",
				"campfire", "chest", "wardstone", "barrel"]:
		remove_object(above, true)


func add_object(cell: Vector2i, object: Dictionary) -> void:
	var key := data.idx(cell.x, cell.y)
	data.objects[key] = object
	_index_object(key)
	if is_loaded(cell):
		_spawn_object_node(key)
	_light_dirty = true


## Remove an object; returns it. With `drop`, its item falls where it stood.
func remove_object(cell: Vector2i, drop := false) -> Dictionary:
	var key := data.idx(cell.x, cell.y)
	if not data.objects.has(key):
		return {}
	var object: Dictionary = data.objects[key]
	data.objects.erase(key)
	var chunk := cell / CHUNK
	if _objects_by_chunk.has(chunk):
		_objects_by_chunk[chunk].erase(key)
	_lit_objects.erase(key)
	if _object_nodes.has(key):
		_object_nodes[key].queue_free()
		_object_nodes.erase(key)
	_light_dirty = true
	if drop:
		var item := ObjectArt.item_for(object)
		if item != "":
			Game.world_drop(item, 1, centre_of(cell))
		for stack in object.get("loot", []):
			Game.world_drop(stack.id, stack.count, centre_of(cell))
	return object


func object_at(cell: Vector2i) -> Dictionary:
	return data.objects.get(data.idx(cell.x, cell.y), {})


func object_node_at(cell: Vector2i) -> Node2D:
	return _object_nodes.get(data.idx(cell.x, cell.y))


func _spawn_object_node(key: int) -> void:
	if _object_nodes.has(key):
		return
	var cell := Vector2i(key % data.width, key / data.width)
	var node := ObjectArt.make(data.objects[key], cell)
	if node == null:
		return
	object_root.add_child(node)
	_object_nodes[key] = node
	if OBJECT_LIGHTS.has(data.objects[key].type):
		var spec: Array = OBJECT_LIGHTS[data.objects[key].type]
		if data.objects[key].get("lit", true):
			node.add_child(Glow.make(spec[0], spec[1] * 0.42))


# =============================================================================
# Light
# =============================================================================

## Sunlight colour for the current time: warm at the edges of the day,
## moonlit blue at night.
func sky_light() -> Color:
	var t := time_of_day
	var day := clampf(sin((t - 0.25) * TAU) * 1.6 + 0.35, 0.0, 1.0)
	var night := Color(0.20, 0.25, 0.42)
	var noon := Color(1.0, 0.98, 0.94)
	var dusk := Color(1.0, 0.62, 0.42)
	var edge := clampf(1.0 - absf(sin((t - 0.25) * TAU)) * 3.0, 0.0, 1.0)
	return night.lerp(noon.lerp(dusk, edge * 0.7), day)


func is_night() -> bool:
	return time_of_day < 0.22 or time_of_day > 0.78


func _update_lighting() -> void:
	var view := visible_cells().grow(10)
	light_map.resize(view)
	light_map.clear()

	var sky := sky_light()
	for x in range(view.position.x, view.end.x):
		if x < 0 or x >= data.width:
			continue
		# Direct sunlight reaches down to the first solid cell of a column.
		var y := 0
		while y < view.end.y and not data.is_solid(x, y):
			if y >= view.position.y:
				light_map.seed_cell(x, y, sky)
			y += 1
		if y >= view.position.y and y < view.end.y:
			light_map.seed_cell(x, y, sky * 0.85)

	for y in range(max(view.position.y, 0), min(view.end.y, data.height)):
		for x in range(max(view.position.x, 0), min(view.end.x, data.width)):
			var ore := data.get_ore(x, y)
			if ore == WorldData.GLOWSHARD:
				light_map.seed_cell(x, y, GLOWSHARD_LIGHT)
			if data.get_liquid(x, y) == WorldData.LAVA:
				light_map.seed_cell(x, y, LAVA_LIGHT)
			elif data.get_wall(x, y) == WorldData.CRYSTAL and not data.is_solid(x, y):
				light_map.seed_cell(x, y, CRYSTAL_AMBIENT)

	for key in _lit_objects:
		var object: Dictionary = data.objects.get(key, {})
		if object.is_empty() or not object.get("lit", true):
			continue
		var spec: Array = OBJECT_LIGHTS[object.type]
		var cell := Vector2i(key % data.width, key / data.width)
		if view.grow(int(spec[1])).has_point(cell):
			var flicker := 1.0 if object.type == "wardstone" else randf_range(0.92, 1.0)
			light_map.seed_radial(Vector2(cell) + Vector2(0.5, 0.5), spec[1], spec[0] * flicker, data)

	for source in dynamic_lights:
		if not source.is_valid():
			continue
		for light in source.call():
			light_map.seed_radial(light[0], light[1], light[2], data)

	light_map.propagate(data)

	var image := light_map.write_image()
	if light_texture.get_size() != Vector2(image.get_size()):
		light_texture.set_image(image)
	else:
		light_texture.update(image)
	light_sprite.texture = light_texture
	light_sprite.position = Vector2(view.position) * TILE
	light_sprite.scale = Vector2(TILE, TILE)
	_light_dirty = false


## Light level 0..1 at a world position, for spawning and the lantern.
func brightness_at(world_position: Vector2) -> float:
	var cell := cell_of(world_position)
	return light_map.brightness(cell.x, cell.y)


func light_color_at(world_position: Vector2) -> Color:
	var cell := cell_of(world_position)
	return light_map.at(cell.x, cell.y)


## Whether a placed light keeps this cell safe from shades.
func near_placed_light(cell: Vector2i, reach := 8.0) -> bool:
	for key in _lit_objects:
		var object: Dictionary = data.objects.get(key, {})
		if object.is_empty() or not object.get("lit", true):
			continue
		var c := Vector2i(key % data.width, key / data.width)
		if Vector2(c).distance_to(Vector2(cell)) <= reach:
			return true
	return false
