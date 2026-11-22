class_name GameMenu3D
extends Control
## The game menu behind the round HUD icons, over a frosted, paused world:
##   Bag        item cards by rarity, filters, a detail panel, Use / Equip
##   Quests     the townsfolk's requests: in progress and completed, Track
##   Map        the whole island with hill shading, roads, isles and markers
##   Character  the heroine turning slowly, her stats and weapon
##   Settings   graphics, camera, sound; back to the title
## Opens from the icons, or I/B, J, M, C and Esc; the same key closes it.

const GOLD := Color(0.96, 0.84, 0.56)
const PALE := Color(0.97, 0.96, 1.0)
const DIM := Color(0.72, 0.74, 0.86)
const PANEL := Color(0.07, 0.08, 0.2, 0.82)
const TABS := [["bag", "Bag"], ["book", "Quests"], ["map", "Map"], ["person", "Character"], ["gear", "Settings"]]
## Card colours by rarity (common .. legendary), Genshin-style.
const RARITY_BG := [Color(0.42, 0.44, 0.5), Color(0.27, 0.52, 0.42), Color(0.27, 0.42, 0.7), Color(0.48, 0.36, 0.7),
	Color(0.76, 0.52, 0.24)]
const FILTERS := [["all", "All"], ["weapon", "Weapons"], ["tool", "Tools"], ["material", "Materials"],
	["food", "Food"], ["treasure", "Treasures"]]

var game: Node
var hud: Hud3D
var tab := ""
var is_open := false
var _body: Control
var _title: Label
var _tab_icons: Array = []
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
	# Top bar: the tab's name, the tab icons, and a close button.
	_title = _label("", 50, GOLD, _title_font)
	_title.position = Vector2(84, 30)
	add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(GOLD, 0.45)
	rule.position = Vector2(84, 112)
	rule.size = Vector2(1752, 2)
	add_child(rule)
	for i in TABS.size():
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(72, 72)
		icon.size = Vector2(72, 72)
		icon.anchor_left = 1.0
		icon.anchor_right = 1.0
		icon.position = Vector2(-560 + i * 84, 24)
		icon.draw.connect(_draw_tab_icon.bind(icon, i))
		icon.gui_input.connect(_on_tab_input.bind(TABS[i][0]))
		add_child(icon)
		_tab_icons.append(icon)
	var close := Control.new()
	close.size = Vector2(72, 72)
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.position = Vector2(-124, 24)
	close.draw.connect(_draw_close.bind(close))
	close.gui_input.connect(_on_close_input)
	add_child(close)
	_body = Control.new()
	_body.position = Vector2(0, 130)
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
	tab = which
	_clear()
	for t in TABS:
		if t[0] == which:
			_title.text = t[1]
	for icon in _tab_icons:
		(icon as Control).queue_redraw()
	match which:
		"bag":
			_build_bag()
		"book":
			_build_quests()
		"map":
			_build_map()
		"person":
			_build_character()
		"gear":
			_build_settings()


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
				which = "gear"
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


func _panel(at: Vector2, size: Vector2, colour := PANEL, radius := 18) -> Panel:
	var p := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = colour
	st.set_corner_radius_all(radius)
	st.border_color = Color(GOLD, 0.25)
	st.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", st)
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
	normal.bg_color = Color(0.95, 0.88, 0.7) if primary else Color(0.16, 0.18, 0.34, 0.9)
	normal.set_corner_radius_all(int(size.y * 0.5))
	normal.border_color = GOLD
	normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color(0.16, 0.12, 0.08) if primary else PALE
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, ink)
	parent.add_child(b)
	return b


func _draw_tab_icon(c: Control, i: int) -> void:
	var active: bool = TABS[i][0] == tab
	var m := c.size * 0.5
	c.draw_circle(m, 32, Color(GOLD, 0.95) if active else Color(0.07, 0.08, 0.2, 0.6))
	c.draw_arc(m, 32, 0, TAU, 40, Color(1, 1, 1, 0.6) if not active else Color(1, 1, 1, 0.9), 2.0, true)
	hud.draw_glyph(c, TABS[i][0], Color(0.16, 0.12, 0.08) if active else PALE)


func _draw_close(c: Control) -> void:
	var m := c.size * 0.5
	c.draw_circle(m, 30, Color(0.07, 0.08, 0.2, 0.6))
	c.draw_arc(m, 30, 0, TAU, 40, Color(1, 1, 1, 0.6), 2.0, true)
	c.draw_line(m + Vector2(-11, -11), m + Vector2(11, 11), PALE, 3.5, true)
	c.draw_line(m + Vector2(11, -11), m + Vector2(-11, 11), PALE, 3.5, true)


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
func _icon_child(parent: Control, id: String, at: Vector2, side: float) -> void:
	var tex: Texture2D = Hud3D.icon_for(id)
	if tex == null:
		return
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = at
	t.size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)


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


# ----------------------------------------------------------------- bag ---

var _cards: Array = []   ## [Control, slot index]
var _detail: Panel


func _build_bag() -> void:
	_cards.clear()
	# Filter chips.
	for i in FILTERS.size():
		var f: Array = FILTERS[i]
		var chip := _button(f[1], Vector2(84 + i * 178, 6), Vector2(166, 54), _body, f[0] == _filter)
		chip.add_theme_font_size_override("font_size", 22)
		chip.pressed.connect(_set_filter.bind(f[0]))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(84, 84)
	scroll.size = Vector2(1100, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var inv: Inventory = game.play.inventory
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
		card.custom_minimum_size = Vector2(124, 154)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.draw.connect(_draw_card.bind(card, i))
		card.gui_input.connect(_on_card_input.bind(i))
		grid.add_child(card)
		_icon_child(card, s.id, Vector2(13, 10), 98.0)
		_cards.append([card, i])
	if _selected < 0 or inv.get_slot(_selected) == null or (_filter != "all" and category(inv.get_slot(_selected).id) != _filter):
		_selected = first
	_detail = _panel(Vector2(1220, 6), Vector2(616, 898))
	_fill_detail()
	if first < 0:
		var empty := _label("Nothing here yet.", 30, DIM, _ui_font)
		empty.position = Vector2(120, 120)
		_body.add_child(empty)


func _set_filter(f: String) -> void:
	_filter = f
	_selected = -1
	Sfx.play("click", -8.0)
	show_tab("bag")


func _draw_card(c: Control, slot: int) -> void:
	var s = game.play.inventory.get_slot(slot)
	if s == null:
		return
	var r: int = Items.rarity(s.id)
	var bg: Color = RARITY_BG[r]
	var w := c.size
	# Rarity backdrop: a vertical wash, darker at the top.
	var top := Rect2(Vector2.ZERO, Vector2(w.x, w.y - 34))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 26
	c.draw_style_box(sb, top)
	c.draw_rect(Rect2(Vector2(0, 0), Vector2(w.x, (w.y - 34) * 0.5)), Color(0, 0, 0, 0.12))
	# Count strip.
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.93, 0.9, 0.84)
	strip.corner_radius_bottom_left = 12
	strip.corner_radius_bottom_right = 12
	c.draw_style_box(strip, Rect2(Vector2(0, w.y - 34), Vector2(w.x, 34)))
	var count := str(s.count) if s.count > 1 else ""
	if slot == game.play.hotbar_index:
		count = "Equipped"
	c.draw_string(_num_font, Vector2(0, w.y - 9), count, HORIZONTAL_ALIGNMENT_CENTER, w.x, 22, Color(0.3, 0.26, 0.22))
	# Stars.
	for k in r + 1:
		var p := Vector2(w.x * 0.5 + (k - r * 0.5) * 14, w.y - 46)
		hud.draw_star(c, p, 6.0, Color(1.0, 0.86, 0.36))
	if slot == _selected:
		c.draw_rect(Rect2(Vector2(-3, -3), w + Vector2(6, 6)), Color(1, 1, 1, 0.95), false, 3.0)
		c.draw_rect(Rect2(Vector2(-7, -7), w + Vector2(14, 14)), Color(GOLD, 0.45), false, 2.0)


func _on_card_input(event: InputEvent, slot: int) -> void:
	if _pressed(event):
		_selected = slot
		Sfx.play("click", -10.0)
		for c in _cards:
			(c[0] as Control).queue_redraw()
		_fill_detail()


func _fill_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var s = game.play.inventory.get_slot(_selected) if _selected >= 0 else null
	if s == null:
		return
	var d: Dictionary = Items.def(s.id)
	var r: int = Items.rarity(s.id)
	var head := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = RARITY_BG[r].darkened(0.1)
	st.corner_radius_top_left = 18
	st.corner_radius_top_right = 18
	head.add_theme_stylebox_override("panel", st)
	head.size = Vector2(616, 300)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(head)
	var name := _label(Items.item_name(s.id), 38, PALE, _ui_font, true)
	name.position = Vector2(28, 20)
	name.size = Vector2(560, 50)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(name)
	var kind := _label(_kind_name(s.id), 22, Color(1, 1, 1, 0.8), _ui_font)
	kind.position = Vector2(30, 78)
	_detail.add_child(kind)
	var stars := Control.new()
	stars.position = Vector2(30, 120)
	stars.size = Vector2(200, 30)
	stars.draw.connect(_draw_stars.bind(stars, r))
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(stars)
	var rarity := _label(Items.RARITY_NAMES[r], 22, Color(1.0, 0.9, 0.6), _ui_font)
	rarity.position = Vector2(30, 150)
	_detail.add_child(rarity)
	var tex: Texture2D = Hud3D.icon_for(s.id)
	if tex:
		var big := TextureRect.new()
		big.texture = tex
		big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		big.position = Vector2(340, 40)
		big.size = Vector2(240, 240)
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail.add_child(big)
	var y := 330.0
	for stat in _stats_of(s.id):
		var row := _label(stat[0], 26, DIM, _num_font)
		row.position = Vector2(30, y)
		_detail.add_child(row)
		var val := _label(stat[1], 26, PALE, _num_font)
		val.position = Vector2(400, y)
		val.size = Vector2(180, 30)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_detail.add_child(val)
		y += 42.0
	var desc := _label(String(d.get("desc", "")), 25, Color(0.88, 0.88, 0.96), _num_font)
	desc.position = Vector2(30, y + 10)
	desc.size = Vector2(556, 200)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	var owned := _label("Owned  %d" % game.play.inventory.count(s.id), 22, DIM, _num_font)
	owned.position = Vector2(30, 760)
	_detail.add_child(owned)
	var cat := category(s.id)
	if cat in ["weapon", "tool"]:
		var b := _button("Equipped" if _selected == game.play.hotbar_index else "Equip", Vector2(330, 810), Vector2(256, 64), _detail)
		b.disabled = _selected == game.play.hotbar_index
		b.pressed.connect(_equip)
	elif cat == "food":
		var b := _button("Use", Vector2(330, 810), Vector2(256, 64), _detail)
		b.pressed.connect(_use)


func _draw_stars(c: Control, r: int) -> void:
	for k in r + 1:
		hud.draw_star(c, Vector2(12 + k * 30, 12), 11.0, Color(1.0, 0.86, 0.36))


func _kind_name(id: String) -> String:
	match category(id):
		"weapon":
			return "Sword" if Items.kind(id) == Items.Kind.SWORD else "Shield"
		"tool":
			return "Gadget"
		"food":
			return "Consumable"
		"treasure":
			return "Treasure"
	return "Material"


func _stats_of(id: String) -> Array:
	var d: Dictionary = Items.def(id)
	var out: Array = []
	if d.has("damage"):
		out.append(["Base ATK", str(int(d.damage))])
	if d.has("power") and category(id) == "tool":
		out.append(["Power", str(d.power)])
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
	task.position = Vector2(50, 190)
	task.size = Vector2(980, 120)
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

const MAP_RES := 200
const MAP_SPAN := (TerrainGen.HALF + 120.0) * 2.0


func _build_map() -> void:
	if _map_tex == null:
		_map_tex = ImageTexture.create_from_image(_bake_map())
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
	_map_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_marks.draw.connect(_draw_map_marks)
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
		["The Starspire", Color(0.75, 0.9, 1.0)], ["The Warden's ruin", Color(0.9, 0.3, 0.32)]]
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
	var tr: Dictionary = game.quests.tracker()
	var goal := _label("Tracking:  " + String(tr.title), 26, GOLD, _ui_font)
	goal.position = Vector2(42, 640)
	goal.size = Vector2(740, 80)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leg.add_child(goal)


func _draw_legend_dot(c: Control, what: String, col: Color) -> void:
	var m := c.size * 0.5
	match what:
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
	# The heroine.
	var p := _map_point(game.player.global_position)
	var face: float = -game.player.model.rotation.y + PI
	var pts := PackedVector2Array([p + Vector2(0, -16).rotated(face), p + Vector2(11, 12).rotated(face),
		p + Vector2(0, 5).rotated(face), p + Vector2(-11, 12).rotated(face)])
	c.draw_colored_polygon(pts, Color(0.55, 0.9, 1.0))
	pts.append(pts[0])
	c.draw_polyline(pts, Color.WHITE, 2.0, true)


# ----------------------------------------------------------- character ---

func _build_character() -> void:
	var stage := SubViewportContainer.new()
	stage.position = Vector2(84, 0)
	stage.size = Vector2(760, 910)
	stage.stretch = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(stage)
	var vp := SubViewport.new()
	vp.size = Vector2i(760, 910)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	stage.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.92)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, -35, 0)
	key.light_energy = 1.3
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_color = Color(0.6, 0.8, 1.0)
	rim.light_energy = 0.9
	vp.add_child(rim)
	var model := CharacterKit.build("player")
	vp.add_child(model)
	_spin = model
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation("Idle"):
		anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
		anim.play("Idle")
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 0.92, 4.4)
	cam.rotation.x = -0.02
	vp.add_child(cam)
	# Stats.
	var p: Player3D = game.player
	var card := _panel(Vector2(900, 6), Vector2(936, 898))
	var name := _label("The Starborn", 52, GOLD, _title_font)
	name.position = Vector2(48, 34)
	card.add_child(name)
	var sub := _label("Chosen of the Fallen Star  ·  Lv. 1", 26, DIM, _ui_font)
	sub.position = Vector2(52, 112)
	card.add_child(sub)
	var weapon: String = game.play.held_id()
	var atk := int(Items.def(weapon).get("damage", 4)) if weapon != "" else 4
	var found: int = game.features.found
	var done := 0
	for qd in Quests3D.QUESTS:
		if game.quests.state.get(qd.id, "") == "done":
			done += 1
	var rows := [["Max HP", "%d" % int(p.max_health)], ["HP", "%d" % ceili(p.health)], ["Max Stamina", "%d" % int(p.max_stamina)],
		["ATK", str(atk)], ["Starshards", "%d / %d" % [found, game.features.total]], ["Quests completed", "%d / %d" % [done, Quests3D.QUESTS.size()]]]
	var y := 200.0
	for r in rows:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.05)
		bar.position = Vector2(40, y - 6)
		bar.size = Vector2(856, 52)
		card.add_child(bar)
		var l := _label(r[0], 28, DIM, _num_font)
		l.position = Vector2(60, y)
		card.add_child(l)
		var v := _label(r[1], 28, PALE, _num_font)
		v.position = Vector2(560, y)
		v.size = Vector2(316, 36)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		card.add_child(v)
		y += 64.0
	if weapon != "":
		var wl := _label("Weapon", 30, PALE, _ui_font)
		wl.position = Vector2(52, 610)
		card.add_child(wl)
		var w := Control.new()
		w.position = Vector2(52, 664)
		w.size = Vector2(124, 154)
		w.draw.connect(_draw_reward.bind(w, weapon, 1))
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(w)
		_icon_child(w, weapon, Vector2(13, 10), 98.0)
		var wn := _label(Items.item_name(weapon), 34, GOLD, _ui_font)
		wn.position = Vector2(210, 690)
		card.add_child(wn)
		var wd := _label(String(Items.def(weapon).get("desc", "")), 22, DIM, _num_font)
		wd.position = Vector2(212, 740)
		wd.size = Vector2(680, 90)
		wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(wd)


# ------------------------------------------------------------ settings ---

func _build_settings() -> void:
	var p := _panel(Vector2(84, 6), Vector2(1752, 898))
	var y := 40.0
	_setting_choice(p, y, "Graphics", ["Low", "Medium", "High"], Settings.quality, _set_quality)
	y += 96
	_setting_toggle(p, y, "Shadows", Settings.shadows, _set_shadows)
	y += 96
	_setting_toggle(p, y, "Bloom and glow", Settings.bloom, _set_bloom)
	y += 96
	_setting_toggle(p, y, "Screen shake", Settings.screen_shake, _set_shake)
	y += 96
	_setting_slider(p, y, "Camera sensitivity", game.input.mouse_sensitivity / 0.0032, 0.4, 2.0, _set_sens)
	y += 96
	_setting_slider(p, y, "Music", Settings.music_volume, 0.0, 1.0, _set_music)
	y += 96
	_setting_slider(p, y, "Sound effects", Settings.sfx_volume, 0.0, 1.0, _set_sfx)
	var resume := _button("Resume", Vector2(1180, 790), Vector2(260, 68), p)
	resume.pressed.connect(close)
	var title := _button("Title Screen", Vector2(1460, 790), Vector2(260, 68), p, false)
	title.pressed.connect(_to_title)
	var note := _label("Draw distance follows the Graphics setting the next time the world loads.", 22, DIM, _num_font)
	note.position = Vector2(60, 820)
	p.add_child(note)


func _row_label(p: Control, y: float, text: String) -> void:
	var l := _label(text, 30, PALE, _ui_font)
	l.position = Vector2(60, y + 10)
	p.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.06)
	line.position = Vector2(40, y + 74)
	line.size = Vector2(1672, 2)
	p.add_child(line)


func _setting_choice(p: Control, y: float, text: String, options: Array, value: int, apply: Callable) -> void:
	_row_label(p, y, text)
	for i in options.size():
		var b := _button(options[i], Vector2(900 + i * 270, y), Vector2(250, 60), p, i == value)
		b.pressed.connect(_choose.bind(apply, i))


func _choose(apply: Callable, i: int) -> void:
	apply.call(i)
	Settings.save_settings()
	show_tab("gear")


func _setting_toggle(p: Control, y: float, text: String, value: bool, apply: Callable) -> void:
	_row_label(p, y, text)
	var on := _button("On", Vector2(1170, y), Vector2(250, 60), p, value)
	on.pressed.connect(_choose.bind(apply, 1))
	var off := _button("Off", Vector2(1440, y), Vector2(250, 60), p, not value)
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
	Settings.quality = i
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if i >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if i >= 2 else Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = 1.0 if i >= 1 else 0.75


func _set_shadows(on: int) -> void:
	Settings.shadows = on == 1
	game.sun.shadow_enabled = Settings.shadows


func _set_bloom(on: int) -> void:
	Settings.bloom = on == 1
	game.environment.glow_enabled = Settings.bloom


func _set_shake(on: int) -> void:
	Settings.screen_shake = on == 1


func _set_sens(v: float) -> void:
	game.input.mouse_sensitivity = 0.0032 * v


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
