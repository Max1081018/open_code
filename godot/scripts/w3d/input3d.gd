class_name Input3D
extends Node
## One frame's intent, from the keyboard and mouse, the touch controls, or a
## test script (which writes these fields itself and sets `scripted`).

var move := Vector2.ZERO        ## x right, y forward, length <= 1
var look := Vector2.ZERO        ## camera turn this frame, radians (x yaw, y pitch)
var jump := false
var sprint := false
var dodge := false
var attack := false             ## light attack / use tool
var heavy := false
var block := false
var interact := false
var toggle_view := false
var scripted := false

## Set by the touch controls each frame.
var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var touch_buttons := {}
var mouse_sensitivity := 0.0032
var _mouse := Vector2.ZERO


func _ready() -> void:
	process_priority = -100   # before everything that reads it
	_ensure_actions()


func _ensure_actions() -> void:
	var keys := {
		"w_forward": [KEY_W, KEY_UP], "w_back": [KEY_S, KEY_DOWN], "w_left": [KEY_A, KEY_LEFT],
		"w_right": [KEY_D, KEY_RIGHT], "w_jump": [KEY_SPACE], "w_sprint": [KEY_SHIFT], "w_dodge": [KEY_CTRL, KEY_C],
		"w_interact": [KEY_E], "w_view": [KEY_V], "w_heavy": [KEY_R],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for k in keys[action]:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(action, e)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += event.relative * mouse_sensitivity
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	if scripted:
		return
	var keys := Vector2(Input.get_axis("w_left", "w_right"), Input.get_axis("w_back", "w_forward"))
	move = (keys + touch_move).limit_length(1.0)
	look = _mouse + touch_look
	_mouse = Vector2.ZERO
	touch_look = Vector2.ZERO
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	jump = Input.is_action_just_pressed("w_jump") or touch_buttons.get("jump", false)
	sprint = Input.is_action_pressed("w_sprint") or touch_buttons.get("sprint", false)
	dodge = Input.is_action_just_pressed("w_dodge") or touch_buttons.get("dodge", false)
	attack = (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or touch_buttons.get("attack", false)
	heavy = Input.is_action_just_pressed("w_heavy") or touch_buttons.get("heavy", false)
	block = (captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or touch_buttons.get("block", false)
	interact = Input.is_action_just_pressed("w_interact") or touch_buttons.get("interact", false)
	toggle_view = Input.is_action_just_pressed("w_view") or touch_buttons.get("view", false)
	# One-shot touch buttons last one frame; held ones are re-set by the HUD.
	for b in ["jump", "dodge", "heavy", "interact", "view"]:
		touch_buttons.erase(b)
