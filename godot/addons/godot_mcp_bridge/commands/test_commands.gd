@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## Playtesting / assertions (SPEC §6 "test", 5 tools).
##
## Every tool except get_test_report needs a running game. All game-side work goes through
## the frozen base_command._send_game_command() file IPC — the game-side commands
## (wait_for_node, find_ui_elements, get_node_properties) are owned by package B07 and appear
## here ONLY as wire strings. Nothing here touches the edited scene: no undo actions,
## no conflict guards, never error_no_scene().
##
## _test_results collects ONLY assertion outcomes (standalone assert_* tools and `assert`
## steps inside a scenario) — input/wait/screenshot rows would skew pass_rate. It lives for
## the plugin session; get_test_report(clear: true) or a plugin reload resets it.

const INPUT_FILE := "mcp_input_commands"
const SCREENSHOT_REQUEST_FILE := "mcp_screenshot_request"
const SCREENSHOT_FILE := "mcp_screenshot.png"

const SCREENSHOT_TIMEOUT := 3.0
const SCREENSHOT_POLL := 0.1

## Settle time after a scenario `input` step: the game consumes one queued event per
## frame_delay rendered frames, and the next write would replace the queue wholesale.
const INPUT_SETTLE_BASE := 0.05
const INPUT_SETTLE_PER_FRAME := 0.02

const OPERATORS: PackedStringArray = [
	"eq", "neq", "gt", "lt", "gte", "lte", "contains", "type_is"
]

## Assertion outcomes recorded this plugin session.
var _test_results: Array[Dictionary] = []


func get_commands() -> Dictionary:
	return {
		"run_test_scenario": _run_test_scenario,
		"assert_node_state": _assert_node_state,
		"assert_screen_text": _assert_screen_text,
		"run_stress_test": _run_stress_test,
		"get_test_report": _get_test_report,
	}


# ---------------------------------------------------------------------------
# run_test_scenario
# ---------------------------------------------------------------------------


func _run_test_scenario(params: Dictionary) -> Dictionary:
	if not params.has("steps") or typeof(params["steps"]) != TYPE_ARRAY:
		return error(-32602, "Missing required parameter: steps (expected an array of steps)")
	var steps: Array = params["steps"]
	if steps.is_empty():
		return error(-32602, "Invalid parameter: steps must not be empty")

	var scene_path: String = optional_string(params, "scene_path", "")

	if not scene_path.is_empty():
		var launch_err: Dictionary = await _launch_scene(scene_path)
		if not launch_err.is_empty():
			return launch_err

	if not EditorInterface.is_playing_scene():
		return error(
			-32000,
			"Game is not running",
			{"suggestion": "provide scene_path or play_scene first"}
		)

	var results: Array[Dictionary] = []
	var passed: int = 0
	var failed: int = 0
	var errors: int = 0
	var completed: int = 0

	for i: int in steps.size():
		var entry: Variant = steps[i]
		var row: Dictionary = {}
		var type: String = ""

		if typeof(entry) != TYPE_DICTIONARY:
			row = {"error": "Step must be an object"}
		else:
			var step: Dictionary = entry
			type = str(step.get("type", ""))
			match type:
				"input":
					row = await _step_input(step)
				"wait":
					row = await _step_wait(step)
				"assert":
					row = await _step_assert(step)
				"screenshot":
					row = await _step_screenshot(step)
				_:
					row = {"error": "Unknown step type: %s" % type}

		row["step"] = i
		row["type"] = type
		results.append(row)
		completed += 1

		if row.has("error"):
			errors += 1
		elif type == "assert":
			if bool(row.get("passed", false)):
				passed += 1
			else:
				failed += 1
			_test_results.append(row.duplicate(true))

		if not EditorInterface.is_playing_scene():
			results.append({"step": i + 1, "error": "Game stopped unexpectedly"})
			errors += 1
			break

	return success(
		{
			"total_steps": steps.size(),
			"completed_steps": completed,
			"passed": passed,
			"failed": failed,
			"errors": errors,
			"all_passed": failed == 0 and errors == 0,
			"results": results,
		}
	)


## Returns an EMPTY Dictionary when the game is up, an error() dict otherwise.
func _launch_scene(scene_path: String) -> Dictionary:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
		await _sleep(0.5)

	if scene_path == "main":
		EditorInterface.play_main_scene()
	elif scene_path == "current":
		EditorInterface.play_current_scene()
	else:
		if not FileAccess.file_exists(scene_path):
			return error_not_found("Scene: %s" % scene_path)
		EditorInterface.play_custom_scene(scene_path)

	await _sleep(1.0)
	return {}


func _step_input(step: Dictionary) -> Dictionary:
	var action: String = str(step.get("action", ""))
	var keycode: String = str(step.get("keycode", ""))
	var pressed: bool = bool(step.get("pressed", true))
	var auto_release: bool = bool(step.get("auto_release", true))
	var frame_delay: int = int(step.get("frame_delay", 1))

	var events: Array = []
	if not action.is_empty():
		# `action` wins when both are given.
		events.append(
			{
				"type": "action",
				"action": action,
				"pressed": pressed,
				"strength": float(step.get("strength", 1.0)),
			}
		)
		if pressed and auto_release:
			events.append(
				{"type": "action", "action": action, "pressed": false, "strength": 0.0}
			)
	elif not keycode.is_empty():
		events.append(
			{
				"type": "key",
				"keycode": keycode,
				"pressed": pressed,
				"shift": bool(step.get("shift", false)),
				"ctrl": bool(step.get("ctrl", false)),
				"alt": bool(step.get("alt", false)),
			}
		)
	else:
		return {"error": "input step needs an 'action' or a 'keycode'"}

	var delay: int = maxi(1, frame_delay)
	var write_err: Dictionary = _write_input_file(
		{"sequence_events": events, "frame_delay": delay}
	)
	if not write_err.is_empty():
		return {"error": _error_message(write_err)}

	# Every write REPLACES the input file / the game's pending queue (mcp_input_service
	# re-assigns _sequence wholesale and drains one event per frame_delay frames). Without a
	# yield here the whole step loop would run inside a single editor frame, so back-to-back
	# `input` steps would overwrite each other and only the last one would ever be injected.
	# Wait for the queue to drain — events.size() * delay game frames (~60fps) plus margin.
	await _sleep(INPUT_SETTLE_BASE + INPUT_SETTLE_PER_FRAME * float(events.size() * delay))
	return {"sent": true, "event_count": events.size()}


func _step_wait(step: Dictionary) -> Dictionary:
	var node_path: String = str(step.get("node_path", ""))
	if not node_path.is_empty():
		var timeout: float = float(step.get("timeout", 5.0))
		var poll_frames: int = int(step.get("poll_frames", 5))
		var resp: Dictionary = await _send_game_command(
			"wait_for_node",
			{"node_path": node_path, "timeout": timeout, "poll_frames": poll_frames},
			timeout + 2.0
		)
		if resp.has("error"):
			return {"error": _error_message(resp)}
		var data: Dictionary = resp.get("result", {})
		return {"waited_for": node_path, "found": bool(data.get("found", false))}

	var seconds: float = float(step.get("seconds", 1.0))
	await _sleep(seconds)
	return {"waited_seconds": seconds}


func _step_assert(step: Dictionary) -> Dictionary:
	if step.has("text"):
		var text: String = str(step["text"])
		var partial: bool = bool(step.get("partial", true))
		var resp: Dictionary = await _send_game_command("find_ui_elements", {})
		if resp.has("error"):
			return {"error": _error_message(resp)}
		var elements: Array = _elements_of(resp.get("result", {}))
		for element: Variant in elements:
			if typeof(element) != TYPE_DICTIONARY:
				continue
			var el: Dictionary = element
			var found: String = str(el.get("text", ""))
			if found.is_empty():
				continue
			if _text_matches(found, text, partial, true):
				return {"passed": true, "expected": text, "found_in": found}
		return {"passed": false, "expected": text}

	var node_path: String = str(step.get("node_path", ""))
	var property: String = str(step.get("property", ""))
	if node_path.is_empty() or property.is_empty():
		return {"error": "assert step needs a 'text', or both 'node_path' and 'property'"}
	if not step.has("expected"):
		return {"error": "assert step is missing 'expected'"}

	var operator: String = str(step.get("operator", "eq"))
	if not OPERATORS.has(operator):
		return {"error": "Unknown operator: %s" % operator}

	var probe: Dictionary = await _read_game_property(node_path, property)
	if probe.has("error"):
		return {"error": _error_message(probe)}

	var row: Dictionary = probe["row"]
	row["operator"] = operator
	if row.has("reason"):
		# Property missing on the node — a FAILED assertion, not a transport error.
		row["expected"] = step["expected"]
		return row

	var actual: Variant = row["actual"]
	var verdict: Dictionary = _compare(actual, step["expected"], operator)
	row["passed"] = bool(verdict["passed"])
	row["expected"] = step["expected"]
	if verdict.has("reason"):
		row["reason"] = verdict["reason"]
	return row


func _step_screenshot(step: Dictionary) -> Dictionary:
	var half_resolution: bool = bool(step.get("half_resolution", true))
	var dir: String = get_game_user_dir()
	var png_path: String = "%s/%s" % [dir, SCREENSHOT_FILE]

	# Drop any stale PNG so an old capture cannot be mistaken for this one.
	if FileAccess.file_exists(png_path):
		DirAccess.remove_absolute(png_path)

	var request: FileAccess = FileAccess.open(
		"%s/%s" % [dir, SCREENSHOT_REQUEST_FILE], FileAccess.WRITE
	)
	if request == null:
		return {"error": "Could not write screenshot request file"}
	request.store_string(JSON.stringify({"half_resolution": half_resolution}))
	request.close()

	var elapsed: float = 0.0
	while elapsed < SCREENSHOT_TIMEOUT:
		await _sleep(SCREENSHOT_POLL)
		elapsed += SCREENSHOT_POLL
		if FileAccess.file_exists(png_path):
			# The PNG stays on disk; pixels are fetched with get_game_screenshot.
			return {"captured": true, "path": png_path}

	return {"captured": false, "error": "Timed out waiting for the game screenshot"}


# ---------------------------------------------------------------------------
# assert_node_state
# ---------------------------------------------------------------------------


func _assert_node_state(params: Dictionary) -> Dictionary:
	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = String(path_res[0])

	var prop_res: Array = require_string(params, "property")
	if prop_res[1] != null:
		return prop_res[1]
	var property: String = String(prop_res[0])

	# zod cannot require the presence of an unknown-typed key, so re-check it here.
	if not params.has("expected"):
		return error(-32602, "Missing required parameter: expected")
	var expected: Variant = params["expected"]

	var operator: String = optional_string(params, "operator", "eq")
	if not OPERATORS.has(operator):
		return error(
			-32602,
			"Invalid parameter: operator '%s' (expected one of %s)"
			% [operator, ", ".join(OPERATORS)]
		)

	var probe: Dictionary = await _read_game_property(node_path, property)
	if probe.has("error"):
		return probe

	var row: Dictionary = probe["row"]
	row["operator"] = operator
	row["expected"] = expected

	if not row.has("reason"):
		var verdict: Dictionary = _compare(row["actual"], expected, operator)
		row["passed"] = bool(verdict["passed"])
		if verdict.has("reason"):
			row["reason"] = verdict["reason"]

	_test_results.append(row.duplicate(true))
	return success(row)


## Fetch one property of a game node. Returns {"row": {...}} — the row already carries
## node_path/property/actual, or passed=false + reason when the property is absent —
## or {"error": {...}} when the IPC itself failed.
func _read_game_property(node_path: String, property: String) -> Dictionary:
	# Ask for the property BY NAME. The unfiltered dump only carries editor-visible properties,
	# so a plain script var (`var score: int`, no @export) would come back "not found" and every
	# assertion against game state would silently read null.
	var resp: Dictionary = await _send_game_command(
		"get_node_properties", {"node_path": node_path, "properties": [property]}
	)
	if resp.has("error"):
		return resp

	var data: Dictionary = resp.get("result", {})
	var properties: Dictionary = {}
	if typeof(data.get("properties")) == TYPE_DICTIONARY:
		properties = data["properties"]

	if not properties.has(property):
		return {
			"row":
			{
				"passed": false,
				"node_path": node_path,
				"property": property,
				"actual": null,
				"reason": "property not found",
			}
		}

	return {
		"row":
		{
			"node_path": node_path,
			"property": property,
			"actual": properties[property],
		}
	}


# ---------------------------------------------------------------------------
# assert_screen_text
# ---------------------------------------------------------------------------


func _assert_screen_text(params: Dictionary) -> Dictionary:
	var text_res: Array = require_string(params, "text")
	if text_res[1] != null:
		return text_res[1]
	var text: String = String(text_res[0])

	var partial: bool = optional_bool(params, "partial", true)
	var case_sensitive: bool = optional_bool(params, "case_sensitive", true)

	var resp: Dictionary = await _send_game_command("find_ui_elements", {})
	if resp.has("error"):
		return resp

	var elements: Array = _elements_of(resp.get("result", {}))
	var visible_texts: Array[String] = []
	var matched: Dictionary = {}

	for element: Variant in elements:
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var el: Dictionary = element
		var found: String = str(el.get("text", ""))
		if found.is_empty():
			continue
		visible_texts.append(found)
		if matched.is_empty() and _text_matches(found, text, partial, case_sensitive):
			matched = {
				"text": found,
				"type": str(el.get("type", "")),
				"path": str(el.get("path", "")),
			}

	var row: Dictionary = {
		"passed": not matched.is_empty(),
		"expected_text": text,
		"partial": partial,
		"case_sensitive": case_sensitive,
	}
	if matched.is_empty():
		# Show what WAS on screen so the caller can see why the match failed.
		row["visible_texts"] = visible_texts
	else:
		row["matched_element"] = matched

	_test_results.append(row.duplicate(true))
	return success(row)


# ---------------------------------------------------------------------------
# run_stress_test
# ---------------------------------------------------------------------------


func _run_stress_test(params: Dictionary) -> Dictionary:
	var duration: float = optional_float(params, "duration", 5.0)
	if duration <= 0.0 or duration > 60.0:
		return error(
			-32602, "Invalid parameter: duration must satisfy 0 < duration <= 60 (seconds)"
		)

	if not EditorInterface.is_playing_scene():
		return error(-32000, "Game is not running — use play_scene first")

	var pool: Array[String] = [
		"ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"
	]
	if params.has("actions") and typeof(params["actions"]) == TYPE_ARRAY:
		for extra: Variant in params["actions"] as Array:
			var extra_action: String = str(extra)
			if not extra_action.is_empty():
				pool.append(extra_action)

	var errors_before: int = _count_log_errors()
	var start_msec: int = Time.get_ticks_msec()
	var events_sent: int = 0

	while _elapsed_since(start_msec) < duration:
		if not EditorInterface.is_playing_scene():
			return success(
				{
					"completed": false,
					"crashed": true,
					"elapsed_seconds": _elapsed_since(start_msec),
					"events_sent": events_sent,
				}
			)

		var batch: Array = []
		for _i: int in 3:
			var action: String = pool[randi() % pool.size()]
			batch.append(
				{"type": "action", "action": action, "pressed": true, "strength": 1.0}
			)
			batch.append(
				{"type": "action", "action": action, "pressed": false, "strength": 0.0}
			)

		var write_err: Dictionary = _write_input_file(
			{"sequence_events": batch, "frame_delay": 1}
		)
		if not write_err.is_empty():
			return write_err
		events_sent += batch.size()

		await _sleep(0.1)

	var still_running: bool = EditorInterface.is_playing_scene()
	var new_errors: int = maxi(0, _count_log_errors() - errors_before)

	return success(
		{
			"completed": true,
			"crashed": not still_running,
			"duration_seconds": _elapsed_since(start_msec),
			"events_sent": events_sent,
			"new_log_errors": new_errors,
			"game_still_running": still_running,
		}
	)


## Error lines in the game's log file. 0 when file logging is disabled / the log is absent.
func _count_log_errors() -> int:
	var log_path: String = "%s/logs/godot.log" % get_game_user_dir()
	if not FileAccess.file_exists(log_path):
		return 0
	var file: FileAccess = FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return 0
	var count: int = 0
	while not file.eof_reached():
		var line: String = file.get_line()
		# "SCRIPT ERROR" lines contain "ERROR", so one substring test covers both.
		if line.contains("ERROR"):
			count += 1
	file.close()
	return count


# ---------------------------------------------------------------------------
# get_test_report
# ---------------------------------------------------------------------------


func _get_test_report(params: Dictionary) -> Dictionary:
	var clear: bool = optional_bool(params, "clear", true)

	var total: int = _test_results.size()
	var passed: int = 0
	for row: Dictionary in _test_results:
		if bool(row.get("passed", false)):
			passed += 1
	var failed: int = total - passed

	var pass_rate: String = "N/A"
	if total > 0:
		pass_rate = "%.1f%%" % (100.0 * float(passed) / float(total))

	var details: Array[Dictionary] = _test_results.duplicate(true)
	if clear:
		_test_results.clear()

	return success(
		{
			"total": total,
			"passed": passed,
			"failed": failed,
			"pass_rate": pass_rate,
			"all_passed": total > 0 and failed == 0,
			"details": details,
		}
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Same tiny writer as input_commands.gd — command modules never import each other.
## Returns an EMPTY Dictionary on success, an error() dict on failure (check .is_empty()).
func _write_input_file(payload: Variant) -> Dictionary:
	var path: String = "%s/%s" % [get_game_user_dir(), INPUT_FILE]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return error(
			-32603,
			"Could not write input command file: %s" % path,
			{"error": error_string(FileAccess.get_open_error())}
		)
	file.store_string(JSON.stringify(payload))
	file.close()
	return {}


func _sleep(seconds: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(maxf(0.0, seconds)).timeout


func _elapsed_since(start_msec: int) -> float:
	return float(Time.get_ticks_msec() - start_msec) / 1000.0


func _elements_of(data: Dictionary) -> Array:
	if typeof(data.get("elements")) == TYPE_ARRAY:
		return data["elements"]
	return []


func _error_message(err: Dictionary) -> String:
	if typeof(err.get("error")) == TYPE_DICTIONARY:
		var inner: Dictionary = err["error"]
		return str(inner.get("message", "Unknown error"))
	return str(err.get("error", "Unknown error"))


func _text_matches(haystack: String, needle: String, partial: bool, case_sensitive: bool) -> bool:
	var a: String = haystack if case_sensitive else haystack.to_lower()
	var b: String = needle if case_sensitive else needle.to_lower()
	if partial:
		return a.contains(b)
	return a == b


## Editor-side comparison. Returns {"passed": bool} plus a "reason" when the operator could
## not be applied to the actual value.
func _compare(actual: Variant, expected: Variant, operator: String) -> Dictionary:
	match operator:
		"eq":
			return {"passed": _equals(actual, expected)}
		"neq":
			return {"passed": not _equals(actual, expected)}
		"gt", "lt", "gte", "lte":
			if not _is_numeric(actual):
				return {
					"passed": false,
					"reason": "actual value is not numeric: %s" % str(actual),
				}
			var a: float = float(actual)
			var b: float = _to_float(expected)
			match operator:
				"gt":
					return {"passed": a > b}
				"lt":
					return {"passed": a < b}
				"gte":
					return {"passed": a >= b}
				_:
					return {"passed": a <= b}
		"contains":
			return {"passed": str(actual).contains(str(expected))}
		"type_is":
			return {"passed": _type_name_of(actual) == str(expected)}
		_:
			return {"passed": false, "reason": "Unknown operator: %s" % operator}


func _equals(actual: Variant, expected: Variant) -> bool:
	if _is_numeric(actual) and _is_numeric(expected):
		return is_equal_approx(float(actual), float(expected))
	return str(actual) == str(expected)


func _is_numeric(value: Variant) -> bool:
	var t: int = typeof(value)
	return t == TYPE_INT or t == TYPE_FLOAT


func _to_float(value: Variant) -> float:
	if _is_numeric(value):
		return float(value)
	var s: String = str(value)
	if s.is_valid_float():
		return s.to_float()
	return 0.0


## Variant type / class name of a value that came back over the JSON game IPC.
func _type_name_of(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		if d.has("type"):
			return str(d["type"])
	return type_string(typeof(value))
