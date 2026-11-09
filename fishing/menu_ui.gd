extends CanvasLayer
## Front-end UI for Lazy Lake: main menu, settings, and pause — all drawn over
## the live 3D lake. Big, thumb-friendly buttons and a consistent dark-glass
## theme. Settings persist to user://settings.cfg.
##
## game.gd owns the app state and connects these signals; the menu applies audio
## settings itself and emits `settings_changed` for the gameplay-affecting ones
## (left_handed, camera_sway).

signal play_pressed
signal resume_pressed
signal to_main_menu
signal settings_changed

const CFG_PATH := "user://settings.cfg"

var settings := {
	"sfx_volume": 0.8,
	"sfx_enabled": true,
	"left_handed": false,
	"camera_sway": true,
}

var _root: Control
var _main: Control
var _settings: Control
var _pause: Control
var _pause_btn: Button
var _title_node: Label
var _title_pulse := 0.0


func _ready() -> void:
	layer = 10
	_load_settings()
	_build()
	_apply_audio()
	show_main()


# --- Theme + builders ---------------------------------------------------------

func _sb(color: Color, radius := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 34
	t.set_stylebox("normal", "Button", _sb(Color(0.10, 0.44, 0.60)))
	t.set_stylebox("hover", "Button", _sb(Color(0.14, 0.54, 0.72)))
	t.set_stylebox("pressed", "Button", _sb(Color(0.07, 0.34, 0.48)))
	t.set_stylebox("disabled", "Button", _sb(Color(0.2, 0.22, 0.26)))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(3)
	focus.border_color = Color(1, 1, 1, 0.5)
	focus.set_corner_radius_all(18)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 40)
	return t


func _button(text: String, w := 460.0, h := 104.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _panel(title: String) -> Array:
	# Returns [center_container, vbox]. The CenterContainer fills the screen and
	# centres the panel at its natural size.
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.08, 0.15, 0.94), 28))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	if title != "":
		var lbl := Label.new()
		lbl.text = title
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 52)
		lbl.add_theme_color_override("font_color", Color(1, 1, 0.9))
		vbox.add_child(lbl)
	panel.add_child(vbox)
	cc.add_child(panel)
	return [cc, vbox]


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = _make_theme()
	add_child(_root)

	# ---- Main menu ----
	_main = Control.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_main)

	# One centered vertical stack so it always fits and never clips.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	_main.add_child(col)

	var title := Label.new()
	title.name = "Title"
	title.text = "LAZY  LAKE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 104)
	title.add_theme_color_override("font_color", Color(1, 0.98, 0.85))
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.15, 0.25))
	title.add_theme_constant_override("outline_size", 14)
	col.add_child(title)
	_title_node = title

	var subtitle := Label.new()
	subtitle.text = "a calm little fishing game"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 32)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	subtitle.add_theme_constant_override("outline_size", 6)
	col.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	col.add_child(spacer)

	var play := _button("PLAY", 480, 118)
	play.add_theme_font_size_override("font_size", 52)
	play.pressed.connect(func(): play_pressed.emit())
	var sbtn := _button("SETTINGS")
	sbtn.pressed.connect(func(): _open_settings(_main))
	var qbtn := _button("QUIT")
	qbtn.pressed.connect(_on_quit)
	col.add_child(play)
	col.add_child(sbtn)
	col.add_child(qbtn)

	# ---- Settings ----
	var sres := _panel("Settings")
	_settings = sres[0]
	var sv: VBoxContainer = sres[1]
	sv.custom_minimum_size = Vector2(620, 0)

	# Sound volume row.
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 20)
	var vol_lbl := _label("Sound")
	vol_lbl.custom_minimum_size = Vector2(220, 0)
	var vol_slider := HSlider.new()
	vol_slider.name = "VolSlider"
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = settings["sfx_volume"]
	vol_slider.custom_minimum_size = Vector2(300, 60)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_slider.value_changed.connect(_on_volume)
	vol_row.add_child(vol_lbl)
	vol_row.add_child(vol_slider)
	sv.add_child(vol_row)

	_settings_toggle(sv, "Sound effects", "sfx_enabled")
	_settings_toggle(sv, "Left-handed controls", "left_handed")
	_settings_toggle(sv, "Camera sway", "camera_sway")

	var back := _button("BACK")
	back.pressed.connect(_on_settings_back)
	sv.add_child(back)
	_root.add_child(_settings)
	_settings.visible = false

	# ---- Pause ----
	var pres := _panel("Paused")
	_pause = pres[0]
	var pv: VBoxContainer = pres[1]
	pv.custom_minimum_size = Vector2(520, 0)
	var resume := _button("RESUME")
	resume.pressed.connect(func(): resume_pressed.emit())
	var pset := _button("SETTINGS")
	pset.pressed.connect(func(): _open_settings(_pause))
	var pmenu := _button("MAIN MENU")
	pmenu.pressed.connect(func(): to_main_menu.emit())
	pv.add_child(resume)
	pv.add_child(pset)
	pv.add_child(pmenu)
	_root.add_child(_pause)
	_pause.visible = false

	# ---- In-game pause button (top-left) ----
	_pause_btn = Button.new()
	_pause_btn.text = "| |"
	_pause_btn.custom_minimum_size = Vector2(86, 86)
	_pause_btn.position = Vector2(24, 24)
	_pause_btn.add_theme_font_size_override("font_size", 36)
	_pause_btn.pressed.connect(func(): resume_pressed.emit() if false else _request_pause())
	_root.add_child(_pause_btn)
	_pause_btn.visible = false

	_settings_return_to = _main


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _settings_toggle(parent: VBoxContainer, label: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lbl := _label(label)
	lbl.custom_minimum_size = Vector2(380, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cb := CheckButton.new()
	cb.button_pressed = settings[key]
	cb.custom_minimum_size = Vector2(0, 60)
	cb.toggled.connect(func(on): _on_toggle(key, on))
	row.add_child(lbl)
	row.add_child(cb)
	parent.add_child(row)


# --- Screen transitions -------------------------------------------------------

var _signal_pause := false
func _request_pause() -> void:
	# game.gd polls consume_pause() so pausing lives in one place.
	_signal_pause = true

func consume_pause() -> bool:
	var p := _signal_pause
	_signal_pause = false
	return p


var _settings_return_to: Control

func show_main() -> void:
	_main.visible = true
	_settings.visible = false
	_pause.visible = false
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func show_play() -> void:
	_main.visible = false
	_settings.visible = false
	_pause.visible = false
	_pause_btn.visible = true
	# Let touches fall through to the gameplay HUD except on the pause button.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_pause() -> void:
	_pause.visible = true
	_main.visible = false
	_settings.visible = false
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _open_settings(from: Control) -> void:
	_settings_return_to = from
	from.visible = false
	_settings.visible = true
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func open_settings_for_test() -> void:
	_open_settings(_main)


func _on_settings_back() -> void:
	_settings.visible = false
	_settings_return_to.visible = true
	if _settings_return_to == _main:
		_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_quit() -> void:
	get_tree().quit()


func _process(delta: float) -> void:
	# Gentle title bob on the main menu.
	if _main.visible and _title_node:
		_title_pulse += delta
		_title_node.pivot_offset = _title_node.size * 0.5
		_title_node.scale = Vector2.ONE * (1.0 + sin(_title_pulse * 1.5) * 0.015)


# --- Settings state -----------------------------------------------------------

func _on_volume(v: float) -> void:
	settings["sfx_volume"] = v
	_apply_audio()
	_save_settings()


func _on_toggle(key: String, on: bool) -> void:
	settings[key] = on
	if key == "sfx_enabled":
		_apply_audio()
	else:
		settings_changed.emit()
	_save_settings()


func _apply_audio() -> void:
	var vol: float = settings["sfx_volume"]
	var on: bool = settings["sfx_enabled"]
	var muted := (not on) or vol <= 0.001
	AudioServer.set_bus_mute(0, muted)
	if not muted:
		AudioServer.set_bus_volume_db(0, linear_to_db(clampf(vol, 0.001, 1.0)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		for key in settings:
			settings[key] = cfg.get_value("settings", key, settings[key])


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(CFG_PATH)
