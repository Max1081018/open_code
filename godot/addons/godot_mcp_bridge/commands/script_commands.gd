@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## script category (SPEC §6, specs/B04-script-shader.md) — 7 tools.
##
## list_scripts, read_script, create_script, edit_script, attach_script,
## get_open_scripts, validate_script.

const SCRIPT_EXTENSIONS: PackedStringArray = ["gd", "cs"]
const LISTABLE_EXTENSIONS: PackedStringArray = ["gd", "cs", "gdshader"]

const EDIT_MODE_HELP := (
	"edit_script requires exactly one mode: "
	+ "{replacements} | {content, start_line[, end_line]} | {content} | {insert_at_line, text}"
)


func get_commands() -> Dictionary:
	return {
		"list_scripts": _list_scripts,
		"read_script": _read_script,
		"create_script": _create_script,
		"edit_script": _edit_script,
		"attach_script": _attach_script,
		"get_open_scripts": _get_open_scripts,
		"validate_script": _validate_script,
	}


# ---------------------------------------------------------------------------
# Shared private helpers
# ---------------------------------------------------------------------------


## Extension guard for create/edit/validate. Empty Dictionary when OK (SPEC §9.1 —
## callers check .is_empty(), never != null).
func _guard_script_path(path: String, tool_name: String) -> Dictionary:
	var ext: String = path.get_extension().to_lower()
	if SCRIPT_EXTENSIONS.has(ext):
		return {}
	return error(
		-32602,
		"%s only supports script files (.gd, .cs)" % tool_name,
		{
			"path": path,
			"extension": ext,
			"suggestion": "use create_shader / edit_shader for .gdshader files",
		}
	)


## Re-import the file and hot-reload the Script resource so the editor sees it at once.
func _reload_script(path: String) -> void:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
	if not ResourceLoader.exists(path):
		return
	var res: Resource = load(path)
	var scr: Script = res as Script
	if scr != null:
		scr.reload(true)


func _write_file(path: String, content: String) -> Dictionary:
	var base_dir: String = path.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return error(
			-32603,
			"Could not open file for writing: %s" % path,
			{"path": path, "error": error_string(FileAccess.get_open_error())}
		)
	file.store_string(content)
	file.close()
	return {}


func _read_file(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [
			null,
			error(
				-32603,
				"Could not read file: %s" % path,
				{"path": path, "error": error_string(FileAccess.get_open_error())}
			)
		]
	var text: String = file.get_as_text()
	file.close()
	return [text, null]


func _relative_node_path(node: Node) -> String:
	var root: Node = get_edited_root()
	if root == null or node == null:
		return "" if node == null else str(node.name)
	if node == root:
		return "."
	return str(root.get_path_to(node))


# ---------------------------------------------------------------------------
# list_scripts
# ---------------------------------------------------------------------------


func _list_scripts(params: Dictionary) -> Dictionary:
	var path: String = optional_string(params, "path", "res://")
	var recursive: bool = optional_bool(params, "recursive", true)

	var scripts: Array = []
	_scan_dir(path, recursive, scripts)
	return success({"scripts": scripts, "count": scripts.size()})


func _scan_dir(dir_path: String, recursive: bool, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		# Unopenable directory: skip silently, keep whatever was collected.
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var child: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			if recursive:
				_scan_dir(child, recursive, out)
		else:
			var ext: String = entry.get_extension().to_lower()
			if LISTABLE_EXTENSIONS.has(ext):
				out.append(_describe_script_file(child, ext))
		entry = dir.get_next()
	dir.list_dir_end()


func _describe_script_file(path: String, ext: String) -> Dictionary:
	var row: Dictionary = {"path": path, "type": ext, "size": 0}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return row
	row["size"] = int(file.get_length())
	var first_line: String = file.get_line().strip_edges()
	file.close()
	if first_line.begins_with("class_name "):
		row["class_name"] = first_line.substr(11).strip_edges()
	elif first_line.begins_with("extends "):
		row["extends"] = first_line.substr(8).strip_edges()
	return row


# ---------------------------------------------------------------------------
# read_script
# ---------------------------------------------------------------------------


func _read_script(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Script: %s" % path)

	var read: Array = _read_file(path)
	if read[1] != null:
		return read[1]
	var content: String = read[0]

	return success(
		{
			"path": path,
			"content": content,
			"line_count": content.count("\n") + 1,
			"size": content.length(),
		}
	)


# ---------------------------------------------------------------------------
# create_script
# ---------------------------------------------------------------------------


func _create_script(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var ext_guard: Dictionary = _guard_script_path(path, "create_script")
	if not ext_guard.is_empty():
		return ext_guard

	var force: bool = optional_bool(params, "force", false)
	var write_guard: Dictionary = guard_text_resource_write(path, force)
	if not write_guard.is_empty():
		return write_guard

	var content: String = optional_string(params, "content", "")
	var template_used: bool = content.is_empty()

	if template_used:
		if path.get_extension().to_lower() == "cs":
			return error(
				-32602,
				"content required for .cs scripts (template is GDScript-only)",
				{"path": path, "suggestion": "pass the full C# source in `content`"}
			)
		content = _gdscript_template(
			optional_string(params, "extends", "Node"), optional_string(params, "class_name", "")
		)

	var write_err: Dictionary = _write_file(path, content)
	if not write_err.is_empty():
		return write_err

	_reload_script(path)

	return success(
		{
			"path": path,
			"created": true,
			"template_used": template_used,
			"size": content.length(),
		}
	)


func _gdscript_template(base_class: String, cls_name: String) -> String:
	var lines: Array[String] = []
	if not cls_name.is_empty():
		lines.append("class_name %s" % cls_name)
	lines.append("extends %s" % base_class)
	lines.append("")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tpass")
	return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# edit_script
# ---------------------------------------------------------------------------


func _edit_script(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var ext_guard: Dictionary = _guard_script_path(path, "edit_script")
	if not ext_guard.is_empty():
		return ext_guard

	if not FileAccess.file_exists(path):
		return error_not_found("Script: %s" % path)

	var force: bool = optional_bool(params, "force", false)
	var write_guard: Dictionary = guard_text_resource_write(path, force)
	if not write_guard.is_empty():
		return write_guard

	var mode: String = _detect_edit_mode(params)
	if mode.is_empty():
		return error(
			-32602,
			EDIT_MODE_HELP,
			{"path": path, "provided": _present_edit_keys(params)}
		)

	var read: Array = _read_file(path)
	if read[1] != null:
		return read[1]
	var original: String = read[0]

	var applied: Dictionary = {}
	match mode:
		"replacements":
			applied = _apply_replacements(original, params)
		"line_range":
			applied = _apply_line_range(original, params)
		"full":
			applied = _apply_full(original, params)
		"insert":
			applied = _apply_insert(original, params)

	if applied.has("error"):
		return applied

	var new_content: String = str(applied["content"])
	var write_err: Dictionary = _write_file(path, new_content)
	if not write_err.is_empty():
		return write_err

	_reload_script(path)
	_refresh_script_editor()

	var out: Dictionary = {
		"path": path,
		"mode": mode,
		"changes_made": int(applied.get("changes_made", 1)),
		"line_count": new_content.split("\n").size(),
	}
	if applied.has("occurrences"):
		out["occurrences"] = int(applied["occurrences"])
	return success(out)


const EDIT_KEYS: PackedStringArray = [
	"replacements", "content", "start_line", "end_line", "insert_at_line", "text"
]


func _present_edit_keys(params: Dictionary) -> Array:
	var present: Array = []
	for key: String in EDIT_KEYS:
		if params.has(key):
			present.append(key)
	return present


## "" when the present-key set matches none of the four legal modes.
func _detect_edit_mode(params: Dictionary) -> String:
	var present: Array = _present_edit_keys(params)
	var joined: String = ",".join(PackedStringArray(present))
	match joined:
		"replacements":
			return "replacements"
		"content,start_line":
			return "line_range"
		"content,start_line,end_line":
			return "line_range"
		"content":
			return "full"
		"insert_at_line,text":
			return "insert"
		_:
			return ""


func _apply_replacements(original: String, params: Dictionary) -> Dictionary:
	var raw: Variant = params.get("replacements", [])
	if typeof(raw) != TYPE_ARRAY:
		return error(-32602, "replacements must be an array of {search, replace, regex?} objects")
	var items: Array = raw
	if items.is_empty():
		return error(-32602, "replacements must contain at least one {search, replace} item")

	var content: String = original
	var total_occurrences: int = 0
	var applied: int = 0
	var index: int = 0

	for item: Variant in items:
		index += 1
		if typeof(item) != TYPE_DICTIONARY:
			return error(
				-32602,
				"replacements[%d] must be an object with search/replace" % (index - 1),
				{"attempted": index, "total": items.size(), "applied": applied}
			)
		var entry: Dictionary = item
		var search: String = str(entry.get("search", ""))
		var replace: String = str(entry.get("replace", ""))
		var use_regex: bool = optional_bool(entry, "regex", false)
		if search.is_empty():
			return error(
				-32602,
				"replacements[%d].search must not be empty" % (index - 1),
				{"attempted": index, "total": items.size(), "applied": applied}
			)

		var hits: int = 0
		if use_regex:
			var re := RegEx.new()
			if re.compile(search) != OK:
				return error(
					-32602,
					"invalid regex: %s" % search,
					{"attempted": index, "total": items.size(), "applied": applied}
				)
			hits = re.search_all(content).size()
			if hits == 0:
				return error(
					-32001,
					"search text not found: %s" % search,
					{"attempted": index, "total": items.size(), "applied": applied}
				)
			content = re.sub(content, replace, true)
		else:
			hits = content.count(search)
			if hits == 0:
				return error(
					-32001,
					"search text not found: %s" % search,
					{"attempted": index, "total": items.size(), "applied": applied}
				)
			content = content.replace(search, replace)

		total_occurrences += hits
		applied += 1

	return {"content": content, "changes_made": applied, "occurrences": total_occurrences}


func _apply_line_range(original: String, params: Dictionary) -> Dictionary:
	var lines: PackedStringArray = original.split("\n")
	var line_count: int = lines.size()
	var start_line: int = optional_int(params, "start_line", 1)
	var end_line: int = optional_int(params, "end_line", start_line)

	if start_line < 1:
		return error(-32602, "start_line must be >= 1 (got %d)" % start_line)
	if end_line < start_line:
		return error(
			-32602, "end_line (%d) must be >= start_line (%d)" % [end_line, start_line]
		)
	if start_line > line_count or end_line > line_count:
		return error(
			-32602,
			"line range %d..%d is outside the file (%d lines)" % [start_line, end_line, line_count]
		)

	var replacement: PackedStringArray = str(params.get("content", "")).split("\n")
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(0, start_line - 1):
		out.append(lines[i])
	for line: String in replacement:
		out.append(line)
	for i: int in range(end_line, line_count):
		out.append(lines[i])

	return {"content": "\n".join(out), "changes_made": 1}


func _apply_full(_original: String, params: Dictionary) -> Dictionary:
	return {"content": str(params.get("content", "")), "changes_made": 1}


func _apply_insert(original: String, params: Dictionary) -> Dictionary:
	var lines: PackedStringArray = original.split("\n")
	var line_count: int = lines.size()
	var insert_at: int = optional_int(params, "insert_at_line", 1)

	if insert_at < 1 or insert_at > line_count + 1:
		return error(
			-32602,
			(
				"insert_at_line must be between 1 and %d (got %d)"
				% [line_count + 1, insert_at]
			)
		)

	var inserted: PackedStringArray = str(params.get("text", "")).split("\n")
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(0, insert_at - 1):
		out.append(lines[i])
	for line: String in inserted:
		out.append(line)
	for i: int in range(insert_at - 1, line_count):
		out.append(lines[i])

	return {"content": "\n".join(out), "changes_made": 1}


## Nudge the script editor so open-tab error indicators re-evaluate.
func _refresh_script_editor() -> void:
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor != null:
		script_editor.notification(CanvasItem.NOTIFICATION_VISIBILITY_CHANGED)


# ---------------------------------------------------------------------------
# attach_script  [E+S]
# ---------------------------------------------------------------------------


func _attach_script(params: Dictionary) -> Dictionary:
	var node_res: Array = require_string(params, "node_path")
	if node_res[1] != null:
		return node_res[1]
	var script_res: Array = require_string(params, "script_path")
	if script_res[1] != null:
		return script_res[1]
	var node_path: String = node_res[0]
	var script_path: String = script_res[0]

	if get_edited_root() == null:
		return error_no_scene()

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)

	if not FileAccess.file_exists(script_path) and not ResourceLoader.exists(script_path):
		return error_not_found("Script: %s" % script_path)

	var loaded: Resource = load(script_path)
	if loaded == null:
		return error(-32603, "Failed to load script: %s" % script_path, {"path": script_path})

	# set_script() silently rejects a non-Script resource at commit time, which would leave an
	# empty action on the undo stack and report attached: true for a no-op.
	var script_to_attach: Script = loaded as Script
	if script_to_attach == null:
		return error(
			-32602,
			"Resource is not a Script: %s" % script_path,
			{"path": script_path, "resource_class": loaded.get_class()}
		)

	var previous: Variant = node.get_script()
	var previous_path: Variant = null
	var previous_script: Script = previous as Script
	if previous_script != null and not previous_script.resource_path.is_empty():
		previous_path = previous_script.resource_path

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return error(-32603, "EditorUndoRedoManager unavailable")

	ur.create_action("MCP: attach_script")
	ur.add_do_method(node, "set_script", script_to_attach)
	ur.add_undo_method(node, "set_script", previous)
	ur.commit_action()

	return success(
		{
			"node_path": _relative_node_path(node),
			"script_path": script_path,
			"previous_script": previous_path,
			"attached": true,
		}
	)


# ---------------------------------------------------------------------------
# get_open_scripts
# ---------------------------------------------------------------------------


func _get_open_scripts(_params: Dictionary) -> Dictionary:
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	var rows: Array = []
	if script_editor != null:
		for scr: Script in script_editor.get_open_scripts():
			if scr == null:
				continue
			rows.append({"path": scr.resource_path, "type": scr.get_class()})
	return success({"scripts": rows, "count": rows.size()})


# ---------------------------------------------------------------------------
# validate_script
# ---------------------------------------------------------------------------


func _validate_script(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var ext_guard: Dictionary = _guard_script_path(path, "validate_script")
	if not ext_guard.is_empty():
		return ext_guard

	if not FileAccess.file_exists(path):
		return error_not_found("Script: %s" % path)

	var read: Array = _read_file(path)
	if read[1] != null:
		return read[1]
	var source: String = read[0]

	if path.get_extension().to_lower() == "cs":
		return success(
			{
				"path": path,
				"valid": false,
				"error_code": ERR_UNAVAILABLE,
				"error_text": "C# compile check not supported editor-side",
			}
		)

	# Throwaway compile — never attached to any node or resource.
	var probe := GDScript.new()
	probe.source_code = source
	var err: int = probe.reload()
	if err == OK:
		return success({"path": path, "valid": true, "error_code": 0, "error_text": ""})

	return success(
		{
			"path": path,
			"valid": false,
			"error_code": err,
			"error_text": error_string(err),
			"hint": "see get_editor_errors / get_output_log for line detail",
		}
	)
