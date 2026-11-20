@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## analysis category (SPEC §6, specs/B12) — 6 tools.
## Every handler is editor-side. Only analyze_scene_complexity (with an empty `path`) needs an
## open scene; analyze_signal_flow always does. The rest never call error_no_scene().

## Candidate resource extensions considered by find_unused_resources.
const RESOURCE_EXTENSIONS: PackedStringArray = [
	"tres",
	"tscn",
	"png",
	"jpg",
	"jpeg",
	"svg",
	"webp",
	"wav",
	"ogg",
	"mp3",
	"ttf",
	"otf",
	"gdshader",
	"material",
	"theme",
	"stylebox",
	"font",
	"anim",
]

## Text files scanned for `res://` references / grepped for substrings.
const TEXT_EXTENSIONS: PackedStringArray = ["tscn", "gd", "tres", "cfg", "godot"]
const SCENE_EXTENSIONS: PackedStringArray = ["tscn"]

const MAX_LINE_CHARS := 200

const NODE_COUNT_WARNING := 500
const NODE_COUNT_CRITICAL := 1000
const DEPTH_WARNING := 10
const DEPTH_CRITICAL := 15


func get_commands() -> Dictionary:
	return {
		"find_unused_resources": _find_unused_resources,
		"analyze_signal_flow": _analyze_signal_flow,
		"analyze_scene_complexity": _analyze_scene_complexity,
		"find_script_references": _find_script_references,
		"detect_circular_dependencies": _detect_circular_dependencies,
		"get_project_statistics": _get_project_statistics,
	}


# ---------------------------------------------------------------------------
# Shared file walk (one walker for the whole module)
# ---------------------------------------------------------------------------


## Recursive DirAccess walk. Skips dotted entries (.godot, .import, …) and, unless
## `include_addons`, any directory literally named "addons" at any depth.
## `extensions` empty means "every file".
func _collect_files(root: String, extensions: PackedStringArray, include_addons: bool) -> Array:
	var out: Array = []
	_walk_dir(root, extensions, include_addons, out)
	out.sort()
	return out


func _walk_dir(path: String, extensions: PackedStringArray, include_addons: bool, out: Array) -> void:
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


# ---------------------------------------------------------------------------
# find_unused_resources
# ---------------------------------------------------------------------------


func _find_unused_resources(params: Dictionary) -> Dictionary:
	var root_path: String = optional_string(params, "path", "res://")
	var include_addons: bool = optional_bool(params, "include_addons", false)

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	# Pass 1 — candidate resources.
	var candidates: Array = _collect_files(root_path, RESOURCE_EXTENSIONS, include_addons)

	# Pass 2 — every res:// path mentioned by any text file under `path`.
	var text_files: Array = _collect_files(root_path, TEXT_EXTENSIONS, include_addons)
	var referenced: Dictionary = {}
	for file_path: String in text_files:
		_extract_res_paths(FileAccess.get_file_as_string(file_path), referenced)

	var unused: Array = []
	for candidate: String in candidates:
		if not referenced.has(candidate):
			unused.append(candidate)

	return success(
		{
			"unused": unused,
			"unused_count": unused.size(),
			"resources_scanned": candidates.size(),
			"files_scanned": text_files.size(),
		}
	)


## Harvests every `res://…` substring, terminating at a quote, whitespace or a closing bracket.
func _extract_res_paths(text: String, out: Dictionary) -> void:
	var idx: int = text.find("res://")
	while idx != -1:
		var end: int = idx + 6
		while end < text.length():
			var c: String = text[end]
			if (
				c == '"'
				or c == "'"
				or c == ")"
				or c == "]"
				or c == "}"
				or c == " "
				or c == "\t"
				or c == "\n"
				or c == "\r"
			):
				break
			end += 1
		if end > idx + 6:
			out[text.substr(idx, end - idx)] = true
		idx = text.find("res://", maxi(end, idx + 6))


# ---------------------------------------------------------------------------
# analyze_signal_flow
# ---------------------------------------------------------------------------


func _analyze_signal_flow(_params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var nodes: Array = []
	_collect_nodes(root, nodes)

	var emitters: Array = []
	var total: int = 0

	for node: Node in nodes:
		var signals_out: Array = []
		for sig: Dictionary in node.get_signal_list():
			var sig_name: String = str(sig.get("name", ""))
			if sig_name.is_empty():
				continue
			var conns: Array = node.get_signal_connection_list(sig_name)
			if conns.is_empty():
				continue
			var rows: Array = []
			for conn: Dictionary in conns:
				rows.append(_connection_row(root, conn))
			total += rows.size()
			signals_out.append({"signal": sig_name, "connections": rows})
		if signals_out.is_empty():
			continue
		emitters.append(
			{"emitter": _rel(root, node), "type": node.get_class(), "signals": signals_out}
		)

	return success(
		{
			"scene": root.scene_file_path,
			"emitters": emitters,
			"total_connections": total,
		}
	)


## {target, method} for one entry of get_signal_connection_list().
func _connection_row(root: Node, conn: Dictionary) -> Dictionary:
	var raw: Variant = conn.get("callable")
	if typeof(raw) != TYPE_CALLABLE:
		return {"target": "", "method": str(conn.get("method", ""))}
	var callable: Callable = raw
	return {
		"target": _target_label(root, callable.get_object()),
		"method": str(callable.get_method()),
	}


## Node inside the edited scene -> path relative to root; anything else -> its class name.
func _target_label(root: Node, obj: Object) -> String:
	if obj == null:
		return ""
	var node: Node = obj as Node
	if node != null and (node == root or root.is_ancestor_of(node)):
		return _rel(root, node)
	return obj.get_class()


# ---------------------------------------------------------------------------
# analyze_scene_complexity
# ---------------------------------------------------------------------------


func _analyze_scene_complexity(params: Dictionary) -> Dictionary:
	var path: String = optional_string(params, "path", "")

	var root: Node = null
	var owned: bool = false
	var scene_path: String = path

	if path.is_empty():
		root = get_edited_root()
		if root == null:
			return error_no_scene()
		scene_path = root.scene_file_path
	else:
		if not ResourceLoader.exists(path):
			return error_not_found("Scene: %s" % path)
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed == null:
			return error(-32603, "Could not load as PackedScene: %s" % path)
		root = packed.instantiate()
		if root == null:
			return error(-32603, "Could not instantiate scene: %s" % path)
		owned = true

	var nodes: Array = []
	_collect_nodes(root, nodes)

	var nodes_by_type: Dictionary = {}
	var scripts: Array = []
	var max_depth: int = 0

	for node: Node in nodes:
		var cls: String = node.get_class()
		nodes_by_type[cls] = int(nodes_by_type.get(cls, 0)) + 1
		max_depth = maxi(max_depth, _depth_of(root, node))
		var scr: Script = node.get_script() as Script
		if scr != null and not scr.resource_path.is_empty():
			scripts.append({"node": _rel(root, node), "script": scr.resource_path})

	var node_count: int = nodes.size()

	if owned:
		root.free()
		root = null

	var issues: Array = []
	if node_count > NODE_COUNT_CRITICAL:
		issues.append(
			{
				"severity": "critical",
				"message": "Scene has %d nodes (over %d)" % [node_count, NODE_COUNT_CRITICAL],
			}
		)
	elif node_count > NODE_COUNT_WARNING:
		issues.append(
			{
				"severity": "warning",
				"message": "Scene has %d nodes (over %d)" % [node_count, NODE_COUNT_WARNING],
			}
		)

	if max_depth > DEPTH_CRITICAL:
		issues.append(
			{
				"severity": "critical",
				"message": "Scene tree is %d levels deep (over %d)" % [max_depth, DEPTH_CRITICAL],
			}
		)
	elif max_depth > DEPTH_WARNING:
		issues.append(
			{
				"severity": "warning",
				"message": "Scene tree is %d levels deep (over %d)" % [max_depth, DEPTH_WARNING],
			}
		)

	return success(
		{
			"scene_path": scene_path,
			"node_count": node_count,
			"max_depth": max_depth,
			"nodes_by_type": nodes_by_type,
			"scripts": scripts,
			"script_count": scripts.size(),
			"issues": issues,
		}
	)


## Depth of `node` below `root`; root itself is 0.
func _depth_of(root: Node, node: Node) -> int:
	var depth: int = 0
	var cursor: Node = node
	while cursor != null and cursor != root:
		depth += 1
		cursor = cursor.get_parent()
	return depth


# ---------------------------------------------------------------------------
# find_script_references
# ---------------------------------------------------------------------------


func _find_script_references(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "query")
	if res[1] != null:
		return res[1]
	var query: String = res[0]
	var root_path: String = optional_string(params, "path", "res://")
	var include_addons: bool = optional_bool(params, "include_addons", false)

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var files: Array = _collect_files(root_path, TEXT_EXTENSIONS, include_addons)
	var references: Array = []

	for file_path: String in files:
		var text: String = FileAccess.get_file_as_string(file_path)
		if not text.contains(query):
			continue
		var lines: PackedStringArray = text.split("\n")
		for i: int in range(lines.size()):
			var line: String = lines[i]
			if not line.contains(query):
				continue
			var stripped: String = line.strip_edges()
			if stripped.length() > MAX_LINE_CHARS:
				stripped = stripped.substr(0, MAX_LINE_CHARS)
			references.append({"file": file_path, "line": i + 1, "text": stripped})

	return success(
		{
			"query": query,
			"references": references,
			"count": references.size(),
			"files_searched": files.size(),
		}
	)


# ---------------------------------------------------------------------------
# detect_circular_dependencies
# ---------------------------------------------------------------------------


func _detect_circular_dependencies(params: Dictionary) -> Dictionary:
	var root_path: String = optional_string(params, "path", "res://")
	var include_addons: bool = optional_bool(params, "include_addons", false)

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var scenes: Array = _collect_files(root_path, SCENE_EXTENSIONS, include_addons)

	var graph: Dictionary = {}
	for scene_path: String in scenes:
		graph[scene_path] = _scene_ext_scene_deps(scene_path)

	var state: Dictionary = {}  # scene path -> 0 unvisited / 1 visiting / 2 visited
	var stack: Array = []
	var cycles: Array = []

	for scene_path: String in scenes:
		if int(state.get(scene_path, 0)) == 0:
			_dfs_cycles(scene_path, graph, state, stack, cycles)

	return success(
		{
			"scenes_checked": scenes.size(),
			"cycles": cycles,
			"has_cycles": not cycles.is_empty(),
			"graph": graph,
		}
	)


## Textual parse: [ext_resource … path="res://foo.tscn" …] lines are scene->scene edges.
func _scene_ext_scene_deps(scene_path: String) -> Array:
	var deps: Array = []
	var text: String = FileAccess.get_file_as_string(scene_path)
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.begins_with("[ext_resource"):
			continue
		var key: String = 'path="'
		var start: int = trimmed.find(key)
		if start == -1:
			continue
		start += key.length()
		var end: int = trimmed.find('"', start)
		if end == -1:
			continue
		var dep: String = trimmed.substr(start, end - start)
		if dep.get_extension().to_lower() != "tscn":
			continue
		if not deps.has(dep):
			deps.append(dep)
	return deps


func _dfs_cycles(
	node: String, graph: Dictionary, state: Dictionary, stack: Array, cycles: Array
) -> void:
	state[node] = 1
	stack.append(node)

	var deps: Array = graph.get(node, [])
	for dep: String in deps:
		if not graph.has(dep):
			# Dependency outside the scanned root (or missing) — not part of the graph.
			continue
		var dep_state: int = int(state.get(dep, 0))
		if dep_state == 0:
			_dfs_cycles(dep, graph, state, stack, cycles)
		elif dep_state == 1:
			var start: int = stack.find(dep)
			if start != -1:
				var cycle: Array = []
				for i: int in range(start, stack.size()):
					cycle.append(stack[i])
				cycle.append(dep)
				cycles.append(cycle)

	stack.remove_at(stack.size() - 1)
	state[node] = 2


# ---------------------------------------------------------------------------
# get_project_statistics
# ---------------------------------------------------------------------------


func _get_project_statistics(params: Dictionary) -> Dictionary:
	var root_path: String = optional_string(params, "path", "res://")
	var include_addons: bool = optional_bool(params, "include_addons", false)

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var files: Array = _collect_files(root_path, PackedStringArray(), include_addons)

	var files_by_extension: Dictionary = {}
	var gdscript_lines: int = 0
	var scene_count: int = 0
	var resource_count: int = 0

	for file_path: String in files:
		var ext: String = file_path.get_extension().to_lower()
		files_by_extension[ext] = int(files_by_extension.get(ext, 0)) + 1
		match ext:
			"gd":
				var text: String = FileAccess.get_file_as_string(file_path)
				gdscript_lines += text.split("\n").size()
			"tscn":
				scene_count += 1
			"tres", "res":
				resource_count += 1

	return success(
		{
			"files_by_extension": files_by_extension,
			"total_files": files.size(),
			"gdscript_lines": gdscript_lines,
			"scene_count": scene_count,
			"resource_count": resource_count,
			"autoloads": _collect_autoloads(),
			"plugins": _collect_plugins(),
		}
	)


## {Name: raw setting value} — a leading "*" marks an enabled singleton and is kept as stored.
func _collect_autoloads() -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with("autoload/"):
			continue
		var singleton: String = prop_name.substr(9)
		if singleton.is_empty():
			continue
		out[singleton] = str(ProjectSettings.get_setting(prop_name, ""))
	return out


## [{name, enabled}] for every res://addons/*/plugin.cfg on disk.
func _collect_plugins() -> Array:
	var out: Array = []
	var enabled_raw: Variant = ProjectSettings.get_setting(
		"editor_plugins/enabled", PackedStringArray()
	)
	var enabled: PackedStringArray = PackedStringArray()
	if typeof(enabled_raw) == TYPE_PACKED_STRING_ARRAY or typeof(enabled_raw) == TYPE_ARRAY:
		for item: Variant in enabled_raw:
			enabled.append(str(item))

	var dir: DirAccess = DirAccess.open("res://addons")
	if dir == null:
		return out

	var plugin_dirs: PackedStringArray = dir.get_directories()
	plugin_dirs.sort()
	for entry: String in plugin_dirs:
		if entry.begins_with("."):
			continue
		var cfg_path: String = "res://addons/%s/plugin.cfg" % entry
		if not FileAccess.file_exists(cfg_path):
			continue
		var plugin_name: String = entry
		var cfg := ConfigFile.new()
		if cfg.load(cfg_path) == OK:
			var declared: String = str(cfg.get_value("plugin", "name", ""))
			if not declared.is_empty():
				plugin_name = declared
		out.append({"name": plugin_name, "enabled": enabled.has(cfg_path)})

	return out
