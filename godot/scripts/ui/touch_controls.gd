class_name TouchControls
extends Control
## On-screen controls with true multitouch.
##
## Every finger is tracked by index from the moment it lands, and keeps the
## meaning of where it landed: a thumb that starts on the stick steers until
## it lifts, wherever it slides; a finger that starts on open world aims
## and uses the held item. Godot's Button nodes are not used for the
## action buttons, because they cannot be held by two fingers at once and
## running while jumping needs exactly that.

const DEADZONE := 0.16

var level: Level
var hud: Node
## Screen rectangles owned by other UI (hotbar, top buttons). Touches that
## start inside them are left for that UI to handle.
var blocked_rects: Array[Rect2] = []

var using := false
var jump_held := false
var active := false  ## any finger down

var _fingers := {}  ## index -> {"role": String, "start": Vector2, "pos": Vector2}
var _buttons := {}  ## role -> {"centre": Vector2, "radius": float, "icon": Texture2D}
var _pad: Texture2D
var _nub: Texture2D
var _button_tex: Texture2D
var _flash := {}  ## role -> seconds of press highlight


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad = load("res://assets/ui/controls/joystick_circle_pad_a.png")
	_nub = load("res://assets/ui/controls/joystick_circle_nub_a.png")
	_button_tex = load("res://assets/ui/controls/button_circle.png")
	_layout()
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_layout)


func _layout() -> void:
	var screen := get_viewport_rect().size
	var unit := minf(screen.y, screen.x * 0.56) / 1080.0 * Settings.control_scale
	var right := screen.x - 150 * unit
	var bottom := screen.y - 150 * unit
	var mirror := Settings.left_handed

	var spec := {
		"jump": [Vector2(right, bottom), 104.0, "icon_jump"],
		"attack": [Vector2(right - 225 * unit, bottom + 30 * unit), 86.0, "icon_sword"],
		"interact": [Vector2(right - 40 * unit, bottom - 215 * unit), 70.0, "icon_hand"],
		"block": [Vector2(right - 255 * unit, bottom - 175 * unit), 66.0, "icon_shield"],
	}
	_buttons.clear()
	for role in spec:
		var centre: Vector2 = spec[role][0]
		var offset: Vector2 = Settings.control_offsets.get(role, Vector2.ZERO)
		centre += offset * screen
		if mirror:
			centre.x = screen.x - centre.x
		_buttons[role] = {
			"centre": centre,
			"radius": spec[role][1] * unit,
			"icon": load("res://assets/ui/icons/%s.png" % spec[role][2]),
		}
	queue_redraw()


func stick_radius() -> float:
	var screen := get_viewport_rect().size
	return 125.0 * minf(screen.y, screen.x * 0.56) / 1080.0 * Settings.control_scale


func _in_stick_zone(p: Vector2) -> bool:
	var screen := get_viewport_rect().size
	var x := p.x if not Settings.left_handed else screen.x - p.x
	return x < screen.x * 0.36 and p.y > screen.y * 0.45


## The block button only exists while a shield is carried.
func _shown(role: String) -> bool:
	if role == "block":
		return level != null and level.player != null and level.player.rig.has_shield()
	return true


func _button_at(p: Vector2) -> String:
	for role in _buttons:
		if not _shown(role):
			continue
		var b: Dictionary = _buttons[role]
		# Generous hit area: a thumb is bigger than it thinks it is.
		if p.distance_to(b.centre) <= b.radius * 1.25:
			return role
	return ""


func _blocked(p: Vector2) -> bool:
	for rect in blocked_rects:
		if rect.has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible or level == null or level.player == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	elif event is InputEventScreenDrag:
		if _fingers.has(event.index):
			_fingers[event.index].pos = event.position


func _finger_down(index: int, p: Vector2) -> void:
	if _blocked(p):
		return
	var role := _button_at(p)
	if role == "" and _in_stick_zone(p):
		role = "stick"
	if role == "":
		role = "world"
	_fingers[index] = {"role": role, "start": p, "pos": p}
	_flash[role] = 0.15
	var input := level.player.input
	match role:
		"jump":
			input.jump_pressed = true
		"attack":
			input.attack_pressed = true
		"interact":
			input.interact_pressed = true
	get_viewport().set_input_as_handled()


func _finger_up(index: int) -> void:
	_fingers.erase(index)


func _process(delta: float) -> void:
	if level == null or level.player == null:
		return
	var input := level.player.input
	active = not _fingers.is_empty()
	jump_held = false
	using = false
	var blocking := false
	var steer := 0.0
	for finger in _fingers.values():
		match finger.role:
			"stick":
				steer = _axis(finger.start, finger.pos)
			"jump":
				jump_held = true
			"block":
				blocking = true
			"world":
				using = true
				input.aim = level.get_canvas_transform().affine_inverse() * finger.pos
	if active:
		input.move = steer
		input.jump_held = jump_held
		input.use_held = using
		input.block_held = blocking
	for role in _flash.keys():
		_flash[role] -= delta
		if _flash[role] <= 0.0:
			_flash.erase(role)
	queue_redraw()


func _axis(anchor: Vector2, p: Vector2) -> float:
	var offset := (p.x - anchor.x) / stick_radius()
	var magnitude := absf(offset)
	if magnitude <= DEADZONE:
		return 0.0
	return clampf((magnitude - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0) * signf(offset)


func _draw() -> void:
	var alpha := Settings.control_opacity
	var screen := get_viewport_rect().size

	# The stick: at rest in its corner, or wherever the thumb is holding it.
	var anchor := Vector2(screen.x * 0.15, screen.y - 190 * screen.y / 1080.0)
	if Settings.left_handed:
		anchor.x = screen.x - anchor.x
	var knob := anchor
	for finger in _fingers.values():
		if finger.role == "stick":
			anchor = finger.start
			var offset: Vector2 = finger.pos - anchor
			knob = anchor + offset.limit_length(stick_radius())
	var r := stick_radius()
	draw_texture_rect(_pad, Rect2(anchor - Vector2(r, r), Vector2(r, r) * 2), false,
		Color(1, 1, 1, alpha * 0.55))
	draw_texture_rect(_nub, Rect2(knob - Vector2(r, r) * 0.48, Vector2(r, r) * 0.96), false,
		Color(1, 1, 1, alpha * 0.9))

	for role in _buttons:
		if not _shown(role):
			continue
		var b: Dictionary = _buttons[role]
		var held := false
		for finger in _fingers.values():
			if finger.role == role:
				held = true
		var radius: float = b.radius * (0.92 if held else 1.0)
		var tint := Color(1, 1, 1, alpha * (1.0 if held else 0.78))
		if role == "interact" and not hud.get("can_interact"):
			tint.a *= 0.4
		draw_texture_rect(_button_tex, Rect2(b.centre - Vector2(radius, radius), Vector2(radius, radius) * 2),
			false, tint)
		var icon: Texture2D = b.icon
		var size := radius * 1.05
		draw_texture_rect(icon, Rect2(b.centre - Vector2(size, size) * 0.5, Vector2(size, size)), false,
			Color(1, 1, 1, tint.a))
		if _flash.has(role):
			draw_circle(b.centre, radius * (1.0 + (0.15 - _flash[role]) * 2.0),
				Color(1, 1, 1, _flash[role] * 1.5))
