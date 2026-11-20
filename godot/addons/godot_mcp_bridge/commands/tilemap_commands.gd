@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B09 — tilemap commands (6 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4).
##
## TM-RES — every handler resolves `node_path` to either a TileMapLayer (Godot 4.3+, preferred,
## single implicit layer, `layer` param ignored and echoed as 0) or a legacy TileMap (multi-layer,
## `layer` honored and validated). The legacy class is detected by STRING class name and every
## TileMap-only method is invoked dynamically via `call()`, so this file still parses on a future
## Godot that drops the deprecated class. The two APIs differ in arity — TileMapLayer methods take
## `(coords)`, TileMap takes `(layer, coords)` — so all access funnels through the helpers below.


## Upper bound on tilemap_fill_rect: each cell costs a do+undo pair on the main thread, so an
## unbounded rect would freeze the editor past the bridge's request timeout.
const MAX_FILL_CELLS := 65536


func get_commands() -> Dictionary:
	return {
		"tilemap_set_cell": _set_cell,
		"tilemap_fill_rect": _fill_rect,
		"tilemap_get_cell": _get_cell,
		"tilemap_clear": _clear,
		"tilemap_get_info": _get_info,
		"tilemap_get_used_cells": _get_used_cells,
	}


# ---------------------------------------------------------------------------
# TM-RES helpers
# ---------------------------------------------------------------------------


## Returns [Node, null] for a TileMapLayer / legacy TileMap, else [null, error_dict].
func _resolve_tilemap(node_path: String) -> Array:
	var node: Node = find_node_by_path(node_path)
	if node == null or not _is_tilemap(node):
		return [null, error_not_found("TileMapLayer or TileMap at '%s'" % node_path)]
	return [node, null]


func _is_tilemap(node: Node) -> bool:
	return _is_layer_node(node) or _is_legacy(node)


func _is_layer_node(node: Node) -> bool:
	return node is TileMapLayer


## Legacy multi-layer TileMap. String check, NOT a typed cast (the class is deprecated).
func _is_legacy(node: Node) -> bool:
	return node.get_class() == "TileMap"


func _layer_count(node: Node) -> int:
	if _is_legacy(node):
		return int(node.call("get_layers_count"))
	return 1


## Resolves the effective layer index. TileMapLayer -> always 0 (`layer` ignored).
## Legacy TileMap -> the `layer` param (default 0), validated against get_layers_count().
## Returns [int, null] or [null, error_dict].
func _layer_for(node: Node, params: Dictionary, default_layer: int = 0) -> Array:
	if not _is_legacy(node):
		return [0, null]
	var layer: int = optional_int(params, "layer", default_layer)
	var count: int = _layer_count(node)
	if layer < 0 or layer >= count:
		return [
			null,
			error(
				-32602,
				"layer %d is out of range — TileMap has %d layer(s)" % [layer, count],
				{"layer": layer, "layer_count": count}
			)
		]
	return [layer, null]


func _cell_source_id(node: Node, layer: int, coords: Vector2i) -> int:
	if _is_legacy(node):
		return int(node.call("get_cell_source_id", layer, coords))
	return int(node.call("get_cell_source_id", coords))


func _cell_atlas_coords(node: Node, layer: int, coords: Vector2i) -> Vector2i:
	if _is_legacy(node):
		return node.call("get_cell_atlas_coords", layer, coords)
	return node.call("get_cell_atlas_coords", coords)


func _cell_alternative(node: Node, layer: int, coords: Vector2i) -> int:
	if _is_legacy(node):
		return int(node.call("get_cell_alternative_tile", layer, coords))
	return int(node.call("get_cell_alternative_tile", coords))


func _used_cells(node: Node, layer: int) -> Array:
	if _is_legacy(node):
		return node.call("get_used_cells", layer)
	return node.call("get_used_cells")


## Immediate (non-undo) cell write. Undo actions register `set_cell` on the node directly,
## with the arity the node's class expects.
func _do_set_cell(
	node: Node, layer: int, coords: Vector2i, source_id: int, atlas: Vector2i, alternative: int
) -> void:
	if _is_legacy(node):
		node.call("set_cell", layer, coords, source_id, atlas, alternative)
	else:
		node.call("set_cell", coords, source_id, atlas, alternative)


## The full state of one cell — enough to restore it. An empty cell has source_id -1, and
## re-setting a captured empty cell erases it again (set_cell with source_id -1 IS the erase).
func _capture_cell(node: Node, layer: int, coords: Vector2i) -> Dictionary:
	return {
		"layer": layer,
		"coords": coords,
		"source_id": _cell_source_id(node, layer, coords),
		"atlas_coords": _cell_atlas_coords(node, layer, coords),
		"alternative": _cell_alternative(node, layer, coords),
	}


## Registers one `set_cell` on `ur` with the arity `node`'s class expects.
func _add_set_cell(
	ur: EditorUndoRedoManager,
	is_do: bool,
	node: Node,
	layer: int,
	coords: Vector2i,
	source_id: int,
	atlas: Vector2i,
	alternative: int
) -> void:
	if _is_legacy(node):
		if is_do:
			ur.add_do_method(node, "set_cell", layer, coords, source_id, atlas, alternative)
		else:
			ur.add_undo_method(node, "set_cell", layer, coords, source_id, atlas, alternative)
	elif is_do:
		ur.add_do_method(node, "set_cell", coords, source_id, atlas, alternative)
	else:
		ur.add_undo_method(node, "set_cell", coords, source_id, atlas, alternative)


## Registers the restore of one captured cell as an UNDO op.
func _add_restore_cell(ur: EditorUndoRedoManager, node: Node, cell: Dictionary) -> void:
	_add_set_cell(
		ur,
		false,
		node,
		int(cell["layer"]),
		cell["coords"],
		int(cell["source_id"]),
		cell["atlas_coords"],
		int(cell["alternative"])
	)


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _set_cell(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	var lr: Array = _layer_for(node, params)
	if lr[1] != null:
		return lr[1]
	var layer: int = lr[0]

	var coords := Vector2i(optional_int(params, "x", 0), optional_int(params, "y", 0))
	var source_id: int = optional_int(params, "source_id", 0)
	var atlas := Vector2i(optional_int(params, "atlas_x", 0), optional_int(params, "atlas_y", 0))
	var alternative: int = optional_int(params, "alternative", 0)

	var old: Dictionary = _capture_cell(node, layer, coords)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: tilemap_set_cell", UndoRedo.MERGE_DISABLE, node)
	_add_set_cell(ur, true, node, layer, coords, source_id, atlas, alternative)
	_add_restore_cell(ur, node, old)
	ur.commit_action()

	return success(
		{
			"x": coords.x,
			"y": coords.y,
			"layer": layer,
			"source_id": source_id,
			"atlas_x": atlas.x,
			"atlas_y": atlas.y,
			"alternative": alternative,
			"node_class": node.get_class(),
		}
	)


func _fill_rect(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	var lr: Array = _layer_for(node, params)
	if lr[1] != null:
		return lr[1]
	var layer: int = lr[0]

	# Corners come in any order; the rect is inclusive of both.
	var x1: int = optional_int(params, "x1", 0)
	var y1: int = optional_int(params, "y1", 0)
	var x2: int = optional_int(params, "x2", 0)
	var y2: int = optional_int(params, "y2", 0)
	var min_x: int = mini(x1, x2)
	var min_y: int = mini(y1, y2)
	var max_x: int = maxi(x1, x2)
	var max_y: int = maxi(y1, y2)

	# Every cell is a do+undo pair on the editor's main thread. An unbounded rect freezes the
	# editor for minutes, and the bridge abandons the request at its 30s timeout, so the reply
	# lands on a dead id. Refuse up front with a number the caller can act on.
	var cell_count: int = (max_x - min_x + 1) * (max_y - min_y + 1)
	if cell_count > MAX_FILL_CELLS:
		return error(
			-32602,
			"rect covers %d cells, max %d — fill in smaller batches" % [cell_count, MAX_FILL_CELLS],
			{"cell_count": cell_count, "max_cells": MAX_FILL_CELLS}
		)

	var source_id: int = optional_int(params, "source_id", 0)
	var atlas := Vector2i(optional_int(params, "atlas_x", 0), optional_int(params, "atlas_y", 0))
	var alternative: int = optional_int(params, "alternative", 0)

	var captured: Array[Dictionary] = []
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			captured.append(_capture_cell(node, layer, Vector2i(x, y)))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: tilemap_fill_rect", UndoRedo.MERGE_DISABLE, node)
	for cell: Dictionary in captured:
		_add_set_cell(ur, true, node, layer, cell["coords"], source_id, atlas, alternative)
		_add_restore_cell(ur, node, cell)
	ur.commit_action()

	return success(
		{
			"filled": captured.size(),
			"rect": [min_x, min_y, max_x, max_y],
			"layer": layer,
			"source_id": source_id,
			"atlas_x": atlas.x,
			"atlas_y": atlas.y,
			"alternative": alternative,
			"node_class": node.get_class(),
		}
	)


func _get_cell(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	var lr: Array = _layer_for(node, params)
	if lr[1] != null:
		return lr[1]
	var layer: int = lr[0]

	var coords := Vector2i(optional_int(params, "x", 0), optional_int(params, "y", 0))
	var cell: Dictionary = _capture_cell(node, layer, coords)
	var source_id: int = int(cell["source_id"])
	var atlas: Vector2i = cell["atlas_coords"]

	return success(
		{
			"x": coords.x,
			"y": coords.y,
			"layer": layer,
			"source_id": source_id,
			"atlas_x": atlas.x,
			"atlas_y": atlas.y,
			"alternative": int(cell["alternative"]),
			"empty": source_id == -1,
			"node_class": node.get_class(),
		}
	)


func _clear(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	# `layer` presence changes the semantics on a legacy TileMap: present -> clear only that
	# layer, absent -> clear every layer. A TileMapLayer always clears its single layer.
	var layer_given: bool = params.has("layer") and params["layer"] != null
	var affected: Array[int] = []
	if _is_legacy(node):
		if layer_given:
			var lr: Array = _layer_for(node, params)
			if lr[1] != null:
				return lr[1]
			affected.append(lr[0])
		else:
			for i: int in range(_layer_count(node)):
				affected.append(i)
	else:
		affected.append(0)

	var captured: Array[Dictionary] = []
	for layer: int in affected:
		for coords: Vector2i in _used_cells(node, layer):
			captured.append(_capture_cell(node, layer, coords))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: tilemap_clear", UndoRedo.MERGE_DISABLE, node)
	if _is_legacy(node) and layer_given:
		ur.add_do_method(node, "clear_layer", affected[0])
	else:
		ur.add_do_method(node, "clear")
	for cell: Dictionary in captured:
		_add_restore_cell(ur, node, cell)
	ur.commit_action()

	return success(
		{
			"cleared": true,
			"layers": affected,
			"cell_count": captured.size(),
			"node_class": node.get_class(),
		}
	)


func _get_info(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	var layers: Array[Dictionary] = []
	if _is_legacy(node):
		for i: int in range(_layer_count(node)):
			layers.append(
				{
					"index": i,
					"name": str(node.call("get_layer_name", i)),
					"enabled": bool(node.call("is_layer_enabled", i)),
					"used_cell_count": _used_cells(node, i).size(),
				}
			)
	else:
		var tml: TileMapLayer = node as TileMapLayer
		layers.append(
			{
				"index": 0,
				"name": str(tml.name),
				"enabled": tml.enabled,
				"used_cell_count": _used_cells(node, 0).size(),
			}
		)

	var sources: Array[Dictionary] = []
	var tile_size: Array[int] = [0, 0]
	var tile_set: TileSet = node.get("tile_set") as TileSet
	if tile_set != null:
		tile_size = [tile_set.tile_size.x, tile_set.tile_size.y]
		for i: int in range(tile_set.get_source_count()):
			var source_id: int = tile_set.get_source_id(i)
			var src: TileSetSource = tile_set.get_source(source_id)
			var row: Dictionary = {
				"source_id": source_id,
				"type": "" if src == null else src.get_class(),
				"texture": "",
				"tile_count": 0,
			}
			var atlas: TileSetAtlasSource = src as TileSetAtlasSource
			if atlas != null:
				row["tile_count"] = atlas.get_tiles_count()
				if atlas.texture != null:
					row["texture"] = atlas.texture.resource_path
			sources.append(row)

	return success(
		{
			"node_path": String(np[0]),
			"node_class": node.get_class(),
			"layer_count": layers.size(),
			"layers": layers,
			"tile_set_sources": sources,
			"tile_size": tile_size,
		}
	)


func _get_used_cells(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var res: Array = _resolve_tilemap(np[0])
	if res[1] != null:
		return res[1]
	var node: Node = res[0]

	var lr: Array = _layer_for(node, params)
	if lr[1] != null:
		return lr[1]
	var layer: int = lr[0]

	var max_count: int = maxi(0, optional_int(params, "max_count", 500))
	var used: Array = _used_cells(node, layer)

	var cells: Array[Dictionary] = []
	for coords: Vector2i in used:
		if cells.size() >= max_count:
			break
		cells.append(
			{"x": coords.x, "y": coords.y, "source_id": _cell_source_id(node, layer, coords)}
		)

	return success(
		{
			"cells": cells,
			"total": used.size(),
			"returned": cells.size(),
			"truncated": used.size() > cells.size(),
			"layer": layer,
			"node_class": node.get_class(),
		}
	)
