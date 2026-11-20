extends Node

## GAME-SIDE autoload (injected by the plugin). No @tool — this only runs in the game.
##
## File IPC (frozen): editor writes `user://mcp_input_commands` containing either
##   [ <event dict>, ... ]                               -> inject all this frame
##   {"sequence_events": [ ... ], "frame_delay": N}      -> inject one event every N frames
##
## Event dict shapes (FROZEN — flat x/y, never nested position):
##   {"type":"key","keycode":"W","pressed":true,"shift":false,"ctrl":false,"alt":false}
##   {"type":"mouse_button","button":1,"pressed":true,"double_click":false,"x":0,"y":0}
##   {"type":"mouse_motion","x":0,"y":0,"relative_x":0,"relative_y":0,"button_mask":0,
##    "unhandled":false}
##   {"type":"action","action":"jump","pressed":true,"strength":1.0}

const COMMANDS_PATH := "user://mcp_input_commands"

var _sequence: Array = []
var _frame_delay: int = 1
var _frame_counter: int = 0


func _ready() -> void:
	if FileAccess.file_exists(COMMANDS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COMMANDS_PATH))


func _process(_delta: float) -> void:
	_consume_file()
	_advance_sequence()


func _consume_file() -> void:
	if not FileAccess.file_exists(COMMANDS_PATH):
		return
	var file: FileAccess = FileAccess.open(COMMANDS_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(COMMANDS_PATH))

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_warning("[MCP] malformed input command payload")
		return

	if typeof(parsed) == TYPE_ARRAY:
		for entry: Variant in parsed as Array:
			if typeof(entry) == TYPE_DICTIONARY:
				_inject(entry)
		return

	if typeof(parsed) == TYPE_DICTIONARY:
		var payload: Dictionary = parsed
		if payload.has("sequence_events"):
			var events: Variant = payload["sequence_events"]
			if typeof(events) == TYPE_ARRAY:
				_sequence = (events as Array).duplicate()
				_frame_delay = maxi(1, int(payload.get("frame_delay", 1)))
				_frame_counter = 0
			return
		_inject(payload)


func _advance_sequence() -> void:
	if _sequence.is_empty():
		return
	_frame_counter += 1
	if _frame_counter < _frame_delay:
		return
	_frame_counter = 0
	var entry: Variant = _sequence.pop_front()
	if typeof(entry) == TYPE_DICTIONARY:
		_inject(entry)


func _inject(event: Dictionary) -> void:
	var type: String = str(event.get("type", ""))
	match type:
		"key":
			_inject_key(event)
		"mouse_button":
			_inject_mouse_button(event)
		"mouse_motion":
			_inject_mouse_motion(event)
		"action":
			_inject_action(event)
		_:
			push_warning("[MCP] unknown input event type: %s" % type)


func _inject_key(event: Dictionary) -> void:
	var ev := InputEventKey.new()
	var keycode: Key = _to_keycode(event.get("keycode", ""))
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = bool(event.get("pressed", true))
	ev.shift_pressed = bool(event.get("shift", false))
	ev.ctrl_pressed = bool(event.get("ctrl", false))
	ev.alt_pressed = bool(event.get("alt", false))
	ev.meta_pressed = bool(event.get("meta", false))
	Input.parse_input_event(ev)


func _to_keycode(raw: Variant) -> Key:
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return int(raw) as Key
	var name: String = str(raw)
	if name.is_empty():
		return KEY_NONE
	var code: int = OS.find_keycode_from_string(name)
	if code == KEY_NONE and name.length() == 1:
		code = OS.find_keycode_from_string(name.to_upper())
	return code as Key


func _inject_mouse_button(event: Dictionary) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = int(event.get("button", 1)) as MouseButton
	ev.pressed = bool(event.get("pressed", true))
	ev.double_click = bool(event.get("double_click", false))
	var pos := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	ev.position = pos
	ev.global_position = pos
	if ev.pressed:
		ev.button_mask = _mask_for(ev.button_index) as MouseButtonMask
	Input.parse_input_event(ev)


func _mask_for(button: MouseButton) -> int:
	match button:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
		_:
			return 0


func _inject_mouse_motion(event: Dictionary) -> void:
	var ev := InputEventMouseMotion.new()
	var pos := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	ev.position = pos
	ev.global_position = pos
	ev.relative = Vector2(
		float(event.get("relative_x", 0.0)), float(event.get("relative_y", 0.0))
	)
	ev.button_mask = int(event.get("button_mask", 0)) as MouseButtonMask

	if bool(event.get("unhandled", false)):
		# Bypass Input's filtering and hand it straight to the viewport's unhandled path.
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.push_input(ev, true)
			return
	Input.parse_input_event(ev)


func _inject_action(event: Dictionary) -> void:
	var action: String = str(event.get("action", ""))
	if action.is_empty():
		return
	if not InputMap.has_action(action):
		push_warning("[MCP] unknown input action: %s" % action)
		return
	if bool(event.get("pressed", true)):
		Input.action_press(action, float(event.get("strength", 1.0)))
	else:
		Input.action_release(action)
