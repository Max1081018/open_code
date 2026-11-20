@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## runtime — 19 tools that drive the RUNNING game (SPEC §6, specs/B07-runtime.md).
##
## Every handler is a thin editor-side shim: validate params, build the IPC command dict,
## pick the IPC timeout, and `await _send_game_command(...)` (SPEC §3.4). The base helper
## already answers -32000 when no scene is playing, so no handler calls error_no_scene(),
## touches the edited scene, or opens an UndoRedo action — game-side mutations are not
## undoable and never belong in the editor's undo history.
##
## Editor->game command renames (the other 15 map 1:1):
##   get_game_scene_tree      -> get_scene_tree
##   get_game_node_properties -> get_node_properties
##   set_game_node_property   -> set_node_property
##   execute_game_script      -> execute_script

const DEFAULT_IPC_TIMEOUT := 5.0


func get_commands() -> Dictionary:
	return {
		"get_game_scene_tree": _get_game_scene_tree,
		"get_game_node_properties": _get_game_node_properties,
		"set_game_node_property": _set_game_node_property,
		"capture_frames": _capture_frames,
		"monitor_properties": _monitor_properties,
		"execute_game_script": _execute_game_script,
		"start_recording": _start_recording,
		"stop_recording": _stop_recording,
		"replay_recording": _replay_recording,
		"find_nodes_by_script": _find_nodes_by_script,
		"get_autoload": _get_autoload,
		"batch_get_properties": _batch_get_properties,
		"find_ui_elements": _find_ui_elements,
		"click_button_by_text": _click_button_by_text,
		"wait_for_node": _wait_for_node,
		"find_nearby_nodes": _find_nearby_nodes,
		"navigate_to": _navigate_to,
		"move_to": _move_to,
		"watch_signals": _watch_signals,
	}


# ---------------------------------------------------------------------------
# Shared param validation
# ---------------------------------------------------------------------------


func _error_missing(key: String) -> Dictionary:
	return error(-32602, "Missing required parameter: %s" % key)


func _error_param(message: String) -> Dictionary:
	return error(-32602, message)


## Optional string[] param. Returns [array_or_null, err_or_null]; absent -> [null, null].
func _optional_string_array(params: Dictionary, key: String) -> Array:
	if not params.has(key) or params[key] == null:
		return [null, null]
	if typeof(params[key]) != TYPE_ARRAY:
		return [null, _error_param("Parameter '%s' must be an array of strings" % key)]
	var out: Array = []
	for item: Variant in params[key] as Array:
		if typeof(item) != TYPE_STRING and typeof(item) != TYPE_STRING_NAME:
			return [null, _error_param("Parameter '%s' must contain only strings" % key)]
		out.append(String(item))
	return [out, null]


## Required, non-empty string[] param. Returns [array, err_or_null].
func _require_string_array(params: Dictionary, key: String) -> Array:
	if not params.has(key):
		return [null, _error_missing(key)]
	var res: Array = _optional_string_array(params, key)
	if res[1] != null:
		return res
	var arr: Variant = res[0]
	if arr == null or (arr as Array).is_empty():
		return [null, _error_param("Parameter '%s' must be a non-empty array of strings" % key)]
	return [arr, null]


## Required position/target param: a node path String, or {x, y[, z]} Dictionary.
func _require_position(params: Dictionary, key: String) -> Array:
	if not params.has(key) or params[key] == null:
		return [null, _error_missing(key)]
	var raw: Variant = params[key]
	match typeof(raw):
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw).strip_edges()
			if s.is_empty():
				return [null, _error_param("Parameter '%s' must not be empty" % key)]
			return [s, null]
		TYPE_DICTIONARY:
			var d: Dictionary = raw
			if not d.has("x") or not d.has("y"):
				return [
					null,
					_error_param("Parameter '%s' object must have numeric 'x' and 'y'" % key)
				]
			return [d, null]
		_:
			return [
				null,
				_error_param("Parameter '%s' must be a node path or an {x, y, z} object" % key)
			]


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------


func _get_game_scene_tree(params: Dictionary) -> Dictionary:
	var cmd: Dictionary = {
		"max_depth": optional_int(params, "max_depth", -1),
		"script_filter": optional_string(params, "script_filter", ""),
		"type_filter": optional_string(params, "type_filter", ""),
		"named_only": optional_bool(params, "named_only", false),
	}
	return await _send_game_command("get_scene_tree", cmd, DEFAULT_IPC_TIMEOUT)


func _get_game_node_properties(params: Dictionary) -> Dictionary:
	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var props: Array = _optional_string_array(params, "properties")
	if props[1] != null:
		return props[1]

	var cmd: Dictionary = {"node_path": np[0]}
	if props[0] != null:
		cmd["properties"] = props[0]
	return await _send_game_command("get_node_properties", cmd, DEFAULT_IPC_TIMEOUT)


func _set_game_node_property(params: Dictionary) -> Dictionary:
	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var prop: Array = require_string(params, "property")
	if prop[1] != null:
		return prop[1]
	if not params.has("value"):
		return _error_missing("value")

	var cmd: Dictionary = {
		"node_path": np[0],
		"property": prop[0],
		"value": params["value"],
	}
	return await _send_game_command("set_node_property", cmd, DEFAULT_IPC_TIMEOUT)


func _capture_frames(params: Dictionary) -> Dictionary:
	var count: int = clampi(optional_int(params, "count", 5), 1, 30)
	var interval: int = maxi(1, optional_int(params, "frame_interval", 10))
	var cmd: Dictionary = {
		"count": count,
		"frame_interval": interval,
		"half_resolution": optional_bool(params, "half_resolution", true),
	}
	var timeout: float = minf(25.0, float(count * interval) / 60.0 + 5.0)
	return await _send_game_command("capture_frames", cmd, timeout)


func _monitor_properties(params: Dictionary) -> Dictionary:
	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var props: Array = _require_string_array(params, "properties")
	if props[1] != null:
		return props[1]

	var frame_count: int = clampi(optional_int(params, "frame_count", 60), 1, 600)
	var interval: int = maxi(1, optional_int(params, "frame_interval", 1))
	var cmd: Dictionary = {
		"node_path": np[0],
		"properties": props[0],
		"frame_count": frame_count,
		"frame_interval": interval,
	}
	var timeout: float = minf(25.0, float(frame_count * interval) / 60.0 + 5.0)
	return await _send_game_command("monitor_properties", cmd, timeout)


func _execute_game_script(params: Dictionary) -> Dictionary:
	var code: Array = require_string(params, "code")
	if code[1] != null:
		return code[1]
	return await _send_game_command("execute_script", {"code": code[0]}, 10.0)


func _start_recording(_params: Dictionary) -> Dictionary:
	return await _send_game_command("start_recording", {}, DEFAULT_IPC_TIMEOUT)


func _stop_recording(_params: Dictionary) -> Dictionary:
	return await _send_game_command("stop_recording", {}, DEFAULT_IPC_TIMEOUT)


func _replay_recording(params: Dictionary) -> Dictionary:
	if not params.has("events") or typeof(params["events"]) != TYPE_ARRAY:
		return _error_missing("events")
	var events: Array = params["events"]
	if events.is_empty():
		return _error_param("Parameter 'events' must be a non-empty array of recorded events")

	var speed: float = optional_float(params, "speed", 1.0)
	if speed <= 0.0:
		return _error_param("Parameter 'speed' must be greater than 0")

	# The replay lasts as long as the last event's timestamp, scaled by speed.
	var max_time_ms: float = 0.0
	for event: Variant in events:
		if typeof(event) != TYPE_DICTIONARY:
			return _error_param("Parameter 'events' must contain only recorded event objects")
		var t: float = float((event as Dictionary).get("time_ms", 0))
		max_time_ms = maxf(max_time_ms, t)

	var cmd: Dictionary = {"events": events, "speed": speed}
	var timeout: float = minf(120.0, max_time_ms / 1000.0 / speed + 5.0)
	return await _send_game_command("replay_recording", cmd, timeout)


func _find_nodes_by_script(params: Dictionary) -> Dictionary:
	var scr: Array = require_string(params, "script")
	if scr[1] != null:
		return scr[1]
	var props: Array = _optional_string_array(params, "properties")
	if props[1] != null:
		return props[1]

	var cmd: Dictionary = {"script": scr[0]}
	if props[0] != null:
		cmd["properties"] = props[0]
	return await _send_game_command("find_nodes_by_script", cmd, DEFAULT_IPC_TIMEOUT)


func _get_autoload(params: Dictionary) -> Dictionary:
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var props: Array = _optional_string_array(params, "properties")
	if props[1] != null:
		return props[1]

	var cmd: Dictionary = {"name": name_res[0]}
	if props[0] != null:
		cmd["properties"] = props[0]
	return await _send_game_command("get_autoload", cmd, DEFAULT_IPC_TIMEOUT)


func _batch_get_properties(params: Dictionary) -> Dictionary:
	if not params.has("nodes") or typeof(params["nodes"]) != TYPE_ARRAY:
		return _error_missing("nodes")
	var raw_nodes: Array = params["nodes"]
	if raw_nodes.is_empty():
		return _error_param("Parameter 'nodes' must be a non-empty array")

	var entries: Array = []
	for item: Variant in raw_nodes:
		if typeof(item) != TYPE_DICTIONARY:
			return _error_param("Parameter 'nodes' must contain {node_path, properties?} objects")
		var entry: Dictionary = item
		var path_res: Array = require_string(entry, "node_path")
		if path_res[1] != null:
			return path_res[1]
		var props: Array = _optional_string_array(entry, "properties")
		if props[1] != null:
			return props[1]
		var out: Dictionary = {"node_path": path_res[0]}
		if props[0] != null:
			out["properties"] = props[0]
		entries.append(out)

	return await _send_game_command("batch_get_properties", {"nodes": entries}, DEFAULT_IPC_TIMEOUT)


func _find_ui_elements(params: Dictionary) -> Dictionary:
	var cmd: Dictionary = {"type_filter": optional_string(params, "type_filter", "")}
	return await _send_game_command("find_ui_elements", cmd, DEFAULT_IPC_TIMEOUT)


func _click_button_by_text(params: Dictionary) -> Dictionary:
	var text: Array = require_string(params, "text")
	if text[1] != null:
		return text[1]
	var cmd: Dictionary = {
		"text": text[0],
		"partial": optional_bool(params, "partial", true),
	}
	return await _send_game_command("click_button_by_text", cmd, DEFAULT_IPC_TIMEOUT)


func _wait_for_node(params: Dictionary) -> Dictionary:
	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]

	# Clamped so the IPC wait always stays under the bridge's 30s default (no ToolDef timeoutMs).
	var timeout: float = clampf(optional_float(params, "timeout", 5.0), 0.5, 20.0)
	var cmd: Dictionary = {
		"node_path": np[0],
		"timeout": timeout,
		"poll_frames": maxi(1, optional_int(params, "poll_frames", 5)),
	}
	return await _send_game_command("wait_for_node", cmd, timeout + 2.0)


func _find_nearby_nodes(params: Dictionary) -> Dictionary:
	var pos: Array = _require_position(params, "position")
	if pos[1] != null:
		return pos[1]

	var cmd: Dictionary = {
		"position": pos[0],
		"radius": maxf(0.0, optional_float(params, "radius", 20.0)),
		"type_filter": optional_string(params, "type_filter", ""),
		"group_filter": optional_string(params, "group_filter", ""),
		"max_results": maxi(1, optional_int(params, "max_results", 10)),
	}
	return await _send_game_command("find_nearby_nodes", cmd, DEFAULT_IPC_TIMEOUT)


func _navigate_to(params: Dictionary) -> Dictionary:
	var target: Array = _require_position(params, "target")
	if target[1] != null:
		return target[1]

	var cmd: Dictionary = {
		"target": target[0],
		"player_path": optional_string(params, "player_path", ""),
		"camera_path": optional_string(params, "camera_path", ""),
		"move_speed": optional_float(params, "move_speed", 5.0),
	}
	return await _send_game_command("navigate_to", cmd, DEFAULT_IPC_TIMEOUT)


func _move_to(params: Dictionary) -> Dictionary:
	var target: Array = _require_position(params, "target")
	if target[1] != null:
		return target[1]

	var timeout: float = clampf(optional_float(params, "timeout", 15.0), 1.0, 120.0)
	var cmd: Dictionary = {
		"target": target[0],
		"player_path": optional_string(params, "player_path", ""),
		"camera_path": optional_string(params, "camera_path", ""),
		"arrival_radius": maxf(0.0, optional_float(params, "arrival_radius", 1.5)),
		"timeout": timeout,
		"run": optional_bool(params, "run", false),
		"look_at_target": optional_bool(params, "look_at_target", true),
	}
	return await _send_game_command("move_to", cmd, timeout + 5.0)


func _watch_signals(params: Dictionary) -> Dictionary:
	var paths: Array = _require_string_array(params, "node_paths")
	if paths[1] != null:
		return paths[1]
	var filter: Array = _optional_string_array(params, "signal_filter")
	if filter[1] != null:
		return filter[1]

	# Mirror the game-side clamp before computing the IPC timeout.
	var duration_ms: int = clampi(optional_int(params, "duration_ms", 5000), 500, 30000)
	var cmd: Dictionary = {
		"node_paths": paths[0],
		"duration_ms": duration_ms,
	}
	if filter[0] != null:
		cmd["signal_filter"] = filter[0]

	var timeout: float = float(duration_ms) / 1000.0 + 5.0
	return await _send_game_command("watch_signals", cmd, timeout)
