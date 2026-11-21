extends CanvasLayer
## Everything drawn over the game: vitals, the hotbar, notifications, the
## touch controls, and the panels that open over the world.

var level: Level
var minimap: Minimap

## Read by main.gd and TouchControls.
var touch_active := false
var pointer_over_ui := false
var can_interact := false

var touch: TouchControls
var _root: Control
var _hearts: HBoxContainer
var _heart_tex := {}
var _glow_bar: Control
var _glow_value := 1.0
var _glow_icon: TextureRect
var _hotbar: HBoxContainer
var _slots: Array[ItemSlot] = []
var _toast_box: VBoxContainer
var _feed: VBoxContainer
var _place_label: Label
var _panel_layer: Control
var _open_panel: Control = null
var _top_buttons: HBoxContainer
var _fps: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: Control
var _boss_fill := 1.0
var dialogue: DialogueBox
var tracker: QuestTracker


func _ready() -> void:
	layer = 10
	# The pause menu lives here, so the HUD must keep running while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)

	for name in ["hud_heart", "hud_heart_half", "hud_heart_empty"]:
		_heart_tex[name] = load("res://assets/props/%s.png" % name)

	_build_vitals()
	_build_hotbar()
	_build_top_buttons()
	_build_messages()

	touch = TouchControls.new()
	touch.level = level
	touch.hud = self
	touch.visible = _is_touch_device()
	_root.add_child(touch)

	_panel_layer = Control.new()
	_panel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_layer)

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_box.offset_top = 30
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	_root.add_child(_boss_box)
	_boss_name = UITheme.title("", 44, UITheme.PAPER)
	_boss_box.add_child(_boss_name)
	_boss_bar = Control.new()
	_boss_bar.custom_minimum_size = Vector2(820, 46)
	_boss_bar.draw.connect(func():
		var r := Rect2(Vector2.ZERO, _boss_bar.size)
		_boss_bar.draw_style_box(UITheme.flat(Color(0.1, 0.05, 0.08, 0.85), 18, Color(0.45, 0.2, 0.2), 4), r)
		var fill := Rect2(Vector2(6, 6), Vector2((r.size.x - 12) * _boss_fill, r.size.y - 12))
		if fill.size.x > 2:
			_boss_bar.draw_style_box(UITheme.flat(UITheme.DANGER, 14), fill))
	_boss_box.add_child(_boss_bar)

	# The map: top right, beside the menu buttons.
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -260 - Minimap.SIZE.x
	minimap.offset_right = -260
	minimap.offset_top = 22
	minimap.offset_bottom = 22 + Minimap.SIZE.y
	_root.add_child(minimap)
	_root.move_child(minimap, _panel_layer.get_index())  # under open panels
	minimap.setup.call_deferred(level)

	tracker = QuestTracker.new()
	_root.add_child(tracker)
	tracker.setup.call_deferred(level)
	dialogue = DialogueBox.new()
	_root.add_child(dialogue)

	_fps = Label.new()
	_fps.position = Vector2(24, 210)
	_fps.add_theme_color_override("font_color", Color.WHITE)
	_fps.add_theme_font_size_override("font_size", 24)
	_root.add_child(_fps)

	var player := level.player
	player.health_changed.connect(func(_h, _m): _refresh_hearts())
	player.glow_changed.connect(func(g, m): _glow_value = g / m)
	player.held_changed.connect(func(_i): _refresh_hotbar())
	player.inventory.changed.connect(_refresh_hotbar)
	Game.notify.connect(_toast)
	Game.item_picked.connect(_picked)
	_refresh_hearts()
	_refresh_hotbar()
	_glow_value = player.glow / player.max_glow()
	get_viewport().size_changed.connect(_update_blocked)
	_update_blocked.call_deferred()


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
		or "--touch" in OS.get_cmdline_user_args()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch_active:
		touch_active = true
		touch.visible = true
	if event is InputEventMouseMotion:
		pointer_over_ui = _over_ui(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB, KEY_I:
				toggle_inventory()
			KEY_ESCAPE:
				if _open_panel:
					close_panel()
				else:
					open_pause()


func _over_ui(p: Vector2) -> bool:
	if _open_panel != null:
		return true
	for rect in touch.blocked_rects:
		if rect.has_point(p):
			return true
	return false


func _update_blocked() -> void:
	touch.blocked_rects.clear()
	touch.blocked_rects.append(_hotbar.get_global_rect().grow(10))
	touch.blocked_rects.append(_top_buttons.get_global_rect().grow(10))
	touch.blocked_rects.append(_hearts.get_parent().get_global_rect())


# =============================================================================
# Vitals
# =============================================================================

func _build_vitals() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(28, 22)
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)

	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 2)
	box.add_child(_hearts)

	var glow_row := HBoxContainer.new()
	glow_row.add_theme_constant_override("separation", 10)
	box.add_child(glow_row)
	_glow_icon = TextureRect.new()
	_glow_icon.texture = load("res://assets/rendered/lantern-glass.png")
	_glow_icon.custom_minimum_size = Vector2(54, 54)
	_glow_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow_row.add_child(_glow_icon)
	_glow_bar = Control.new()
	_glow_bar.custom_minimum_size = Vector2(300, 54)
	_glow_bar.draw.connect(_draw_glow_bar)
	glow_row.add_child(_glow_bar)

	_place_label = Label.new()
	_place_label.add_theme_font_override("font", UITheme.title_font())
	_place_label.add_theme_font_size_override("font_size", 30)
	_place_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_place_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.8))
	_place_label.add_theme_constant_override("outline_size", 10)
	box.add_child(_place_label)


func _refresh_hearts() -> void:
	var player := level.player
	var count := int(ceil(player.max_health / 20.0))
	while _hearts.get_child_count() < count:
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(64, 64)
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_hearts.add_child(heart)
	for i in _hearts.get_child_count():
		var heart: TextureRect = _hearts.get_child(i)
		var fill := clampf((player.health - i * 20.0) / 20.0, 0.0, 1.0)
		heart.texture = _heart_tex.hud_heart if fill > 0.66 else (_heart_tex.hud_heart_half \
			if fill > 0.0 else _heart_tex.hud_heart_empty)
		heart.visible = i < count
	if player.health < player.max_health * 0.3 and player.health > 0:
		var tween := create_tween()
		_hearts.scale = Vector2(1.12, 1.12)
		tween.tween_property(_hearts, "scale", Vector2.ONE, 0.25)


func _draw_glow_bar() -> void:
	var size := _glow_bar.size
	var rect := Rect2(Vector2(0, 10), Vector2(size.x, size.y - 20))
	_glow_bar.draw_style_box(UITheme.flat(Color(0.08, 0.07, 0.14, 0.82), 16,
		Color(0.25, 0.22, 0.38), 3), rect)
	var low := _glow_value < 0.2
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 160.0) if low else 1.0
	var color := UITheme.GLOW.lerp(Color(1.0, 0.55, 0.3), clampf(1.0 - _glow_value * 3.0, 0.0, 1.0))
	var fill := Rect2(rect.position + Vector2(5, 5), Vector2((rect.size.x - 10) * _glow_value, rect.size.y - 10))
	if fill.size.x > 2:
		_glow_bar.draw_style_box(UITheme.flat(Color(color, pulse), 12), fill)
		_glow_bar.draw_rect(Rect2(fill.position + Vector2(8, 3), Vector2(fill.size.x - 16, 4)),
			Color(1, 1, 1, 0.35 * pulse))


# =============================================================================
# Hotbar
# =============================================================================

func _build_hotbar() -> void:
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 8)
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.offset_bottom = -18
	_root.add_child(_hotbar)
	for i in Inventory.HOTBAR_SIZE:
		var slot := ItemSlot.new(104.0)
		slot.pressed.connect(func(): _hotbar_pressed(i))
		_hotbar.add_child(slot)
		_slots.append(slot)


func _hotbar_pressed(index: int) -> void:
	var player := level.player
	if index == player.hotbar_index:
		# A second tap on a selected food or flask uses it: on a phone there
		# is no right mouse button to mean "use this now".
		var slot = player.inventory.get_slot(index)
		if slot != null and Items.kind(slot.id) == Items.Kind.CONSUMABLE:
			player.consume(index)
		return
	player.select_hotbar(index)


func _refresh_hotbar() -> void:
	var player := level.player
	for i in _slots.size():
		var slot = player.inventory.get_slot(i)
		_slots[i].set_item("" if slot == null else slot.id, 0 if slot == null else slot.count)
		_slots[i].selected = i == player.hotbar_index


func _build_top_buttons() -> void:
	_top_buttons = HBoxContainer.new()
	_top_buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_top_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_top_buttons.offset_right = -24
	_top_buttons.offset_top = 22
	_top_buttons.add_theme_constant_override("separation", 14)
	_root.add_child(_top_buttons)
	for spec in [["icon_menu", toggle_inventory], ["icon_pause", open_pause]]:
		var button := TextureButton.new()
		button.texture_normal = load("res://assets/ui/controls/button_circle.png")
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.custom_minimum_size = Vector2(100, 100)
		button.modulate = Color(1, 1, 1, 0.9)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/icons/%s.png" % spec[0])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 24
		icon.offset_top = 24
		icon.offset_right = -24
		icon.offset_bottom = -24
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		button.pressed.connect(spec[1])
		_top_buttons.add_child(button)


# =============================================================================
# Messages
# =============================================================================

func _build_messages() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.offset_top = 150
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(28, 330)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", 6)
	_root.add_child(_feed)


func _toast(text: String, icon: Texture2D) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box("banner_hanging", 30, 22))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	if icon:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(56, 56)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
	var label := UITheme.text(text, 32, UITheme.PAPER)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.06))
	label.add_theme_constant_override("outline_size", 8)
	row.add_child(label)
	_toast_box.add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.2)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func _picked(id: String, count: int) -> void:
	# Merge repeated pickups into one rising line, so mining a seam reads
	# as "+9 Stone" rather than a scroll of nine "+1 Stone".
	for row in _feed.get_children():
		if row.get_meta("id", "") == id and not row.is_queued_for_deletion():
			var total: int = row.get_meta("count") + count
			row.set_meta("count", total)
			row.get_node("Label").text = "+%d %s" % [total, Items.item_name(id)]
			row.set_meta("age", 0.0)
			return
	var row := HBoxContainer.new()
	row.set_meta("id", id)
	row.set_meta("count", count)
	row.set_meta("age", 0.0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = Items.icon(id)
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var label := Label.new()
	label.name = "Label"
	label.text = "+%d %s" % [count, Items.item_name(id)]
	label.add_theme_font_override("font", UITheme.title_font())
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.1))
	label.add_theme_constant_override("outline_size", 10)
	row.add_child(label)
	_feed.add_child(row)
	if _feed.get_child_count() > 5:
		_feed.get_child(0).queue_free()


func show_message(text: String) -> void:
	var panel := _make_panel(Vector2(1000, 0), "A note")
	var body := UITheme.text(text, 36)
	body.custom_minimum_size = Vector2(900, 0)
	panel.get_meta("content").add_child(body)
	_open(panel)


# =============================================================================
# Panels
# =============================================================================

func _make_panel(min_size: Vector2, title: String) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.03, 0.08, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_panel())

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := UITheme.title(title, 54, UITheme.PAPER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close := TextureButton.new()
	close.texture_normal = load("res://assets/ui/panels/button_red_close.png")
	close.ignore_texture_size = true
	close.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close.custom_minimum_size = Vector2(84, 84)
	close.pressed.connect(close_panel)
	header.add_child(close)

	shade.set_meta("content", column)
	return shade


func _open(panel: Control) -> void:
	close_panel()
	_open_panel = panel
	_panel_layer.add_child(panel)
	touch.visible = false
	minimap.visible = false
	panel.modulate.a = 0.0
	var inner: Control = panel.get_child(0).get_child(0)
	inner.pivot_offset = inner.size * 0.5
	inner.scale = Vector2(0.92, 0.92)
	var tween := panel.create_tween().set_parallel()
	tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	tween.tween_property(inner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	Sfx.play("click", -6.0)


func close_panel() -> void:
	if _open_panel == null:
		return
	if _open_panel.has_meta("on_close_callable"):
		_open_panel.get_meta("on_close_callable").call()
	_open_panel.queue_free()
	_open_panel = null
	minimap.visible = true
	get_tree().paused = false
	touch.visible = touch_active or _is_touch_device()
	_refresh_hotbar()


func toggle_inventory() -> void:
	if _open_panel and _open_panel.get_meta("kind", "") == "inventory":
		close_panel()
		return
	var panel := InventoryPanel.build(self, level.player, "")
	panel.set_meta("kind", "inventory")
	_open(panel)


func open_crafting() -> void:
	var panel := InventoryPanel.build(self, level.player, "craft")
	panel.set_meta("kind", "inventory")
	_open(panel)


func open_chest(cell: Vector2i, object: Dictionary) -> void:
	Sfx.play("chest", -2.0)
	var panel := InventoryPanel.build_chest(self, level.player, object)
	_open(panel)


func open_pause() -> void:
	var panel := PauseMenu.build(self)
	_open(panel)
	get_tree().paused = true


func make_panel(min_size: Vector2, title: String) -> Control:
	return _make_panel(min_size, title)


func summon_at_altar(cell: Vector2i) -> void:
	if level.has_method("summon_boss"):
		level.summon_boss(cell)


# =============================================================================
# Frame
# =============================================================================

func _process(delta: float) -> void:
	_glow_bar.queue_redraw()
	_glow_icon.modulate = Color(1, 1, 1, 0.55 + 0.45 * _glow_value)

	for row in _feed.get_children():
		var age: float = row.get_meta("age", 0.0) + delta
		row.set_meta("age", age)
		row.modulate.a = clampf(3.0 - age, 0.0, 1.0)
		if age > 3.0:
			row.queue_free()

	var player := level.player
	var cell := World.cell_of(player.global_position - Vector2(0, 60))
	var data := level.data
	var depth := cell.y - data.surface[clampi(cell.x, 0, data.width - 1)]
	var names := {
		WorldData.Biome.MEADOW: "Greenwood", WorldData.Biome.DESERT: "Sunscorch",
		WorldData.Biome.TUNDRA: "Rimefrost", WorldData.Biome.CRYSTAL: "Crystal Hollows",
		WorldData.Biome.DEPTHS: "The Deep Dark",
	}
	var place: String = names.get(data.biome_at(cell.x, cell.y), "")
	_place_label.text = place if depth < 4 else "%s · %dm" % [place, depth * 2]

	can_interact = false
	for dy in range(-2, 2):
		for dx in range(-3, 4):
			var o := level.world.object_at(cell + Vector2i(dx, dy))
			if o.get("type", "") in ["chest", "workbench", "anvil", "campfire", "sign", "altar",
					"wardstone", "torch", "geode"]:
				can_interact = true
	if level.npc_near() != null:
		can_interact = true
	var boss = level.boss
	_boss_box.visible = boss != null and is_instance_valid(boss) and boss.is_alive()
	if _boss_box.visible:
		_boss_name.text = boss.spec.boss
		_boss_fill = clampf(boss.health / boss.max_health, 0.0, 1.0)
		_boss_bar.queue_redraw()

	_fps.visible = Settings.show_fps
	if _fps.visible:
		_fps.text = "%d fps" % Engine.get_frames_per_second()



# =============================================================================
# Death
# =============================================================================

signal respawn_requested

var _death_screen: Control


## Dimmed screen, a title, where you'll wake, and a button; it goes on by
## itself after a few seconds so a dropped phone doesn't strand you.
func show_death(seconds := 4.0) -> void:
	close_panel()
	if dialogue:
		dialogue.stop()
	_death_screen = Control.new()
	_death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.06, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_screen.add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	_death_screen.add_child(column)
	column.add_child(UITheme.title("You fell", 110, Color(0.95, 0.55, 0.45)))
	var text := UITheme.text("The lantern gutters, but it does not go out.\nIt carries you back to your last light.", 34,
		UITheme.PAPER)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size = Vector2(980, 0)
	column.add_child(text)
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 100)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(button)
	_root.add_child(_death_screen)
	touch.visible = false
	var tween := _death_screen.create_tween()
	tween.tween_property(shade, "color:a", 0.78, 0.8)
	column.modulate.a = 0.0
	tween.parallel().tween_property(column, "modulate:a", 1.0, 0.8)
	var left := [seconds]
	button.text = "Rise  (%d)" % ceili(seconds)
	var done := func():
		if _death_screen == null:
			return
		_death_screen.queue_free()
		_death_screen = null
		touch.visible = touch_active or _is_touch_device()
		respawn_requested.emit()
	button.pressed.connect(done)
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	_death_screen.add_child(timer)
	timer.timeout.connect(func():
		left[0] -= 0.25
		button.text = "Rise  (%d)" % maxi(ceili(left[0]), 0)
		if left[0] <= 0.0:
			done.call())


func death_showing() -> bool:
	return _death_screen != null
