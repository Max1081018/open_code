@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## project category (SPEC §6, specs/B01) — 10 tools.
## Every handler is editor-side and needs no open scene: never call error_no_scene() here.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

const DEFAULT_SEARCH_EXTENSIONS: PackedStringArray = [
	"gd", "tscn", "tres", "cfg", "godot", "gdshader", "md", "txt", "json"
]
const MAX_VALUE_CHARS := 200
const MAX_LINE_CHARS := 200


func get_commands() -> Dictionary:
	return {
		"get_project_info": _get_project_info,
		"get_filesystem_tree": _get_filesystem_tree,
		"search_files": _search_files,
		"search_in_files": _search_in_files,
		"get_project_settings": _get_project_settings,
		"set_project_setting": _set_project_setting,
		"uid_to_project_path": _uid_to_project_path,
		"project_path_to_uid": _project_path_to_uid,
		"add_autoload": _add_autoload,
		"remove_autoload": _remove_autoload,
	}


# ---------------------------------------------------------------------------
# get_project_info
# ---------------------------------------------------------------------------


func _get_project_info(_params: Dictionary) -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var data: Dictionary = {
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"godot_version":
		{
			"major": int(version.get("major", 0)),
			"minor": int(version.get("minor", 0)),
			"patch": int(version.get("patch", 0)),
			"string": str(version.get("string", "")),
		},
		"project_path": ProjectSettings.globalize_path("res://"),
		"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"viewport_width": int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		"viewport_height":
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
		"window_width":
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		"window_height":
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"autoloads": _collect_autoloads(),
	}
	return success(data)


func _collect_autoloads() -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with("autoload/"):
			continue
		var singleton: String = prop_name.substr(9)
		if singleton.is_empty():
			continue
		var raw: String = str(ProjectSettings.get_setting(prop_name, ""))
		out[singleton] = raw.trim_prefix("*")
	return out


# ---------------------------------------------------------------------------
# get_filesystem_tree
# ---------------------------------------------------------------------------


func _get_filesystem_tree(params: Dictionary) -> Dictionary:
	var root_path: String = optional_string(params, "path", "res://")
	var filter: String = optional_string(params, "filter", "")
	var max_depth: int = maxi(0, optional_int(params, "max_depth", 10))

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var tree: Dictionary = _walk_dir(root_path, filter, max_depth, 0)
	return success({"path": root_path, "filter": filter, "max_depth": max_depth, "tree": tree})


func _walk_dir(path: String, filter: String, max_depth: int, depth: int) -> Dictionary:
	var display_name: String = path.trim_suffix("/").get_file()
	if display_name.is_empty():
		display_name = path
	var node: Dictionary = {"name": display_name, "path": path, "type": "dir", "children": []}

	if depth >= max_depth:
		node["truncated"] = true
		return node

	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return node

	var children: Array = []

	var dir_names: PackedStringArray = dir.get_directories()
	dir_names.sort()
	for entry: String in dir_names:
		if entry.begins_with("."):
			continue
		var child: Dictionary = _walk_dir(_join(path, entry), filter, max_depth, depth + 1)
		# With a filter set, prune directories that ended up holding nothing.
		if not filter.is_empty():
			var child_children: Array = child.get("children", [])
			if child_children.is_empty() and not bool(child.get("truncated", false)):
				continue
		children.append(child)

	var file_names: PackedStringArray = dir.get_files()
	file_names.sort()
	for entry: String in file_names:
		if entry.begins_with("."):
			continue
		if not filter.is_empty() and not entry.match(filter):
			continue
		children.append({"name": entry, "path": _join(path, entry), "type": "file"})

	node["children"] = children
	return node


func _join(base: String, entry: String) -> String:
	if base.ends_with("/"):
		return base + entry
	return "%s/%s" % [base, entry]


# ---------------------------------------------------------------------------
# search_files
# ---------------------------------------------------------------------------


func _search_files(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "query")
	if res[1] != null:
		return res[1]
	var query: String = res[0]
	var root_path: String = optional_string(params, "path", "res://")
	var file_type: String = optional_string(params, "file_type", "").trim_prefix(".").to_lower()
	var max_results: int = maxi(1, optional_int(params, "max_results", 50))

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var is_glob: bool = query.contains("*") or query.contains("?")
	var hits: Array = []
	var total: int = _collect_matching_files(root_path, query, is_glob, file_type, max_results, hits)

	return success(
		{
			"results": hits,
			"total": total,
			"truncated": total > hits.size(),
			"query": query,
		}
	)


## Appends up to max_results paths into `hits`; returns the total number of matches found.
func _collect_matching_files(
	path: String, query: String, is_glob: bool, file_type: String, max_results: int, hits: Array
) -> int:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return 0

	var total: int = 0
	var lowered: String = query.to_lower()

	var file_names: PackedStringArray = dir.get_files()
	file_names.sort()
	for entry: String in file_names:
		if entry.begins_with("."):
			continue
		if not file_type.is_empty() and entry.get_extension().to_lower() != file_type:
			continue
		var matched: bool = (
			entry.matchn(query) if is_glob else entry.to_lower().contains(lowered)
		)
		if not matched:
			continue
		total += 1
		if hits.size() < max_results:
			hits.append(_join(path, entry))

	var dir_names: PackedStringArray = dir.get_directories()
	dir_names.sort()
	for entry: String in dir_names:
		if entry.begins_with("."):
			continue
		total += _collect_matching_files(
			_join(path, entry), query, is_glob, file_type, max_results, hits
		)
	return total


# ---------------------------------------------------------------------------
# search_in_files
# ---------------------------------------------------------------------------


func _search_in_files(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "query")
	if res[1] != null:
		return res[1]
	var query: String = res[0]
	var root_path: String = optional_string(params, "path", "res://")
	var max_results: int = maxi(1, optional_int(params, "max_results", 50))
	var use_regex: bool = optional_bool(params, "regex", false)
	var file_type: String = optional_string(params, "file_type", "").trim_prefix(".").to_lower()

	if not DirAccess.dir_exists_absolute(root_path):
		return error_not_found("Directory: %s" % root_path)

	var extensions: PackedStringArray = DEFAULT_SEARCH_EXTENSIONS
	if not file_type.is_empty():
		extensions = PackedStringArray([file_type])

	var regex: RegEx = null
	if use_regex:
		regex = RegEx.new()
		if regex.compile(query) != OK:
			return error(-32602, "Invalid regular expression: %s" % query)

	var rows: Array = []
	var total: int = _grep_dir(root_path, query, regex, extensions, max_results, rows)

	return success(
		{
			"results": rows,
			"total": total,
			"truncated": total > rows.size(),
			"query": query,
			"regex": use_regex,
		}
	)


func _grep_dir(
	path: String,
	query: String,
	regex: RegEx,
	extensions: PackedStringArray,
	max_results: int,
	rows: Array
) -> int:
	var normalized: String = path.trim_suffix("/")
	if normalized == "res://addons" or normalized.begins_with("res://addons/"):
		return 0
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return 0

	var total: int = 0

	var file_names: PackedStringArray = dir.get_files()
	file_names.sort()
	for entry: String in file_names:
		if entry.begins_with("."):
			continue
		if not extensions.has(entry.get_extension().to_lower()):
			continue
		total += _grep_file(_join(path, entry), query, regex, max_results, rows)

	var dir_names: PackedStringArray = dir.get_directories()
	dir_names.sort()
	for entry: String in dir_names:
		if entry.begins_with("."):
			continue
		total += _grep_dir(_join(path, entry), query, regex, extensions, max_results, rows)
	return total


func _grep_file(
	file_path: String, query: String, regex: RegEx, max_results: int, rows: Array
) -> int:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	var text: String = file.get_as_text()
	file.close()

	var total: int = 0
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		var line: String = lines[i]
		var matched: bool = (
			regex.search(line) != null if regex != null else line.findn(query) != -1
		)
		if not matched:
			continue
		total += 1
		if rows.size() < max_results:
			var stripped: String = line.strip_edges()
			if stripped.length() > MAX_LINE_CHARS:
				stripped = stripped.substr(0, MAX_LINE_CHARS)
			rows.append({"file": file_path, "line": i + 1, "text": stripped})
	return total


# ---------------------------------------------------------------------------
# get_project_settings
# ---------------------------------------------------------------------------


func _get_project_settings(params: Dictionary) -> Dictionary:
	var key: String = optional_string(params, "key", "")
	var section: String = optional_string(params, "section", "")

	if not key.is_empty():
		if not ProjectSettings.has_setting(key):
			return error_not_found("Project setting: %s" % key)
		var value: Variant = ProjectSettings.get_setting(key)
		return success(
			{
				"key": key,
				"value": PropertyParser.serialize_value(value),
				"type": type_string(typeof(value)),
			}
		)

	var settings: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty():
			continue
		if not section.is_empty() and not prop_name.begins_with(section):
			continue
		if not ProjectSettings.has_setting(prop_name):
			continue
		var raw: Variant = ProjectSettings.get_setting(prop_name)
		var text: String = str(PropertyParser.serialize_value(raw))
		if text.length() > MAX_VALUE_CHARS:
			text = text.substr(0, MAX_VALUE_CHARS) + "..."
		settings[prop_name] = text

	return success({"section": section, "count": settings.size(), "settings": settings})


# ---------------------------------------------------------------------------
# set_project_setting
# ---------------------------------------------------------------------------


func _set_project_setting(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "key")
	if res[1] != null:
		return res[1]
	var key: String = res[0]
	if not params.has("value") or params["value"] == null:
		return error(-32602, "Missing required parameter: value")

	var old_value: Variant = null
	if ProjectSettings.has_setting(key):
		old_value = ProjectSettings.get_setting(key)
	var new_value: Variant = PropertyParser.parse_value(params["value"], TYPE_NIL)

	ProjectSettings.set_setting(key, new_value)
	var err: int = ProjectSettings.save()
	if err != OK:
		return error(-32603, "Failed to save project settings: %s" % error_string(err))

	return success(
		{
			"key": key,
			"old_value": PropertyParser.serialize_value(old_value),
			"new_value": PropertyParser.serialize_value(new_value),
		}
	)


# ---------------------------------------------------------------------------
# uid_to_project_path / project_path_to_uid
# ---------------------------------------------------------------------------


func _uid_to_project_path(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "uid")
	if res[1] != null:
		return res[1]
	var uid: String = res[0]

	var id: int = ResourceUID.text_to_id(uid)
	if id == -1 or not ResourceUID.has_id(id):
		return error_not_found("UID: %s" % uid)

	var path: String = ResourceUID.get_id_path(id)
	if path.is_empty():
		return error_not_found("UID: %s" % uid)
	return success({"uid": uid, "path": path, "id": id})


func _project_path_to_uid(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var id: int = ResourceLoader.get_resource_uid(path)
	if id == -1:
		return error(-32001, "no UID for path: %s" % path, {"path": path})
	return success({"path": path, "uid": ResourceUID.id_to_text(id), "id": id})


# ---------------------------------------------------------------------------
# add_autoload / remove_autoload
# ---------------------------------------------------------------------------


func _add_autoload(params: Dictionary) -> Dictionary:
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var path_res: Array = require_string(params, "path")
	if path_res[1] != null:
		return path_res[1]

	var singleton: String = name_res[0]
	var path: String = path_res[0]
	var key: String = "autoload/%s" % singleton

	if ProjectSettings.has_setting(key):
		return error(
			-32000,
			"Autoload already exists: %s" % singleton,
			{"name": singleton, "suggestion": "remove_autoload first"}
		)
	if not FileAccess.file_exists(path):
		return error_not_found("File: %s" % path)

	ProjectSettings.set_setting(key, "*" + path)
	var err: int = ProjectSettings.save()
	if err != OK:
		return error(-32603, "Failed to save project settings: %s" % error_string(err))

	return success({"name": singleton, "path": path, "singleton": true})


func _remove_autoload(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "name")
	if res[1] != null:
		return res[1]
	var singleton: String = res[0]
	var key: String = "autoload/%s" % singleton

	if not ProjectSettings.has_setting(key):
		return error_not_found("Autoload: %s" % singleton)

	var old_path: String = str(ProjectSettings.get_setting(key, "")).trim_prefix("*")
	ProjectSettings.set_setting(key, null)
	var err: int = ProjectSettings.save()
	if err != OK:
		return error(-32603, "Failed to save project settings: %s" % error_string(err))

	return success({"name": singleton, "old_path": old_path, "removed": true})
