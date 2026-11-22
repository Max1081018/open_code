class_name Hud3D
extends CanvasLayer
## The in-game HUD, laid out like a modern anime action RPG:
##   top-left   round minimap with north marker and nearby points, quest tracker
##   top-right  round menu icons (bag, map, quests, character, settings)
##   bottom     level, HP bar with numbers; stamina as a gold arc by the hero
##   right      skill buttons: attack, Starfall Slash (E, cooldown ring),
##              Starburst (Q, fills with energy), jump, dash; the gadget slot
##              shows what is in hand (tap or mouse wheel to change)
## plus region titles, a pickup feed, the boss bar and touch controls.

var game: Node
var root: Control
var _title_font: Font
var _ui_font: Font
var _num_font: Font
var _region: Label
var _region_time := 0.0
var _last_biome := -1
var _feed: VBoxContainer
var _boss_box: Control
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss: Enemy3D
var _hp_bar: Control
var _hp_label: Label
var _level: Label
var _minimap: Control
var _quest: Label
var _quest_dist: Label
var _stamina: Control
var _skills: Control
var _gadget_swap: HBoxContainer
var _gadget_time := 0.0
var _gadget_icon: TextureRect
var _crosshair: Control
var touch := false
var _stick_center := Vector2.ZERO
var _stick_touch := -1
var _look_touch := -1
var _stick_knob: Control
var _stick_base: Control

const GOLD := Color(0.96, 0.84, 0.56)
const PALE := Color(0.97, 0.96, 1.0)
const INDIGO := Color(0.07, 0.08, 0.2, 0.62)
const HP_GREEN := Color(0.55, 0.86, 0.38)


func setup(the_game: Node) -> void:
	game = the_game
	layer = 10
	_title_font = load("res://assets/fonts/CinzelDecorative-Bold.ttf")
	var cinzel := FontVariation.new()
	cinzel.base_font = load("res://assets/fonts/Cinzel.ttf")
	cinzel.variation_opentype = {"wght": 600}
	_ui_font = cinzel
	_num_font = load("res://assets/fonts/Fredoka.ttf")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	touch = DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")
	_build_minimap()
	_build_menu_icons()
	_build_vitals()
	_build_skills()
	_build_region()
	_build_feed()
	_build_boss_bar()
	_crosshair = _canvas(Vector2.ZERO, Vector2(1, 1), func(c: Control):
		c.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		c.draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.35), 2.0))
	_place(_crosshair, Vector2(0.5, 0.5), Vector2.ZERO)
	if touch:
		_build_touch()
	dialogue = DialogueBox3D.new()
	add_child(dialogue)
	menu = GameMenu3D.new()
	add_child(menu)
	menu.setup(game, self)
	process_priority = 100  # after everything that asks for prompts this frame
	game.play.toast.connect(_toast)
	game.play.inventory_changed.connect(_show_gadgets)
	_show_gadgets()
	_gadget_time = 0.0


# ------------------------------------------------------------- helpers ---

func _label(text: String, size: int, colour: Color, font: Font, outline := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.12, 0.75))
		l.add_theme_constant_override("outline_size", maxi(4, size / 8))
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Anchor `c` at a point of the screen (0..1 each way) with its top-left
## `offset` pixels from there.
func _place(c: Control, anchor: Vector2, offset: Vector2) -> void:
	var size := c.size
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + maxf(size.x, 1.0)
	c.offset_bottom = offset.y + maxf(size.y, 1.0)


func _canvas(at: Vector2, size: Vector2, painter: Callable) -> Control:
	var c := Control.new()
	c.position = at
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(painter.bind(c))
	root.add_child(c)
	return c


static func icon_for(id: String) -> Texture2D:
	var path := "res://assets/icons3d/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else Items.icon(id)


func _ring(c: Control, centre: Vector2, r: float, fill: Color, rim: Color, rim_w := 2.5) -> void:
	c.draw_circle(centre, r, fill)
	c.draw_arc(centre, r, 0, TAU, 64, rim, rim_w, true)


# ------------------------------------------------------------- minimap ---

func _build_minimap() -> void:
	_minimap = _canvas(Vector2(40, 30), Vector2(200, 200), _draw_minimap)
	var diamond := _canvas(Vector2(44, 250), Vector2(24, 24), func(c: Control):
		var m := Vector2(12, 12)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -9), m + Vector2(9, 0), m + Vector2(0, 9), m + Vector2(-9, 0)]), GOLD)
		c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -4), m + Vector2(4, 0), m + Vector2(0, 4), m + Vector2(-4, 0)]), Color(0.3, 0.2, 0.05)))
	_quest = _label("Find the Rusted Warden", 24, PALE, _ui_font)
	_quest.position = Vector2(78, 244)
	root.add_child(_quest)
	_quest_dist = _label("", 20, GOLD, _num_font)
	_quest_dist.position = Vector2(80, 278)
	root.add_child(_quest_dist)


func _draw_minimap(c: Control) -> void:
	var centre := c.size * 0.5
	var r := 96.0
	var p: Player3D = game.player
	var gen: TerrainGen = game.world.gen
	# Ground colours around the player, sampled coarsely (radius ~120 m).
	var step := 16.0
	var scale := 120.0 / r
	var yaw: float = game.cam.yaw
	for gy in range(-6, 7):
		for gx in range(-6, 7):
			var local := Vector2(gx, gy) * step
			if local.length() > r - 4:
				continue
			# Map rotates with the camera, forward is up.
			var world_off := local.rotated(-yaw) * scale
			var wx := p.global_position.x + world_off.x
			var wz := p.global_position.z + world_off.y
			var h := gen.height(wx, wz)
			var col := Color(0.45, 0.62, 0.36)
			if h < TerrainGen.WATER:
				col = Color(0.32, 0.55, 0.78)
			else:
				match gen.biome(wx, wz):
					TerrainGen.Biome.SNOW:
						col = Color(0.86, 0.9, 0.96)
					TerrainGen.Biome.DRY, TerrainGen.Biome.BEACH:
						col = Color(0.85, 0.76, 0.52)
					TerrainGen.Biome.VOLCANIC:
						col = Color(0.42, 0.36, 0.36)
					TerrainGen.Biome.DARK_FOREST:
						col = Color(0.27, 0.42, 0.3)
					TerrainGen.Biome.CORRUPTED:
						col = Color(0.48, 0.38, 0.6)
				col = col.lightened(clampf((h - 10.0) / 120.0, 0.0, 0.3))
			c.draw_circle(centre + local, step * 0.75, col)
	# Frame: dark edge and gold rim.
	c.draw_arc(centre, r + 6, 0, TAU, 96, Color(0.06, 0.07, 0.18, 0.85), 14.0, true)
	c.draw_arc(centre, r + 12, 0, TAU, 96, GOLD, 2.0, true)
	# Boss arena marker.
	var to_boss: Vector3 = game.play.boss_site - p.global_position
	var mark := Vector2(to_boss.x, to_boss.z).rotated(yaw) / scale
	if mark.length() > r - 10:
		mark = mark.normalized() * (r - 10)
	c.draw_circle(centre + mark, 7, Color(0.85, 0.25, 0.3))
	c.draw_arc(centre + mark, 7, 0, TAU, 16, Color(1, 0.9, 0.8), 2.0)
	# Townsfolk (gold dots) and the tracked quest's goal (a gold diamond).
	if game.get("quests"):
		for n in game.quests.npcs.values():
			var to_n: Vector3 = (n as Node3D).global_position - p.global_position
			var nm := Vector2(to_n.x, to_n.z).rotated(yaw) / scale
			if nm.length() < r - 6:
				c.draw_circle(centre + nm, 5, GOLD)
				c.draw_arc(centre + nm, 5, 0, TAU, 12, Color(0.2, 0.12, 0.02), 1.5)
		var target = game.quests.tracker().target
		if target != null:
			var to_t: Vector3 = target - p.global_position
			var tm := Vector2(to_t.x, to_t.z).rotated(yaw) / scale
			if tm.length() > r - 12:
				tm = tm.normalized() * (r - 12)
			var q := centre + tm
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -11), q + Vector2(9, 0), q + Vector2(0, 11), q + Vector2(-9, 0)]), GOLD)
			c.draw_polyline(PackedVector2Array([q + Vector2(0, -11), q + Vector2(9, 0), q + Vector2(0, 11), q + Vector2(-9, 0), q + Vector2(0, -11)]), Color(0.25, 0.14, 0.02), 2.0, true)
	# North marker.
	var north := Vector2(0, -1).rotated(yaw) * (r + 6)
	c.draw_circle(centre + north, 11, Color(0.08, 0.09, 0.2))
	c.draw_string(_num_font, centre + north + Vector2(-6, 7), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PALE)
	# The player: an arrow pointing where they face.
	var face: float = -p.model.rotation.y + yaw + PI
	var tip := centre + Vector2(0, -14).rotated(face)
	var l := centre + Vector2(-8, 9).rotated(face)
	var rr := centre + Vector2(8, 9).rotated(face)
	c.draw_colored_polygon(PackedVector2Array([tip, rr, centre + Vector2(0, 4).rotated(face), l]), Color(0.55, 0.9, 1.0))
	c.draw_polyline(PackedVector2Array([tip, rr, centre + Vector2(0, 4).rotated(face), l, tip]), Color.WHITE, 2.0, true)


# --------------------------------------------------------- menu icons ---

func _build_menu_icons() -> void:
	var icons := ["bag", "map", "book", "person", "gear"]
	for i in icons.size():
		var kind: String = icons[i]
		var c := _canvas(Vector2.ZERO, Vector2(64, 64), func(cv: Control): _draw_icon(cv, kind))
		_place(c, Vector2(1, 0), Vector2(-100 - (icons.size() - 1 - i) * 78, 30))


func _draw_icon(c: Control, kind: String) -> void:
	_ring(c, c.size * 0.5, 28, Color(0.07, 0.08, 0.2, 0.45), Color(1, 1, 1, 0.55), 2.0)
	draw_glyph(c, kind, Color(0.98, 0.97, 1.0))


## The line glyph of a menu icon, centred in `c`.
func draw_glyph(c: Control, kind: String, w: Color) -> void:
	var m := c.size * 0.5
	match kind:
		"bag":
			c.draw_rect(Rect2(m + Vector2(-12, -6), Vector2(24, 20)), w, false, 2.5)
			c.draw_arc(m + Vector2(0, -6), 7, PI, TAU, 12, w, 2.5)
			c.draw_line(m + Vector2(-12, 2), m + Vector2(12, 2), w, 2.0)
		"map":
			var pts := PackedVector2Array([m + Vector2(-14, -10), m + Vector2(-5, -13), m + Vector2(5, -10), m + Vector2(14, -13),
				m + Vector2(14, 11), m + Vector2(5, 14), m + Vector2(-5, 11), m + Vector2(-14, 14), m + Vector2(-14, -10)])
			c.draw_polyline(pts, w, 2.5, true)
			c.draw_line(m + Vector2(-5, -13), m + Vector2(-5, 11), w, 1.5)
			c.draw_line(m + Vector2(5, -10), m + Vector2(5, 14), w, 1.5)
		"book":
			c.draw_rect(Rect2(m + Vector2(-13, -12), Vector2(12, 24)), w, false, 2.5)
			c.draw_rect(Rect2(m + Vector2(1, -12), Vector2(12, 24)), w, false, 2.5)
		"person":
			c.draw_circle(m + Vector2(0, -7), 6, w)
			c.draw_arc(m + Vector2(0, 14), 12, PI, TAU, 16, w, 3.0)
		"gear":
			for k in 8:
				var a := k * TAU / 8.0
				c.draw_line(m + Vector2.from_angle(a) * 9, m + Vector2.from_angle(a) * 15, w, 4.0)
			c.draw_arc(m, 10, 0, TAU, 24, w, 3.0)
			c.draw_circle(m, 4, w)


## A four-pointed star (for rarity and the Starspire).
func draw_star(c: Control, at: Vector2, r: float, col: Color) -> void:
	_star(c, at, r, col)


# -------------------------------------------------------------- vitals ---

func _build_vitals() -> void:
	_level = _label("Lv. 1", 24, PALE, _num_font)
	root.add_child(_level)
	_place(_level, Vector2(0.5, 1), Vector2(-320, -74))
	_hp_bar = _canvas(Vector2.ZERO, Vector2(480, 16), _draw_hp)
	_place(_hp_bar, Vector2(0.5, 1), Vector2(-240, -64))
	_hp_label = _label("", 18, PALE, _num_font)
	root.add_child(_hp_label)
	_place(_hp_label, Vector2(0.5, 1), Vector2(-40, -98))
	# Stamina: a gold arc beside the hero (centre-right of the screen).
	_stamina = _canvas(Vector2.ZERO, Vector2(1, 1), _draw_stamina)
	_place(_stamina, Vector2(0.5, 0.5), Vector2(110, -20))


func _draw_hp(c: Control) -> void:
	var p: Player3D = game.player
	var f := clampf(p.health / p.max_health, 0.0, 1.0)
	var rect := Rect2(Vector2.ZERO, c.size)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.1, 0.65)
	back.set_corner_radius_all(8)
	back.border_color = Color(1, 1, 1, 0.3)
	back.set_border_width_all(1)
	c.draw_style_box(back, rect)
	if f > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = HP_GREEN if f > 0.3 else Color(0.9, 0.35, 0.3)
		fill.set_corner_radius_all(8)
		c.draw_style_box(fill, Rect2(Vector2(2, 2), Vector2((c.size.x - 4) * f, c.size.y - 4)))


func _draw_stamina(c: Control) -> void:
	var p: Player3D = game.player
	var f := clampf(p.stamina / p.max_stamina, 0.0, 1.0)
	if f > 0.995:
		return
	var start := PI * 0.75
	var span := PI * 1.5
	c.draw_arc(Vector2.ZERO, 34, start, start + span, 40, Color(0.05, 0.05, 0.1, 0.55), 9.0, true)
	c.draw_arc(Vector2.ZERO, 34, start, start + span * f, 40, GOLD if f > 0.25 else Color(1, 0.45, 0.35), 6.0, true)


# -------------------------------------------------------------- skills ---

func _build_skills() -> void:
	_skills = _canvas(Vector2.ZERO, Vector2(1, 1), _draw_skills)
	_place(_skills, Vector2(1, 1), Vector2.ZERO)
	_gadget_icon = TextureRect.new()
	_gadget_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_gadget_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_gadget_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gadget_icon.size = Vector2(64, 64)
	root.add_child(_gadget_icon)
	_place(_gadget_icon, Vector2(1, 1), SKILL_POS.gadget - Vector2(32, 32))
	_gadget_swap = HBoxContainer.new()
	_gadget_swap.add_theme_constant_override("separation", 10)
	_gadget_swap.modulate.a = 0.0
	root.add_child(_gadget_swap)
	_place(_gadget_swap, Vector2(0.5, 1), Vector2(-300, -190))


## Buttons' centres relative to the bottom-right corner.
const SKILL_POS := {"attack": Vector2(-150, -150), "skill": Vector2(-300, -110), "burst": Vector2(-150, -310),
	"jump": Vector2(-60, -280), "dash": Vector2(-300, -250), "gadget": Vector2(-420, -80),
	"interact": Vector2(-430, -230)}


func _draw_skills(c: Control) -> void:
	var play: Play3D = game.play
	# Attack: big round button with a sword.
	var a: Vector2 = SKILL_POS.attack
	_ring(c, a, 70, Color(0.08, 0.09, 0.2, 0.5), Color(1, 1, 1, 0.6), 3.0)
	c.draw_line(a + Vector2(-26, 26), a + Vector2(24, -24), PALE, 7.0, true)
	c.draw_line(a + Vector2(-30, 14), a + Vector2(-14, 30), PALE, 5.0, true)
	c.draw_line(a + Vector2(-34, 34), a + Vector2(-26, 26), PALE, 6.0, true)
	# Skill (E): a star slash, with a cooldown sweep.
	var s: Vector2 = SKILL_POS.skill
	_ring(c, s, 50, Color(0.18, 0.14, 0.34, 0.75), GOLD, 3.0)
	_star(c, s, 24, Color(0.8, 0.72, 1.0))
	var cd: float = play.skill_cooldown / Play3D.SKILL_COOLDOWN
	if cd > 0.0:
		c.draw_circle(s, 50, Color(0, 0, 0, 0.45))
		c.draw_arc(s, 46, -PI * 0.5, -PI * 0.5 + TAU * cd, 40, Color(1, 1, 1, 0.65), 6.0, true)
		c.draw_string(_num_font, s + Vector2(-14, 10), "%.0f" % ceilf(play.skill_cooldown), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, PALE)
	elif not touch:
		c.draw_string(_num_font, s + Vector2(-8, 76), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PALE)
	# Burst (Q): fills with energy, glows when ready.
	var b: Vector2 = SKILL_POS.burst
	var e: float = play.energy / Play3D.BURST_COST
	var ready := e >= 1.0
	if ready:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 180.0)
		c.draw_circle(b, 66 + pulse * 6, Color(0.55, 0.85, 1.0, 0.25))
	_ring(c, b, 58, Color(0.1, 0.18, 0.4, 0.8), Color(0.6, 0.9, 1.0) if ready else Color(1, 1, 1, 0.4), 3.0)
	c.draw_arc(b, 52, -PI * 0.5, -PI * 0.5 + TAU * clampf(e, 0, 1), 48, Color(0.55, 0.9, 1.0), 6.0, true)
	_star(c, b, 30, Color(0.7, 0.95, 1.0) if ready else Color(0.5, 0.6, 0.75))
	if not touch:
		c.draw_string(_num_font, b + Vector2(-8, 84), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PALE)
	# Interact appears only when there is something to use.
	if _prompt and _prompt.text != "" and touch:
		var ip: Vector2 = SKILL_POS.interact
		_ring(c, ip, 40, Color(0.25, 0.2, 0.08, 0.6), GOLD, 2.5)
		c.draw_circle(ip, 9, GOLD)
	# Jump and dash: small rings.
	for k in ["jump", "dash"]:
		var p: Vector2 = SKILL_POS[k]
		_ring(c, p, 40, Color(0.08, 0.09, 0.2, 0.45), Color(1, 1, 1, 0.5), 2.0)
		if k == "jump":
			c.draw_polyline(PackedVector2Array([p + Vector2(-14, 8), p + Vector2(0, -8), p + Vector2(14, 8)]), PALE, 4.0, true)
		else:
			for o in [-10, 4]:
				c.draw_polyline(PackedVector2Array([p + Vector2(o, -12), p + Vector2(o + 10, 0), p + Vector2(o, 12)]), PALE, 4.0, true)
	# Gadget: what's in hand.
	var g: Vector2 = SKILL_POS.gadget
	_ring(c, g, 44, Color(0.08, 0.09, 0.2, 0.55), GOLD, 2.0)
	# (the item's icon is a TextureRect over this ring: _gadget_icon)


func _star(c: Control, at: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var a := k * PI / 4.0 - PI * 0.5
		pts.append(at + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.38))
	c.draw_colored_polygon(pts, col)


## The bag's tools and weapons in a row for a moment when switching.
func _show_gadgets() -> void:
	var held: String = game.play.held_id()
	_gadget_icon.texture = icon_for(held) if held != "" else null
	for ch in _gadget_swap.get_children():
		ch.queue_free()
	var inv: Inventory = game.play.inventory
	for i in Inventory.HOTBAR_SIZE:
		var stack = inv.get_slot(i)
		if stack == null:
			continue
		var selected: bool = i == game.play.hotbar_index
		var idx := i
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(68, 68)
		cell.draw.connect(func():
			_ring(cell, Vector2(34, 34), 32, Color(0.08, 0.09, 0.2, 0.7), GOLD if selected else Color(1, 1, 1, 0.35), 3.0 if selected else 1.5)
			var tex := icon_for(stack.id)
			if tex:
				cell.draw_texture_rect(tex, Rect2(Vector2(10, 10), Vector2(48, 48)), false)
			if stack.count > 1:
				cell.draw_string(_num_font, Vector2(40, 64), str(stack.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PALE))
		cell.gui_input.connect(func(ev):
			if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
				game.play.select(idx))
		_gadget_swap.add_child(cell)
	_gadget_time = 2.5


# ---------------------------------------------------------- feed, boss ---

func _build_region() -> void:
	_region = _label("", 64, Color(1.0, 0.95, 0.85), _title_font)
	_region.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_region.offset_left = -600
	_region.offset_right = 600
	_region.offset_top = 150
	_region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_region)


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 6)
	root.add_child(_feed)
	_place(_feed, Vector2(1, 0.5), Vector2(-620, -60))


func _toast(text: String) -> void:
	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.18, 0.6)
	st.set_corner_radius_all(14)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", st)
	row.add_child(_label(text, 24, PALE, _num_font, false))
	_feed.add_child(row)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()
	var t := row.create_tween()
	t.tween_interval(2.6)
	t.tween_property(row, "modulate:a", 0.0, 0.6)
	t.tween_callback(row.queue_free)


func _build_boss_bar() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_box.offset_left = -420
	_boss_box.offset_right = 420
	_boss_box.offset_top = 40
	_boss_name = _label("", 34, Color(1.0, 0.86, 0.7), _ui_font)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(840, 14)
	_boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.22, 0.3)
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.04, 0.08, 0.7)
	back.set_corner_radius_all(6)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	_boss_bar.add_theme_stylebox_override("background", back)
	_boss_box.add_child(_boss_bar)
	_boss_box.visible = false
	root.add_child(_boss_box)


var _prompt: Label


var _prompt_req := ""


## Ask for an interaction hint beside the hero this frame ("Open chest").
## Several things may ask; the last one wins. It clears itself next frame.
func prompt(text: String) -> void:
	if text != "":
		_prompt_req = text


func _show_prompt() -> void:
	if _prompt == null:
		_prompt = _label("", 26, PALE, _ui_font)
		root.add_child(_prompt)
		_place(_prompt, Vector2(0.5, 0.5), Vector2(140, 40))
	_prompt.text = ("[F]  " if not touch else "✋  ") + _prompt_req if _prompt_req != "" else ""
	_prompt_req = ""


var dialogue: DialogueBox3D
var menu: GameMenu3D
const MENU_ICONS := ["bag", "map", "book", "person", "gear"]
var _banner: Label
var _banner_sub: Label
var _banner_tween: Tween


## A big title across the screen: "New Quest" / "Quest Complete" and its name.
func banner(title: String, sub: String) -> void:
	if _banner == null:
		_banner = _label("", 30, GOLD, _ui_font)
		_banner_sub = _label("", 52, Color(1.0, 0.97, 0.9), _title_font)
		for l in [_banner, _banner_sub]:
			l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			l.offset_left = -700
			l.offset_right = 700
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(l)
		_banner.offset_top = 236
		_banner_sub.offset_top = 272
	_banner.text = "✦  " + title.to_upper() + "  ✦"
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.4)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.5)
	_banner_tween.chain().tween_interval(2.6)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.7)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.7)


func boss_bar(e: Enemy3D) -> void:
	_boss = e
	_boss_box.visible = e != null
	if e:
		_boss_name.text = e.spec.boss


func _process(delta: float) -> void:
	var p: Player3D = game.player
	if p == null:
		return
	_hp_label.text = "%d / %d" % [ceili(p.health), int(p.max_health)]
	_hp_bar.queue_redraw()
	_stamina.queue_redraw()
	_skills.queue_redraw()
	_minimap.queue_redraw()
	_crosshair.visible = game.cam.first_person
	root.visible = not dialogue.showing and not menu.is_open
	_show_prompt()
	if game.get("quests"):
		var tr: Dictionary = game.quests.tracker()
		_quest.text = tr.title
		var target = tr.target
		var detail: String = tr.detail
		if target != null:
			var dist := "%d m" % int(p.global_position.distance_to(target))
			detail = dist if detail == "" else detail + "  ·  " + dist
		_quest_dist.text = detail
	if _boss:
		_boss_bar.value = maxf(_boss.health, 0.0) / _boss.max_health * 100.0
	_gadget_time -= delta
	_gadget_swap.modulate.a = clampf(_gadget_time, 0.0, 1.0)
	var b: int = game.world.biome_at(p.global_position)
	if b != _last_biome:
		_last_biome = b
		_region.text = game.world.gen.biome_name(b)
		_region_time = 3.5
	_region_time -= delta
	_region.modulate.a = clampf(_region_time, 0.0, 1.0)


# ---------------------------------------------------------------- touch ---

func _build_touch() -> void:
	_stick_base = _canvas(Vector2.ZERO, Vector2(240, 240), func(c: Control):
		c.draw_circle(Vector2(120, 120), 110, Color(0.06, 0.07, 0.18, 0.28))
		c.draw_arc(Vector2(120, 120), 110, 0, TAU, 64, Color(1, 1, 1, 0.3), 2.0, true))
	_place(_stick_base, Vector2(0, 1), Vector2(110, -330))
	_stick_knob = Control.new()
	_stick_knob.size = Vector2(90, 90)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.draw.connect(func(): _stick_knob.draw_circle(Vector2(45, 45), 42, Color(1, 1, 1, 0.42)))
	_stick_base.add_child(_stick_knob)
	_stick_knob.position = Vector2(75, 75)


func _input(event: InputEvent) -> void:
	var screen := root.get_viewport_rect().size
	if event is InputEventScreenTouch or (event is InputEventMouseButton and not Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		var pos: Vector2 = event.position
		var pressed: bool = event.pressed
		var index: int = event.index if event is InputEventScreenTouch else 0
		# The round menu icons (top-right).
		if pressed and not dialogue.showing:
			for i in MENU_ICONS.size():
				var centre := Vector2(screen.x - 100 - (MENU_ICONS.size() - 1 - i) * 78 + 32, 62)
				if pos.distance_to(centre) < 36:
					menu.open(MENU_ICONS[i])
					get_viewport().set_input_as_handled()
					return
		# Skill buttons (bottom-right).
		if pressed:
			for k in SKILL_POS:
				var centre: Vector2 = screen + SKILL_POS[k]
				var radius := 70.0 if k == "attack" else 50.0
				if pos.distance_to(centre) < radius:
					match k:
						"attack":
							game.input.touch_buttons["attack"] = true
						"gadget":
							game.play.select((game.play.hotbar_index + 1) % Inventory.HOTBAR_SIZE)
						_:
							game.input.touch_buttons[k] = true
					get_viewport().set_input_as_handled()
					return
		elif event is InputEventScreenTouch:
			game.input.touch_buttons.erase("attack")
		if not touch or not (event is InputEventScreenTouch):
			return
		if pressed:
			if pos.x < screen.x * 0.4 and pos.y > screen.y * 0.35 and _stick_touch < 0:
				_stick_touch = index
				_stick_center = pos
			elif pos.x >= screen.x * 0.4 and _look_touch < 0:
				_look_touch = index
		else:
			if index == _stick_touch:
				_stick_touch = -1
				game.input.touch_move = Vector2.ZERO
				_stick_knob.position = Vector2(75, 75)
			if index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			var v: Vector2 = (event.position - _stick_center) / 110.0
			v = v.limit_length(1.0)
			game.input.touch_move = Vector2(v.x, -v.y)
			_stick_knob.position = Vector2(75, 75) + v * 70.0
		elif event.index == _look_touch:
			game.input.touch_look += event.relative * 0.005
