class_name GameMenu3D
extends Control
## The game's screens, over a frosted, paused world, in one style: dark
## translucent blue-violet panels, gold for what is chosen, lavender lines,
## Cinzel titles.
##   Backpack   categories, a grid of item slots (rarity frames, counts),
##              the chosen item's details, Equip / Use / Discard, Sort
##   Crafting   recipes by category, required materials (have / need), a
##              quantity stepper and Craft
##   Quests     the townsfolk's requests, Track
##   Map        the whole island with its marks
##   Character  the heroine turning slowly, attributes, the Moonblade's arts
##   Paused     Resume and every screen, Settings, Title
## Opens from the HUD (backpack button, top icons) or I/B, K, J, M, C, Esc.

const GOLD := Color(0.96, 0.84, 0.56)
const PALE := Color(0.97, 0.96, 1.0)
const DIM := Color(0.72, 0.74, 0.86)
const LAVENDER := Color(0.78, 0.72, 1.0)
const INK := Color(0.16, 0.12, 0.08)
const PANEL := Color(0.08, 0.08, 0.2, 0.8)
const TABS := [["bag", "Backpack"], ["craft", "Crafting"], ["book", "Quests"], ["map", "Map"],
	["person", "Character"], ["pause", "Game Paused"]]
const TITLES := {"gear": "Settings", "shop": "Tobin's Stall"}
## Slot colours by rarity (common .. legendary).
const RARITY_BG := [Color(0.36, 0.38, 0.46), Color(0.24, 0.46, 0.4), Color(0.24, 0.38, 0.66), Color(0.44, 0.32, 0.68),
	Color(0.72, 0.5, 0.24)]
const RARITY_EDGE := [Color(0.72, 0.74, 0.8), Color(0.55, 0.9, 0.62), Color(0.55, 0.78, 1.0), Color(0.84, 0.66, 1.0),
	Color(1.0, 0.84, 0.45)]
const FILTERS := [["all", "All"], ["weapon", "Weapons"], ["tool", "Tools"], ["food", "Consumables"],
	["material", "Materials"], ["treasure", "Treasures"]]
## Things that never leave her: her own blade and the keys of the story.
const KEEP := ["moonblade", "vault_key"]

var game: Node
var hud: Hud3D
var tab := ""
var is_open := false
var _body: Control
var _title: Label
var _emblem: Control
var _tab_icons: Array = []
var _chips: Control
var _filter := "all"
var _selected := -1
var _quest_sel := ""
var _map_tex: ImageTexture
var _map_marks: Control
var _ui_font: Font
var _title_font: Font
var _num_font: Font
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _spin: Node3D


func setup(the_game: Node, the_hud: Hud3D) -> void:
	game = the_game
	hud = the_hud
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_title_font = load("res://assets/fonts/CinzelDecorative-Bold.ttf")
	var cinzel := FontVariation.new()
	cinzel.base_font = load("res://assets/fonts/Cinzel.ttf")
	cinzel.variation_opentype = {"wght": 600}
	_ui_font = cinzel
	_num_font = load("res://assets/fonts/Fredoka.ttf")
	var frost := ColorRect.new()
	add_child(frost)
	frost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/shaders/menu_blur.gdshader")
	frost.material = mat
	frost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A violet dusk over the frost, darker at the edges.
	var veil := Control.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.draw.connect(func():
		var s := veil.size
		veil.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.04, 0.14, 0.5))
		for k in 12:
			var f := float(k) / 12.0
			veil.draw_rect(Rect2(Vector2(0, s.y * (0.6 + f * 0.4)), Vector2(s.x, s.y * 0.034)), Color(0.02, 0.01, 0.06, 0.03 * k)))
	add_child(veil)
	# Header: emblem and title on the left, the screens in the middle,
	# coins and shards, and a close button on the right.
	_emblem = Control.new()
	_emblem.size = Vector2(76, 76)
	_emblem.position = Vector2(40, 22)
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.draw.connect(_draw_emblem)
	add_child(_emblem)
	_title = _label("", 40, PALE, _ui_font, true)
	_title.position = Vector2(132, 38)
	add_child(_title)
	var rule := Control.new()
	rule.position = Vector2(40, 112)
	rule.size = Vector2(1840, 4)
	rule.anchor_right = 1.0
	rule.offset_right = -40
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func():
		var w := rule.size.x
		rule.draw_line(Vector2(0, 1), Vector2(w, 1), Color(LAVENDER, 0.22), 1.0)
		rule.draw_line(Vector2(w * 0.35, 1), Vector2(w * 0.65, 1), Color(GOLD, 0.55), 1.5)
		var m := Vector2(w * 0.5, 1)
		rule.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0)]), GOLD))
	add_child(rule)
	var strip := Control.new()
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.position = Vector2(-(TABS.size() * 76 - 12) * 0.5, 28)
	strip.size = Vector2(TABS.size() * 76, 64)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	for i in TABS.size():
		var icon := Control.new()
		icon.size = Vector2(64, 64)
		icon.position = Vector2(i * 76, 0)
		icon.tooltip_text = TABS[i][1]
		icon.draw.connect(_draw_tab_icon.bind(icon, i))
		icon.gui_input.connect(_on_tab_input.bind(TABS[i][0]))
		strip.add_child(icon)
		_tab_icons.append(icon)
	_chips = Control.new()
	_chips.anchor_left = 1.0
	_chips.anchor_right = 1.0
	_chips.position = Vector2(-560, 36)
	_chips.size = Vector2(420, 48)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)
	var close := Control.new()
	close.size = Vector2(64, 64)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.position = Vector2(-108, 28)
	close.draw.connect(_draw_close.bind(close))
	close.gui_input.connect(_on_close_input)
	add_child(close)
	# The screens are laid out on 1920 x 950; wider phones centre them.
	_body = Control.new()
	_body.anchor_left = 0.5
	_body.anchor_right = 0.5
	_body.position = Vector2(-960, 130)
	_body.size = Vector2(1920, 950)
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_body)


# ------------------------------------------------------------ opening ---

func open(which: String) -> void:
	if not is_open:
		is_open = true
		visible = true
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
		Sfx.play("click")
	show_tab(which)


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_was
	_clear()
	Sfx.play("click", -6.0)


func toggle(which: String) -> void:
	if is_open and tab == which:
		close()
	else:
		open(which)


func show_tab(which: String) -> void:
	var changed := which != tab
	tab = which
	_clear()
	_title.text = TITLES.get(which, "")
	for t in TABS:
		if t[0] == which:
			_title.text = t[1]
	_emblem.queue_redraw()
	for icon in _tab_icons:
		(icon as Control).queue_redraw()
	_build_chips()
	# A soft rise as the screen changes.
	if changed:
		_body.modulate.a = 0.0
		_body.position.y = 146
	var t := create_tween().set_parallel()
	t.tween_property(_body, "modulate:a", 1.0, 0.18)
	t.tween_property(_body, "position:y", 130.0, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	match which:
		"bag":
			_build_bag()
		"craft":
			_build_craft()
		"book":
			_build_quests()
		"map":
			_build_map()
		"person":
			_build_character()
		"pause":
			_build_pause()
		"gear":
			_build_settings()
		"shop":
			_build_shop()


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()
	_spin = null


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var which := ""
		match event.physical_keycode:
			KEY_I, KEY_B:
				which = "bag"
			KEY_K:
				which = "craft"
			KEY_J:
				which = "book"
			KEY_M:
				which = "map"
			KEY_C:
				which = "person"
			KEY_ESCAPE:
				if is_open:
					close()
					get_viewport().set_input_as_handled()
					return
				which = "pause"
		if which != "" and (is_open or not game.input.blocked):
			toggle(which)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _spin:
		_spin.rotation.y += delta * 0.5


# ------------------------------------------------------------- helpers ---

func _label(text: String, size: int, colour: Color, font: Font, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if font:
		l.add_theme_font_override("font", font)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.08, 0.7))
		l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(colour := PANEL, radius := 18, edge := Color(LAVENDER, 0.28)) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = colour
	st.set_corner_radius_all(radius)
	st.border_color = edge
	st.set_border_width_all(1)
	st.shadow_color = Color(0, 0, 0, 0.25)
	st.shadow_size = 8
	st.anti_aliasing = true
	return st


func _panel(at: Vector2, size: Vector2, colour := PANEL, radius := 18) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _style(colour, radius))
	p.position = at
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_child(p)
	return p


func _button(text: String, at: Vector2, size: Vector2, parent: Control, primary := true) -> Button:
	var b := Button.new()
	b.text = text
	b.position = at
	b.size = size
	b.add_theme_font_override("font", _ui_font)
	b.add_theme_font_size_override("font_size", 26)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.97, 0.9, 0.74) if primary else Color(0.16, 0.16, 0.34, 0.92)
	normal.set_corner_radius_all(int(size.y * 0.5))
	normal.border_color = GOLD if primary else Color(LAVENDER, 0.5)
	normal.set_border_width_all(2)
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.12)
	var off := normal.duplicate() as StyleBoxFlat
	off.bg_color = Color(0.3, 0.3, 0.4, 0.6)
	off.border_color = Color(1, 1, 1, 0.15)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := INK if primary else PALE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, ink)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	parent.add_child(b)
	return b


## A screen's emblem: a gold ring with the screen's glyph.
func _draw_emblem() -> void:
	var c := _emblem
	var m := c.size * 0.5
	c.draw_circle(m, 34, Color(0.1, 0.09, 0.24, 0.9))
	c.draw_arc(m, 34, 0, TAU, 48, GOLD, 2.0, true)
	c.draw_arc(m, 29, 0, TAU, 48, Color(GOLD, 0.35), 1.0, true)
	glyph(c, tab, m, PALE, 1.0)


func _draw_tab_icon(c: Control, i: int) -> void:
	var active: bool = TABS[i][0] == tab or (tab == "gear" and TABS[i][0] == "pause")
	var sb := _style(Color(0.95, 0.84, 0.58, 0.95) if active else Color(0.09, 0.09, 0.22, 0.7), 16,
		Color(1, 1, 1, 0.8) if active else Color(LAVENDER, 0.35))
	sb.shadow_size = 0
	c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
	glyph(c, TABS[i][0], c.size * 0.5, INK if active else PALE, 0.9)


func _draw_close(c: Control) -> void:
	var m := c.size * 0.5
	c.draw_circle(m, 28, Color(0.09, 0.09, 0.22, 0.75))
	c.draw_arc(m, 28, 0, TAU, 40, Color(LAVENDER, 0.6), 2.0, true)
	c.draw_line(m + Vector2(-10, -10), m + Vector2(10, 10), PALE, 3.5, true)
	c.draw_line(m + Vector2(10, -10), m + Vector2(-10, 10), PALE, 3.5, true)


## Coins and starshards carried, top right.
func _build_chips() -> void:
	for c in _chips.get_children():
		c.queue_free()
	var inv: Inventory = game.play.inventory
	var x := 0.0
	for pair in [["glowshard", inv.count("glowshard")], ["gold_coin", inv.count("gold_coin")]]:
		var chip := Panel.new()
		var st := _style(Color(0.06, 0.06, 0.16, 0.75), 24, Color(LAVENDER, 0.3))
		st.shadow_size = 0
		chip.add_theme_stylebox_override("panel", st)
		chip.position = Vector2(x, 0)
		chip.size = Vector2(196, 48)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chips.add_child(chip)
		_icon_child(chip, pair[0], Vector2(8, 4), 40.0)
		var n := _label(str(pair[1]), 26, PALE, _num_font)
		n.position = Vector2(56, 6)
		n.size = Vector2(124, 36)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chip.add_child(n)
		x += 210.0


func _on_tab_input(event: InputEvent, which: String) -> void:
	if _pressed(event):
		Sfx.play("click", -6.0)
		show_tab(which)


func _on_close_input(event: InputEvent) -> void:
	if _pressed(event):
		close()


func _pressed(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)


## An item's icon as a child TextureRect (textures drawn with
## draw_texture_rect came out as white squares on the Compatibility renderer).
func _icon_child(parent: Control, id: String, at: Vector2, side: float) -> TextureRect:
	var tex: Texture2D = Hud3D.icon_for(id)
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = at
	t.size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


static func category(id: String) -> String:
	if id == "gold_coin":
		return "treasure"
	match Items.kind(id):
		Items.Kind.SWORD, Items.Kind.SHIELD:
			return "weapon"
		Items.Kind.PICKAXE, Items.Kind.AXE, Items.Kind.HAMMER, Items.Kind.ROD:
			return "tool"
		Items.Kind.CONSUMABLE:
			return "food"
		Items.Kind.RELIC, Items.Kind.KEY:
			return "treasure"
	return "material"


## Line glyphs for screens and categories, centred on `m`, scaled by `k`.
func glyph(c: Control, kind: String, m: Vector2, w: Color, k := 1.0) -> void:
	match kind:
		"bag":
			hud.draw_backpack(c, m, k * 0.95)
		"craft":
			# A hammer over an anvil.
			c.draw_line(m + Vector2(-12, 10) * k, m + Vector2(8, -10) * k, w, 3.5 * k, true)
			c.draw_rect(Rect2(m + Vector2(2, -18) * k, Vector2(16, 9) * k), w)
			c.draw_rect(Rect2(m + Vector2(-16, 12) * k, Vector2(32, 5) * k), w)
		"shop":
			c.draw_circle(m, 13 * k, Color(0.98, 0.8, 0.36))
			c.draw_arc(m, 13 * k, 0, TAU, 24, Color(0.6, 0.4, 0.1), 2.0, true)
			hud.draw_star(c, m, 7.0 * k, Color(0.6, 0.4, 0.1))
		"buy", "sell":
			c.draw_circle(m, 9 * k, w)
			c.draw_line(m + Vector2(0, -15 if kind == "sell" else 15) * k, m + Vector2(0, 5 if kind == "sell" else -5) * k, w, 2.5, true)
		"pause":
			c.draw_rect(Rect2(m + Vector2(-10, -12) * k, Vector2(7, 24) * k), w)
			c.draw_rect(Rect2(m + Vector2(3, -12) * k, Vector2(7, 24) * k), w)
		"all":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -11) * k, m + Vector2(11, 0) * k, m + Vector2(0, 11) * k, m + Vector2(-11, 0) * k]), w)
		"weapon":
			c.draw_line(m + Vector2(-11, 11) * k, m + Vector2(10, -10) * k, w, 3.5 * k, true)
			c.draw_line(m + Vector2(-12, 3) * k, m + Vector2(-3, 12) * k, w, 3.0 * k, true)
		"tool":
			c.draw_line(m + Vector2(-10, 12) * k, m + Vector2(6, -6) * k, w, 3.0 * k, true)
			c.draw_arc(m + Vector2(6, -6) * k, 9 * k, PI * 0.75, PI * 1.75, 10, w, 3.0 * k, true)
		"food":
			c.draw_circle(m + Vector2(0, 3) * k, 10 * k, w)
			c.draw_line(m + Vector2(0, -7) * k, m + Vector2(3, -13) * k, w, 2.5 * k, true)
		"material":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -12) * k, m + Vector2(10, -2) * k, m + Vector2(0, 12) * k, m + Vector2(-10, -2) * k]), w)
			c.draw_line(m + Vector2(-10, -2) * k, m + Vector2(10, -2) * k, Color(0, 0, 0, 0.35), 1.5)
		"treasure":
			hud.draw_star(c, m, 12.0 * k, w)
		_:
			hud.draw_glyph(c, kind, w)


# ----------------------------------------------------------------- bag ---

var _cards: Array = []   ## [Control, slot index]
var _detail: Panel
var _discard_armed := false
const SLOT := 132.0


## Categories down the left: name, glyph, how many.
func _category_column(entries: Array, current: String, counts: Dictionary, pick: Callable) -> Panel:
	var col := _panel(Vector2(40, 6), Vector2(300, 880), Color(0.07, 0.07, 0.18, 0.72))
	var y := 18.0
	for f in entries:
		var row := Control.new()
		row.position = Vector2(14, y)
		row.size = Vector2(272, 62)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var key: String = f[0]
		var active := key == current
		row.draw.connect(func():
			if active:
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.95, 0.84, 0.58, 0.95)
				sb.set_corner_radius_all(31)
				sb.anti_aliasing = true
				row.draw_style_box(sb, Rect2(Vector2.ZERO, row.size))
			glyph(row, key, Vector2(34, 31), INK if active else LAVENDER, 0.85)
			row.draw_string(_ui_font, Vector2(64, 40), f[1], HORIZONTAL_ALIGNMENT_LEFT, 170, 22, INK if active else PALE)
			if counts.has(key):
				row.draw_string(_num_font, Vector2(226, 40), str(counts[key]), HORIZONTAL_ALIGNMENT_RIGHT, 36, 20,
					Color(INK, 0.7) if active else DIM))
		row.gui_input.connect(func(ev):
			if _pressed(ev):
				pick.call(key))
		col.add_child(row)
		y += 70.0
	return col


func _build_bag() -> void:
	_cards.clear()
	_discard_armed = false
	var inv: Inventory = game.play.inventory
	var counts := {"all": 0}
	for i in inv.size():
		var s = inv.get_slot(i)
		if s != null:
			counts.all += 1
			var c := category(s.id)
			counts[c] = int(counts.get(c, 0)) + 1
	var col := _category_column(FILTERS, _filter, counts, _set_filter)
	var used := _label("%d / %d" % [counts.all, inv.size()], 22, DIM, _num_font)
	used.position = Vector2(24, 800)
	col.add_child(used)
	var sort := _button("Sort", Vector2(150, 788), Vector2(132, 52), col, false)
	sort.add_theme_font_size_override("font_size", 22)
	sort.pressed.connect(func():
		inv.sort_bag()
		_selected = -1
		Sfx.play("click", -6.0)
		show_tab("bag"))
	# The grid of slots.
	var grid_panel := _panel(Vector2(360, 6), Vector2(900, 880), Color(0.06, 0.06, 0.16, 0.55))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(870, 846)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var first := -1
	for i in inv.size():
		var s = inv.get_slot(i)
		if s == null:
			continue
		if _filter != "all" and category(s.id) != _filter:
			continue
		if first < 0:
			first = i
		var card := Control.new()
		card.custom_minimum_size = Vector2(SLOT, SLOT)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.draw.connect(_draw_slot_card.bind(card, s.id, s.count, i == game.play.hotbar_index, i == _selected))
		card.gui_input.connect(_on_card_input.bind(i))
		grid.add_child(card)
		_icon_child(card, s.id, Vector2(16, 8), SLOT - 32)
		_cards.append([card, i])
	if _selected < 0 or inv.get_slot(_selected) == null or (_filter != "all" and category(inv.get_slot(_selected).id) != _filter):
		_selected = first
	_detail = _panel(Vector2(1280, 6), Vector2(600, 880))
	_fill_detail()
	if first < 0:
		var empty := _label("Nothing here yet.", 30, DIM, _ui_font)
		empty.position = Vector2(40, 40)
		grid_panel.add_child(empty)


func _set_filter(f: String) -> void:
	_filter = f
	_selected = -1
	Sfx.play("click", -8.0)
	show_tab("bag")


## An item slot: a rarity-tinted tile with a bright rarity edge, the count
## in a band along the bottom, a gold frame when chosen, a mark if in hand.
func _draw_slot_card(c: Control, id: String, count: int, equipped: bool, chosen: bool, dim := false) -> void:
	var r: int = Items.rarity(id)
	var w := c.size
	var base := StyleBoxFlat.new()
	base.bg_color = RARITY_BG[r].darkened(0.25)
	base.set_corner_radius_all(16)
	base.anti_aliasing = true
	c.draw_style_box(base, Rect2(Vector2.ZERO, w))
	# A lighter wash toward the top, like light falling on the tile.
	var wash := StyleBoxFlat.new()
	wash.bg_color = Color(RARITY_BG[r].lightened(0.25), 0.55)
	wash.corner_radius_top_left = 16
	wash.corner_radius_top_right = 16
	wash.corner_radius_bottom_left = 40
	wash.corner_radius_bottom_right = 40
	wash.anti_aliasing = true
	c.draw_style_box(wash, Rect2(Vector2(0, 0), Vector2(w.x, w.y * 0.62)))
	var band := StyleBoxFlat.new()
	band.bg_color = Color(0.04, 0.04, 0.1, 0.62)
	band.corner_radius_bottom_left = 16
	band.corner_radius_bottom_right = 16
	c.draw_style_box(band, Rect2(Vector2(0, w.y - 30), Vector2(w.x, 30)))
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_corner_radius_all(16)
	edge.set_border_width_all(2)
	edge.border_color = Color(RARITY_EDGE[r], 0.85)
	edge.anti_aliasing = true
	c.draw_style_box(edge, Rect2(Vector2.ZERO, w))
	if count > 1:
		c.draw_string(_num_font, Vector2(0, w.y - 8), str(count), HORIZONTAL_ALIGNMENT_CENTER, w.x, 22, PALE)
	if equipped:
		var e := Vector2(18, 18)
		c.draw_colored_polygon(PackedVector2Array([e + Vector2(0, -9), e + Vector2(9, 0), e + Vector2(0, 9), e + Vector2(-9, 0)]), GOLD)
		c.draw_string(_num_font, Vector2(0, w.y - 8), "In hand", HORIZONTAL_ALIGNMENT_CENTER, w.x, 18, GOLD)
	if dim:
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color(0.02, 0.02, 0.06, 0.5)
		shade.set_corner_radius_all(16)
		c.draw_style_box(shade, Rect2(Vector2.ZERO, w))
	if chosen:
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.set_corner_radius_all(20)
		glow.set_border_width_all(3)
		glow.border_color = Color(1.0, 0.92, 0.7)
		glow.shadow_color = Color(GOLD, 0.6)
		glow.shadow_size = 10
		glow.anti_aliasing = true
		c.draw_style_box(glow, Rect2(Vector2(-4, -4), w + Vector2(8, 8)))


func _on_card_input(event: InputEvent, slot: int) -> void:
	if _pressed(event):
		_selected = slot
		_discard_armed = false
		Sfx.play("click", -10.0)
		show_tab("bag")


## The chosen item: a rarity-lit header with the item large, its name,
## kind and stars, its numbers, its story, and what can be done with it.
func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var s = game.play.inventory.get_slot(_selected) if _selected >= 0 else null
	if s == null:
		return
	_detail_card(_detail, s.id)
	var owned := _label("Owned  %d" % game.play.inventory.count(s.id), 22, DIM, _num_font)
	owned.position = Vector2(32, 744)
	_detail.add_child(owned)
	var cat := category(s.id)
	var x := 32.0
	if cat in ["weapon", "tool"]:
		var held: bool = _selected == game.play.hotbar_index
		var b := _button("In hand" if held else "Equip", Vector2(x, 794), Vector2(260, 62), _detail)
		b.disabled = held
		b.pressed.connect(_equip)
		x += 276.0
	elif cat == "food":
		var b := _button("Use", Vector2(x, 794), Vector2(260, 62), _detail)
		b.pressed.connect(_use)
		x += 276.0
	elif Items.kind(s.id) == Items.Kind.RELIC:
		# Relics are worn (three slots) for their effect.
		var worn: bool = game.play.wearing(s.id)
		var full: bool = game.play.relics.size() >= Play3D.RELIC_SLOTS
		var b := _button("Remove" if worn else ("Slots full" if full else "Wear"), Vector2(x, 794), Vector2(260, 62), _detail, not worn)
		b.disabled = not worn and full
		var rid: String = s.id
		b.pressed.connect(func():
			if game.play.wearing(rid):
				game.play.unequip_relic(rid)
			else:
				game.play.equip_relic(rid)
			Sfx.play("craft", -4.0)
			show_tab("bag"))
		x += 276.0
		var worn_l := _label("Worn relics  %d / %d" % [game.play.relics.size(), Play3D.RELIC_SLOTS], 22, GOLD, _num_font)
		worn_l.position = Vector2(300, 744)
		_detail.add_child(worn_l)
	if not (s.id in KEEP) and Items.kind(s.id) != Items.Kind.KEY:
		var d := _button("Confirm?" if _discard_armed else "Discard", Vector2(x, 794), Vector2(260, 62), _detail, false)
		if _discard_armed:
			d.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		d.pressed.connect(_discard)


## Name, kind, stars, picture, numbers and description of `id`, into `p`.
func _detail_card(p: Control, id: String) -> void:
	var d: Dictionary = Items.def(id)
	var r: int = Items.rarity(id)
	var head := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = RARITY_BG[r].darkened(0.15)
	st.corner_radius_top_left = 18
	st.corner_radius_top_right = 18
	st.anti_aliasing = true
	head.add_theme_stylebox_override("panel", st)
	head.size = Vector2(p.size.x, 300)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.draw.connect(func():
		# A soft halo behind the item.
		for k in 6:
			head.draw_circle(Vector2(p.size.x - 170, 150), 150 - k * 22, Color(RARITY_EDGE[r], 0.05)))
	p.add_child(head)
	var name := _label(Items.item_name(id), 36, PALE, _ui_font, true)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.size = Vector2(320, 100)
	name.position = Vector2(30, 22)
	p.add_child(name)
	var kind := _label(_kind_name(id), 22, Color(1, 1, 1, 0.8), _ui_font)
	kind.position = Vector2(32, 136)
	p.add_child(kind)
	var stars := Control.new()
	stars.position = Vector2(30, 180)
	stars.size = Vector2(200, 30)
	stars.draw.connect(_draw_stars.bind(stars, r))
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stars)
	var rarity := _label(Items.RARITY_NAMES[r], 22, RARITY_EDGE[r].lightened(0.2), _ui_font)
	rarity.position = Vector2(32, 214)
	p.add_child(rarity)
	_icon_child(p, id, Vector2(p.size.x - 290, 30), 240.0)
	var y := 326.0
	for stat in _stats_of(id):
		var row := _label(stat[0], 24, DIM, _num_font)
		row.position = Vector2(32, y)
		p.add_child(row)
		var val := _label(stat[1], 24, PALE, _num_font)
		val.position = Vector2(p.size.x - 232, y)
		val.size = Vector2(200, 30)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.add_child(val)
		y += 40.0
	var line := ColorRect.new()
	line.color = Color(LAVENDER, 0.2)
	line.position = Vector2(32, y + 8)
	line.size = Vector2(p.size.x - 64, 1)
	p.add_child(line)
	var desc := _label(String(d.get("desc", "")), 24, Color(0.9, 0.9, 0.98), _num_font)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size = Vector2(p.size.x - 64, 220)
	desc.position = Vector2(32, y + 24)
	p.add_child(desc)


func _draw_stars(c: Control, r: int) -> void:
	for k in r + 1:
		hud.draw_star(c, Vector2(12 + k * 30, 12), 11.0, Color(1.0, 0.86, 0.36))


func _kind_name(id: String) -> String:
	if id == "moonblade":
		return "Signature Weapon"
	match category(id):
		"weapon":
			return "Sword" if Items.kind(id) == Items.Kind.SWORD else "Shield"
		"tool":
			return "Tool"
		"food":
			return "Consumable"
		"treasure":
			return "Treasure"
	return "Material"


func _stats_of(id: String) -> Array:
	var d: Dictionary = Items.def(id)
	var out: Array = []
	if d.has("damage"):
		# Her power with this weapon at her level (DamageCalc.power).
		out.append(["Power", str(int(round(DamageCalc.power({"weapon": float(d.damage), "level": game.play.prog.level}))))])
	if d.has("power"):
		out.append(["Gathering power", str(d.power)])
	if d.has("heal"):
		out.append(["Restores HP", str(int(d.heal))])
	if d.has("max_health"):
		out.append(["Max HP", "+%d" % int(d.max_health)])
	if d.has("glow") and not d.has("heal"):
		out.append(["Restores Stamina", "Full"])
	if d.has("lantern_tier"):
		out.append(["Max Stamina", "+10"])
	return out


func _equip() -> void:
	var inv: Inventory = game.play.inventory
	var to: int = game.play.hotbar_index
	inv.move(_selected, to)
	game.play.select(to)
	_selected = to
	Sfx.play("craft", -4.0)
	show_tab("bag")


func _use() -> void:
	var inv: Inventory = game.play.inventory
	var s = inv.get_slot(_selected)
	if s == null:
		return
	var d: Dictionary = Items.def(s.id)
	var p: Player3D = game.player
	if d.has("max_health"):
		p.max_health += float(d.max_health)
		p.health = p.max_health
		game.play.toast.emit("Max HP +%d" % int(d.max_health))
	if d.has("heal"):
		p.health = minf(p.max_health, p.health + float(d.heal))
	if d.has("glow"):
		p.stamina = p.max_stamina
	if d.has("lantern_tier"):
		p.max_stamina += 10.0
		p.stamina = p.max_stamina
		game.play.toast.emit("Max stamina +10")
	inv.remove_at(_selected, 1)
	Sfx.play("pickup")
	show_tab("bag")


## Discard one of the chosen item (asks once: the button turns to Confirm?).
func _discard() -> void:
	if not _discard_armed:
		_discard_armed = true
		Sfx.play("click", -6.0)
		_fill_detail()
		return
	var inv: Inventory = game.play.inventory
	var s = inv.get_slot(_selected)
	if s == null:
		return
	inv.remove_at(_selected, 1)
	if inv.get_slot(_selected) == null:
		if _selected == game.play.hotbar_index:
			game.play.select(_selected)
		_selected = -1
	_discard_armed = false
	Sfx.play("break", -8.0)
	show_tab("bag")


# -------------------------------------------------------------- quests ---

func _build_quests() -> void:
	var q: Quests3D = game.quests
	var list := _panel(Vector2(84, 6), Vector2(640, 898))
	var rows: Array = []
	for state in ["ready", "active", "done"]:
		for quest in Quests3D.QUESTS:
			if q.state.get(quest.id, "") == state:
				rows.append(quest)
	if rows.is_empty():
		var none := _label("No requests yet.\nTalk to the townsfolk of Starfall Haven:\nthose with a gold  !  have something to ask.", 28, DIM, _ui_font)
		none.position = Vector2(820, 120)
		_body.add_child(none)
		return
	if _quest_sel == "" or not q.state.has(_quest_sel):
		_quest_sel = rows[0].id
	var y := 24.0
	for quest in rows:
		var row := Control.new()
		row.position = Vector2(20, y)
		row.size = Vector2(600, 96)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.draw.connect(_draw_quest_row.bind(row, quest.id))
		row.gui_input.connect(_on_quest_input.bind(quest.id))
		list.add_child(row)
		y += 108.0
	_quest_detail(_quest_sel)


func _draw_quest_row(c: Control, id: String) -> void:
	var q: Quests3D = game.quests
	var quest := q.quest(id)
	var st: String = q.state.get(id, "")
	var sel := id == _quest_sel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.88, 0.7, 0.95) if sel else Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(14)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
	var ink := Color(0.18, 0.13, 0.08) if sel else PALE
	c.draw_string(_ui_font, Vector2(24, 42), quest.title, HORIZONTAL_ALIGNMENT_LEFT, 440, 28, ink)
	var giver: String = q.speakers.get(quest.giver, {}).get("name", "")
	c.draw_string(_num_font, Vector2(24, 76), giver, HORIZONTAL_ALIGNMENT_LEFT, 300, 20, ink.lerp(Color(0.5, 0.5, 0.6), 0.4))
	var badge := {"active": "In progress", "ready": "Report back", "done": "Completed"}[st] as String
	var badge_col := {"active": Color(0.45, 0.75, 1.0), "ready": GOLD, "done": Color(0.55, 0.85, 0.5)}[st] as Color
	c.draw_string(_num_font, Vector2(330, 76), badge, HORIZONTAL_ALIGNMENT_RIGHT, 250, 20, badge_col.darkened(0.35) if sel else badge_col)
	if id == q.tracked:
		c.draw_colored_polygon(PackedVector2Array([Vector2(c.size.x - 34, 22), Vector2(c.size.x - 24, 32),
			Vector2(c.size.x - 34, 42), Vector2(c.size.x - 44, 32)]), Color(0.7, 0.5, 0.15) if sel else GOLD)


func _on_quest_input(event: InputEvent, id: String) -> void:
	if _pressed(event):
		_quest_sel = id
		Sfx.play("click", -10.0)
		show_tab("book")


func _quest_detail(id: String) -> void:
	var q: Quests3D = game.quests
	var quest := q.quest(id)
	var st: String = q.state.get(id, "")
	var p := _panel(Vector2(760, 6), Vector2(1076, 898))
	var title := _label(quest.title, 46, GOLD, _title_font)
	title.position = Vector2(48, 36)
	p.add_child(title)
	var who: Dictionary = q.speakers.get(quest.giver, {})
	var from := _label("From  %s, %s" % [who.get("name", ""), who.get("title", "")], 24, DIM, _ui_font)
	from.position = Vector2(50, 112)
	p.add_child(from)
	var task := _label(String(quest.get("task", "")), 30, PALE, _num_font)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task.size = Vector2(980, 120)
	task.position = Vector2(50, 190)
	p.add_child(task)
	var status := ""
	match st:
		"ready":
			status = "Done! Return to %s." % who.get("name", "")
		"done":
			status = "Completed."
		_:
			var tr: Dictionary = q.tracker() if q.tracked == id else {}
			if quest.goal in ["kill", "shards", "item"]:
				status = "Progress  %d / %d" % [mini(int(q.progress.get(id, 0)), int(quest.count)), int(quest.count)]
			elif tr.get("target") != null:
				status = "%d m away" % int(game.player.global_position.distance_to(tr.target))
	var stl := _label(status, 28, GOLD, _num_font)
	stl.position = Vector2(50, 330)
	p.add_child(stl)
	var rw := _label("Rewards", 30, PALE, _ui_font)
	rw.position = Vector2(50, 430)
	p.add_child(rw)
	var x := 50.0
	for r in quest.reward:
		var card := Control.new()
		card.position = Vector2(x, 490)
		card.size = Vector2(124, 154)
		card.draw.connect(_draw_reward.bind(card, r[0], r[1]))
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(card)
		_icon_child(card, r[0], Vector2(13, 10), 98.0)
		var nm := _label(Items.item_name(r[0]), 20, DIM, _num_font)
		nm.position = Vector2(x - 20, 652)
		nm.size = Vector2(164, 30)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(nm)
		x += 168.0
	if st == "active" or st == "ready":
		var tb := _button("Tracking" if q.tracked == id else "Track", Vector2(780, 800), Vector2(250, 64), p)
		tb.disabled = q.tracked == id
		tb.pressed.connect(_track.bind(id))


func _draw_reward(c: Control, id: String, count: int) -> void:
	var r: int = Items.rarity(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = RARITY_BG[r]
	sb.set_corner_radius_all(12)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(c.size.x, c.size.y - 34)))
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.93, 0.9, 0.84)
	strip.corner_radius_bottom_left = 12
	strip.corner_radius_bottom_right = 12
	c.draw_style_box(strip, Rect2(Vector2(0, c.size.y - 34), Vector2(c.size.x, 34)))
	c.draw_string(_num_font, Vector2(0, c.size.y - 9), "×%d" % count, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, Color(0.3, 0.26, 0.22))


func _track(id: String) -> void:
	game.quests.tracked = id
	show_tab("book")


# ----------------------------------------------------------------- map ---

const MAP_RES := 256
const MAP_SPAN := (TerrainGen.HALF + 120.0) * 2.0


func _build_map() -> void:
	if _map_tex == null:
		_map_tex = ImageTexture.create_from_image(_bake_map())
		_regions = _find_regions()
	var frame := _panel(Vector2(84, 6), Vector2(900, 900), Color(0.05, 0.06, 0.15, 0.9), 22)
	var img := TextureRect.new()
	img.texture = _map_tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.position = Vector2(14, 14)
	img.size = Vector2(872, 872)
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(img)
	_map_marks = Control.new()
	_map_marks.position = img.position
	_map_marks.size = img.size
	_map_marks.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_marks.draw.connect(_draw_map_marks)
	_map_marks.gui_input.connect(_on_map_input)
	frame.add_child(_map_marks)
	# Legend.
	var leg := _panel(Vector2(1020, 6), Vector2(816, 900))
	var t := _label("The Starfall", 44, GOLD, _title_font)
	t.position = Vector2(40, 30)
	leg.add_child(t)
	var region := _label(game.world.gen.biome_name(game.world.biome_at(game.player.global_position)), 30, PALE, _ui_font)
	region.position = Vector2(42, 104)
	leg.add_child(region)
	var keys := [["You", Color(0.55, 0.9, 1.0)], ["Starfall Haven", Color(1.0, 0.95, 0.85)],
		["Townsfolk", GOLD], ["Quest goal", GOLD], ["Floating isle", Color(0.85, 0.92, 1.0)],
		["The Starspire", Color(0.75, 0.9, 1.0)], ["The Warden's ruin", Color(0.9, 0.3, 0.32)],
		["Starstone", Color(0.82, 0.62, 1.0)]]
	var y := 190.0
	for k in keys:
		var dot := Control.new()
		dot.position = Vector2(46, y + 6)
		dot.size = Vector2(28, 28)
		dot.draw.connect(_draw_legend_dot.bind(dot, k[0], k[1]))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		leg.add_child(dot)
		var l := _label(k[0], 26, PALE, _num_font)
		l.position = Vector2(92, y)
		leg.add_child(l)
		y += 56.0
	# Fast travel: tap an attuned starstone on the map.
	var ss: Starstones = game.starstones
	var pick: Dictionary = ss.stone(_map_pick) if ss and _map_pick != "" else {}
	var hint := _label("Tap a glowing starstone to travel there." if pick.is_empty() else "Starstone:  " + String(pick.name), 24,
		DIM if pick.is_empty() else PALE, _ui_font)
	hint.position = Vector2(42, 740)
	leg.add_child(hint)
	if not pick.is_empty():
		var go := _button("Travel", Vector2(500, 790), Vector2(270, 64), leg)
		go.pressed.connect(func():
			var id := _map_pick
			_map_pick = ""
			close()
			game.starstones.travel(id))
	var tr: Dictionary = game.quests.tracker()
	var goal := _label("Tracking:  " + String(tr.title), 26, GOLD, _ui_font)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.size = Vector2(740, 80)
	goal.position = Vector2(42, 640)
	leg.add_child(goal)


var _map_pick := ""


func _on_map_input(event: InputEvent) -> void:
	if not _pressed(event) or game.starstones == null:
		return
	var at: Vector2 = event.position
	var best := ""
	var best_d := 30.0
	for s in game.starstones.stones:
		var d := _map_point(s.pos).distance_to(at)
		if game.starstones.attuned.has(s.id) and d < best_d:
			best = s.id
			best_d = d
	if best != "":
		_map_pick = best
		Sfx.play("click", -6.0)
		show_tab("map")


func _draw_legend_dot(c: Control, what: String, col: Color) -> void:
	var m := c.size * 0.5
	match what:
		"Starstone":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -12), m + Vector2(8, 0), m + Vector2(0, 12), m + Vector2(-8, 0)]), col)
		"You":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -12), m + Vector2(9, 9), m + Vector2(0, 4), m + Vector2(-9, 9)]), col)
		"Quest goal":
			c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -12), m + Vector2(10, 0), m + Vector2(0, 12), m + Vector2(-10, 0)]), col)
		"Floating isle":
			c.draw_arc(m, 10, 0, TAU, 24, col, 3.0, true)
		"The Starspire":
			hud.draw_star(c, m, 12.0, col)
		_:
			c.draw_circle(m, 8, col)
			c.draw_arc(m, 8, 0, TAU, 16, Color(0.1, 0.08, 0.05), 1.5)


## The whole island, top down: biome colours, water, hill shading, roads.
func _bake_map() -> Image:
	var gen: TerrainGen = game.world.gen
	var n := MAP_RES
	var cell := MAP_SPAN / n
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = gen.height(-MAP_SPAN * 0.5 + (i + 0.5) * cell, -MAP_SPAN * 0.5 + (j + 0.5) * cell)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.65, -0.45).normalized()
	for j in n:
		for i in n:
			var x := -MAP_SPAN * 0.5 + (i + 0.5) * cell
			var z := -MAP_SPAN * 0.5 + (j + 0.5) * cell
			var h := heights[j * n + i]
			var col: Color
			if h < TerrainGen.WATER:
				var depth := clampf(-h / 18.0, 0.0, 1.0)
				col = Color(0.42, 0.72, 0.86).lerp(Color(0.16, 0.36, 0.62), depth)
			else:
				col = _biome_colour(gen.biome(x, z), h)
				var hx := heights[j * n + mini(i + 1, n - 1)] - heights[j * n + maxi(i - 1, 0)]
				var hz := heights[mini(j + 1, n - 1) * n + i] - heights[maxi(j - 1, 0) * n + i]
				var nor := Vector3(-hx, cell * 2.0, -hz).normalized()
				var shade := clampf(nor.dot(light) * 1.25, 0.55, 1.15)
				col = col * shade
				if gen.paved(x, z) > 0.3:
					col = Color(0.86, 0.8, 0.66)
				if h < TerrainGen.WATER + 1.2:
					col = col.lerp(Color(0.9, 0.86, 0.7), 0.5)
			img.set_pixel(i, j, col)
	return img


func _biome_colour(b: int, h: float) -> Color:
	var col := Color(0.5, 0.7, 0.38)
	match b:
		TerrainGen.Biome.SNOW:
			col = Color(0.9, 0.93, 0.98)
		TerrainGen.Biome.DRY:
			col = Color(0.86, 0.76, 0.5)
		TerrainGen.Biome.BEACH:
			col = Color(0.9, 0.84, 0.62)
		TerrainGen.Biome.VOLCANIC:
			col = Color(0.42, 0.36, 0.36)
		TerrainGen.Biome.DARK_FOREST:
			col = Color(0.27, 0.45, 0.32)
		TerrainGen.Biome.CORRUPTED:
			col = Color(0.5, 0.4, 0.62)
	return col.lightened(clampf((h - 20.0) / 160.0, 0.0, 0.35))


## Each region's heartland: the sample with the most same-region
## neighbours (one label per region, set where it is unmistakable).
var _regions: Array = []


func _find_regions() -> Array:
	var gen: TerrainGen = game.world.gen
	var n := 36
	var cell := MAP_SPAN / n
	var grid := []
	for j in n:
		for i in n:
			var x := -MAP_SPAN * 0.5 + (i + 0.5) * cell
			var z := -MAP_SPAN * 0.5 + (j + 0.5) * cell
			grid.append(gen.biome(x, z) if gen.height(x, z) > TerrainGen.WATER else -1)
	var best := {}
	for j in range(1, n - 1):
		for i in range(1, n - 1):
			var b: int = grid[j * n + i]
			if b < 0 or b == TerrainGen.Biome.BEACH:
				continue
			var score := 0
			for dj in range(-2, 3):
				for di in range(-2, 3):
					var jj := clampi(j + dj, 0, n - 1)
					var ii := clampi(i + di, 0, n - 1)
					if grid[jj * n + ii] == b:
						score += 1
			if not best.has(b) or score > best[b][0]:
				best[b] = [score, Vector3(-MAP_SPAN * 0.5 + (i + 0.5) * cell, 0, -MAP_SPAN * 0.5 + (j + 0.5) * cell)]
	var out := []
	for b in best:
		if b != TerrainGen.Biome.FOREST:  # Greenwood is the town's own label
			out.append([gen.biome_name(b), best[b][1]])
	return out


func _map_point(w: Vector3) -> Vector2:
	return (Vector2(w.x, w.z) / MAP_SPAN + Vector2(0.5, 0.5)) * _map_marks.size


func _draw_map_marks() -> void:
	var c := _map_marks
	# Isles and the Starspire.
	var tops: Array = game.islands.tops
	for i in tops.size():
		var at := _map_point(tops[i][0])
		var r: float = float(tops[i][1]) / MAP_SPAN * c.size.x
		if i == 0:
			c.draw_circle(at, r + 4, Color(0.75, 0.9, 1.0, 0.25))
			hud.draw_star(c, at, 16.0, Color(0.85, 0.95, 1.0))
		else:
			c.draw_arc(at, maxf(r, 6.0), 0, TAU, 28, Color(0.9, 0.95, 1.0, 0.9), 2.5, true)
	# Region names, in small caps with a dark halo.
	for r in _regions:
		var at := _map_point(r[1])
		var txt: String = String(r[0]).to_upper()
		for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			c.draw_string(_ui_font, at + o * 1.5 + Vector2(-100, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(0.05, 0.04, 0.1, 0.75))
		c.draw_string(_ui_font, at + Vector2(-100, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, 200, 18, Color(1.0, 0.96, 0.86, 0.95))
	# The town.
	var town := _map_point(Vector3.ZERO)
	c.draw_circle(town, 11, Color(1.0, 0.95, 0.85))
	c.draw_arc(town, 11, 0, TAU, 24, Color(0.35, 0.25, 0.1), 2.0, true)
	c.draw_string(_ui_font, town + Vector2(16, 8), "Starfall Haven", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1))
	# The Warden's ruin.
	var boss := _map_point(game.play.boss_site)
	c.draw_circle(boss, 9, Color(0.9, 0.3, 0.32))
	c.draw_arc(boss, 9, 0, TAU, 20, Color(1, 0.9, 0.8), 2.0, true)
	# Quest goal.
	var target = game.quests.tracker().target
	if target != null:
		var q := _map_point(target)
		c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -14), q + Vector2(11, 0), q + Vector2(0, 14), q + Vector2(-11, 0)]), GOLD)
		c.draw_polyline(PackedVector2Array([q + Vector2(0, -14), q + Vector2(11, 0), q + Vector2(0, 14), q + Vector2(-11, 0), q + Vector2(0, -14)]), Color(0.3, 0.18, 0.04), 2.0, true)
	# Starstones: violet diamonds, bright once attuned; the chosen one ringed.
	if game.starstones:
		for st in game.starstones.stones:
			var at := _map_point(st.pos)
			var on: bool = game.starstones.attuned.has(st.id)
			var dia := PackedVector2Array([at + Vector2(0, -11), at + Vector2(7, 0), at + Vector2(0, 11), at + Vector2(-7, 0)])
			if on:
				c.draw_circle(at, 13, Color(0.75, 0.55, 1.0, 0.3))
				c.draw_colored_polygon(dia, Color(0.86, 0.68, 1.0))
			else:
				dia.append(dia[0])
				c.draw_polyline(dia, Color(0.86, 0.8, 1.0, 0.6), 2.0, true)
			if st.id == _map_pick:
				c.draw_arc(at, 18, 0, TAU, 32, GOLD, 3.0, true)
	# The heroine.
	var p := _map_point(game.player.global_position)
	var face: float = -game.player.model.rotation.y + PI
	var pts := PackedVector2Array([p + Vector2(0, -16).rotated(face), p + Vector2(11, 12).rotated(face),
		p + Vector2(0, 5).rotated(face), p + Vector2(-11, 12).rotated(face)])
	c.draw_colored_polygon(pts, Color(0.55, 0.9, 1.0))
	pts.append(pts[0])
	c.draw_polyline(pts, Color.WHITE, 2.0, true)


# ---------------------------------------------------------------- craft ---

const CRAFT_FILTERS := [["all", "All"], ["weapon", "Weapons"], ["tool", "Tools"], ["food", "Consumables"],
	["material", "Materials"], ["treasure", "Treasures"]]
var _craft_filter := "all"
var _recipe := -1
var _craft_qty := 1


## What she can make in the field: by hand and at her workbench anywhere,
## the campfire's dishes with her cookpot, anvil work only at the forge in
## Starfall Haven. Blocks and furniture are for the old world, not here.
func _recipes() -> Array:
	var out: Array = []
	for i in Items.recipes.size():
		var r: Array = Items.recipes[i]
		var k: int = Items.kind(r[0])
		if k == Items.Kind.BLOCK or k == Items.Kind.PLACEABLE:
			continue
		out.append(i)
	return out


func _at_forge() -> bool:
	return Vector2(game.player.global_position.x, game.player.global_position.z).distance_to(TerrainGen.VILLAGE) < TerrainGen.VILLAGE_RADIUS * 1.3


func _station_ok(r: Array) -> bool:
	return r[2] != Items.Station.ANVIL or _at_forge()


## How many batches of recipe `r` the bag could make now.
func _batches(r: Array) -> int:
	var inv: Inventory = game.play.inventory
	var n := 999
	for id in r[3]:
		n = mini(n, inv.count(id) / int(r[3][id]))
	return n


func _build_craft() -> void:
	var counts := {"all": 0}
	var shown: Array = []
	for i in _recipes():
		var r: Array = Items.recipes[i]
		var c := category(r[0])
		counts.all += 1
		counts[c] = int(counts.get(c, 0)) + 1
		if _craft_filter == "all" or c == _craft_filter:
			shown.append(i)
	_category_column(CRAFT_FILTERS, _craft_filter, counts, func(f):
		_craft_filter = f
		_recipe = -1
		Sfx.play("click", -8.0)
		show_tab("craft"))
	if _recipe < 0 or not (_recipe in shown):
		_recipe = shown[0] if shown.size() > 0 else -1
		_craft_qty = 1
	var grid_panel := _panel(Vector2(360, 6), Vector2(760, 880), Color(0.06, 0.06, 0.16, 0.55))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 20)
	scroll.size = Vector2(730, 846)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_panel.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for i in shown:
		var r: Array = Items.recipes[i]
		var can := _batches(r) > 0 and _station_ok(r)
		var card := Control.new()
		card.custom_minimum_size = Vector2(SLOT, SLOT)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.draw.connect(_draw_slot_card.bind(card, r[0], int(r[1]), false, i == _recipe, not can))
		var idx: int = i
		card.gui_input.connect(func(ev):
			if _pressed(ev):
				_recipe = idx
				_craft_qty = 1
				Sfx.play("click", -10.0)
				show_tab("craft"))
		grid.add_child(card)
		var icon := _icon_child(card, r[0], Vector2(16, 8), SLOT - 32)
		if icon and not can:
			icon.modulate = Color(1, 1, 1, 0.45)
	var p := _panel(Vector2(1140, 6), Vector2(740, 880))
	if _recipe < 0:
		return
	var rec: Array = Items.recipes[_recipe]
	_detail_card(p, rec[0])
	# Required materials: a small slot for each, have / need beneath.
	var req := _label("Required Materials", 26, PALE, _ui_font)
	req.position = Vector2(32, 560)
	p.add_child(req)
	var x := 32.0
	for id in rec[3]:
		var need: int = int(rec[3][id]) * _craft_qty
		var have: int = game.play.inventory.count(id)
		var cell := Control.new()
		cell.position = Vector2(x, 604)
		cell.size = Vector2(96, 96)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.draw.connect(_draw_slot_card.bind(cell, id, 1, false, false))
		p.add_child(cell)
		_icon_child(cell, id, Vector2(12, 6), 72.0)
		var hn := _label("%d / %d" % [have, need], 22, PALE if have >= need else Color(1.0, 0.55, 0.5), _num_font)
		hn.position = Vector2(x - 10, 704)
		hn.size = Vector2(116, 28)
		hn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(hn)
		x += 116.0
	var where := _label(String(Items.STATION_NAMES[rec[2]]) + ("" if _station_ok(rec) else "  ·  at the forge in Starfall Haven"), 20,
		DIM if _station_ok(rec) else Color(1.0, 0.7, 0.55), _num_font)
	where.position = Vector2(32, 742)
	p.add_child(where)
	# Quantity stepper and the Craft button.
	var most := maxi(1, _batches(rec))
	var minus := _button("-", Vector2(32, 794), Vector2(62, 62), p, false)
	minus.add_theme_font_override("font", _num_font)
	minus.add_theme_font_size_override("font_size", 36)
	minus.disabled = _craft_qty <= 1
	minus.pressed.connect(func():
		_craft_qty = maxi(1, _craft_qty - 1)
		show_tab("craft"))
	var qty := _label("%d" % (_craft_qty * int(rec[1])), 30, PALE, _num_font)
	qty.position = Vector2(98, 804)
	qty.size = Vector2(100, 40)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(qty)
	var plus := _button("+", Vector2(202, 794), Vector2(62, 62), p, false)
	plus.add_theme_font_override("font", _num_font)
	plus.add_theme_font_size_override("font_size", 36)
	plus.disabled = _craft_qty >= most
	plus.pressed.connect(func():
		_craft_qty = mini(most, _craft_qty + 1)
		show_tab("craft"))
	var craft := _button("Craft", Vector2(420, 794), Vector2(288, 62), p)
	craft.disabled = _batches(rec) < _craft_qty or not _station_ok(rec)
	craft.pressed.connect(_do_craft)


func _do_craft() -> void:
	var rec: Array = Items.recipes[_recipe]
	var made := 0
	for k in _craft_qty:
		if game.play.inventory.craft(rec):
			game.play.crafted.emit(String(rec[0]))
			made += 1
	if made > 0:
		Sfx.play("craft")
		game.play.toast.emit("Crafted %s ×%d" % [Items.item_name(rec[0]), made * int(rec[1])])
		if game.quests.has_method("event"):
			game.quests.event("craft", rec[0], made * int(rec[1]))
	_craft_qty = 1
	show_tab("craft")


# ---------------------------------------------------------------- pause ---

const PAUSE_TILES := [["resume", "Resume"], ["bag", "Backpack"], ["craft", "Crafting"], ["book", "Quests"],
	["map", "Map"], ["person", "Character"], ["gear", "Settings"], ["title", "Title"]]


func _build_pause() -> void:
	var w := 168.0
	var gap := 22.0
	var total := PAUSE_TILES.size() * w + (PAUSE_TILES.size() - 1) * gap
	var x0 := 960.0 - total * 0.5
	var sub := _label("The world waits.", 26, DIM, _ui_font)
	sub.position = Vector2(760, 250)
	sub.size = Vector2(400, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(sub)
	for i in PAUSE_TILES.size():
		var key: String = PAUSE_TILES[i][0]
		var tile := Control.new()
		tile.position = Vector2(x0 + i * (w + gap), 330)
		tile.size = Vector2(w, w + 10)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.draw.connect(func():
			var first := i == 0
			var sb := _style(Color(0.1, 0.09, 0.24, 0.86), 18, GOLD if first else Color(LAVENDER, 0.35))
			sb.set_border_width_all(2 if first else 1)
			if first:
				sb.shadow_color = Color(GOLD, 0.35)
				sb.shadow_size = 12
			tile.draw_style_box(sb, Rect2(Vector2.ZERO, tile.size))
			var m := Vector2(w * 0.5, 66)
			match key:
				"resume":
					tile.draw_colored_polygon(PackedVector2Array([m + Vector2(-12, -18), m + Vector2(20, 0), m + Vector2(-12, 18)]), PALE)
				"title":
					tile.draw_rect(Rect2(m + Vector2(-14, -16), Vector2(20, 32)), PALE, false, 3.0)
					tile.draw_line(m + Vector2(0, 0), m + Vector2(22, 0), PALE, 3.0)
					tile.draw_polyline(PackedVector2Array([m + Vector2(15, -7), m + Vector2(22, 0), m + Vector2(15, 7)]), PALE, 3.0)
				_:
					glyph(tile, key, m, PALE, 1.4)
			tile.draw_string(_ui_font, Vector2(0, w - 18), PAUSE_TILES[i][1], HORIZONTAL_ALIGNMENT_CENTER, w, 22, PALE))
		tile.gui_input.connect(func(ev):
			if _pressed(ev):
				_pause_pick(key))
		_body.add_child(tile)
	var hint := _label("Esc  resume   ·   I  backpack   ·   K  crafting   ·   M  map   ·   C  character", 20, Color(DIM, 0.8), _num_font)
	hint.position = Vector2(360, 600)
	hint.size = Vector2(1200, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(hint)


func _pause_pick(key: String) -> void:
	Sfx.play("click", -6.0)
	match key:
		"resume":
			close()
		"title":
			_to_title()
		_:
			show_tab(key)


# ----------------------------------------------------------- character ---

var _char_page := "attributes"


func _build_character() -> void:
	# Left: the pages.
	_category_column([["attributes", "Attributes"], ["arts", "Arts"]], _char_page, {}, func(k):
		_char_page = k
		Sfx.play("click", -8.0)
		show_tab("person"))
	# Middle: the heroine on a rune circle, turning slowly.
	var stage := SubViewportContainer.new()
	stage.position = Vector2(360, 0)
	stage.size = Vector2(700, 900)
	stage.stretch = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(stage)
	var vp := SubViewport.new()
	vp.size = Vector2i(700, 900)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	stage.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.95)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_color = Color(0.75, 0.6, 1.0)
	rim.light_energy = 1.1
	vp.add_child(rim)
	var model := CharacterKit.build("player")
	vp.add_child(model)
	_spin = model
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation("Idle"):
		anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")
	var floor_circle := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.2, 2.2)
	floor_circle.mesh = plane
	var cm := ShaderMaterial.new()
	cm.shader = load("res://scripts/shaders/magic_circle_ui.gdshader")
	cm.set_shader_parameter("strength", 0.9)
	floor_circle.material_override = cm
	vp.add_child(floor_circle)
	floor_circle.position = Vector3(0, 0.01, 0)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 0.95, 4.4)
	cam.rotation.x = -0.05
	vp.add_child(cam)
	# Right: name, level, experience, then the page.
	var p: Player3D = game.player
	var prog: Progression = game.play.prog
	var card := _panel(Vector2(1080, 6), Vector2(800, 880))
	var name := _label("The Starborn", 46, GOLD, _title_font)
	name.position = Vector2(40, 28)
	card.add_child(name)
	var lv := _label("Lv. %d  / %d" % [prog.level, Progression.MAX_LEVEL], 30, PALE, _num_font)
	lv.position = Vector2(42, 104)
	card.add_child(lv)
	var need := Progression.need(prog.level)
	var xp_l := _label("%d / %d XP" % [prog.xp, need], 22, DIM, _num_font)
	xp_l.position = Vector2(520, 110)
	xp_l.size = Vector2(240, 30)
	xp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(xp_l)
	var bar := Control.new()
	bar.position = Vector2(42, 150)
	bar.size = Vector2(718, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		var f := clampf(float(prog.xp) / need, 0.0, 1.0)
		bar.draw_style_box(_style(Color(1, 1, 1, 0.1), 5, Color(0, 0, 0, 0)), Rect2(Vector2.ZERO, bar.size))
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.78, 0.58, 1.0)
		fill.set_corner_radius_all(5)
		bar.draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(bar.size.x * f, bar.size.y))))
	card.add_child(bar)
	if _char_page == "arts":
		_character_arts(card, prog)
		return
	var weapon: String = game.play.held_id()
	var atk := int(round(DamageCalc.power(game.play.attacker_stats())))
	var found: int = game.features.found
	var done := 0
	for qd in Quests3D.QUESTS:
		if game.quests.state.get(qd.id, "") == "done":
			done += 1
	var rows := [["Max HP", "%d" % int(p.max_health)], ["HP", "%d" % ceili(p.health)], ["Max Stamina", "%d" % int(p.max_stamina)],
		["Power", str(atk)], ["Critical", "%d%%  x%.1f" % [int(DamageCalc.CRIT_CHANCE * 100.0), DamageCalc.CRIT_DAMAGE]],
		["Skill points", str(prog.points())],
		["Starshards", "%d / %d" % [found, game.features.total]], ["Quests completed", "%d / %d" % [done, Quests3D.QUESTS.size()]]]
	var y := 196.0
	for r in rows:
		var l := _label(r[0], 26, DIM, _num_font)
		l.position = Vector2(46, y)
		card.add_child(l)
		var v := _label(r[1], 26, PALE, _num_font)
		v.position = Vector2(460, y)
		v.size = Vector2(300, 34)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(v)
		var line := ColorRect.new()
		line.color = Color(LAVENDER, 0.12)
		line.position = Vector2(42, y + 44)
		line.size = Vector2(718, 1)
		card.add_child(line)
		y += 56.0
	if weapon != "":
		var w := Control.new()
		w.position = Vector2(42, 620)
		w.size = Vector2(SLOT, SLOT)
		w.draw.connect(_draw_slot_card.bind(w, weapon, 1, false, false))
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(w)
		_icon_child(w, weapon, Vector2(16, 8), SLOT - 32)
		var wn := _label(Items.item_name(weapon), 32, GOLD, _ui_font)
		wn.position = Vector2(196, 626)
		card.add_child(wn)
		var wd := _label(String(Items.def(weapon).get("desc", "")), 21, DIM, _num_font)
		wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wd.size = Vector2(560, 150)
		wd.position = Vector2(198, 672)
		card.add_child(wd)


## The Moonblade's arts: each with its mark, what it does, and the level
## that opens it (sealed ones dimmed behind a padlock).
func _character_arts(card: Control, prog: Progression) -> void:
	var arts := [["slash", "Violet Slashes", 1, "Her strokes leave violet crescents; three in time make a combo whose finisher hits hardest. The blade parts wood and stone as easily as foes.", "attack"]]
	var keys := {"comet": "E", "phase": "Z", "orbit": "X", "starfall": "Q", "crescent": "hold"}
	for a in ["crescent", "comet", "phase", "orbit", "starfall"]:
		arts.append([a, Progression.ART_NAMES[a], Progression.UNLOCKS[a], Progression.ARTS[a].desc, keys[a]])
	var pts := _label("Skill points:  %d" % prog.points(), 24, GOLD, _num_font)
	pts.position = Vector2(46, 150)
	card.add_child(pts)
	var sc := ScrollContainer.new()
	sc.position = Vector2(30, 190)
	sc.size = Vector2(752, card.size.y - 210)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(sc)
	var list := Control.new()
	list.custom_minimum_size = Vector2(736, arts.size() * 128.0)
	sc.add_child(list)
	var y := 0.0
	for a in arts:
		var key: String = a[0]
		var open: bool = prog.level >= int(a[2])
		var rank: int = prog.rank(key) if Progression.ARTS.has(key) else (1 if open else 0)
		var row := Panel.new()
		row.add_theme_stylebox_override("panel", _style(Color(0.12, 0.1, 0.28, 0.7) if open else Color(0.05, 0.05, 0.12, 0.6), 14,
			Color(GOLD, 0.5) if open else Color(LAVENDER, 0.18)))
		row.position = Vector2(10, y)
		row.size = Vector2(722, 118)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.draw.connect(func():
			var m := Vector2(58, 59)
			row.draw_circle(m, 38, Color(0.2, 0.12, 0.38, 0.9) if open else Color(0.1, 0.1, 0.16, 0.9))
			row.draw_arc(m, 38, 0, TAU, 40, Color(0.85, 0.65, 1.0) if open else Color(1, 1, 1, 0.2), 2.0, true)
			var ink := Color(0.9, 0.78, 1.0) if open else Color(0.5, 0.5, 0.6)
			match key:
				"comet":
					hud._comet_glyph(row, m, ink)
				"starfall":
					hud._rune_glyph(row, m, ink)
				"phase":
					for k in 3:
						row.draw_line(m + Vector2(-20 + k * 8, -14), m + Vector2(-8 + k * 8, 14), Color(ink, 1.0 - k * 0.3), 4.0, true)
					row.draw_circle(m + Vector2(16, 0), 7, ink)
				"orbit":
					row.draw_arc(m, 22, 0, TAU * 0.8, 30, ink, 3.0, true)
					row.draw_line(m + Vector2(18, -14), m + Vector2(26, -26), ink, 4.0, true)
				_:
					row.draw_arc(m + Vector2(6, 0), 22, PI * 0.6, PI * 1.4, 18, ink, 5.0, true)
			if not open:
				hud._locked(row, m, 38, int(a[2]))
			# Rank pips.
			if Progression.ARTS.has(key) and open:
				for k in Progression.MAX_RANK:
					var c := Vector2(132 + k * 22, 98)
					var pts2 := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
					row.draw_colored_polygon(pts2, GOLD if k < rank else Color(1, 1, 1, 0.15)))
		list.add_child(row)
		var t := _label("%s  (%s)" % [a[1], a[4]], 26, PALE if open else DIM, _ui_font)
		t.position = Vector2(120, 8)
		row.add_child(t)
		var d := _label(a[3], 18, Color(0.88, 0.88, 0.96) if open else Color(DIM, 0.7), _num_font)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size = Vector2(450, 56)
		d.position = Vector2(122, 40)
		row.add_child(d)
		if not open:
			var lvl := _label("Awakens at Lv. %d" % int(a[2]), 18, Color(1.0, 0.7, 0.55), _num_font)
			lvl.position = Vector2(560, 12)
			lvl.size = Vector2(150, 24)
			lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(lvl)
		elif Progression.ARTS.has(key):
			if rank < Progression.MAX_RANK:
				var cost := prog.upgrade_cost(key)
				var b := _button("Rank up · %d" % cost, Vector2(584, 34), Vector2(128, 50), row, prog.points() >= cost)
				b.disabled = prog.points() < cost
				b.pressed.connect(func():
					if prog.upgrade(key):
						Sfx.play("magic_cast", -6.0)
						game.call_deferred("autosave")
					show_tab("person"))
			else:
				var mx := _label("Mastered", 18, GOLD, _num_font)
				mx.position = Vector2(584, 44)
				row.add_child(mx)
		y += 128.0


# ------------------------------------------------------------ settings ---

var _settings_sc: ScrollContainer
var _settings_scroll := 0


func _build_settings() -> void:
	var panel := _panel(Vector2(84, 6), Vector2(1752, 898))
	# The rows scroll (drag on a phone) inside the panel.
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, 8)
	sc.size = Vector2(1752, 760)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_settings_sc = sc
	# Keep the place in the list when a choice rebuilds the page.
	var keep := _settings_scroll
	sc.ready.connect(func(): sc.set_deferred("scroll_vertical", keep))
	var p := Control.new()
	sc.add_child(p)
	var y := 14.0
	var rows := [
		["choice", "Graphics preset", ["Low", "Medium", "High", "Ultra"], Settings.quality, _set_quality],
		["toggle", "Shadows", Settings.shadows, _set_shadows],
		["toggle", "Bloom and glow", Settings.bloom, _set_bloom],
		["toggle", "Ambient occlusion", Settings.ao, _set_ao],
		["toggle", "Sun shafts", Settings.sun_shafts, _set_shafts],
		["choice", "Anti-aliasing", ["Off", "FXAA", "MSAA 2x", "MSAA 4x"], Settings.antialiasing, _set_aa],
		["choice", "View distance", ["Near", "Medium", "Far", "Farthest"], Settings.view_distance, _set_view],
		["slider", "Render scale", Settings.render_scale, 0.5, 1.0, _set_scale],
		["choice", "Frame rate", ["30", "60", "Unlimited"], [30, 60, 0].find(Settings.fps_cap), _set_fps],
		["toggle", "Show FPS", Settings.show_fps, _set_show_fps],
		["toggle", "Screen shake", Settings.screen_shake, _set_shake],
		["slider", "Camera sensitivity", Settings.look_sensitivity, 0.4, 2.0, _set_sens],
		["slider", "Button size", Settings.control_scale, 0.7, 1.4, _set_button_size],
		["slider", "Button opacity", Settings.control_opacity, 0.3, 1.0, _set_button_opacity],
		["slider", "Master volume", Settings.master_volume, 0.0, 1.0, _set_master],
		["slider", "Music", Settings.music_volume, 0.0, 1.0, _set_music],
		["slider", "Ambience", Settings.ambient_volume, 0.0, 1.0, _set_ambient],
		["slider", "Sound effects", Settings.sfx_volume, 0.0, 1.0, _set_sfx],
		["slider", "Voices", Settings.voice_volume, 0.0, 1.0, _set_voice],
	]
	for r in rows:
		match r[0]:
			"choice":
				_setting_choice(p, y, r[1], r[2], r[3], r[4])
			"toggle":
				_setting_toggle(p, y, r[1], r[2], r[3])
			"slider":
				_setting_slider(p, y, r[1], r[2], r[3], r[4], r[5])
		y += 74
	p.custom_minimum_size = Vector2(1730, y + 10)
	var resume := _button("Resume", Vector2(1180, 790), Vector2(260, 68), panel)
	resume.pressed.connect(close)
	var title := _button("Title Screen", Vector2(1460, 790), Vector2(260, 68), panel, false)
	title.pressed.connect(_to_title)
	var note := _label("View distance applies the next time the world loads. Scroll for more.", 22, DIM, _num_font)
	note.position = Vector2(60, 812)
	panel.add_child(note)


func _row_label(p: Control, y: float, text: String) -> void:
	var l := _label(text, 30, PALE, _ui_font)
	l.position = Vector2(60, y + 10)
	p.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.06)
	line.position = Vector2(40, y + 66)
	line.size = Vector2(1672, 2)
	p.add_child(line)


func _setting_choice(p: Control, y: float, text: String, options: Array, value: int, apply: Callable) -> void:
	_row_label(p, y, text)
	var w := (790.0 - (options.size() - 1) * 16.0) / options.size()
	for i in options.size():
		var b := _button(options[i], Vector2(900 + i * (w + 16.0), y + 4), Vector2(w, 54), p, i == value)
		b.pressed.connect(_choose.bind(apply, i))


func _choose(apply: Callable, i: int) -> void:
	if is_instance_valid(_settings_sc):
		_settings_scroll = _settings_sc.scroll_vertical
	apply.call(i)
	Settings.save_settings()
	show_tab("gear")


func _setting_toggle(p: Control, y: float, text: String, value: bool, apply: Callable) -> void:
	_row_label(p, y, text)
	var on := _button("On", Vector2(1170, y + 4), Vector2(250, 54), p, value)
	on.pressed.connect(_choose.bind(apply, 1))
	var off := _button("Off", Vector2(1440, y + 4), Vector2(250, 54), p, not value)
	off.pressed.connect(_choose.bind(apply, 0))


func _setting_slider(p: Control, y: float, text: String, value: float, lo: float, hi: float, apply: Callable) -> void:
	_row_label(p, y, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.position = Vector2(900, y + 16)
	s.size = Vector2(790, 40)
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(1, 1, 1, 0.15)
	groove.set_corner_radius_all(6)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	var fill := groove.duplicate() as StyleBoxFlat
	fill.bg_color = GOLD
	s.add_theme_stylebox_override("slider", groove)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.value_changed.connect(_slide.bind(apply))
	p.add_child(s)


func _slide(v: float, apply: Callable) -> void:
	apply.call(v)
	Settings.save_settings()


func _set_quality(i: int) -> void:
	# A preset: shadows, glow and render scale follow it.
	Settings.apply_preset(i)
	Settings.apply_display(get_viewport())
	game.sun.shadow_enabled = Settings.shadows
	game.environment.glow_enabled = Settings.bloom
	game.refresh_depth_fx()


func _set_fps(i: int) -> void:
	Settings.fps_cap = [30, 60, 0][i]
	Settings.apply_display(get_viewport())


func _set_scale(v: float) -> void:
	Settings.render_scale = v
	Settings.apply_display(get_viewport())


func _set_show_fps(on: int) -> void:
	Settings.show_fps = on == 1


func _set_shadows(on: int) -> void:
	Settings.shadows = on == 1
	game.sun.shadow_enabled = Settings.shadows


func _set_bloom(on: int) -> void:
	Settings.bloom = on == 1
	game.environment.glow_enabled = Settings.bloom


func _set_shake(on: int) -> void:
	Settings.screen_shake = on == 1


func _set_sens(v: float) -> void:
	Settings.look_sensitivity = v


func _set_button_size(v: float) -> void:
	Settings.control_scale = v


func _set_button_opacity(v: float) -> void:
	Settings.control_opacity = v


func _set_voice(v: float) -> void:
	Settings.voice_volume = v
	if Settings.has_method("_apply_audio"):
		Settings._apply_audio()


func _set_ao(on: int) -> void:
	Settings.ao = on == 1
	game.refresh_depth_fx()


func _set_shafts(on: int) -> void:
	Settings.sun_shafts = on == 1
	game.refresh_depth_fx()


func _set_aa(i: int) -> void:
	Settings.antialiasing = i
	Settings.apply_display(get_viewport())


func _set_view(i: int) -> void:
	Settings.view_distance = i


func _set_master(v: float) -> void:
	Settings.master_volume = v
	Settings._apply_audio()


func _set_ambient(v: float) -> void:
	Settings.ambient_volume = v
	Settings._apply_audio()


func _set_music(v: float) -> void:
	Settings.music_volume = v
	if Settings.has_method("_apply_audio"):
		Settings._apply_audio()


func _set_sfx(v: float) -> void:
	Settings.sfx_volume = v
	if Settings.has_method("_apply_audio"):
		Settings._apply_audio()


func _to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu3d.tscn")


# ----------------------------------------------------------------- shop ---

var _shop_page := "buy"
var _shop_sel := -1
var _shop_qty := 1


## What Tobin pays for one: more for rarer things; never her own blade,
## coins, keys or relics.
static func sell_price(id: String) -> int:
	if id in KEEP or id == "gold_coin" or Items.kind(id) in [Items.Kind.KEY, Items.Kind.RELIC]:
		return 0
	return 1 + Items.rarity(id) * 3 + int(Items.def(id).get("tier", 0))


func _shop_rows() -> Array:
	var rows: Array = []
	if _shop_page == "buy":
		for t in Items.TRADES:
			rows.append({"id": t[0], "count": int(t[1]), "price": int(t[2])})
	else:
		var inv: Inventory = game.play.inventory
		var seen := {}
		for i in inv.size():
			var st = inv.get_slot(i)
			if st == null or seen.has(st.id) or sell_price(st.id) <= 0:
				continue
			seen[st.id] = true
			rows.append({"id": st.id, "count": 1, "price": sell_price(st.id), "have": inv.count(st.id)})
	return rows


func _build_shop() -> void:
	_category_column([["buy", "Buy"], ["sell", "Sell"]], _shop_page, {}, func(k):
		_shop_page = k
		_shop_sel = -1
		_shop_qty = 1
		Sfx.play("click", -8.0)
		show_tab("shop"))
	var rows := _shop_rows()
	if _shop_sel < 0 or _shop_sel >= rows.size():
		_shop_sel = 0 if rows.size() > 0 else -1
		_shop_qty = 1
	var coins: int = game.play.inventory.count("gold_coin")
	var grid_panel := _panel(Vector2(360, 6), Vector2(760, 880), Color(0.06, 0.06, 0.16, 0.55))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(20, 20)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 40)
	grid_panel.add_child(grid)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(SLOT, SLOT)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var can: bool = _shop_page == "sell" or coins >= int(r.price)
		cell.draw.connect(func():
			_draw_slot_card(cell, r.id, int(r.get("have", r.count)), false, i == _shop_sel, not can)
			cell.draw_string(_num_font, Vector2(0, SLOT + 28), "%d" % int(r.price), HORIZONTAL_ALIGNMENT_CENTER, SLOT - 24, 22, GOLD))
		var idx := i
		cell.gui_input.connect(func(ev):
			if _pressed(ev):
				_shop_sel = idx
				_shop_qty = 1
				Sfx.play("click", -10.0)
				show_tab("shop"))
		grid.add_child(cell)
		_icon_child(cell, r.id, Vector2(16, 8), SLOT - 32)
		_icon_child(cell, "gold_coin", Vector2(SLOT - 30, SLOT + 6), 26.0)
	var p := _panel(Vector2(1140, 6), Vector2(740, 880))
	if rows.is_empty():
		var none := _label("Nothing he wants from you yet." if _shop_page == "sell" else "His stall is bare.", 28, DIM, _ui_font)
		none.position = Vector2(40, 40)
		p.add_child(none)
		return
	var row: Dictionary = rows[_shop_sel]
	_detail_card(p, row.id)
	var most := 1
	if _shop_page == "buy":
		most = maxi(1, coins / maxi(1, int(row.price)))
	else:
		most = maxi(1, int(row.get("have", 1)))
	_shop_qty = clampi(_shop_qty, 1, most)
	var total := int(row.price) * _shop_qty
	var line := _label(("Buy  %d" if _shop_page == "buy" else "Sell  %d") % (_shop_qty * int(row.count)), 28, PALE, _ui_font)
	line.position = Vector2(32, 700)
	p.add_child(line)
	var price := _label("%d" % total, 30, GOLD if (_shop_page == "sell" or total <= coins) else Color(1.0, 0.55, 0.5), _num_font)
	price.position = Vector2(560, 700)
	price.size = Vector2(110, 36)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(price)
	_icon_child(p, "gold_coin", Vector2(676, 698), 38.0)
	var minus := _button("-", Vector2(32, 794), Vector2(62, 62), p, false)
	minus.add_theme_font_override("font", _num_font)
	minus.add_theme_font_size_override("font_size", 36)
	minus.disabled = _shop_qty <= 1
	minus.pressed.connect(func():
		_shop_qty -= 1
		show_tab("shop"))
	var qty := _label("%d" % _shop_qty, 30, PALE, _num_font)
	qty.position = Vector2(98, 804)
	qty.size = Vector2(100, 40)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(qty)
	var plus := _button("+", Vector2(202, 794), Vector2(62, 62), p, false)
	plus.add_theme_font_override("font", _num_font)
	plus.add_theme_font_size_override("font_size", 36)
	plus.disabled = _shop_qty >= most
	plus.pressed.connect(func():
		_shop_qty += 1
		show_tab("shop"))
	var deal := _button("Buy" if _shop_page == "buy" else "Sell", Vector2(420, 794), Vector2(288, 62), p)
	deal.disabled = _shop_page == "buy" and total > coins
	deal.pressed.connect(_trade.bind(row))


func _trade(row: Dictionary) -> void:
	var inv: Inventory = game.play.inventory
	var total := int(row.price) * _shop_qty
	if _shop_page == "buy":
		if inv.count("gold_coin") < total or not inv.can_fit(row.id, int(row.count) * _shop_qty):
			game.play.toast.emit("No room in the bag")
			return
		inv.remove("gold_coin", total)
		inv.add(row.id, int(row.count) * _shop_qty)
		game.play.toast.emit("Bought %s ×%d" % [Items.item_name(row.id), int(row.count) * _shop_qty])
	else:
		if not inv.remove(row.id, _shop_qty):
			return
		inv.add("gold_coin", total)
		game.play.toast.emit("Sold %s ×%d for %d coins" % [Items.item_name(row.id), _shop_qty, total])
	Sfx.play("pickup")
	_shop_qty = 1
	show_tab("shop")
