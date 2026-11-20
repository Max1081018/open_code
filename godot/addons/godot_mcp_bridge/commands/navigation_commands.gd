@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B09 — navigation commands (5 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4) — except
## bake_navigation_mesh, which is deliberately NOT undoable (its output is regenerable).
##
## MODE-RES — "2d"/"3d" force the dimension; "auto" infers it from the target node via
## _is_3d_context(). Properties whose Godot defaults differ between 2D and 3D are applied ONLY
## when the caller passed them (params.has()), so a bridge-side default can never leak one
## dimension's value into the other.

const NodeUtils := preload("res://addons/godot_mcp_bridge/utils/node_utils.gd")

const NAV_LAYER_COUNT := 32


func get_commands() -> Dictionary:
	return {
		"setup_navigation_region": _setup_navigation_region,
		"bake_navigation_mesh": _bake_navigation_mesh,
		"setup_navigation_agent": _setup_navigation_agent,
		"set_navigation_layers": _set_navigation_layers,
		"get_navigation_info": _get_navigation_info,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## MODE-RES: Node3D -> 3D, Node2D -> 2D, else the nearest such ancestor decides; none -> 2D.
func _is_3d_context(node: Node) -> bool:
	var cur: Node = node
	while cur != null:
		if cur is Node3D:
			return true
		if cur is Node2D:
			return false
		cur = cur.get_parent()
	return false


## Resolves the requested dimension. `mode` is "2d" / "3d" / "auto".
func _resolve_mode(node: Node, params: Dictionary) -> bool:
	var mode: String = optional_string(params, "mode", "auto").to_lower()
	if mode == "3d":
		return true
	if mode == "2d":
		return false
	return _is_3d_context(node)


func _has(params: Dictionary, key: String) -> bool:
	return params.has(key) and params[key] != null


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


func _rel(root: Node, node: Node) -> String:
	if node == root:
		return "."
	return String(root.get_path_to(node))


## Adds `child` under `parent` in ONE undo action labeled "MCP: <tool_name>".
func _commit_add_child(tool_name: String, parent: Node, child: Node, root: Node) -> Dictionary:
	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		child.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: %s" % tool_name, UndoRedo.MERGE_DISABLE, parent)
	ur.add_do_method(parent, "add_child", child, true)
	ur.add_do_method(child, "set_owner", root)
	ur.add_do_reference(child)
	ur.add_undo_method(parent, "remove_child", child)
	ur.commit_action()

	NodeUtils.set_owner_recursive(child, root)
	return {}


func _is_nav_node(node: Node) -> bool:
	return (
		node is NavigationRegion2D
		or node is NavigationRegion3D
		or node is NavigationAgent2D
		or node is NavigationAgent3D
	)


func _is_2d_nav_node(node: Node) -> bool:
	return node is NavigationRegion2D or node is NavigationAgent2D


## ProjectSettings-named navigation layers of one dimension, as {bit (1-based): name}.
func _project_layer_names(is_3d: bool) -> Dictionary:
	var prefix: String = "layer_names/3d_navigation/layer_" if is_3d else (
		"layer_names/2d_navigation/layer_"
	)
	var out: Dictionary = {}
	for n: int in range(1, NAV_LAYER_COUNT + 1):
		var name: String = str(ProjectSettings.get_setting("%s%d" % [prefix, n], ""))
		if not name.is_empty():
			out[n] = name
	return out


## Decodes a bitmask into [{bit (1-based), name ("" when unnamed)}].
func _decode_layers(bitmask: int, is_3d: bool) -> Array[Dictionary]:
	var names: Dictionary = _project_layer_names(is_3d)
	var out: Array[Dictionary] = []
	for n: int in range(1, NAV_LAYER_COUNT + 1):
		if bitmask & (1 << (n - 1)) != 0:
			out.append({"bit": n, "name": str(names.get(n, ""))})
	return out


## One outline vertex, accepted as [x, y] or {x, y}. Returns [Vector2, null] or [null, error].
func _parse_point(raw: Variant, index: int) -> Array:
	if typeof(raw) == TYPE_ARRAY:
		var a: Array = raw
		if a.size() != 2:
			return [null, error(-32602, "outline[%d] must have exactly 2 numbers" % index)]
		return [Vector2(float(a[0]), float(a[1])), null]
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		if not d.has("x") or not d.has("y"):
			return [null, error(-32602, "outline[%d] must have x and y" % index)]
		return [Vector2(float(d["x"]), float(d["y"])), null]
	return [null, error(-32602, "outline[%d] must be [x, y] or {x, y}" % index)]


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _setup_navigation_region(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var parent: Node = find_node_by_path(np[0])
	if parent == null:
		return error_not_found("Node at '%s'" % np[0])

	var is_3d: bool = _resolve_mode(parent, params)
	var applied: Dictionary = {}
	var region: Node = null

	if is_3d:
		var region3d := NavigationRegion3D.new()
		var mesh := NavigationMesh.new()
		# 3D fallbacks (meters / degrees) — see spec B09 setup_navigation_region.
		mesh.agent_radius = optional_float(params, "agent_radius", 0.5)
		mesh.cell_size = optional_float(params, "cell_size", 0.25)
		mesh.agent_height = optional_float(params, "agent_height", 1.5)
		mesh.agent_max_climb = optional_float(params, "agent_max_climb", 0.25)
		mesh.agent_max_slope = optional_float(params, "agent_max_slope", 45.0)
		mesh.cell_height = optional_float(params, "cell_height", 0.25)
		region3d.navigation_mesh = mesh
		applied = {
			"agent_radius": mesh.agent_radius,
			"cell_size": mesh.cell_size,
			"agent_height": mesh.agent_height,
			"agent_max_climb": mesh.agent_max_climb,
			"agent_max_slope": mesh.agent_max_slope,
			"cell_height": mesh.cell_height,
		}
		region = region3d
	else:
		var region2d := NavigationRegion2D.new()
		var poly := NavigationPolygon.new()
		if _has(params, "cell_size"):
			poly.cell_size = optional_float(params, "cell_size", poly.cell_size)
			applied["cell_size"] = poly.cell_size
		if _has(params, "agent_radius"):
			poly.agent_radius = optional_float(params, "agent_radius", poly.agent_radius)
			applied["agent_radius"] = poly.agent_radius
		if _has(params, "source_geometry_mode"):
			var sgm: String = optional_string(params, "source_geometry_mode", "root_node")
			match sgm:
				"root_node":
					poly.source_geometry_mode = (
						NavigationPolygon.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
					)
				"groups_with_children":
					poly.source_geometry_mode = (
						NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
					)
				"groups_explicit":
					poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_EXPLICIT
				_:
					region2d.free()
					return error(
						-32602,
						(
							"source_geometry_mode must be root_node, groups_with_children or "
							+ "groups_explicit, got '%s'" % sgm
						)
					)
			applied["source_geometry_mode"] = sgm
		region2d.navigation_polygon = poly
		region = region2d

	var type_name: String = "NavigationRegion3D" if is_3d else "NavigationRegion2D"
	region.name = unique_child_name(parent, optional_string(params, "name", type_name), type_name)

	if _has(params, "navigation_layers"):
		var layers: int = optional_int(params, "navigation_layers", 1)
		region.set("navigation_layers", layers)
		applied["navigation_layers"] = layers

	var err: Dictionary = _commit_add_child("setup_navigation_region", parent, region, root)
	if not err.is_empty():
		return err

	return success(
		{
			"node_path": _rel(root, region),
			"type": type_name,
			"created": true,
			"mode": "3d" if is_3d else "2d",
			"parent": String(np[0]),
			"applied": applied,
		}
	)


func _bake_navigation_mesh(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node: Node = find_node_by_path(np[0])
	if node == null:
		return error_not_found("Node at '%s'" % np[0])

	var region3d: NavigationRegion3D = node as NavigationRegion3D
	var region2d: NavigationRegion2D = node as NavigationRegion2D
	if region3d == null and region2d == null:
		return error(
			-32602,
			(
				"'%s' is not a NavigationRegion2D or NavigationRegion3D (got %s)"
				% [np[0], node.get_class()]
			)
		)

	var out: Dictionary = {"node_path": String(np[0]), "baked": true}

	if region3d != null:
		if region3d.navigation_mesh == null:
			return error(-32000, "region has no NavigationMesh")
		region3d.bake_navigation_mesh(false)
		out["type"] = "NavigationRegion3D"
		out["vertex_count"] = region3d.navigation_mesh.get_vertices().size()
		out["polygon_count"] = region3d.navigation_mesh.get_polygon_count()
	else:
		out["type"] = "NavigationRegion2D"
		var poly: NavigationPolygon = region2d.navigation_polygon
		var created_polygon: bool = false
		if poly == null:
			poly = NavigationPolygon.new()
			region2d.navigation_polygon = poly
			created_polygon = true
		out["created_polygon"] = created_polygon

		if _has(params, "outline"):
			var raw: Variant = params["outline"]
			if typeof(raw) != TYPE_ARRAY:
				return error(-32602, "outline must be an array of [x, y] or {x, y} points")
			var raw_points: Array = raw
			if raw_points.size() < 3:
				return error(
					-32602,
					"outline needs at least 3 vertices, got %d" % raw_points.size()
				)
			var points := PackedVector2Array()
			for i: int in range(raw_points.size()):
				var pt: Array = _parse_point(raw_points[i], i)
				if pt[1] != null:
					return pt[1]
				points.append(pt[0])
			# Explicit outline replaces the region's geometry wholesale.
			poly.clear_outlines()
			poly.add_outline(points)
			poly.make_polygons_from_outlines()
			out["outline_vertices"] = points.size()
		else:
			region2d.bake_navigation_polygon(false)

		out["polygon_count"] = poly.get_polygon_count()
		out["outline_count"] = poly.get_outline_count()

	# Bake output is regenerable, so it is deliberately not an undo action — but the scene did
	# change, so flag it as unsaved.
	EditorInterface.mark_scene_as_unsaved()
	return success(out)


func _setup_navigation_agent(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var parent: Node = find_node_by_path(np[0])
	if parent == null:
		return error_not_found("Node at '%s'" % np[0])

	var is_3d: bool = _resolve_mode(parent, params)
	var type_name: String = "NavigationAgent3D" if is_3d else "NavigationAgent2D"

	var agent: Node = null
	if is_3d:
		agent = NavigationAgent3D.new()
	else:
		agent = NavigationAgent2D.new()
	agent.name = unique_child_name(parent, optional_string(params, "name", type_name), type_name)

	# Godot's 2D and 3D agent defaults differ (px vs m), so ONLY the props actually passed are set.
	var applied: Dictionary = {}
	for key: String in [
		"path_desired_distance",
		"target_desired_distance",
		"radius",
		"neighbor_distance",
		"max_speed",
	]:
		if _has(params, key):
			var f: float = optional_float(params, key, 0.0)
			agent.set(key, f)
			applied[key] = f
	for key: String in ["max_neighbors", "navigation_layers"]:
		if _has(params, key):
			var i: int = optional_int(params, key, 0)
			agent.set(key, i)
			applied[key] = i
	if _has(params, "avoidance_enabled"):
		var b: bool = optional_bool(params, "avoidance_enabled", false)
		agent.set("avoidance_enabled", b)
		applied["avoidance_enabled"] = b

	var err: Dictionary = _commit_add_child("setup_navigation_agent", parent, agent, root)
	if not err.is_empty():
		return err

	return success(
		{
			"node_path": _rel(root, agent),
			"type": type_name,
			"created": true,
			"mode": "3d" if is_3d else "2d",
			"parent": String(np[0]),
			"applied": applied,
		}
	)


func _set_navigation_layers(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node: Node = find_node_by_path(np[0])
	if node == null:
		return error_not_found("Node at '%s'" % np[0])
	if not _is_nav_node(node):
		return error(
			-32602,
			(
				"'%s' is not a NavigationRegion2D/3D or NavigationAgent2D/3D (got %s)"
				% [np[0], node.get_class()]
			)
		)

	var is_3d: bool = not _is_2d_nav_node(node)

	# Exactly one of layers / layer_bits / layer_names.
	var given: Array[String] = []
	for key: String in ["layers", "layer_bits", "layer_names"]:
		if _has(params, key):
			given.append(key)
	if given.size() != 1:
		return error(
			-32602,
			(
				"Provide exactly one of layers, layer_bits or layer_names (got %d: %s)"
				% [given.size(), ", ".join(given)]
			)
		)

	var bitmask: int = 0
	match given[0]:
		"layers":
			bitmask = optional_int(params, "layers", 0)
		"layer_bits":
			var raw_bits: Variant = params["layer_bits"]
			if typeof(raw_bits) != TYPE_ARRAY:
				return error(-32602, "layer_bits must be an array of 1-based bit numbers")
			for raw: Variant in (raw_bits as Array):
				var bit: int = int(raw)
				if bit < 1 or bit > NAV_LAYER_COUNT:
					return error(
						-32602,
						"layer_bits entries must be 1..%d, got %d" % [NAV_LAYER_COUNT, bit]
					)
				bitmask |= 1 << (bit - 1)
		"layer_names":
			var raw_names: Variant = params["layer_names"]
			if typeof(raw_names) != TYPE_ARRAY:
				return error(-32602, "layer_names must be an array of strings")
			var names: Dictionary = _project_layer_names(is_3d)
			for raw: Variant in (raw_names as Array):
				var wanted: String = str(raw)
				var bit: int = 0
				for n: int in names:
					if str(names[n]) == wanted:
						bit = n
						break
				if bit == 0:
					return error_not_found(
						(
							"Navigation layer named '%s' (%s)"
							% [wanted, "3d" if is_3d else "2d"]
						)
					)
				bitmask |= 1 << (bit - 1)

	var old_value: int = int(node.get("navigation_layers"))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_navigation_layers", UndoRedo.MERGE_DISABLE, node)
	ur.add_do_property(node, "navigation_layers", bitmask)
	ur.add_undo_property(node, "navigation_layers", old_value)
	ur.commit_action()

	return success(
		{
			"node_path": String(np[0]),
			"bitmask": bitmask,
			"previous_bitmask": old_value,
			"active_layers": _decode_layers(bitmask, is_3d),
		}
	)


func _get_navigation_info(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node: Node = find_node_by_path(np[0])
	if node == null:
		return error_not_found("Node at '%s'" % np[0])

	var regions: Array[Dictionary] = []
	var agents: Array[Dictionary] = []
	_collect_navigation(node, root, regions, agents)

	return success(
		{
			"node_path": String(np[0]),
			"regions": regions,
			"agents": agents,
			"region_count": regions.size(),
			"agent_count": agents.size(),
			"layer_names_2d": _project_layer_names(false),
			"layer_names_3d": _project_layer_names(true),
		}
	)


## Depth-first over `node` and its descendants, appending region/agent rows.
func _collect_navigation(
	node: Node, root: Node, regions: Array[Dictionary], agents: Array[Dictionary]
) -> void:
	if node is NavigationRegion2D:
		var r2: NavigationRegion2D = node
		var row: Dictionary = {
			"path": _rel(root, node),
			"type": "NavigationRegion2D",
			"enabled": r2.enabled,
			"navigation_layers": r2.navigation_layers,
			"has_polygon": r2.navigation_polygon != null,
		}
		var poly: NavigationPolygon = r2.navigation_polygon
		if poly != null:
			row["outline_count"] = poly.get_outline_count()
			row["polygon_count"] = poly.get_polygon_count()
			row["cell_size"] = poly.cell_size
			row["agent_radius"] = poly.agent_radius
		regions.append(row)
	elif node is NavigationRegion3D:
		var r3: NavigationRegion3D = node
		var row3: Dictionary = {
			"path": _rel(root, node),
			"type": "NavigationRegion3D",
			"enabled": r3.enabled,
			"navigation_layers": r3.navigation_layers,
			"has_mesh": r3.navigation_mesh != null,
		}
		var mesh: NavigationMesh = r3.navigation_mesh
		if mesh != null:
			row3["agent_radius"] = mesh.agent_radius
			row3["agent_height"] = mesh.agent_height
			row3["agent_max_climb"] = mesh.agent_max_climb
			row3["agent_max_slope"] = mesh.agent_max_slope
			row3["cell_size"] = mesh.cell_size
			row3["cell_height"] = mesh.cell_height
		regions.append(row3)
	elif node is NavigationAgent2D or node is NavigationAgent3D:
		agents.append(
			{
				"path": _rel(root, node),
				"type": node.get_class(),
				"radius": float(node.get("radius")),
				"max_speed": float(node.get("max_speed")),
				"path_desired_distance": float(node.get("path_desired_distance")),
				"target_desired_distance": float(node.get("target_desired_distance")),
				"neighbor_distance": float(node.get("neighbor_distance")),
				"max_neighbors": int(node.get("max_neighbors")),
				"avoidance_enabled": bool(node.get("avoidance_enabled")),
				"navigation_layers": int(node.get("navigation_layers")),
			}
		)

	for child: Node in node.get_children():
		_collect_navigation(child, root, regions, agents)
