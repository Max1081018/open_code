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
signal shop_opened
signal buy_pressed(key)
signal first_help_done

const CFG_PATH := "user://settings.cfg"

const GRAPHICS_LEVELS := ["Low", "Medium", "High"]

var settings := {
	"sfx_volume": 0.8,
	"sfx_enabled": true,
	"left_handed": false,
	"camera_sway": true,
	"look_sens": 1.0,
	"graphics": "High",
	"shadows": true,
	"crosshair": true,
	"show_body": true,
	"hud_scale": 1.0,
	"hud_opacity": 1.0,
	"fixed_joystick": false,
	"weather": true,
}

var _root: Control
var _main: Control
var _settings: Control
var _pause: Control
var _shop: Control
var _shop_rows: VBoxContainer
var _shop_coins: Label
var _shop_return_to: Control
var _help: Control
var _help_btn: Button
var _help_return_to: Control
var _help_firsttime := false
var _pause_btn: Button
var _title_node: Label
var _where_lbl: Label
var _stat_rows := {}
var _title_pulse := 0.0


func _ready() -> void:
	layer = 10
	_load_settings()
	_build()
	_apply_audio()
	show_main()


# --- Theme + builders ---------------------------------------------------------

func _sb(color: Color, radius := 18) -> StyleBoxFlat:
	return UITheme.box(color, radius, 26, 12)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 34
	t.set_stylebox("normal", "Button", _sb(UITheme.PRIMARY))
	t.set_stylebox("hover", "Button", _sb(UITheme.PRIMARY_HI))
	t.set_stylebox("pressed", "Button", _sb(UITheme.PRIMARY_LO))
	t.set_stylebox("disabled", "Button", _sb(Color(0.16, 0.20, 0.26)))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(3)
	focus.border_color = Color(1, 1, 1, 0.35)
	focus.set_corner_radius_all(18)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", UITheme.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", UITheme.TEXT_DIM)
	t.set_font_size("font_size", "Button", 36)
	return t


func _button(text: String, w := 460.0, h := 78.0) -> Button:
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
	panel.add_theme_stylebox_override("panel", UITheme.box_edged(UITheme.PANEL, Color(1, 1, 1, 0.07), 26))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	if title != "":
		var lbl := Label.new()
		lbl.text = title
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 52)
		lbl.add_theme_color_override("font_color", UITheme.TEXT_WARM)
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

	# Left-side shade so the text reads over the live 3D island behind it.
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.06, 0.13, 0.86))
	grad.set_color(1, Color(0.02, 0.06, 0.13, 0.0))
	grad.add_point(0.42, Color(0.02, 0.06, 0.13, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	_main.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 40)
	_main.add_child(margin)

	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 40)
	margin.add_child(layout)

	# ---- left column: brand, play, tiles ----
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(540, 0)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 14)
	layout.add_child(left)

	var title := Label.new()
	title.name = "Title"
	title.text = "LAZY LAKE"
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", UITheme.TEXT_WARM)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.15))
	title.add_theme_constant_override("outline_size", 12)
	left.add_child(title)
	_title_node = title

	var bar := ColorRect.new()
	bar.color = UITheme.ACCENT
	bar.custom_minimum_size = Vector2(130, 6)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(bar)

	var tag := Label.new()
	tag.text = "Catch it. Bonk it. Sell it. Sail further."
	tag.add_theme_font_size_override("font_size", 26)
	tag.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	left.add_child(tag)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	left.add_child(gap)

	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(540, 104)
	play.add_theme_font_size_override("font_size", 50)
	play.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT, 22))
	play.add_theme_stylebox_override("hover", UITheme.box(UITheme.ACCENT_HI, 22))
	play.add_theme_stylebox_override("pressed", UITheme.box(UITheme.ACCENT_LO, 22))
	play.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), 22))
	play.add_theme_color_override("font_color", Color(0.12, 0.07, 0.03))
	play.add_theme_color_override("font_hover_color", Color(0.12, 0.07, 0.03))
	play.add_theme_color_override("font_pressed_color", Color(0.12, 0.07, 0.03))
	play.pressed.connect(func(): play_pressed.emit())
	left.add_child(play)

	_where_lbl = Label.new()
	_where_lbl.text = "Island 1  -  Bait Bay"
	_where_lbl.add_theme_font_size_override("font_size", 22)
	_where_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	left.add_child(_where_lbl)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 14)
	left.add_child(tiles)
	var shopb := _tile("UPGRADES")
	shopb.pressed.connect(func(): _open_shop(_main))
	var howb := _tile("GUIDE")
	howb.pressed.connect(func(): _open_help(_main))
	var sbtn := _tile("SETTINGS")
	sbtn.pressed.connect(func(): _open_settings(_main))
	tiles.add_child(shopb)
	tiles.add_child(howb)
	tiles.add_child(sbtn)

	var qbtn := Button.new()
	qbtn.text = "Quit"
	qbtn.flat = true
	qbtn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	qbtn.add_theme_font_size_override("font_size", 24)
	qbtn.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	qbtn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	qbtn.pressed.connect(_on_quit)
	left.add_child(qbtn)

	# ---- right: progress card ----
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(fill)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	card.add_theme_stylebox_override("panel", UITheme.box_edged(UITheme.PANEL, Color(1, 1, 1, 0.08), 22))
	layout.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	card.add_child(cv)
	var ch := Label.new()
	ch.text = "YOUR PROGRESS"
	ch.add_theme_font_size_override("font_size", 20)
	ch.add_theme_color_override("font_color", UITheme.PRIMARY_HI)
	cv.add_child(ch)
	_stat_rows = {}
	for key in ["Coins", "Catches", "Best catch", "Boss", "Next island"]:
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = key
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 24)
		k.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		var v := Label.new()
		v.text = "-"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_theme_font_size_override("font_size", 24)
		v.add_theme_color_override("font_color", UITheme.GOLD if key == "Coins" else UITheme.TEXT)
		row.add_child(k)
		row.add_child(v)
		cv.add_child(row)
		_stat_rows[key] = v

	var ver := Label.new()
	ver.text = "v0.4"
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-70, -40)
	ver.add_theme_font_size_override("font_size", 18)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	_main.add_child(ver)

	# ---- Settings ----
	var sres := _panel("Settings")
	_settings = sres[0]
	var sv: VBoxContainer = sres[1]
	sv.custom_minimum_size = Vector2(700, 0)

	var sscroll := ScrollContainer.new()
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sscroll.custom_minimum_size = Vector2(700, 420)
	var sbody := VBoxContainer.new()
	sbody.add_theme_constant_override("separation", 14)
	sbody.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.add_child(sbody)
	sv.add_child(sscroll)

	_group(sbody, "AUDIO")
	_slider_row(sbody, "Sound volume", "sfx_volume", 0.0, 1.0, 0.05)
	_settings_toggle(sbody, "Sound effects", "sfx_enabled")

	_group(sbody, "CONTROLS")
	_slider_row(sbody, "Look sensitivity", "look_sens", 0.3, 2.0, 0.05)
	_settings_toggle(sbody, "Left-handed controls", "left_handed")
	_settings_toggle(sbody, "Camera sway", "camera_sway")

	_group(sbody, "HUD")
	_slider_row(sbody, "HUD size", "hud_scale", 0.8, 1.35, 0.05)
	_slider_row(sbody, "HUD opacity", "hud_opacity", 0.4, 1.0, 0.05)
	_settings_toggle(sbody, "Fixed joystick", "fixed_joystick")

	_group(sbody, "DISPLAY")
	_cycle_row(sbody, "Graphics", "graphics", GRAPHICS_LEVELS)
	_settings_toggle(sbody, "Shadows", "shadows")
	_settings_toggle(sbody, "Weather (light rain)", "weather")
	_settings_toggle(sbody, "Crosshair", "crosshair")
	_settings_toggle(sbody, "Show your body", "show_body")

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
	var pshop := _button("SHOP")
	pshop.pressed.connect(func(): _open_shop(_pause))
	var phow := _button("HOW TO PLAY")
	phow.pressed.connect(func(): _open_help(_pause))
	var pset := _button("SETTINGS")
	pset.pressed.connect(func(): _open_settings(_pause))
	var pmenu := _button("MAIN MENU")
	pmenu.pressed.connect(func(): to_main_menu.emit())
	pv.add_child(resume)
	pv.add_child(pshop)
	pv.add_child(phow)
	pv.add_child(pset)
	pv.add_child(pmenu)
	_root.add_child(_pause)
	_pause.visible = false

	# ---- Shop ----
	var shres := _panel("Shop")
	_shop = shres[0]
	var shv: VBoxContainer = shres[1]
	shv.custom_minimum_size = Vector2(720, 0)
	_shop_coins = Label.new()
	_shop_coins.text = "Coins: 0"
	_shop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_coins.add_theme_font_size_override("font_size", 36)
	_shop_coins.add_theme_color_override("font_color", UITheme.GOLD)
	shv.add_child(_shop_coins)
	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 14)
	shv.add_child(_shop_rows)
	var shback := _button("BACK")
	shback.pressed.connect(_on_shop_back)
	shv.add_child(shback)
	_root.add_child(_shop)
	_shop.visible = false

	# ---- How to Play ----
	var hres := _panel("How to Play")
	_help = hres[0]
	var hv: VBoxContainer = hres[1]
	hv.custom_minimum_size = Vector2(780, 0)
	hv.add_theme_constant_override("separation", 18)
	for linetext in [
		"HOLD the button to charge, release to cast.",
		"When you see  TAP!  — tap fast to hook it.",
		"HOLD to reel in, but keep LINE TENSION",
		"out of the red or the line snaps.",
		"Catch fish for coins, then buy upgrades",
		"in the Shop to land bigger ones.",
	]:
		var l := Label.new()
		l.text = linetext
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		hv.add_child(l)
	_help_btn = _button("BACK")
	_help_btn.pressed.connect(_on_help_button)
	hv.add_child(_help_btn)
	_root.add_child(_help)
	_help.visible = false

	# ---- In-game pause button (top-left) ----
	_pause_btn = Button.new()
	_pause_btn.text = "| |"
	_pause_btn.custom_minimum_size = Vector2(86, 86)
	_pause_btn.position = Vector2(24, 24)
	_pause_btn.add_theme_font_size_override("font_size", 32)
	_pause_btn.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL, 22, 10, 10))
	_pause_btn.add_theme_stylebox_override("hover", UITheme.box(UITheme.RAISED, 22, 10, 10))
	_pause_btn.add_theme_stylebox_override("pressed", UITheme.box(UITheme.PANEL_SOLID, 22, 10, 10))
	_pause_btn.pressed.connect(func(): resume_pressed.emit() if false else _request_pause())
	_root.add_child(_pause_btn)
	_pause_btn.visible = false

	_settings_return_to = _main


## A square-ish secondary tile for the main menu.
func _tile(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(170, 88)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_stylebox_override("normal", UITheme.box_edged(UITheme.PANEL, Color(1, 1, 1, 0.10), 18))
	b.add_theme_stylebox_override("hover", UITheme.box_edged(UITheme.RAISED, Color(1, 1, 1, 0.18), 18))
	b.add_theme_stylebox_override("pressed", UITheme.box_edged(UITheme.PRIMARY_LO, Color(1, 1, 1, 0.18), 18))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), 18))
	b.add_theme_color_override("font_color", UITheme.TEXT)
	return b


## Fills the progress card on the main menu.
func set_menu_stats(st: Dictionary) -> void:
	for key in st:
		if _stat_rows.has(key):
			(_stat_rows[key] as Label).text = str(st[key])
	if _where_lbl and st.has("Where"):
		_where_lbl.text = str(st["Where"])


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", UITheme.TEXT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A small section heading inside the settings list.
func _group(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UITheme.PRIMARY_HI)
	parent.add_child(l)


func _row(parent: VBoxContainer, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var lbl := _label(label)
	lbl.custom_minimum_size = Vector2(330, 54)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	parent.add_child(row)
	return row


func _slider_row(parent: VBoxContainer, label: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := _row(parent, label)
	var value := _label("")
	value.custom_minimum_size = Vector2(80, 0)
	value.add_theme_color_override("font_color", UITheme.GOLD)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = settings[key]
	sl.custom_minimum_size = Vector2(250, 54)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.text = "%d%%" % int(round(float(settings[key]) * 100.0))
	sl.value_changed.connect(func(v):
		settings[key] = v
		value.text = "%d%%" % int(round(v * 100.0))
		if key == "sfx_volume":
			_apply_audio()
		else:
			settings_changed.emit()
		_save_settings())
	row.add_child(sl)
	row.add_child(value)


## A button that cycles through a list of named options.
func _cycle_row(parent: VBoxContainer, label: String, key: String, options: Array) -> void:
	var row := _row(parent, label)
	var b := _button(str(settings[key]), 230, 62)
	b.pressed.connect(func():
		var i: int = options.find(str(settings[key]))
		settings[key] = options[(i + 1) % options.size()]
		b.text = str(settings[key])
		settings_changed.emit()
		_save_settings())
	row.add_child(b)


func _settings_toggle(parent: VBoxContainer, label: String, key: String) -> void:
	var row := _row(parent, label)
	var cb := CheckButton.new()
	cb.button_pressed = settings[key]
	cb.custom_minimum_size = Vector2(0, 54)
	cb.toggled.connect(func(on): _on_toggle(key, on))
	row.add_child(cb)


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

func _hide_overlays() -> void:
	_settings.visible = false
	if _shop:
		_shop.visible = false
	if _help:
		_help.visible = false


func show_main() -> void:
	_main.visible = true
	_pause.visible = false
	_pause_btn.visible = false
	_hide_overlays()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func show_play() -> void:
	_main.visible = false
	_pause.visible = false
	_pause_btn.visible = true
	_hide_overlays()
	# Let touches fall through to the gameplay HUD except on the pause button.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_pause() -> void:
	_pause.visible = true
	_main.visible = false
	_pause_btn.visible = false
	_hide_overlays()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _open_settings(from: Control) -> void:
	_settings_return_to = from
	from.visible = false
	_settings.visible = true
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func set_pause_button_visible(v: bool) -> void:
	if _pause_btn:
		_pause_btn.visible = v


func open_settings_for_test() -> void:
	_open_settings(_main)


func open_shop_for_test() -> void:
	_open_shop(_main)


func open_help_for_test() -> void:
	_open_help(_main)


func show_first_help() -> void:
	# Modal help the first time the player starts; button resumes play.
	_help_firsttime = true
	_help_btn.text = "START FISHING"
	_main.visible = false
	_pause.visible = false
	_pause_btn.visible = false
	_settings.visible = false
	if _shop:
		_shop.visible = false
	_help.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _open_help(from: Control) -> void:
	_help_firsttime = false
	_help_btn.text = "BACK"
	_help_return_to = from
	from.visible = false
	_help.visible = true
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_help_button() -> void:
	if _help_firsttime:
		_help.visible = false
		first_help_done.emit()
	else:
		_help.visible = false
		_help_return_to.visible = true
		if _help_return_to == _main:
			_root.mouse_filter = Control.MOUSE_FILTER_STOP


func _open_shop(from: Control) -> void:
	_shop_return_to = from
	from.visible = false
	_shop.visible = true
	_pause_btn.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_opened.emit()


func _on_shop_back() -> void:
	_shop.visible = false
	_shop_return_to.visible = true
	if _shop_return_to == _main:
		_root.mouse_filter = Control.MOUSE_FILTER_STOP


func set_coins(c: int) -> void:
	if _shop_coins:
		_shop_coins.text = "Coins: %d" % c


## rows: Array of { key, name, desc, level, max, cost, maxed, afford }.
func set_shop_model(coins: int, rows: Array) -> void:
	set_coins(coins)
	if not _shop_rows:
		return
	for c in _shop_rows.get_children():
		c.queue_free()
	for row in rows:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 16)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = "%s  (Lv %d/%d)" % [row["name"], row["level"], row["max"]]
		name_lbl.add_theme_font_size_override("font_size", 32)
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
		var desc_lbl := Label.new()
		desc_lbl.text = row["desc"]
		desc_lbl.add_theme_font_size_override("font_size", 24)
		desc_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		info.add_child(name_lbl)
		info.add_child(desc_lbl)
		hb.add_child(info)
		var buy := _button("", 240, 78)
		if row["maxed"]:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = "%d" % row["cost"]
			buy.disabled = not row["afford"]
			var key: String = row["key"]
			buy.pressed.connect(func(): buy_pressed.emit(key))
		hb.add_child(buy)
		_shop_rows.add_child(hb)


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
		_title_node.pivot_offset = Vector2(0, _title_node.size.y * 0.5)
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
