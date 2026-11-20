@tool
extends Node

## Base class for every MCP command module.
##
## FROZEN CONTRACT (SPEC §3.4). Helper names and return conventions must not drift —
## 13 later packages build on them.
##
## Every command module:
##   @tool
##   extends "res://addons/godot_mcp_bridge/commands/base_command.gd"
##   func get_commands() -> Dictionary: return {"tool_name": _handler, ...}
##   func _handler(params: Dictionary) -> Dictionary  # returns success()/error()

var editor_plugin: EditorPlugin

const GAME_REQUEST_FILE := "mcp_game_request"
const GAME_RESPONSE_FILE := "mcp_game_response"
const DEBUGGER_CONTINUE_FILE := "mcp_debugger_continue"


## Overridden by every command module. Maps wire method name -> Callable.
func get_commands() -> Dictionary:
	return {}


# ---------------------------------------------------------------------------
# Result helpers
# ---------------------------------------------------------------------------


func success(data: Dictionary) -> Dictionary:
	return {"result": data}


func error(code: int, message: String, data: Dictionary = {}) -> Dictionary:
	var err: Dictionary = {"code": code, "message": message}
	if not data.is_empty():
		err["data"] = data
	return {"error": err}


func error_no_scene() -> Dictionary:
	return error(-32000, "No scene is currently open")


func error_not_found(what: String) -> Dictionary:
	return error(-32001, "%s not found" % what)


# ---------------------------------------------------------------------------
# Param helpers
# ---------------------------------------------------------------------------


## Returns [value, null] on success, [null, error_dict] on failure.
func require_string(params: Dictionary, key: String) -> Array:
	if not params.has(key):
		return [null, error(-32602, "Missing required parameter: %s" % key)]
	var raw: Variant = params[key]
	if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:
		return [
			null,
			error(
				-32602,
				(
					"Missing required parameter: %s (expected a string, got %s)"
					% [key, type_string(typeof(raw))]
				)
			)
		]
	var value: String = String(raw)
	if value.is_empty():
		return [null, error(-32602, "Missing required parameter: %s (must not be empty)" % key)]
	return [value, null]


func optional_string(params: Dictionary, key: String, default: String = "") -> String:
	if not params.has(key) or params[key] == null:
		return default
	var raw: Variant = params[key]
	if typeof(raw) == TYPE_STRING or typeof(raw) == TYPE_STRING_NAME:
		return String(raw)
	return str(raw)


func optional_int(params: Dictionary, key: String, default: int = 0) -> int:
	if not params.has(key) or params[key] == null:
		return default
	var raw: Variant = params[key]
	match typeof(raw):
		TYPE_INT:
			return int(raw)
		TYPE_FLOAT:
			return int(roundf(float(raw)))
		TYPE_BOOL:
			return 1 if bool(raw) else 0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw)
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return int(roundf(s.to_float()))
			return default
		_:
			return default


func optional_float(params: Dictionary, key: String, default: float = 0.0) -> float:
	if not params.has(key) or params[key] == null:
		return default
	var raw: Variant = params[key]
	match typeof(raw):
		TYPE_FLOAT:
			return float(raw)
		TYPE_INT:
			return float(raw)
		TYPE_BOOL:
			return 1.0 if bool(raw) else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw)
			if s.is_valid_float():
				return s.to_float()
			return default
		_:
			return default


func optional_bool(params: Dictionary, key: String, default: bool = false) -> bool:
	if not params.has(key) or params[key] == null:
		return default
	var raw: Variant = params[key]
	match typeof(raw):
		TYPE_BOOL:
			return bool(raw)
		TYPE_INT:
			return int(raw) != 0
		TYPE_FLOAT:
			return not is_zero_approx(float(raw))
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw).strip_edges().to_lower()
			if s == "true" or s == "1" or s == "yes":
				return true
			if s == "false" or s == "0" or s == "no":
				return false
			return default
		_:
			return default


# ---------------------------------------------------------------------------
# Scene / node helpers
# ---------------------------------------------------------------------------


func get_edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


## A sibling-unique, human-readable name for a node about to be added under `parent`.
##
## Godot only produces readable names ("Body2") when add_child() is called with
## force_readable_name = true; the flag does NOT survive being forwarded through
## EditorUndoRedoManager.add_do_method()'s varargs, and the fallback path names the node after its
## CLASS ("@Sprite2D@18537"), discarding the caller's requested name entirely. Resolving the name
## up front makes insertion deterministic and independent of that flag.
func unique_child_name(parent: Node, desired: String, fallback: String = "Node") -> String:
	var base: String = desired.strip_edges()
	if base.is_empty():
		base = fallback
	if parent == null or not parent.has_node(NodePath(base)):
		return base
	var i: int = 2
	while parent.has_node(NodePath("%s%d" % [base, i])):
		i += 1
	return "%s%d" % [base, i]


## Resolves ".", "", the root's own name, root-prefixed paths, or plain relative paths.
func find_node_by_path(path: String) -> Node:
	var root: Node = get_edited_root()
	if root == null:
		return null
	var p: String = path.strip_edges()
	if p.is_empty() or p == "." or p == "/root" or p == str(root.name):
		return root
	if p.begins_with("/root/"):
		p = p.substr(6)
	var root_prefix: String = "%s/" % str(root.name)
	if p.begins_with(root_prefix):
		return root.get_node_or_null(NodePath(p.substr(root_prefix.length())))
	return root.get_node_or_null(NodePath(p))


func undo_redo() -> EditorUndoRedoManager:
	if editor_plugin == null:
		return null
	return editor_plugin.get_undo_redo()


# ---------------------------------------------------------------------------
# Conflict guards — return an EMPTY Dictionary when OK.
# CALLERS CHECK WITH .is_empty(); a Dictionary is never null (SPEC §9.1).
# ---------------------------------------------------------------------------


func guard_offline_scene_save(path: String) -> Dictionary:
	var ext: String = path.get_extension().to_lower()
	if ext != "tscn" and ext != "scn":
		return {}
	var open_scenes: PackedStringArray = EditorInterface.get_open_scenes()
	for open_path: String in open_scenes:
		if open_path == path:
			return error(
				-32009,
				"Scene is open in the editor — use save_scene / close it first",
				{"path": path, "suggestion": "use save_scene, or close the scene in the editor"}
			)
	return {}


func guard_text_resource_write(path: String, force: bool) -> Dictionary:
	if force:
		return {}
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor == null:
		return {}
	var open_scripts: Array[Script] = script_editor.get_open_scripts()
	for scr: Script in open_scripts:
		if scr != null and scr.resource_path == path:
			return error(
				-32009,
				"File is open in the script editor — its buffer would be overwritten",
				{"path": path, "suggestion": "pass force: true to overwrite the editor buffer"}
			)
	return {}


# ---------------------------------------------------------------------------
# Game IPC (frozen contract, SPEC §3.4)
# ---------------------------------------------------------------------------


## The running game's user:// dir on disk. Re-derived from project.godot every call so
## a renamed project still resolves. Falls back to the editor's own user data dir.
func get_game_user_dir() -> String:
	var fallback: String = OS.get_user_data_dir()
	var project_name: String = ""
	var use_custom_dir: bool = false
	var custom_dir_name: String = ""

	var file: FileAccess = FileAccess.open("res://project.godot", FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line: String = file.get_line().strip_edges()
			if line.begins_with("config/name="):
				project_name = line.substr(12).strip_edges().trim_prefix('"').trim_suffix('"')
			elif line.begins_with("config/use_custom_user_dir="):
				use_custom_dir = line.substr(27).strip_edges().to_lower() == "true"
			elif line.begins_with("config/custom_user_dir_name="):
				custom_dir_name = line.substr(28).strip_edges().trim_prefix('"').trim_suffix('"')
		file.close()

	if project_name.is_empty() and custom_dir_name.is_empty():
		return fallback

	# OS.get_user_data_dir() already resolves use_custom_user_dir, so we cannot assume
	# `fallback` sits under <data_path>/Godot/app_userdata. Recover <data_path> by
	# stripping the suffix the EDITOR's own settings imply, then rebuild it from the
	# values just read off disk (so a renamed project / custom dir still resolves).
	var data_path: String = _get_platform_data_path(fallback)
	if data_path.is_empty():
		return fallback

	if use_custom_dir:
		# Mirrors OS::get_user_data_dir(): empty custom_user_dir_name falls back to the app name.
		var custom: String = _sanitize_custom_dir_name(custom_dir_name)
		if custom.is_empty():
			custom = _sanitize_dir_name(project_name)
		if custom.is_empty():
			return fallback
		return "%s/%s" % [data_path, custom]

	if project_name.is_empty():
		return fallback
	return "%s/Godot/app_userdata/%s" % [data_path, _sanitize_dir_name(project_name)]


## Recovers the platform user data path (e.g. ~/Library/Application Support) by stripping
## the suffix that OS::get_user_data_dir() appended for the EDITOR's current settings.
## Returns "" when the expected suffix is not present.
func _get_platform_data_path(user_dir: String) -> String:
	var editor_custom: bool = bool(
		ProjectSettings.get_setting("application/config/use_custom_user_dir", false)
	)
	if not editor_custom:
		# <data_path>/Godot/app_userdata/<safe_name>
		var stripped: String = user_dir.get_base_dir().get_base_dir().get_base_dir()
		if user_dir.get_base_dir().get_base_dir().get_file() != "Godot":
			return ""
		return stripped

	# <data_path>/<safe(custom_user_dir_name or name)>
	var suffix: String = _sanitize_custom_dir_name(
		str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	)
	if suffix.is_empty():
		suffix = _sanitize_dir_name(
			str(ProjectSettings.get_setting("application/config/name", ""))
		)
	if suffix.is_empty():
		return ""
	var tail: String = "/%s" % suffix
	if not user_dir.ends_with(tail):
		return ""
	return user_dir.substr(0, user_dir.length() - tail.length())


func _sanitize_dir_name(project_name: String) -> String:
	# Mirrors OS::get_safe_dir_name(): strip characters that are invalid in a path segment.
	var out: String = project_name.strip_edges()
	for c: String in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(c, "-")
	return out.strip_edges()


## Mirrors OS::get_safe_dir_name(name, allow_paths = true), used for custom_user_dir_name:
## separators survive (a custom dir may be nested), "..", and invalid chars do not.
func _sanitize_custom_dir_name(custom_name: String) -> String:
	var out: String = custom_name.replace("\\", "/").strip_edges()
	for c: String in [":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(c, "-")
	out = out.replace("..", "")
	return out.strip_edges().trim_prefix("/").trim_suffix("/")


## Send one command to the running game over the file IPC and await its response.
func _send_game_command(cmd: String, params: Dictionary, timeout: float = 5.0) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return error(-32000, "Game is not running — use play_scene first")

	var dir: String = get_game_user_dir()
	var request_path: String = "%s/%s" % [dir, GAME_REQUEST_FILE]
	var response_path: String = "%s/%s" % [dir, GAME_RESPONSE_FILE]

	# Clear any stale response before issuing a new request.
	if FileAccess.file_exists(response_path):
		DirAccess.remove_absolute(response_path)

	var payload: Dictionary = {"command": cmd, "params": params}
	var req: FileAccess = FileAccess.open(request_path, FileAccess.WRITE)
	if req == null:
		return error(
			-32000,
			"Could not write game request file: %s" % request_path,
			{"error": error_string(FileAccess.get_open_error())}
		)
	req.store_string(JSON.stringify(payload))
	req.close()

	var elapsed: float = 0.0
	var step: float = 0.1
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	while elapsed < timeout:
		if tree != null:
			await tree.create_timer(step).timeout
		else:
			await Engine.get_main_loop().process_frame
		elapsed += step
		if FileAccess.file_exists(response_path):
			var resp: FileAccess = FileAccess.open(response_path, FileAccess.READ)
			if resp == null:
				continue
			var text: String = resp.get_as_text()
			resp.close()
			DirAccess.remove_absolute(response_path)
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				return error(-32000, "Malformed game response", {"raw": text})
			var d: Dictionary = parsed
			if bool(d.get("success", false)):
				var data: Variant = d.get("data", {})
				if typeof(data) == TYPE_DICTIONARY:
					return success(data)
				return success({"data": data})
			return error(-32000, str(d.get("error", "Unknown game error")))

	# Timed out: the game may be halted in the debugger. Ask the plugin to press Continue.
	var flag: FileAccess = FileAccess.open("%s/%s" % [dir, DEBUGGER_CONTINUE_FILE], FileAccess.WRITE)
	if flag != null:
		flag.store_string("1")
		flag.close()
	return error(
		-32000,
		"Timed out waiting for game response",
		{
			"game_running": EditorInterface.is_playing_scene(),
			"debugger_paused": true,
			"runtime_errors": "check the editor Debugger panel",
			"suggestion": "game may be paused in debugger",
		}
	)
