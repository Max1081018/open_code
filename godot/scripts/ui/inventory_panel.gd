class_name InventoryPanel
extends RefCounted
## The bag, crafting, and chests — all touch-first: tap to pick up a stack,
## tap another slot to put it there.


static func build(hud: Node, player: Player, focus: String) -> Control:
	var panel: Control = hud.make_panel(Vector2(1640, 0), "Pack & Crafting")
	var content: VBoxContainer = panel.get_meta("content")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	content.add_child(row)

	var state := {"picked": -1, "slots": [], "player": player, "hud": hud}

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(UITheme.text("Tap a stack, then tap where it goes. The top row is your hotbar.",
		26, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for i in player.inventory.size():
		var slot := ItemSlot.new(94.0)
		grid.add_child(slot)
		state.slots.append(slot)
		slot.pressed.connect(func(): _tap(state, i))

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	details.custom_minimum_size = Vector2(0, 150)
	left.add_child(details)
	state["details"] = details

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size = Vector2(700, 0)
	row.add_child(right)
	var stations := player.nearby_stations()
	var names := []
	for station in stations:
		names.append(Items.STATION_NAMES[station])
	var heading := UITheme.title("Crafting", 42, UITheme.GOLD)
	heading.add_theme_color_override("font_outline_color", Color(0.36, 0.20, 0.10))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	right.add_child(heading)
	right.add_child(UITheme.text("Near: " + ", ".join(names), 26, UITheme.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	state["recipes"] = list
	state["stations"] = stations

	var refresh := func(): _refresh(state)
	state["refresh"] = refresh
	player.inventory.changed.connect(refresh)
	panel.set_meta("on_close_callable", func(): player.inventory.changed.disconnect(refresh))
	_refresh(state)
	return panel


static func _tap(state: Dictionary, index: int) -> void:
	var player: Player = state.player
	var inventory := player.inventory
	if state.picked == -1:
		if inventory.get_slot(index) != null:
			state.picked = index
			Sfx.play("click", -8.0)
	elif state.picked == index:
		state.picked = -1
	else:
		inventory.move(state.picked, index)
		state.picked = -1
		Sfx.play("land", -8.0)
	_refresh(state)


static func _refresh(state: Dictionary) -> void:
	var player: Player = state.player
	var inventory := player.inventory
	for i in state.slots.size():
		var slot: ItemSlot = state.slots[i]
		var stack = inventory.get_slot(i)
		slot.set_item("" if stack == null else stack.id, 0 if stack == null else stack.count)
		slot.selected = i == state.picked
		slot.modulate = Color(1, 1, 1) if i >= Inventory.HOTBAR_SIZE else Color(1.08, 1.04, 0.95)

	var details: VBoxContainer = state.details
	for child in details.get_children():
		child.queue_free()
	var picked = inventory.get_slot(state.picked) if state.picked >= 0 else null
	if picked != null:
		var d := Items.def(picked.id)
		var title := UITheme.title(Items.item_name(picked.id), 40, UITheme.GOLD)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		details.add_child(title)
		var info := []
		if d.has("power"):
			info.append("Mining power %d" % d.power)
		if d.has("damage") and d.kind == Items.Kind.SWORD:
			info.append("Damage %d" % d.damage)
		if d.has("heal"):
			info.append("Heals %d" % d.heal)
		if d.has("glow"):
			info.append("Lantern +%d" % d.glow)
		var text: String = d.get("desc", "")
		if not info.is_empty():
			text = " · ".join(info) + "\n" + text
		var body := UITheme.text(text, 28, UITheme.INK)
		body.custom_minimum_size = Vector2(800, 0)
		details.add_child(body)
		if d.kind == Items.Kind.CONSUMABLE:
			var use := Button.new()
			use.text = "Use"
			use.custom_minimum_size = Vector2(220, 76)
			var index: int = state.picked
			use.pressed.connect(func():
				player.consume(index)
				state.picked = -1
				_refresh(state))
			details.add_child(use)

	var list: VBoxContainer = state.recipes
	for child in list.get_children():
		child.queue_free()
	var ready_first := []
	var later := []
	for recipe in Items.recipes:
		var at_station: bool = recipe[2] in state.stations
		var affordable := inventory.has_all(recipe[3])
		(ready_first if at_station and affordable else later).append(recipe)
	for recipe in ready_first + later:
		list.add_child(_recipe_row(state, recipe))


static func _recipe_row(state: Dictionary, recipe: Array) -> Control:
	var player: Player = state.player
	var inventory := player.inventory
	var at_station: bool = recipe[2] in state.stations
	var affordable := inventory.has_all(recipe[3])
	var can := at_station and affordable

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UITheme.box("panel_brown_dark" if can else "panel_grey_dark", 24, 12))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)

	var icon := TextureRect.new()
	icon.texture = Items.icon(recipe[0])
	icon.custom_minimum_size = Vector2(82, 82)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(icon)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 2)
	line.add_child(middle)
	var name := "%s%s" % [Items.item_name(recipe[0]), " ×%d" % recipe[1] if recipe[1] > 1 else ""]
	var title := UITheme.title(name, 32, UITheme.PAPER if can else Color(0.8, 0.8, 0.82))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	middle.add_child(title)
	var needs := HBoxContainer.new()
	needs.add_theme_constant_override("separation", 10)
	middle.add_child(needs)
	for id in recipe[3]:
		var have := inventory.count(id)
		var want: int = recipe[3][id]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		var small := TextureRect.new()
		small.texture = Items.icon(id)
		small.custom_minimum_size = Vector2(38, 38)
		small.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		small.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(small)
		var amount := Label.new()
		amount.text = "%d/%d" % [min(have, want), want]
		amount.add_theme_font_size_override("font_size", 24)
		amount.add_theme_color_override("font_color",
			Color(0.75, 1.0, 0.65) if have >= want else Color(1.0, 0.55, 0.5))
		chip.add_child(amount)
		needs.add_child(chip)
	if not at_station:
		var where := UITheme.text("Needs a %s nearby" % Items.STATION_NAMES[recipe[2]], 22,
			Color(1.0, 0.86, 0.6))
		middle.add_child(where)

	var craft := Button.new()
	craft.text = "Craft"
	craft.custom_minimum_size = Vector2(170, 80)
	craft.disabled = not can
	craft.pressed.connect(func():
		if inventory.craft(recipe):
			Sfx.play("craft")
			Game.crafted.emit(recipe[0], recipe[1])
			Game.toast("Crafted %s" % Items.item_name(recipe[0]), Items.icon(recipe[0])))
	line.add_child(craft)
	return row


# =============================================================================
# Chests
# =============================================================================

static func build_chest(hud: Node, player: Player, object: Dictionary) -> Control:
	var panel: Control = hud.make_panel(Vector2(1640, 0), "Chest")
	var content: VBoxContainer = panel.get_meta("content")
	content.add_child(UITheme.text("Tap a stack to move it across.", 26, UITheme.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	content.add_child(row)

	var chest := Inventory.new(20)
	chest.from_array(object.get("loot", []))
	var state := {"chest": chest, "player": player, "chest_slots": [], "bag_slots": []}

	var left := GridContainer.new()
	left.columns = 5
	left.add_theme_constant_override("h_separation", 8)
	left.add_theme_constant_override("v_separation", 8)
	row.add_child(left)
	for i in chest.size():
		var slot := ItemSlot.new(104.0)
		left.add_child(slot)
		state.chest_slots.append(slot)
		slot.pressed.connect(func(): _transfer(state, chest, player.inventory, i))

	var right := GridContainer.new()
	right.columns = 8
	right.add_theme_constant_override("h_separation", 8)
	right.add_theme_constant_override("v_separation", 8)
	row.add_child(right)
	for i in player.inventory.size():
		var slot := ItemSlot.new(94.0)
		right.add_child(slot)
		state.bag_slots.append(slot)
		slot.pressed.connect(func(): _transfer(state, player.inventory, chest, i))

	var take_all := Button.new()
	take_all.text = "Take all"
	take_all.custom_minimum_size = Vector2(300, 84)
	take_all.pressed.connect(func():
		for i in chest.size():
			_transfer(state, chest, player.inventory, i))
	content.add_child(take_all)

	panel.set_meta("on_close_callable", func():
		var loot := []
		for stack in chest.to_array():
			if stack != null:
				loot.append(stack)
		object["loot"] = loot)
	_refresh_chest(state)
	return panel


static func _transfer(state: Dictionary, from: Inventory, to: Inventory, index: int) -> void:
	var stack = from.get_slot(index)
	if stack == null:
		return
	var left := to.add(stack.id, stack.count)
	var moved: int = stack.count - left
	if moved > 0:
		from.remove_at(index, moved)
		Sfx.play("pickup", -6.0)
	_refresh_chest(state)


static func _refresh_chest(state: Dictionary) -> void:
	for pair in [[state.chest, state.chest_slots], [state.player.inventory, state.bag_slots]]:
		var inventory: Inventory = pair[0]
		for i in pair[1].size():
			var stack = inventory.get_slot(i)
			pair[1][i].set_item("" if stack == null else stack.id, 0 if stack == null else stack.count)
