@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## InputMap action editing (SPEC §6 "input_map", 2 tools).
##
## Both tools work with no game running and never touch the edited scene — no undo actions,
## no conflict guards. Action bindings live in ProjectSettings ("input/<action>"), which is the
## authoritative source and the ONLY one that sees project actions: the editor process does not
## load them into its own InputMap. Reads and writes therefore go through ProjectSettings; the
## live editor InputMap is mirrored on write purely as a convenience.
## project.godot is NEVER edited as text.

const BUILTIN_PREFIX := "ui_"
const SETTING_PREFIX := "input/"

const VALID_EVENT_TYPES: PackedStringArray = [
	"key", "mouse_button", "joypad_button", "joypad_motion"
]


func get_commands() -> Dictionary:
	return {
		"get_input_actions": _get_input_actions,
		"set_input_action": _set_input_action,
	}


# ---------------------------------------------------------------------------
# get_input_actions
# ---------------------------------------------------------------------------


func _get_input_actions(params: Dictionary) -> Dictionary:
	var filter: String = optional_string(params, "filter", "")
	var include_builtin: bool = optional_bool(params, "include_builtin", false)

	# Read the PROJECT's actions from ProjectSettings, not from the editor's InputMap.
	# The editor process never loads project actions into its own InputMap (only the running
	# game does), so InputMap.get_actions() here would return the editor's OWN shortcuts
	# ("spatial_editor/freelook_backwards", …) and none of the project's — the opposite of
	# what this tool is for. Verified: InputMap.has_action("jump") == false in the editor
	# while ProjectSettings.has_setting("input/jump") == true.
	var actions: Dictionary = {}
	for prop: Dictionary in ProjectSettings.get_property_list():
		var setting: String = str(prop.get("name", ""))
		if not setting.begins_with(SETTING_PREFIX):
			continue

		var action: String = setting.substr(SETTING_PREFIX.length())
		if action.is_empty():
			continue
		if not include_builtin and action.begins_with(BUILTIN_PREFIX):
			continue
		if not filter.is_empty() and not action.contains(filter):
			continue

		var entry: Variant = ProjectSettings.get_setting(setting)
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var entry_dict: Dictionary = entry

		var events: Array = []
		var raw_events: Variant = entry_dict.get("events", [])
		if typeof(raw_events) == TYPE_ARRAY:
			for ev: Variant in (raw_events as Array):
				if ev is InputEvent:
					events.append(_serialize_event(ev as InputEvent))

		actions[action] = {
			"deadzone": float(entry_dict.get("deadzone", 0.5)),
			"events": events,
		}

	return success({"actions": actions, "count": actions.size()})


func _serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var key: InputEventKey = ev
		var out: Dictionary = {
			"type": "key",
			"keycode": _keycode_string(key.keycode),
			"physical_keycode": _keycode_string(key.physical_keycode),
		}
		# Modifier flags appear only when actually set, keeping the payload small.
		if key.ctrl_pressed:
			out["ctrl"] = true
		if key.shift_pressed:
			out["shift"] = true
		if key.alt_pressed:
			out["alt"] = true
		if key.meta_pressed:
			out["meta"] = true
		return out

	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		return {"type": "mouse_button", "button_index": int(mb.button_index)}

	if ev is InputEventJoypadButton:
		var jb: InputEventJoypadButton = ev
		return {"type": "joypad_button", "button_index": int(jb.button_index)}

	if ev is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = ev
		return {"type": "joypad_motion", "axis": int(jm.axis), "axis_value": jm.axis_value}

	return {"type": ev.get_class()}


func _keycode_string(code: Key) -> String:
	if code == KEY_NONE:
		return ""
	return OS.get_keycode_string(code)


# ---------------------------------------------------------------------------
# set_input_action
# ---------------------------------------------------------------------------


func _set_input_action(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "action")
	if res[1] != null:
		return res[1]
	var action: String = String(res[0])

	if not params.has("events") or typeof(params["events"]) != TYPE_ARRAY:
		return error(-32602, "Missing required parameter: events (expected an array of events)")
	var raw_events: Array = params["events"]

	var deadzone: float = optional_float(params, "deadzone", 0.5)

	# Validate first, mutate second: a half-applied action is worse than no action at all.
	var built: Array[InputEvent] = []
	for index: int in raw_events.size():
		var entry: Variant = raw_events[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return error(-32602, "Invalid parameter: events[%d] must be an object" % index)
		var spec: Dictionary = entry
		var type: String = str(spec.get("type", ""))
		if not VALID_EVENT_TYPES.has(type):
			return error(
				-32602,
				(
					"Invalid parameter: events[%d].type '%s' (expected one of %s)"
					% [index, type, ", ".join(VALID_EVENT_TYPES)]
				)
			)
		if type == "key":
			# A key name that OS.find_keycode_from_string cannot parse resolves to KEY_NONE —
			# a dead binding. Reject it here, BEFORE ProjectSettings is written: mutating first
			# would persist the dead event to project.godot and erase the action's real bindings.
			var key_err: Dictionary = _validate_key_spec(spec, index)
			if not key_err.is_empty():
				return key_err
		built.append(_build_event(type, spec))

	# 1. Persist to ProjectSettings — the authoritative store.
	ProjectSettings.set_setting(
		SETTING_PREFIX + action, {"deadzone": deadzone, "events": built}
	)
	var err: int = ProjectSettings.save()
	if err != OK:
		return error(
			-32603, "Could not save project settings: %s" % error_string(err), {"action": action}
		)

	# 2. Mirror into the live InputMap so this editor session sees it immediately.
	if not InputMap.has_action(action):
		InputMap.add_action(action, deadzone)
	else:
		InputMap.action_set_deadzone(action, deadzone)
		InputMap.action_erase_events(action)
	for ev: InputEvent in built:
		InputMap.action_add_event(action, ev)

	return success(
		{
			"action": action,
			"deadzone": deadzone,
			"events_count": built.size(),
			"saved": true,
		}
	)


## Both keycode fields are zod-optional, so a "key" entry can arrive with neither, or with a
## name Godot's keycode table does not know ("KeyW", "SPACEBAR", "Ctrl"). Both cases would
## build an InputEventKey holding KEY_NONE — an event that can never fire. Returns an EMPTY
## Dictionary when the spec is usable, an error() dict otherwise.
func _validate_key_spec(spec: Dictionary, index: int) -> Dictionary:
	var keycode: String = str(spec.get("keycode", ""))
	var physical: String = str(spec.get("physical_keycode", ""))
	if keycode.is_empty() and physical.is_empty():
		return error(
			-32602,
			"Invalid parameter: events[%d].type 'key' needs a keycode or physical_keycode" % index
		)

	if not keycode.is_empty() and _resolve_keycode(keycode) == KEY_NONE:
		return _unknown_keycode_error(index, "keycode", keycode)
	if not physical.is_empty() and _resolve_keycode(physical) == KEY_NONE:
		return _unknown_keycode_error(index, "physical_keycode", physical)
	return {}


func _unknown_keycode_error(index: int, field: String, name: String) -> Dictionary:
	return error(
		-32602,
		(
			"Invalid parameter: events[%d].%s '%s' is not a known key name "
			% [index, field, name]
			+ "(use OS.find_keycode_from_string names, e.g. W, SPACE, ESCAPE, F1)"
		)
	)


## KEY_NONE means "unparseable". Single characters are retried upper-cased, matching the
## game-side service (services/mcp_input_service.gd).
func _resolve_keycode(name: String) -> Key:
	var code: int = OS.find_keycode_from_string(name)
	if code == KEY_NONE and name.length() == 1:
		code = OS.find_keycode_from_string(name.to_upper())
	return code as Key


func _build_event(type: String, spec: Dictionary) -> InputEvent:
	match type:
		"key":
			var key := InputEventKey.new()
			var keycode: String = str(spec.get("keycode", ""))
			if not keycode.is_empty():
				key.keycode = _resolve_keycode(keycode)
			var physical: String = str(spec.get("physical_keycode", ""))
			if not physical.is_empty():
				key.physical_keycode = _resolve_keycode(physical)
			key.ctrl_pressed = bool(spec.get("ctrl", false))
			key.shift_pressed = bool(spec.get("shift", false))
			key.alt_pressed = bool(spec.get("alt", false))
			key.meta_pressed = bool(spec.get("meta", false))
			return key
		"mouse_button":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(spec.get("button_index", 1)) as MouseButton
			return mb
		"joypad_button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(spec.get("button_index", 0)) as JoyButton
			return jb
		_:
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(spec.get("axis", 0)) as JoyAxis
			jm.axis_value = float(spec.get("axis_value", 1.0))
			return jm
