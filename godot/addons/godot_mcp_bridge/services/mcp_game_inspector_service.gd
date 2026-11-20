extends Node

## GAME-SIDE autoload (injected by the plugin). Deliberately carries no editor-tool
## annotation: this script only ever runs inside the running game, never in the editor.
##
## File IPC (frozen, SPEC §3.4): the editor writes
##   <user>/mcp_game_request   {"command": String, "params": Dictionary}
## we poll it every frame, delete it, dispatch, and write
##   <user>/mcp_game_response  {"success": true, "data": ...}
##                          |  {"success": false, "error": String}
##
## The 20 inspector commands below are FROZEN (specs/B07-runtime.md) — B05/B06 call them
## by wire-string. Names, params and response shapes never change; additions are additive.
##
## Design rules that keep the game alive:
##   * Long-running commands are coroutines that await process frames. `_process` fires the
##     flow WITHOUT awaiting it and the flow writes the response itself — blocking `_process`
##     for 300 frames would freeze the game we are supposed to be observing.
##   * One command at a time (`_busy`): a request arriving mid-command is answered with an
##     explicit refusal rather than aborting the running one. Recording and navigate_to
##     movement are BACKGROUND activities, not busy states.
##   * A crash inside a coroutine kills it silently, so a watchdog releases `_busy` (and any
##     held movement keys) once the command's deadline passes with no response written.
##   * Responses are written tmp+rename: the editor polls every 0.1s and must never read a
##     half-written multi-megabyte frame payload.
##   * GDScript has no exceptions: every handler validates first and returns an error dict
##     instead of ever indexing blind. A missing response is the one unrecoverable failure.

const REQUEST_PATH := "user://mcp_game_request"
const RESPONSE_PATH := "user://mcp_game_response"
const RESPONSE_TMP_PATH := "user://mcp_game_response.tmp"
const DEBUGGER_CONTINUE_PATH := "user://mcp_debugger_continue"

## Grace added to a command's own budget before the watchdog declares it crashed.
const WATCHDOG_GRACE_MS := 5000
const DEFAULT_BUDGET_S := 10.0
## Recursion cap for _serialize_value (deep resources would otherwise blow the stack).
const MAX_SERIALIZE_DEPTH := 6
## Packed arrays longer than this are summarized instead of dumped.
const MAX_PACKED_ELEMENTS := 64
## Camera pivot steering rate while walking to a target.
const MAX_YAW_RATE := 10.0
## Hard safety cap on a fire-and-forget navigate_to movement.
const NAVIGATE_HARD_CAP_S := 30.0
const NAVIGATE_ARRIVAL_RADIUS := 1.5

# --- busy / watchdog ---------------------------------------------------------
var _busy := false
var _busy_command := ""
var _busy_deadline_ms := 0

# --- recording ---------------------------------------------------------------
var _recording := false
var _replaying := false
var _record_start_ms := 0
var _recorded_events: Array = []

# --- signal watching ---------------------------------------------------------
var _watch_connections: Array = []
var _watch_events: Array = []
var _watch_start_ms := 0

# --- movement engine (shared by navigate_to and move_to) ---------------------
var _move_active := false
var _move_player: Node3D = null
var _move_pivot: Node3D = null
var _move_target := Vector3.ZERO
var _move_arrival_radius := 1.5
var _move_deadline_ms := 0
var _move_start_ms := 0
var _move_timeout_s := 0.0
var _move_look_at_target := true
var _move_last_position := Vector3.ZERO
var _held_keys: Array[int] = []
var _move_result: Dictionary = {}


func _ready() -> void:
	# The IPC must keep answering while the SceneTree is paused. (It still halts when the
	# DEBUGGER breaks — that is what the mcp_debugger_continue flag path exists for.)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(false)
	for path: String in [REQUEST_PATH, RESPONSE_PATH, RESPONSE_TMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _process(delta: float) -> void:
	_watchdog_tick()
	_move_tick(delta)
	_poll_request()


# ---------------------------------------------------------------------------
# IPC
# ---------------------------------------------------------------------------


func _poll_request() -> void:
	if not FileAccess.file_exists(REQUEST_PATH):
		return

	var file: FileAccess = FileAccess.open(REQUEST_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST_PATH))

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_write_response({"success": false, "error": "Malformed request payload"})
		return

	var request: Dictionary = parsed
	var command: String = str(request.get("command", ""))
	var raw_params: Variant = request.get("params", {})
	var params: Dictionary = raw_params if typeof(raw_params) == TYPE_DICTIONARY else {}

	if command.is_empty():
		_write_response({"success": false, "error": "Missing command"})
		return

	if _busy:
		# Under the bridge's strict-FIFO rule this only happens after the editor abandoned a
		# timed-out call. An explicit refusal beats silently switching mid-operation.
		_write_response(
			{"success": false, "error": "Inspector busy: '%s' still running" % _busy_command}
		)
		return

	# An editor that timed out and walked away may have left its response behind.
	for stale: String in [RESPONSE_PATH, RESPONSE_TMP_PATH]:
		if FileAccess.file_exists(stale):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))

	_busy = true
	_busy_command = command
	_busy_deadline_ms = (
		Time.get_ticks_msec() + int(_budget_for(command, params) * 1000.0) + WATCHDOG_GRACE_MS
	)

	# Fired WITHOUT await: a coroutine runs until its first suspend and resumes on its own,
	# so _process returns immediately even for a 600-frame monitor_properties.
	_run_request(command, params)


func _run_request(command: String, params: Dictionary) -> void:
	var out: Dictionary = await _dispatch(command, params)
	if out.has("error"):
		_write_response({"success": false, "error": str(out["error"])})
	else:
		_write_response({"success": true, "data": out})


## FROZEN command list (specs/B07-runtime.md). Every branch awaits — awaiting a
## non-coroutine result is legal, so quick and long-running handlers dispatch uniformly.
func _dispatch(command: String, params: Dictionary) -> Dictionary:
	match command:
		"ping":
			return {"pong": true}
		"get_scene_tree":
			return await _cmd_get_scene_tree(params)
		"get_node_properties":
			return await _cmd_get_node_properties(params)
		"set_node_property":
			return await _cmd_set_node_property(params)
		"capture_frames":
			return await _cmd_capture_frames(params)
		"monitor_properties":
			return await _cmd_monitor_properties(params)
		"execute_script":
			return await _cmd_execute_script(params)
		"start_recording":
			return await _cmd_start_recording(params)
		"stop_recording":
			return await _cmd_stop_recording(params)
		"replay_recording":
			return await _cmd_replay_recording(params)
		"find_nodes_by_script":
			return await _cmd_find_nodes_by_script(params)
		"get_autoload":
			return await _cmd_get_autoload(params)
		"batch_get_properties":
			return await _cmd_batch_get_properties(params)
		"find_ui_elements":
			return await _cmd_find_ui_elements(params)
		"click_button_by_text":
			return await _cmd_click_button_by_text(params)
		"wait_for_node":
			return await _cmd_wait_for_node(params)
		"find_nearby_nodes":
			return await _cmd_find_nearby_nodes(params)
		"navigate_to":
			return await _cmd_navigate_to(params)
		"move_to":
			return await _cmd_move_to(params)
		"watch_signals":
			return await _cmd_watch_signals(params)
		_:
			return {"error": "Unknown inspector command: %s" % command}


## Atomic write: the editor polls every 0.1s and must never see a partial payload.
func _write_response(response: Dictionary) -> void:
	_busy = false
	_busy_command = ""

	var file: FileAccess = FileAccess.open(RESPONSE_TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[MCP] could not write game response file")
		return
	file.store_string(JSON.stringify(response))
	file.close()

	var err: int = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(RESPONSE_TMP_PATH),
		ProjectSettings.globalize_path(RESPONSE_PATH)
	)
	if err != OK:
		push_error("[MCP] could not publish game response file: %s" % error_string(err))


## A runtime error inside a coroutine kills it silently — without this, the response would
## never be written and _busy would stick forever.
func _watchdog_tick() -> void:
	if not _busy:
		return
	if Time.get_ticks_msec() <= _busy_deadline_ms:
		return
	if FileAccess.file_exists(RESPONSE_PATH):
		return

	var stalled: String = _busy_command
	_stop_movement()
	_disconnect_watchers()
	_replaying = false

	# The plugin watches for this flag and presses the debugger's Continue button.
	var flag: FileAccess = FileAccess.open(DEBUGGER_CONTINUE_PATH, FileAccess.WRITE)
	if flag != null:
		flag.store_string("1")
		flag.close()

	_write_response(
		{
			"success": false,
			"error": (
				"Inspector command '%s' crashed or stalled — check the debugger" % stalled
			),
		}
	)


## Per-command watchdog budget in seconds (the command's own internal ceiling).
func _budget_for(command: String, params: Dictionary) -> float:
	match command:
		"capture_frames":
			var count: int = clampi(_pint(params, "count", 5), 1, 30)
			var interval: int = maxi(1, _pint(params, "frame_interval", 10))
			return minf(25.0, float(count * interval) / 60.0 + 5.0)
		"monitor_properties":
			var frames: int = clampi(_pint(params, "frame_count", 60), 1, 600)
			var step: int = maxi(1, _pint(params, "frame_interval", 1))
			return minf(25.0, float(frames * step) / 60.0 + 5.0)
		"execute_script":
			return 10.0
		"wait_for_node":
			return clampf(_pfloat(params, "timeout", 5.0), 0.5, 20.0)
		"move_to":
			return clampf(_pfloat(params, "timeout", 15.0), 1.0, 120.0)
		"watch_signals":
			return float(clampi(_pint(params, "duration_ms", 5000), 500, 30000)) / 1000.0
		"replay_recording":
			var speed: float = _pfloat(params, "speed", 1.0)
			if speed <= 0.0:
				speed = 1.0
			var last_ms: float = 0.0
			if typeof(params.get("events")) == TYPE_ARRAY:
				for event: Variant in params["events"] as Array:
					if typeof(event) == TYPE_DICTIONARY:
						last_ms = maxf(last_ms, float((event as Dictionary).get("time_ms", 0)))
			return minf(120.0, last_ms / 1000.0 / speed + 5.0)
		_:
			return DEFAULT_BUDGET_S


# ---------------------------------------------------------------------------
# Param helpers — the inspector never trusts its caller (other packages call it directly).
# ---------------------------------------------------------------------------


func _pint(params: Dictionary, key: String, default: int) -> int:
	var raw: Variant = params.get(key)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return int(roundf(float(raw)))
	return default


func _pfloat(params: Dictionary, key: String, default: float) -> float:
	var raw: Variant = params.get(key)
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return float(raw)
	return default


func _pbool(params: Dictionary, key: String, default: bool) -> bool:
	var raw: Variant = params.get(key)
	if typeof(raw) == TYPE_BOOL:
		return bool(raw)
	return default


func _pstring(params: Dictionary, key: String, default: String = "") -> String:
	var raw: Variant = params.get(key)
	if typeof(raw) == TYPE_STRING or typeof(raw) == TYPE_STRING_NAME:
		return String(raw)
	return default


## Whitelist param: null when absent, PackedStringArray-ish Array of names otherwise.
func _pstring_array(params: Dictionary, key: String) -> Variant:
	var raw: Variant = params.get(key)
	if typeof(raw) != TYPE_ARRAY:
		return null
	var out: Array = []
	for item: Variant in raw as Array:
		out.append(str(item))
	return out


func _err(message: String) -> Dictionary:
	return {"error": message}


# ---------------------------------------------------------------------------
# Node resolution — absolute /root paths are preferred and documented as such.
# ---------------------------------------------------------------------------


func _resolve(path: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	var p: String = path.strip_edges()
	if p.is_empty():
		return null
	if p.begins_with("/root"):
		return tree.root.get_node_or_null(NodePath(p))
	var found: Node = tree.root.get_node_or_null(NodePath(p))
	if found != null:
		return found
	if tree.current_scene != null:
		return tree.current_scene.get_node_or_null(NodePath(p))
	return null


func _script_path(node: Node) -> String:
	var scr: Script = node.get_script() as Script
	if scr == null:
		return ""
	return scr.resource_path


# ---------------------------------------------------------------------------
# Serialization — structured objects, deliberately unlike the editor-side string form.
# Runtime data is consumed numerically, so {x, y} beats "Vector2(1, 2)".
# ---------------------------------------------------------------------------


func _serialize_value(value: Variant, depth: int = 0) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return {"x": v2.x, "y": v2.y}
		TYPE_VECTOR2I:
			var v2i: Vector2i = value
			return {"x": v2i.x, "y": v2i.y}
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return {"x": v3.x, "y": v3.y, "z": v3.z}
		TYPE_VECTOR3I:
			var v3i: Vector3i = value
			return {"x": v3i.x, "y": v3i.y, "z": v3i.z}
		TYPE_VECTOR4:
			var v4: Vector4 = value
			return {"x": v4.x, "y": v4.y, "z": v4.z, "w": v4.w}
		TYPE_RECT2:
			var r: Rect2 = value
			return {"x": r.position.x, "y": r.position.y, "width": r.size.x, "height": r.size.y}
		TYPE_RECT2I:
			var ri: Rect2i = value
			return {
				"x": ri.position.x,
				"y": ri.position.y,
				"width": ri.size.x,
				"height": ri.size.y,
			}
		TYPE_COLOR:
			var c: Color = value
			return {"r": c.r, "g": c.g, "b": c.b, "a": c.a, "html": "#%s" % c.to_html(true)}
		TYPE_ARRAY:
			if depth >= MAX_SERIALIZE_DEPTH:
				return str(value)
			var out_arr: Array = []
			for item: Variant in value as Array:
				out_arr.append(_serialize_value(item, depth + 1))
			return out_arr
		TYPE_DICTIONARY:
			if depth >= MAX_SERIALIZE_DEPTH:
				return str(value)
			var out_dict: Dictionary = {}
			for key: Variant in value as Dictionary:
				out_dict[str(key)] = _serialize_value((value as Dictionary)[key], depth + 1)
			return out_dict
		TYPE_OBJECT:
			if value == null:
				return null
			var obj: Object = value
			if obj is Resource:
				var res: Resource = obj as Resource
				return {"type": res.get_class(), "path": res.resource_path}
			return str(value)
		_:
			return _serialize_packed(value)


func _serialize_packed(value: Variant) -> Variant:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var size: int = int(value.size())
			if size > MAX_PACKED_ELEMENTS:
				return "<%s size=%d>" % [type_string(typeof(value)), size]
			var out: Array = []
			for item: Variant in value:
				out.append(_serialize_value(item, MAX_SERIALIZE_DEPTH - 1))
			return out
		_:
			# Basis / Transform2D / Transform3D / Quaternion / Plane / AABB / anything exotic.
			return str(value)


## Editor-visible properties of a node (script and _-prefixed internals excluded).
func _dump_properties(node: Node) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in node.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY) != 0:
			continue
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty() or prop_name == "script" or prop_name.begins_with("_"):
			continue
		out[prop_name] = _serialize_value(node.get(prop_name))
	return out


## Whitelisted read: names the node does not have come back as null rather than failing.
func _read_properties(node: Node, names: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in names:
		var prop_name: String = str(raw)
		if prop_name in node:
			out[prop_name] = _serialize_value(node.get(prop_name))
		else:
			out[prop_name] = null
	return out


# ---------------------------------------------------------------------------
# Value parsing — the inspector's self-contained copy of §3.4's coercion rules.
# Deliberately not a preload of the editor-side property_parser: no editor-side util change
# can ever break a running game. The rules must stay behaviorally identical.
# ---------------------------------------------------------------------------


func _parse_value(raw: Variant, target_type: int) -> Variant:
	var t: int = typeof(raw)

	if t == target_type:
		return raw

	if t == TYPE_DICTIONARY:
		var d: Dictionary = raw
		match target_type:
			TYPE_VECTOR2:
				return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
			TYPE_VECTOR2I:
				return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
			TYPE_VECTOR3:
				return Vector3(
					float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0))
				)
			TYPE_VECTOR3I:
				return Vector3i(int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("z", 0)))
			TYPE_COLOR:
				return Color(
					float(d.get("r", 0.0)),
					float(d.get("g", 0.0)),
					float(d.get("b", 0.0)),
					float(d.get("a", 1.0))
				)
		return raw

	if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
		match target_type:
			TYPE_INT:
				return int(roundf(float(raw)))
			TYPE_FLOAT:
				return float(raw)
			TYPE_BOOL:
				return not is_zero_approx(float(raw))
		return raw

	if t != TYPE_STRING and t != TYPE_STRING_NAME:
		return raw

	var s: String = String(raw).strip_edges()
	match target_type:
		TYPE_BOOL:
			return s.to_lower() == "true" or s == "1"
		TYPE_INT:
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return int(roundf(s.to_float()))
			return _eval_constructor(s)
		TYPE_FLOAT:
			if s.is_valid_float():
				return s.to_float()
			return _eval_constructor(s)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return s
		TYPE_COLOR:
			if s.begins_with("#"):
				return Color.html(s)
			return _eval_constructor(s)
		TYPE_NIL:
			var lower: String = s.to_lower()
			if lower == "true":
				return true
			if lower == "false":
				return false
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return s.to_float()
			if s.begins_with("#"):
				return Color.html(s)
			return _eval_constructor(s)
		_:
			return _eval_constructor(s)


## Only strings shaped like a Godot constructor are evaluated; anything else is the raw string.
func _eval_constructor(s: String) -> Variant:
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_]+\\(")
	if re.search(s) == null or not s.ends_with(")"):
		return s
	var expr := Expression.new()
	if expr.parse(s) != OK:
		return s
	var out: Variant = expr.execute([], null, false)
	if expr.has_execute_failed():
		return s
	return out


# ---------------------------------------------------------------------------
# get_scene_tree
# ---------------------------------------------------------------------------


func _cmd_get_scene_tree(params: Dictionary) -> Dictionary:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")

	var max_depth: int = _pint(params, "max_depth", -1)
	var script_filter: String = _pstring(params, "script_filter").to_lower()
	var type_filter: String = _pstring(params, "type_filter")
	var named_only: bool = _pbool(params, "named_only", false)
	var filtering: bool = (
		not script_filter.is_empty() or not type_filter.is_empty() or named_only
	)

	var current: Variant = null
	if tree.current_scene != null:
		current = str(tree.current_scene.get_path())

	var built: Variant = _build_tree(
		tree.root, 0, max_depth, script_filter, type_filter, named_only, filtering
	)
	if built == null:
		return {
			"tree": null,
			"current_scene": current,
			"message": "No nodes matched the given filters",
		}
	return {"tree": built, "current_scene": current}


## Returns the node dict, or null when nothing in this subtree matches. Non-matching ancestors
## of a match are kept as path scaffolding.
func _build_tree(
	node: Node,
	depth: int,
	max_depth: int,
	script_filter: String,
	type_filter: String,
	named_only: bool,
	filtering: bool
) -> Variant:
	var children: Array = []
	if max_depth < 0 or depth < max_depth:
		for child: Node in node.get_children():
			var sub: Variant = _build_tree(
				child, depth + 1, max_depth, script_filter, type_filter, named_only, filtering
			)
			if sub != null:
				children.append(sub)

	var self_matches: bool = (
		not filtering or _matches_filters(node, script_filter, type_filter, named_only)
	)
	if not self_matches and children.is_empty():
		return null

	var out: Dictionary = {
		"name": str(node.name),
		"type": node.get_class(),
		"path": str(node.get_path()),
	}
	var scr: String = _script_path(node)
	if not scr.is_empty():
		out["script"] = scr
	if not children.is_empty():
		out["children"] = children
	return out


func _matches_filters(
	node: Node, script_filter: String, type_filter: String, named_only: bool
) -> bool:
	if named_only and str(node.name).begins_with("@"):
		return false
	if not type_filter.is_empty() and not node.is_class(type_filter):
		return false
	if not script_filter.is_empty():
		var scr: String = _script_path(node).to_lower()
		if scr.is_empty() or not scr.contains(script_filter):
			return false
	return true


# ---------------------------------------------------------------------------
# get_node_properties / set_node_property / batch_get_properties / get_autoload
# ---------------------------------------------------------------------------


func _cmd_get_node_properties(params: Dictionary) -> Dictionary:
	var path: String = _pstring(params, "node_path")
	if path.is_empty():
		return _err("Missing required parameter: node_path")
	var node: Node = _resolve(path)
	if node == null:
		return _err("Node not found: %s" % path)

	var whitelist: Variant = _pstring_array(params, "properties")
	var props: Dictionary = (
		_read_properties(node, whitelist) if whitelist != null else _dump_properties(node)
	)
	return {
		"node_path": str(node.get_path()),
		"type": node.get_class(),
		"properties": props,
	}


func _cmd_set_node_property(params: Dictionary) -> Dictionary:
	var path: String = _pstring(params, "node_path")
	if path.is_empty():
		return _err("Missing required parameter: node_path")
	var property: String = _pstring(params, "property")
	if property.is_empty():
		return _err("Missing required parameter: property")
	if not params.has("value"):
		return _err("Missing required parameter: value")

	var node: Node = _resolve(path)
	if node == null:
		return _err("Node not found: %s" % path)
	if not (property in node):
		return _err("Property not found: %s on %s" % [property, node.get_class()])

	var old_value: Variant = node.get(property)
	node.set(property, _parse_value(params["value"], typeof(old_value)))
	# Re-read rather than echo: setters clamp, snap and normalize.
	return {
		"node_path": str(node.get_path()),
		"property": property,
		"old_value": _serialize_value(old_value),
		"new_value": _serialize_value(node.get(property)),
	}


func _cmd_batch_get_properties(params: Dictionary) -> Dictionary:
	var raw: Variant = params.get("nodes")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return _err("Missing required parameter: nodes")

	var results: Array = []
	for item: Variant in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var path: String = _pstring(entry, "node_path")
		var node: Node = _resolve(path) if not path.is_empty() else null
		if node == null:
			# A missing node reports inline — it never fails the whole batch.
			results.append({"node_path": path, "properties": {}, "error": "Node not found"})
			continue
		var whitelist: Variant = _pstring_array(entry, "properties")
		var props: Dictionary = (
			_read_properties(node, whitelist) if whitelist != null else _dump_properties(node)
		)
		results.append({"node_path": str(node.get_path()), "properties": props})

	return {"nodes": results, "count": results.size()}


func _cmd_get_autoload(params: Dictionary) -> Dictionary:
	var autoload_name: String = _pstring(params, "name")
	if autoload_name.is_empty():
		return _err("Missing required parameter: name")

	var node: Node = _resolve("/root/%s" % autoload_name)
	if node == null:
		return _err("Autoload not found: %s" % autoload_name)

	var whitelist: Variant = _pstring_array(params, "properties")
	var props: Dictionary = (
		_read_properties(node, whitelist) if whitelist != null else _dump_properties(node)
	)
	var out: Dictionary = {
		"name": autoload_name,
		"path": str(node.get_path()),
		"type": node.get_class(),
		"properties": props,
	}
	var scr: String = _script_path(node)
	if not scr.is_empty():
		out["script"] = scr
	return out


# ---------------------------------------------------------------------------
# find_nodes_by_script
# ---------------------------------------------------------------------------


func _cmd_find_nodes_by_script(params: Dictionary) -> Dictionary:
	var needle: String = _pstring(params, "script").to_lower()
	if needle.is_empty():
		return _err("Missing required parameter: script")
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")

	var whitelist: Variant = _pstring_array(params, "properties")
	var matches: Array = []
	for node: Node in _walk(tree.root):
		var scr: String = _script_path(node)
		if scr.is_empty() or not scr.to_lower().contains(needle):
			continue
		var entry: Dictionary = {
			"name": str(node.name),
			"path": str(node.get_path()),
			"type": node.get_class(),
			"script": scr,
		}
		if whitelist != null:
			entry["properties"] = _read_properties(node, whitelist)
		matches.append(entry)

	return {"nodes": matches, "count": matches.size()}


## Flat depth-first list of a subtree, root included.
func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		var children: Array[Node] = node.get_children()
		for i: int in range(children.size() - 1, -1, -1):
			stack.append(children[i])
	return out


# ---------------------------------------------------------------------------
# capture_frames
# ---------------------------------------------------------------------------


func _cmd_capture_frames(params: Dictionary) -> Dictionary:
	var count: int = clampi(_pint(params, "count", 5), 1, 30)
	var interval: int = maxi(1, _pint(params, "frame_interval", 10))
	var half: bool = _pbool(params, "half_resolution", true)

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return _err("Viewport is not available")

	var frames: Array = []
	var width: int = 0
	var height: int = 0

	for i: int in range(count):
		await RenderingServer.frame_post_draw
		var texture: ViewportTexture = viewport.get_texture()
		if texture == null:
			return _err("Viewport texture is not available")
		var image: Image = texture.get_image()
		if image == null:
			return _err("Could not read the viewport image")
		if half and image.get_width() > 1 and image.get_height() > 1:
			image.resize(
				maxi(1, image.get_width() / 2),
				maxi(1, image.get_height() / 2),
				Image.INTERPOLATE_BILINEAR
			)
		width = image.get_width()
		height = image.get_height()
		frames.append(Marshalls.raw_to_base64(image.save_png_to_buffer()))

		if i < count - 1:
			for _f: int in range(interval):
				await get_tree().process_frame

	return {
		"frames": frames,
		"count": frames.size(),
		"width": width,
		"height": height,
		"half_resolution": half,
	}


# ---------------------------------------------------------------------------
# monitor_properties
# ---------------------------------------------------------------------------


func _cmd_monitor_properties(params: Dictionary) -> Dictionary:
	var path: String = _pstring(params, "node_path")
	if path.is_empty():
		return _err("Missing required parameter: node_path")
	var names: Variant = _pstring_array(params, "properties")
	if names == null or (names as Array).is_empty():
		return _err("Missing required parameter: properties")

	var node: Node = _resolve(path)
	if node == null:
		return _err("Node not found: %s" % path)

	var frame_count: int = clampi(_pint(params, "frame_count", 60), 1, 600)
	var interval: int = maxi(1, _pint(params, "frame_interval", 1))
	var resolved_path: String = str(node.get_path())
	var samples: Array = []

	for i: int in range(frame_count):
		if is_instance_valid(node):
			samples.append(_read_properties(node, names))
		else:
			# The node despawned mid-run: keep sampling nulls, the timing is the finding.
			var blank: Dictionary = {}
			for raw: Variant in names as Array:
				blank[str(raw)] = null
			samples.append(blank)

		if i < frame_count - 1:
			for _f: int in range(interval):
				await get_tree().process_frame

	return {
		"node_path": resolved_path,
		"properties": names,
		"samples": samples,
		"sample_count": samples.size(),
		"frame_interval": interval,
	}


# ---------------------------------------------------------------------------
# execute_script
# ---------------------------------------------------------------------------


func _cmd_execute_script(params: Dictionary) -> Dictionary:
	var code: String = _pstring(params, "code")
	if code.is_empty():
		return _err("Missing required parameter: code")

	var script := GDScript.new()
	script.source_code = _build_script_source(code)
	var err: int = script.reload()
	if err != OK:
		return _err("Script compile failed: %s" % error_string(err))

	var instance: Object = script.new()
	if instance == null:
		return _err("Script compile failed: could not instantiate the wrapper")
	if not instance.has_method("run"):
		return _err("Script compile failed: wrapper has no run()")

	var ret: Variant = instance.call("run", get_tree().root)
	var output: Variant = instance.get("_mcp_output")
	var lines: Array = output if typeof(output) == TYPE_ARRAY else []
	return {"output": lines.duplicate(), "return_value": _serialize_value(ret)}


## The user's lines become the body of run(root). print() is rewritten to _mcp_print() so the
## output comes back over the IPC instead of only reaching the game's own console.
func _build_script_source(code: String) -> String:
	var body: PackedStringArray = _normalize_indentation(code)
	var source: String = (
		"extends RefCounted\n"
		+ "var _mcp_output: Array = []\n"
		+ "func _mcp_print(value) -> void:\n"
		+ "\t_mcp_output.append(str(value))\n"
		+ "func run(root: Node) -> Variant:\n"
	)
	var re := RegEx.new()
	re.compile("(?<![\\w.])print\\s*\\(")
	for line: String in body:
		source += "\t%s\n" % re.sub(line, "_mcp_print(", true)
	source += "\treturn null\n"
	return source


## Space indentation becomes tabs (GDScript will not mix them): the smallest positive run of
## leading spaces in the snippet is one indent level.
func _normalize_indentation(code: String) -> PackedStringArray:
	var lines: PackedStringArray = code.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var unit: int = 0
	for line: String in lines:
		if line.strip_edges().is_empty() or line.begins_with("\t"):
			continue
		var spaces: int = line.length() - line.lstrip(" ").length()
		if spaces > 0 and (unit == 0 or spaces < unit):
			unit = spaces

	var out := PackedStringArray()
	for line: String in lines:
		if unit <= 0 or line.begins_with("\t"):
			out.append(line)
			continue
		var spaces: int = line.length() - line.lstrip(" ").length()
		var depth: int = spaces / unit
		out.append("\t".repeat(depth) + line.substr(spaces))
	return out


# ---------------------------------------------------------------------------
# Recording / replay
# ---------------------------------------------------------------------------


func _cmd_start_recording(_params: Dictionary) -> Dictionary:
	# Restart semantics: a second start clears whatever was buffered.
	_recorded_events.clear()
	_record_start_ms = Time.get_ticks_msec()
	_recording = true
	set_process_input(true)
	return {"recording": true}


func _cmd_stop_recording(_params: Dictionary) -> Dictionary:
	var duration_ms: int = 0
	if _recording:
		duration_ms = Time.get_ticks_msec() - _record_start_ms
	_recording = false
	set_process_input(false)

	var events: Array = _recorded_events.duplicate()
	_recorded_events.clear()
	return {
		"recording": false,
		"events": events,
		"event_count": events.size(),
		"duration_ms": duration_ms,
	}


func _input(event: InputEvent) -> void:
	if not _recording or _replaying:
		return
	var entry: Variant = _record_event(event)
	if entry != null:
		_recorded_events.append(entry)


## FROZEN event shapes — replay_recording consumes them verbatim.
func _record_event(event: InputEvent) -> Variant:
	var time_ms: int = Time.get_ticks_msec() - _record_start_ms

	if event is InputEventKey:
		var key: InputEventKey = event
		return {
			"type": "key",
			"time_ms": time_ms,
			"keycode": OS.get_keycode_string(key.keycode) if key.keycode != 0 else "",
			"physical_keycode": (
				OS.get_keycode_string(key.physical_keycode) if key.physical_keycode != 0 else ""
			),
			"pressed": key.pressed,
			"shift": key.shift_pressed,
			"ctrl": key.ctrl_pressed,
			"alt": key.alt_pressed,
		}

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		return {
			"type": "mouse_button",
			"time_ms": time_ms,
			"button": int(mb.button_index),
			"pressed": mb.pressed,
			"double_click": mb.double_click,
			"position": {"x": mb.position.x, "y": mb.position.y},
		}

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		return {
			"type": "mouse_motion",
			"time_ms": time_ms,
			"position": {"x": mm.position.x, "y": mm.position.y},
			"relative": {"x": mm.relative.x, "y": mm.relative.y},
		}

	if event is InputEventAction:
		var ia: InputEventAction = event
		return {
			"type": "action",
			"time_ms": time_ms,
			"action": str(ia.action),
			"pressed": ia.pressed,
			"strength": ia.strength,
		}

	return null


func _cmd_replay_recording(params: Dictionary) -> Dictionary:
	var raw: Variant = params.get("events")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return _err("Missing required parameter: events")
	var speed: float = _pfloat(params, "speed", 1.0)
	if speed <= 0.0:
		return _err("Parameter 'speed' must be greater than 0")

	var events: Array = raw
	var start_ms: int = Time.get_ticks_msec()
	var replayed: int = 0
	_replaying = true

	for item: Variant in events:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = item
		var due_ms: float = float(entry.get("time_ms", 0)) / speed
		while float(Time.get_ticks_msec() - start_ms) < due_ms:
			await get_tree().process_frame

		var event: InputEvent = _rebuild_event(entry)
		if event == null:
			continue
		Input.parse_input_event(event)
		replayed += 1

	_replaying = false
	return {"replayed": true, "event_count": replayed, "speed": speed}


func _rebuild_event(entry: Dictionary) -> InputEvent:
	match str(entry.get("type", "")):
		"key":
			var key := InputEventKey.new()
			var keycode: String = str(entry.get("keycode", ""))
			var physical: String = str(entry.get("physical_keycode", ""))
			if not keycode.is_empty():
				key.keycode = OS.find_keycode_from_string(keycode)
			if not physical.is_empty():
				key.physical_keycode = OS.find_keycode_from_string(physical)
			key.pressed = bool(entry.get("pressed", true))
			key.shift_pressed = bool(entry.get("shift", false))
			key.ctrl_pressed = bool(entry.get("ctrl", false))
			key.alt_pressed = bool(entry.get("alt", false))
			return key
		"mouse_button":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(entry.get("button", MOUSE_BUTTON_LEFT)) as MouseButton
			mb.pressed = bool(entry.get("pressed", true))
			mb.double_click = bool(entry.get("double_click", false))
			mb.position = _point(entry.get("position"))
			mb.global_position = mb.position
			return mb
		"mouse_motion":
			var mm := InputEventMouseMotion.new()
			mm.position = _point(entry.get("position"))
			mm.global_position = mm.position
			mm.relative = _point(entry.get("relative"))
			return mm
		"action":
			var ia := InputEventAction.new()
			ia.action = StringName(str(entry.get("action", "")))
			ia.pressed = bool(entry.get("pressed", true))
			ia.strength = float(entry.get("strength", 1.0))
			return ia
		_:
			return null


func _point(raw: Variant) -> Vector2:
	if typeof(raw) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var d: Dictionary = raw
	return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))


# ---------------------------------------------------------------------------
# find_ui_elements / click_button_by_text
# ---------------------------------------------------------------------------


func _cmd_find_ui_elements(params: Dictionary) -> Dictionary:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")
	var type_filter: String = _pstring(params, "type_filter")

	var elements: Array = []
	for node: Node in _walk(tree.root):
		if not (node is Control):
			continue
		var control: Control = node as Control
		# is_visible_in_tree, not .visible — a hidden ancestor hides its children.
		if not control.is_visible_in_tree():
			continue
		var entry: Variant = _describe_control(control)
		if entry == null:
			continue
		var described: Dictionary = entry
		if not type_filter.is_empty() and str(described.get("type", "")) != type_filter:
			continue
		elements.append(described)

	return {"elements": elements, "count": elements.size()}


## Most-derived classes FIRST: CheckBox/CheckButton/OptionButton all extend Button, so an
## `is Button` first-match would report every one of them as a plain "Button".
func _describe_control(control: Control) -> Variant:
	var out: Dictionary = {}

	if control is CheckBox:
		var cb: CheckBox = control as CheckBox
		out = {"type": "CheckBox", "text": cb.text, "checked": cb.button_pressed}
	elif control is CheckButton:
		var cbtn: CheckButton = control as CheckButton
		out = {"type": "CheckButton", "text": cbtn.text, "checked": cbtn.button_pressed}
	elif control is OptionButton:
		var ob: OptionButton = control as OptionButton
		out = {"type": "OptionButton", "text": ob.text, "selected": ob.selected}
	elif control is Button:
		var btn: Button = control as Button
		out = {"type": "Button", "text": btn.text, "disabled": btn.disabled}
	elif control is LineEdit:
		var le: LineEdit = control as LineEdit
		out = {"type": "LineEdit", "text": le.text, "placeholder": le.placeholder_text}
	elif control is TextEdit:
		var te: TextEdit = control as TextEdit
		out = {"type": "TextEdit", "text": te.text.substr(0, 200)}
	elif control is RichTextLabel:
		var rtl: RichTextLabel = control as RichTextLabel
		out = {"type": "RichTextLabel", "text": rtl.get_parsed_text().substr(0, 200)}
	elif control is Label:
		var label: Label = control as Label
		out = {"type": "Label", "text": label.text}
	elif control is HSlider:
		var hs: HSlider = control as HSlider
		out = {"type": "HSlider", "value": hs.value, "min": hs.min_value, "max": hs.max_value}
	elif control is VSlider:
		var vs: VSlider = control as VSlider
		out = {"type": "VSlider", "value": vs.value, "min": vs.min_value, "max": vs.max_value}
	else:
		return null

	var rect: Rect2 = control.get_global_rect()
	var center: Vector2 = rect.get_center()
	out["name"] = str(control.name)
	out["path"] = str(control.get_path())
	out["rect"] = {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}
	out["center"] = {"x": center.x, "y": center.y}
	return out


func _cmd_click_button_by_text(params: Dictionary) -> Dictionary:
	var needle: String = _pstring(params, "text")
	if needle.is_empty():
		return _err("Missing required parameter: text")
	var partial: bool = _pbool(params, "partial", true)
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")

	var wanted: String = needle.strip_edges().to_lower()
	for node: Node in _walk(tree.root):
		if not (node is Button):
			continue
		var button: Button = node as Button
		if not button.is_visible_in_tree():
			continue
		var text: String = button.text.strip_edges().to_lower()
		var hit: bool = text.contains(wanted) if partial else text == wanted
		if not hit:
			continue

		# Capture before pressing: the press may free the button via a scene transition.
		var button_text: String = button.text
		var button_path: String = str(button.get_path())
		var center: Vector2 = button.get_global_rect().get_center()

		# Programmatic press — reliable regardless of overlays or mouse position.
		if button.toggle_mode:
			button.button_pressed = not button.button_pressed
		button.emit_signal("pressed")

		var out: Dictionary = {
			"clicked": true,
			"button_text": button_text,
			"button_path": button_path,
			"position": {"x": center.x, "y": center.y},
		}
		if not is_instance_valid(button) or not button.is_inside_tree():
			out["note"] = "Button was removed from scene tree after click"
		return out

	return _err("Button not found with text: %s" % needle)


# ---------------------------------------------------------------------------
# wait_for_node
# ---------------------------------------------------------------------------


func _cmd_wait_for_node(params: Dictionary) -> Dictionary:
	var path: String = _pstring(params, "node_path")
	if path.is_empty():
		return _err("Missing required parameter: node_path")
	var timeout: float = clampf(_pfloat(params, "timeout", 5.0), 0.5, 20.0)
	var poll_frames: int = maxi(1, _pint(params, "poll_frames", 5))

	# Wall clock, not frame-count math — frame-based estimates drift badly at low fps.
	var start_ms: int = Time.get_ticks_msec()
	var deadline_ms: int = start_ms + int(timeout * 1000.0)
	while true:
		var node: Node = _resolve(path)
		if node != null:
			var out: Dictionary = {
				"found": true,
				"node_path": str(node.get_path()),
				"type": node.get_class(),
				"name": str(node.name),
				"waited_ms": Time.get_ticks_msec() - start_ms,
			}
			var scr: String = _script_path(node)
			if not scr.is_empty():
				out["script"] = scr
			return out

		if Time.get_ticks_msec() >= deadline_ms:
			break
		for _f: int in range(poll_frames):
			await get_tree().process_frame

	return _err("Node not found after %ss: %s" % [timeout, path])


# ---------------------------------------------------------------------------
# find_nearby_nodes
# ---------------------------------------------------------------------------


func _cmd_find_nearby_nodes(params: Dictionary) -> Dictionary:
	if not params.has("position"):
		return _err("Missing required parameter: position")
	var origin_res: Array = _resolve_position(params["position"])
	if origin_res[1] != null:
		return _err(str(origin_res[1]))
	var origin: Vector3 = origin_res[0]

	var radius: float = maxf(0.0, _pfloat(params, "radius", 20.0))
	var type_filter: String = _pstring(params, "type_filter")
	var group_filter: String = _pstring(params, "group_filter")
	var max_results: int = maxi(1, _pint(params, "max_results", 10))

	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")

	var hits: Array = []
	for node: Node in _walk(tree.root):
		var pos: Variant = _global_position_of(node)
		if pos == null:
			continue
		if not type_filter.is_empty() and not node.is_class(type_filter):
			continue
		if not group_filter.is_empty() and not node.is_in_group(group_filter):
			continue
		var world: Vector3 = pos
		var distance: float = origin.distance_to(world)
		if distance > radius:
			continue

		var offset: Vector3 = world - origin
		var direction: Vector3 = offset.normalized() if offset.length() > 0.0 else Vector3.ZERO
		var entry: Dictionary = {
			"node_path": str(node.get_path()),
			"name": str(node.name),
			"type": node.get_class(),
			"distance": snappedf(distance, 0.01),
			"global_position": _snapped_vec3(world),
			"direction": _snapped_vec3(direction),
		}
		var scr: String = _script_path(node)
		if not scr.is_empty():
			entry["script"] = scr
		hits.append(entry)

	hits.sort_custom(_by_distance)
	if hits.size() > max_results:
		hits = hits.slice(0, max_results)

	return {
		"origin": _snapped_vec3(origin),
		"radius": radius,
		"nodes": hits,
		"count": hits.size(),
	}


func _by_distance(a: Variant, b: Variant) -> bool:
	return float((a as Dictionary)["distance"]) < float((b as Dictionary)["distance"])


func _snapped_vec3(v: Vector3) -> Dictionary:
	return {
		"x": snappedf(v.x, 0.01),
		"y": snappedf(v.y, 0.01),
		"z": snappedf(v.z, 0.01),
	}


## Node2D global_position is lifted to z = 0; anything else has no world position.
func _global_position_of(node: Node) -> Variant:
	if node is Node3D:
		return (node as Node3D).global_position
	if node is Node2D:
		var p: Vector2 = (node as Node2D).global_position
		return Vector3(p.x, p.y, 0.0)
	return null


## Returns [Vector3, null] or [null, error_message]. Accepts {x, y[, z]} or a node path.
func _resolve_position(raw: Variant) -> Array:
	match typeof(raw):
		TYPE_DICTIONARY:
			var d: Dictionary = raw
			return [
				Vector3(
					float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0))
				),
				null,
			]
		TYPE_STRING, TYPE_STRING_NAME:
			var path: String = String(raw)
			var node: Node = _resolve(path)
			if node == null:
				return [null, "Node not found: %s" % path]
			var pos: Variant = _global_position_of(node)
			if pos == null:
				return [null, "Node has no global position (not a Node2D/Node3D): %s" % path]
			return [pos, null]
		_:
			return [null, "Position must be a node path or an {x, y, z} object"]


# ---------------------------------------------------------------------------
# Movement engine — shared by navigate_to (fire-and-forget) and move_to (awaited).
#
# Movement is INPUT-DRIVEN, not teleportation: we hold W (and Shift when running) and steer
# the camera pivot's yaw toward the target, exactly like a player would. This assumes a WASD,
# camera-relative 3D controller. Every exit path releases the held keys — a stuck W key is by
# far the worst failure mode this service can leave behind.
# ---------------------------------------------------------------------------


func _cmd_navigate_to(params: Dictionary) -> Dictionary:
	var setup: Dictionary = _start_movement(params, NAVIGATE_ARRIVAL_RADIUS, NAVIGATE_HARD_CAP_S)
	if setup.has("error"):
		return setup

	var move_speed: float = maxf(0.01, _pfloat(params, "move_speed", 5.0))
	var distance: float = float(setup["distance"])
	return {
		"started": true,
		"player_path": str(setup["player_path"]),
		"distance": snappedf(distance, 0.01),
		# Advisory only — we cannot change the game's real movement speed.
		"estimated_duration": snappedf(distance / move_speed, 0.01),
		"player_position": _snapped_vec3(setup["player_position"]),
		"target_position": _snapped_vec3(setup["target_position"]),
	}


func _cmd_move_to(params: Dictionary) -> Dictionary:
	var arrival_radius: float = maxf(0.0, _pfloat(params, "arrival_radius", 1.5))
	var timeout: float = clampf(_pfloat(params, "timeout", 15.0), 1.0, 120.0)
	var setup: Dictionary = _start_movement(params, arrival_radius, timeout)
	if setup.has("error"):
		return setup

	# Already there: nothing to walk.
	if not _move_active:
		return _move_result.duplicate()

	while _move_active:
		await get_tree().process_frame

	return _move_result.duplicate()


## Shared setup. Returns {"error": …} or the resolved movement context.
func _start_movement(params: Dictionary, arrival_radius: float, timeout: float) -> Dictionary:
	if not params.has("target"):
		return _err("Missing required parameter: target")

	# A new navigate_to/move_to supersedes any movement already in flight.
	_stop_movement()

	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return _err("Scene tree is not available")

	var player: Node3D = null
	var player_path: String = _pstring(params, "player_path")
	if player_path.is_empty():
		player = _auto_detect_player(tree.root)
		if player == null:
			return _err("No CharacterBody3D found — pass player_path")
	else:
		var node: Node = _resolve(player_path)
		if node == null:
			return _err("Node not found: %s" % player_path)
		if not (node is Node3D):
			return _err(
				"Player must be a Node3D (2D games: use the input tools instead): %s" % player_path
			)
		player = node as Node3D

	var target_res: Array = _resolve_position(params["target"])
	if target_res[1] != null:
		return _err(str(target_res[1]))
	var target: Vector3 = target_res[0]

	var pivot: Node3D = null
	var camera_path: String = _pstring(params, "camera_path")
	if camera_path.is_empty():
		pivot = _auto_detect_pivot(player)
	else:
		var cam: Node = _resolve(camera_path)
		if cam == null:
			return _err("Node not found: %s" % camera_path)
		if not (cam is Node3D):
			return _err("Camera pivot must be a Node3D: %s" % camera_path)
		pivot = cam as Node3D

	_move_player = player
	_move_pivot = pivot
	_move_target = target
	_move_arrival_radius = arrival_radius
	_move_timeout_s = timeout
	_move_look_at_target = _pbool(params, "look_at_target", true)
	_move_start_ms = Time.get_ticks_msec()
	_move_deadline_ms = _move_start_ms + int(timeout * 1000.0)
	_move_last_position = player.global_position
	_move_result = {}
	_move_active = true

	var context: Dictionary = {
		"player_path": str(player.get_path()),
		"player_position": player.global_position,
		"target_position": target,
		"distance": _xz_distance(player.global_position, target),
	}

	# Already inside the arrival radius: settle immediately, hold no keys.
	if float(context["distance"]) <= arrival_radius:
		_finish_movement(true, "Already within arrival radius")
		return context

	_hold_key(KEY_W)
	if _pbool(params, "run", false):
		_hold_key(KEY_SHIFT)
	return context


func _move_tick(_delta: float) -> void:
	if not _move_active:
		return

	if not is_instance_valid(_move_player) or not _move_player.is_inside_tree():
		_finish_movement(false, "Player node was freed")
		return

	_move_last_position = _move_player.global_position
	var distance: float = _xz_distance(_move_last_position, _move_target)

	if distance <= _move_arrival_radius:
		_finish_movement(true, "Arrived")
		return

	if Time.get_ticks_msec() >= _move_deadline_ms:
		_finish_movement(false, "Timeout after %ss" % _move_timeout_s)
		return

	if _move_look_at_target and _move_pivot != null and is_instance_valid(_move_pivot):
		_steer_pivot(_delta)


## Rotate the pivot so its forward (-Z) points at the target, at most MAX_YAW_RATE rad/s.
func _steer_pivot(delta: float) -> void:
	var offset: Vector3 = _move_target - _move_last_position
	if absf(offset.x) < 0.0001 and absf(offset.z) < 0.0001:
		return
	var desired_yaw: float = atan2(-offset.x, -offset.z)
	var current_yaw: float = _move_pivot.global_rotation.y
	var diff: float = wrapf(desired_yaw - current_yaw, -PI, PI)
	var step: float = clampf(diff, -MAX_YAW_RATE * delta, MAX_YAW_RATE * delta)
	_move_pivot.global_rotation.y = current_yaw + step


func _finish_movement(arrived: bool, message: String) -> void:
	_release_keys()
	var elapsed: float = float(Time.get_ticks_msec() - _move_start_ms) / 1000.0
	_move_result = {
		"arrived": arrived,
		"message": message,
		"final_distance": snappedf(_xz_distance(_move_last_position, _move_target), 0.01),
		"final_position": _snapped_vec3(_move_last_position),
		"target_position": _snapped_vec3(_move_target),
		"elapsed_time": snappedf(elapsed, 0.01),
	}
	_move_active = false
	_move_player = null
	_move_pivot = null


## Abort path (supersede / watchdog): keys must never stay held.
func _stop_movement() -> void:
	if _move_active:
		_finish_movement(false, "Movement superseded")
	else:
		_release_keys()


func _xz_distance(a: Vector3, b: Vector3) -> float:
	# Y is ignored: slopes and jumps must not prevent arrival.
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _auto_detect_player(root: Node) -> Node3D:
	# Breadth-first: the player is normally high in the tree.
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is CharacterBody3D:
			return node as Node3D
		for child: Node in node.get_children():
			queue.append(child)
	return null


func _auto_detect_pivot(player: Node3D) -> Node3D:
	for child: Node in player.get_children():
		if child is SpringArm3D:
			return child as Node3D

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return null
	var parent: Node = camera.get_parent()
	if parent is Node3D and parent != get_tree().root:
		return parent as Node3D
	return null


func _hold_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	if not _held_keys.has(int(keycode)):
		_held_keys.append(int(keycode))


func _release_keys() -> void:
	for keycode: int in _held_keys:
		var event := InputEventKey.new()
		event.keycode = keycode as Key
		event.physical_keycode = keycode as Key
		event.pressed = false
		Input.parse_input_event(event)
	_held_keys.clear()


# ---------------------------------------------------------------------------
# watch_signals
# ---------------------------------------------------------------------------


func _cmd_watch_signals(params: Dictionary) -> Dictionary:
	var raw_paths: Variant = _pstring_array(params, "node_paths")
	if raw_paths == null or (raw_paths as Array).is_empty():
		return _err("Missing required parameter: node_paths")
	var node_paths: Array = raw_paths
	var filters: Variant = _pstring_array(params, "signal_filter")
	var duration_ms: int = clampi(_pint(params, "duration_ms", 5000), 500, 30000)

	_disconnect_watchers()
	_watch_events = []
	_watch_start_ms = Time.get_ticks_msec()

	var warnings: Array = []
	for raw: Variant in node_paths:
		var path: String = str(raw)
		var node: Node = _resolve(path)
		if node == null:
			# Warnings stay OUT of the event stream — they are not emissions.
			warnings.append("Node not found: %s" % path)
			continue
		_connect_watchers(node, filters)

	if _watch_connections.is_empty():
		return _err("No signals connected — check node_paths and signal_filter")

	var deadline_ms: int = _watch_start_ms + duration_ms
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame

	var events: Array = _watch_events.duplicate()
	_disconnect_watchers()

	var out: Dictionary = {
		"node_paths": node_paths,
		"signal_filter": filters if filters != null else [],
		"duration_ms": duration_ms,
		"events": events,
		"event_count": events.size(),
	}
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


func _connect_watchers(node: Node, filters: Variant) -> void:
	var node_path: String = str(node.get_path())
	for sig: Dictionary in node.get_signal_list():
		var sig_name: String = str(sig.get("name", ""))
		if sig_name.is_empty():
			continue
		if filters != null and not _signal_matches(sig_name, filters):
			continue

		var raw_args: Variant = sig.get("args", [])
		var arity: int = (raw_args as Array).size() if typeof(raw_args) == TYPE_ARRAY else 0
		var callback: Callable = _watcher_for(arity, node_path, sig_name)
		if node.connect(StringName(sig_name), callback) != OK:
			continue
		_watch_connections.append(
			{"node": node, "signal": sig_name, "callable": callback}
		)


func _signal_matches(sig_name: String, filters: Variant) -> bool:
	var lower: String = sig_name.to_lower()
	for raw: Variant in filters as Array:
		if lower.contains(str(raw).to_lower()):
			return true
	return false


## One recorder per arity. Signals with 5+ args are logged WITHOUT their args: unbind() drops
## the emitted arguments so the connection stays valid whatever the signature.
func _watcher_for(arity: int, node_path: String, sig_name: String) -> Callable:
	match arity:
		0:
			return _on_signal_0.bind(node_path, sig_name)
		1:
			return _on_signal_1.bind(node_path, sig_name)
		2:
			return _on_signal_2.bind(node_path, sig_name)
		3:
			return _on_signal_3.bind(node_path, sig_name)
		4:
			return _on_signal_4.bind(node_path, sig_name)
		_:
			return _on_signal_0.bind(node_path, sig_name).unbind(arity)


func _on_signal_0(node_path: String, sig_name: String) -> void:
	_record_signal(node_path, sig_name, [])


func _on_signal_1(a0: Variant, node_path: String, sig_name: String) -> void:
	_record_signal(node_path, sig_name, [a0])


func _on_signal_2(a0: Variant, a1: Variant, node_path: String, sig_name: String) -> void:
	_record_signal(node_path, sig_name, [a0, a1])


func _on_signal_3(
	a0: Variant, a1: Variant, a2: Variant, node_path: String, sig_name: String
) -> void:
	_record_signal(node_path, sig_name, [a0, a1, a2])


func _on_signal_4(
	a0: Variant, a1: Variant, a2: Variant, a3: Variant, node_path: String, sig_name: String
) -> void:
	_record_signal(node_path, sig_name, [a0, a1, a2, a3])


func _record_signal(node_path: String, sig_name: String, args: Array) -> void:
	var entry: Dictionary = {
		"time_ms": Time.get_ticks_msec() - _watch_start_ms,
		"node": node_path,
		"signal": sig_name,
	}
	if not args.is_empty():
		var serialized: Array = []
		for arg: Variant in args:
			serialized.append(_serialize_value(arg))
		entry["args"] = serialized
	_watch_events.append(entry)


## Never leak a connection: called after the watch window, on abort and from the watchdog.
func _disconnect_watchers() -> void:
	for raw: Variant in _watch_connections:
		var conn: Dictionary = raw
		var node: Variant = conn.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var target: Node = node as Node
		var sig_name: StringName = StringName(str(conn.get("signal", "")))
		var callback: Callable = conn.get("callable")
		if target.is_connected(sig_name, callback):
			target.disconnect(sig_name, callback)
	_watch_connections.clear()
