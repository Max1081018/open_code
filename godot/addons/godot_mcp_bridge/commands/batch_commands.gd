@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## batch category (SPEC §6, specs/B12) — 7 tools.
## find_nodes_by_type / find_signal_connections / batch_set_property / batch_add_nodes operate on
## the edited scene (error_no_scene() when none is open). find_node_references /
## get_scene_dependencies / cross_scene_set_property are project-wide and need no open scene.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")
const NodeUtils := preload("res://addons/godot_mcp_bridge/utils/node_utils.gd")

## Extensions searched by find_node_references (addons included — no flag for this tool).
const REFERENCE_EXTENSIONS: PackedStringArray = ["tscn", "gd", "tres", "gdshader"]
const SCENE_EXTENSIONS: PackedStringArray = ["tscn"]

const MAX_REFERENCE_FILES := 100
const MAX_LINES_PER_FILE := 5


func get_commands() -> Dictionary:
	return {
		"find_nodes_by_type": _find_nodes_by_type,
		"find_signal_connections": _find_signal_connections,
		"batch_set_property": _batch_set_property,
		"batch_add_nodes": _batch_add_nodes,
		"find_node_references": _find_node_references,
		"get_scene_dependencies": _get_scene_dependencies,
		"cross_scene_set_property": _cross_scene_set_property,
	}


# ---------------------------------------------------------------------------
# Shared helpers (one file walker for the whole module)
# ---------------------------------------------------------------------------


func _collect_files(root: String, extensions: PackedStringArray, include_addons: bool) -> Array:
	var out: Array = []
	_walk_dir(root, extensions, include_addons, out)
	out.sort()
	return out


func _walk_dir(
	path: String, extensions: PackedStringArray, include_addons: bool, out: Array
) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return

	for entry: String in dir.get_files():
		if entry.begins_with("."):
			continue
		if not extensions.is_empty() and not extensions.has(entry.get_extension().to_lower()):
			continue
		out.append(_join(path, entry))

	for entry: String in dir.get_directories():
		if entry.begins_with("."):
			continue
		if not include_addons and entry == "addons":
			continue
		_walk_dir(_join(path, entry), extensions, include_addons, out)


func _join(base: String, entry: String) -> String:
	if base.ends_with("/"):
		return base + entry
	return "%s/%s" % [base, entry]


func _rel(root: Node, node: Node) -> String:
	if node == root:
		return "."
	return str(root.get_path_to(node))


func _collect_nodes(node: Node, out: Array) -> void:
	out.append(node)
	for child: Node in node.get_children():
		_collect_nodes(child, out)


## Every node at or below `root` whose engine class matches `type_name` (inheritance-aware).
func _collect_class_matches(root: Node, type_name: String) -> Array:
	var all_nodes: Array = []
	_collect_nodes(root, all_nodes)
	var out: Array = []
	for node: Node in all_nodes:
		if node.is_class(type_name):
			out.append(node)
	return out


func _error_no_undo() -> Dictionary:
	return error(-32603, "Undo/redo manager is unavailable")


## [value, null] / [null, error_dict] — mirrors require_string for the untyped `value` param.
func _require_value(params: Dictionary) -> Array:
	if not params.has("value") or params["value"] == null:
		return [null, error(-32602, "Missing required parameter: value")]
	return [params["value"], null]


# ---------------------------------------------------------------------------
# find_nodes_by_type
# ---------------------------------------------------------------------------


func _find_nodes_by_type(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "type")
	if res[1] != null:
		return res[1]
	var type_name: String = res[0]
	var recursive: bool = optional_bool(params, "recursive", true)

	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var candidates: Array = []
	if recursive:
		candidates = _collect_class_matches(root, type_name)
	elif root.is_class(type_name):
		candidates.append(root)

	var matches: Array = []
	for node: Node in candidates:
		matches.append({"path": _rel(root, node), "name": str(node.name), "type": node.get_class()})

	return success({"type": type_name, "matches": matches, "count": matches.size()})


# ---------------------------------------------------------------------------
# find_signal_connections
# ---------------------------------------------------------------------------


func _find_signal_connections(params: Dictionary) -> Dictionary:
	var signal_filter: String = optional_string(params, "signal_name", "")
	var path_filter: String = optional_string(params, "node_path", "")

	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var nodes: Array = []
	_collect_nodes(root, nodes)

	var connections: Array = []
	for node: Node in nodes:
		var source: String = _rel(root, node)
		if not path_filter.is_empty() and not source.contains(path_filter):
			continue
		for sig: Dictionary in node.get_signal_list():
			var sig_name: String = str(sig.get("name", ""))
			if sig_name.is_empty():
				continue
			if not signal_filter.is_empty() and not sig_name.contains(signal_filter):
				continue
			for conn: Dictionary in node.get_signal_connection_list(sig_name):
				var raw: Variant = conn.get("callable")
				if typeof(raw) != TYPE_CALLABLE:
					continue
				var callable: Callable = raw
				connections.append(
					{
						"source": source,
						"signal": sig_name,
						"target": _target_label(root, callable.get_object()),
						"method": str(callable.get_method()),
					}
				)

	return success({"connections": connections, "count": connections.size()})


## Node inside the edited scene -> path relative to root; anything else -> its class name.
func _target_label(root: Node, obj: Object) -> String:
	if obj == null:
		return ""
	var node: Node = obj as Node
	if node != null and (node == root or root.is_ancestor_of(node)):
		return _rel(root, node)
	return obj.get_class()


# ---------------------------------------------------------------------------
# batch_set_property
# ---------------------------------------------------------------------------


func _batch_set_property(params: Dictionary) -> Dictionary:
	var type_res: Array = require_string(params, "type")
	if type_res[1] != null:
		return type_res[1]
	var type_name: String = type_res[0]

	var prop_res: Array = require_string(params, "property")
	if prop_res[1] != null:
		return prop_res[1]
	var property: String = prop_res[0]

	var value_res: Array = _require_value(params)
	if value_res[1] != null:
		return value_res[1]
	var raw_value: Variant = value_res[0]

	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	# Nodes lacking the property are skipped silently; zero matches is a success, not an error.
	var targets: Array = []
	for node: Node in _collect_class_matches(root, type_name):
		if property in node:
			targets.append(node)

	if targets.is_empty():
		return success({"type": type_name, "property": property, "changed": [], "count": 0})

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	var changed: Array = []
	ur.create_action("MCP: batch_set_property")
	for node: Node in targets:
		var old_value: Variant = node.get(property)
		var new_value: Variant = PropertyParser.parse_value(raw_value, typeof(old_value))
		ur.add_do_property(node, property, new_value)
		ur.add_undo_property(node, property, old_value)
		changed.append(
			{
				"node": _rel(root, node),
				"old": PropertyParser.serialize_value(old_value),
				"new": PropertyParser.serialize_value(new_value),
			}
		)
	ur.commit_action()

	return success(
		{"type": type_name, "property": property, "changed": changed, "count": changed.size()}
	)


# ---------------------------------------------------------------------------
# batch_add_nodes
# ---------------------------------------------------------------------------


func _batch_add_nodes(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	if not params.has("nodes"):
		return error(-32602, "Missing required parameter: nodes")
	var raw: Variant = params["nodes"]
	if typeof(raw) != TYPE_ARRAY:
		return error(-32602, "Parameter 'nodes' must be an array of node specs")
	var entries: Array = raw
	if entries.is_empty():
		return error(-32602, "Parameter 'nodes' must not be empty")

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	var created: Array = []
	var errors: Array = []
	# Nodes made by earlier entries of this same batch, keyed by every path they answer to.
	var batch_lookup: Dictionary = {}
	# Adds whose parent already existed in the scene — these carry their subtrees through undo.
	var top_adds: Array = []
	var all_created: Array = []

	for i: int in range(entries.size()):
		var entry_raw: Variant = entries[i]
		if typeof(entry_raw) != TYPE_DICTIONARY:
			errors.append({"index": i, "error": "Entry must be an object"})
			continue
		var entry: Dictionary = entry_raw

		var type_name: String = optional_string(entry, "type", "")
		if type_name.is_empty():
			errors.append({"index": i, "error": "Missing required field: type"})
			continue
		if not ClassDB.class_exists(type_name):
			errors.append({"index": i, "error": "Unknown class: %s" % type_name})
			continue
		if not ClassDB.is_parent_class(type_name, "Node"):
			errors.append({"index": i, "error": "Class does not derive from Node: %s" % type_name})
			continue
		if not ClassDB.can_instantiate(type_name):
			errors.append({"index": i, "error": "Class cannot be instantiated: %s" % type_name})
			continue

		var parent_path: String = optional_string(entry, "parent_path", ".")
		if parent_path.is_empty():
			parent_path = "."

		var parent: Node = null
		if batch_lookup.has(parent_path):
			parent = batch_lookup[parent_path]
		else:
			parent = find_node_by_path(parent_path)
		if parent == null:
			errors.append({"index": i, "error": "Parent node not found: %s" % parent_path})
			continue

		var node: Node = ClassDB.instantiate(type_name) as Node
		if node == null:
			errors.append({"index": i, "error": "Could not instantiate: %s" % type_name})
			continue

		# Always resolve a name; an empty one makes Godot fall back to "@Sprite2D@18537".
		var node_name: String = optional_string(entry, "name", "")
		node.name = unique_child_name(parent, node_name, node.get_class())

		var properties: Dictionary = {}
		var props_raw: Variant = entry.get("properties", {})
		if typeof(props_raw) == TYPE_DICTIONARY:
			properties = props_raw
		for key: Variant in properties:
			var prop_name: String = str(key)
			if not (prop_name in node):
				continue
			var current: Variant = node.get(prop_name)
			node.set(prop_name, PropertyParser.parse_value(properties[key], typeof(current)))

		# Applied eagerly: Godot's collision auto-rename must settle so we can report the final
		# path, and a later entry may parent onto this node. The undo action below is therefore
		# committed with execute = false.
		var parent_is_new: bool = _is_batch_node(all_created, parent)
		parent.add_child(node, true)
		node.owner = root

		all_created.append(node)
		if not parent_is_new:
			top_adds.append({"parent": parent, "node": node})

		var node_path: String = _rel(root, node)
		batch_lookup[node_path] = node
		if not batch_lookup.has(str(node.name)):
			batch_lookup[str(node.name)] = node

		created.append(
			{"index": i, "node_path": node_path, "type": type_name, "name": str(node.name)}
		)

	if created.is_empty():
		return success({"created": [], "errors": errors, "count": 0})

	ur.create_action("MCP: batch_add_nodes")
	for add: Dictionary in top_adds:
		var parent_node: Node = add["parent"]
		var child_node: Node = add["node"]
		ur.add_do_method(parent_node, "add_child", child_node, true)
		ur.add_do_reference(child_node)
		ur.add_undo_method(parent_node, "remove_child", child_node)
	for node: Node in all_created:
		ur.add_do_method(node, "set_owner", root)
	ur.commit_action(false)

	# Any nested children the instantiated types brought along also belong to the scene.
	for node: Node in all_created:
		NodeUtils.set_owner_recursive(node, root)

	return success({"created": created, "errors": errors, "count": created.size()})


func _is_batch_node(all_created: Array, node: Node) -> bool:
	for made: Node in all_created:
		if made == node:
			return true
	return false


# ---------------------------------------------------------------------------
# find_node_references
# ---------------------------------------------------------------------------


func _find_node_references(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "pattern")
	if res[1] != null:
		return res[1]
	var pattern: String = res[0]

	var files: Array = _collect_files("res://", REFERENCE_EXTENSIONS, true)

	var matches: Array = []
	var truncated: bool = false

	for file_path: String in files:
		if matches.size() >= MAX_REFERENCE_FILES:
			truncated = true
			break
		var text: String = FileAccess.get_file_as_string(file_path)
		if not text.contains(pattern):
			continue
		var lines: PackedStringArray = text.split("\n")
		var hit_lines: Array = []
		for i: int in range(lines.size()):
			if not lines[i].contains(pattern):
				continue
			hit_lines.append(i + 1)
			if hit_lines.size() >= MAX_LINES_PER_FILE:
				break
		if hit_lines.is_empty():
			continue
		matches.append({"file": file_path, "lines": hit_lines})

	return success(
		{
			"pattern": pattern,
			"matches": matches,
			"count": matches.size(),
			"truncated": truncated,
		}
	)


# ---------------------------------------------------------------------------
# get_scene_dependencies
# ---------------------------------------------------------------------------


func _get_scene_dependencies(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	if not FileAccess.file_exists(path):
		return error_not_found("File: %s" % path)

	var dependencies: Array = []
	for entry: String in ResourceLoader.get_dependencies(path):
		# "uid://abc::PackedScene::res://foo.tscn" — 3 slices; bare paths arrive as one.
		var parts: PackedStringArray = entry.split("::")
		if parts.size() >= 3:
			dependencies.append({"path": parts[2], "uid": parts[0], "type": parts[1]})
		else:
			dependencies.append({"path": entry, "uid": "", "type": ""})

	return success({"path": path, "dependencies": dependencies, "count": dependencies.size()})


# ---------------------------------------------------------------------------
# cross_scene_set_property
# ---------------------------------------------------------------------------


func _cross_scene_set_property(params: Dictionary) -> Dictionary:
	var type_res: Array = require_string(params, "type")
	if type_res[1] != null:
		return type_res[1]
	var type_name: String = type_res[0]

	var prop_res: Array = require_string(params, "property")
	if prop_res[1] != null:
		return prop_res[1]
	var property: String = prop_res[0]

	var value_res: Array = _require_value(params)
	if value_res[1] != null:
		return value_res[1]
	var raw_value: Variant = value_res[0]

	var path_filter: String = optional_string(params, "path_filter", "res://")
	var exclude_addons: bool = optional_bool(params, "exclude_addons", true)
	var force: bool = optional_bool(params, "force", false)
	# Cross-field default: preview unless the caller explicitly forced a write. This is why
	# dry_run carries no bridge-side zod default — default(true) would make force a no-op.
	var dry_run: bool = optional_bool(params, "dry_run", not force)

	if not dry_run and not force:
		return error(-32602, "cross_scene_set_property requires force=true when dry_run=false")

	if not DirAccess.dir_exists_absolute(path_filter):
		return error_not_found("Directory: %s" % path_filter)

	var scenes: Array = _collect_files(path_filter, SCENE_EXTENSIONS, not exclude_addons)

	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()
	var active_root: Node = get_edited_root()
	var active_path: String = ""
	if active_root != null:
		active_path = active_root.scene_file_path

	var changed: Array = []
	var skipped: Array = []
	var written: Array = []
	var touched: Dictionary = {}

	for scene_path: String in scenes:
		var is_open: bool = open_scenes.has(scene_path)
		var is_active: bool = not active_path.is_empty() and scene_path == active_path

		# Preview: nothing is written and every open scene is skipped and listed.
		if dry_run:
			if is_open:
				skipped.append(
					{"scene": scene_path, "reason": "open in the editor — not inspected on disk"}
				)
				continue
			for row: Dictionary in _preview_scene(scene_path, type_name, property, raw_value):
				changed.append(row)
				touched[scene_path] = true
			continue

		# Write mode (force = true).
		if is_active:
			for row: Dictionary in _apply_live(
				active_root, scene_path, type_name, property, raw_value
			):
				changed.append(row)
				touched[scene_path] = true
			continue

		if is_open:
			skipped.append(
				{
					"scene": scene_path,
					"reason": "open in a non-active editor tab — unsaved changes protected",
				}
			)
			continue

		var guard: Dictionary = guard_offline_scene_save(scene_path)
		if not guard.is_empty():
			skipped.append({"scene": scene_path, "reason": "conflict guard refused the write"})
			continue

		var outcome: Dictionary = _write_scene(scene_path, type_name, property, raw_value)
		if outcome.has("error"):
			return error(
				-32603,
				str(outcome["error"]),
				{"scene": scene_path, "scenes_written": written}
			)
		var rows: Array = outcome.get("rows", [])
		if rows.is_empty():
			continue
		written.append(scene_path)
		touched[scene_path] = true
		for row: Dictionary in rows:
			changed.append(row)

	if not written.is_empty():
		var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.scan()

	return success(
		{
			"type": type_name,
			"property": property,
			"dry_run": dry_run,
			"force": force,
			"changed": changed,
			"skipped_open_scenes": skipped,
			"scenes_touched": touched.size(),
			"node_count": changed.size(),
		}
	)


## Instantiate a closed scene, collect would-change rows, free it. Writes nothing.
func _preview_scene(
	scene_path: String, type_name: String, property: String, raw_value: Variant
) -> Array:
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return []
	var instance: Node = packed.instantiate()
	if instance == null:
		return []

	var rows: Array = []
	for node: Node in _collect_class_matches(instance, type_name):
		if not (property in node):
			continue
		var old_value: Variant = node.get(property)
		var new_value: Variant = PropertyParser.parse_value(raw_value, typeof(old_value))
		rows.append(
			{
				"scene": scene_path,
				"node": _rel(instance, node),
				"old": PropertyParser.serialize_value(old_value),
				"new": PropertyParser.serialize_value(new_value),
			}
		)

	instance.free()
	return rows


## Load, mutate, re-pack and save a closed scene. {"rows": [...]} or {"error": "message"}.
func _write_scene(
	scene_path: String, type_name: String, property: String, raw_value: Variant
) -> Dictionary:
	var packed: PackedScene = ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return {"error": "Could not load as PackedScene: %s" % scene_path}
	var instance: Node = packed.instantiate()
	if instance == null:
		return {"error": "Could not instantiate scene: %s" % scene_path}

	var rows: Array = []
	for node: Node in _collect_class_matches(instance, type_name):
		if not (property in node):
			continue
		var old_value: Variant = node.get(property)
		var new_value: Variant = PropertyParser.parse_value(raw_value, typeof(old_value))
		node.set(property, new_value)
		rows.append(
			{
				"scene": scene_path,
				"node": _rel(instance, node),
				"old": PropertyParser.serialize_value(old_value),
				"new": PropertyParser.serialize_value(new_value),
			}
		)

	if rows.is_empty():
		instance.free()
		return {"rows": []}

	var repacked := PackedScene.new()
	var pack_err: int = repacked.pack(instance)
	if pack_err != OK:
		instance.free()
		return {"error": "Could not pack scene %s: %s" % [scene_path, error_string(pack_err)]}

	var save_err: int = ResourceSaver.save(repacked, scene_path)
	instance.free()
	if save_err != OK:
		return {"error": "Could not save scene %s: %s" % [scene_path, error_string(save_err)]}

	return {"rows": rows}


## Mutate the ACTIVE edited scene in memory, in one undo action.
func _apply_live(
	root: Node, scene_path: String, type_name: String, property: String, raw_value: Variant
) -> Array:
	var targets: Array = []
	for node: Node in _collect_class_matches(root, type_name):
		if property in node:
			targets.append(node)
	if targets.is_empty():
		return []

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return []

	var rows: Array = []
	ur.create_action("MCP: cross_scene_set_property")
	for node: Node in targets:
		var old_value: Variant = node.get(property)
		var new_value: Variant = PropertyParser.parse_value(raw_value, typeof(old_value))
		ur.add_do_property(node, property, new_value)
		ur.add_undo_property(node, property, old_value)
		rows.append(
			{
				"scene": scene_path,
				"node": _rel(root, node),
				"old": PropertyParser.serialize_value(old_value),
				"new": PropertyParser.serialize_value(new_value),
			}
		)
	ur.commit_action()

	return rows
