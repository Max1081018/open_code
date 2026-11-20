@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## Input simulation (SPEC §6 "input", 5 tools).
##
## Fire-and-forget: every tool serializes events to <game_user_dir>/mcp_input_commands and
## returns immediately. There is DELIBERATELY no is_playing_scene() check — with no game
## running the events are simply dropped (the file is overwritten by the next write, cleaned
## by the plugin on exit, or consumed by the next game launch).
##
## Each write REPLACES the whole file, so unconsumed events from a prior call are lost —
## batch multi-event interactions through simulate_sequence.
##
## Event dict shapes are the frozen A2 runtime shapes (services/mcp_input_service.gd).
## Nothing here touches the edited scene: no undo actions, no conflict guards.

const INPUT_FILE := "mcp_input_commands"


func get_commands() -> Dictionary:
	return {
		"simulate_key": _simulate_key,
		"simulate_mouse_click": _simulate_mouse_click,
		"simulate_mouse_move": _simulate_mouse_move,
		"simulate_action": _simulate_action,
		"simulate_sequence": _simulate_sequence,
	}


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _simulate_key(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "keycode")
	if res[1] != null:
		return res[1]

	var event: Dictionary = {
		"type": "key",
		"keycode": String(res[0]),
		"pressed": optional_bool(params, "pressed", true),
		"shift": optional_bool(params, "shift", false),
		"ctrl": optional_bool(params, "ctrl", false),
		"alt": optional_bool(params, "alt", false),
	}

	var write_err: Dictionary = _write_input_file([event])
	if not write_err.is_empty():
		return write_err
	return success({"sent": true, "event": event})


func _simulate_mouse_click(params: Dictionary) -> Dictionary:
	var pressed: bool = optional_bool(params, "pressed", true)
	var auto_release: bool = optional_bool(params, "auto_release", true)

	var press: Dictionary = {
		"type": "mouse_button",
		"button": optional_int(params, "button", 1),
		"pressed": pressed,
		"double_click": optional_bool(params, "double_click", false),
		"x": optional_float(params, "x", 0.0),
		"y": optional_float(params, "y", 0.0),
	}

	var write_err: Dictionary = {}
	if pressed and auto_release:
		# Godot UI buttons fire on RELEASE — a lone press never clicks anything.
		var release: Dictionary = press.duplicate()
		release["pressed"] = false
		release["double_click"] = false
		write_err = _write_input_file(
			{"sequence_events": [press, release], "frame_delay": 1}
		)
	else:
		write_err = _write_input_file([press])

	if not write_err.is_empty():
		return write_err
	return success(
		{"sent": true, "event": press, "auto_release": pressed and auto_release}
	)


func _simulate_mouse_move(params: Dictionary) -> Dictionary:
	var button_mask: int = optional_int(params, "button_mask", 0)

	var event: Dictionary = {
		"type": "mouse_motion",
		"x": optional_float(params, "x", 0.0),
		"y": optional_float(params, "y", 0.0),
		"relative_x": optional_float(params, "relative_x", 0.0),
		"relative_y": optional_float(params, "relative_y", 0.0),
		"button_mask": button_mask,
	}

	# `unhandled` routing: a drag with a held button is almost always camera/gameplay input
	# consumed in _unhandled_input, while a plain move must go through normal GUI dispatch
	# (hover, mouse_entered, Control drag targets). So: honor an explicit caller value
	# (true OR false — UI drag-and-drop tests opt back in with unhandled: false), otherwise
	# auto-set it to true only when a button is held.
	if params.has("unhandled") and params["unhandled"] != null:
		event["unhandled"] = optional_bool(params, "unhandled", false)
	elif button_mask > 0:
		event["unhandled"] = true

	var write_err: Dictionary = _write_input_file([event])
	if not write_err.is_empty():
		return write_err
	return success({"sent": true, "event": event})


func _simulate_action(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "action")
	if res[1] != null:
		return res[1]

	var event: Dictionary = {
		"type": "action",
		"action": String(res[0]),
		"pressed": optional_bool(params, "pressed", true),
		"strength": optional_float(params, "strength", 1.0),
	}

	var write_err: Dictionary = _write_input_file([event])
	if not write_err.is_empty():
		return write_err
	return success({"sent": true, "event": event})


func _simulate_sequence(params: Dictionary) -> Dictionary:
	if not params.has("events") or typeof(params["events"]) != TYPE_ARRAY:
		return error(-32602, "Missing required parameter: events (expected an array of events)")

	var events: Array = params["events"]
	if events.is_empty():
		return error(-32602, "Invalid parameter: events must not be empty")

	for entry: Variant in events:
		if typeof(entry) != TYPE_DICTIONARY:
			return error(-32602, "Invalid parameter: every entry of events must be an object")
		var d: Dictionary = entry
		if not d.has("type") or typeof(d["type"]) != TYPE_STRING or String(d["type"]).is_empty():
			return error(-32602, "Invalid parameter: every event needs a non-empty string 'type'")

	var frame_delay: int = optional_int(params, "frame_delay", 1)

	var write_err: Dictionary = {}
	if frame_delay <= 0:
		# All events land in a single frame.
		write_err = _write_input_file(events)
	else:
		write_err = _write_input_file(
			{"sequence_events": events, "frame_delay": frame_delay}
		)

	if not write_err.is_empty():
		return write_err
	return success(
		{"sent": true, "event_count": events.size(), "frame_delay": frame_delay}
	)


# ---------------------------------------------------------------------------
# Input file writer
# ---------------------------------------------------------------------------


## Serialize `payload` (plain Array, or {"sequence_events": [...], "frame_delay": N}) to the
## game's user:// input file. Returns an EMPTY Dictionary on success, an error() dict on
## failure — callers check with .is_empty(), never != null (a Dictionary is never null).
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
