class_name IslandSelect
extends Control
## Where the journey begins: three cards — the Great Jungle (recommended),
## Skybound Isle and the Crystal Coast — each with a preview captured in the
## game itself, a description, difficulty and recommended level. Choosing one
## asks for confirmation, stores it on the profile and emits `chosen(id)`.

signal chosen(id: String)
signal back

var _cards: Array = []
var _pick := ""
var _confirm: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.02, 0.62)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var head := UiKit.label("WHERE DOES YOUR JOURNEY BEGIN?", 44, UiKit.PALE, "title")
	head.position = Vector2(0, 50)
	head.size = Vector2(1920, 80)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(head)
	var sub := UiKit.label("Every shore leads to the same Starfall. You can travel to the others later.", 28, UiKit.DIM, "italic")
	sub.position = Vector2(0, 130)
	sub.size = Vector2(1920, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)
	var hd := UiKit.divider(700)
	hd.position = Vector2(610, 172)
	add_child(hd)
	var i := 0
	for id in Realms.START_ORDER:
		var card := _card(id)
		card.position = Vector2(70 + i * 600, 222)
		add_child(card)
		UiKit.appear(card, 0.08 * i)
		_cards.append(card)
		i += 1
	var b := UiKit.button("Back", func(): back.emit(), "normal", 240)
	b.position = Vector2(90, 980)
	add_child(b)


func _card(id: String) -> Control:
	var d: Dictionary = Realms.STARTS[id]
	var p := UiKit.panel(Vector2(580, 740))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	var img := TextureRect.new()
	img.custom_minimum_size = Vector2(464, 270)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(d.preview):
		img.texture = load(d.preview)
	box.add_child(img)
	var name_row := HBoxContainer.new()
	name_row.add_child(UiKit.label(String(d.name).to_upper(), 30, UiKit.PALE, "title"))
	box.add_child(name_row)
	if d.get("recommended", false):
		box.add_child(UiKit.label("Recommended start", 22, UiKit.GOLD, "italic"))
	var desc := UiKit.label(d.desc, 22, UiKit.PALE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(464, 140)
	box.add_child(desc)
	box.add_child(UiKit.label("Difficulty:  %s" % d.difficulty, 24, UiKit.DIM, "bold"))
	box.add_child(UiKit.label("Recommended level:  %d" % d.level, 24, UiKit.DIM, "bold"))
	box.add_child(UiKit.button("Begin here", _ask.bind(id), "primary" if d.get("recommended", false) else "normal", 464, 76))
	return p


func _ask(id: String) -> void:
	_pick = id
	if _confirm:
		_confirm.queue_free()
	_confirm = ColorRect.new()
	(_confirm as ColorRect).color = Color(0, 0, 0, 0.6)
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var p := UiKit.panel(Vector2(860, 0))
	p.position = Vector2(530, 340)
	_confirm.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	p.add_child(box)
	var t := UiKit.label("Begin on %s?" % Realms.STARTS[id].name, 34, UiKit.PALE, "title")
	box.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.add_child(UiKit.button("Not yet", func(): _confirm.queue_free(), "normal", 320))
	row.add_child(UiKit.button("Begin", _go, "primary", 340))
	box.add_child(row)
	UiKit.appear(p)


func _go() -> void:
	Account.set_start_island(_pick)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(func(): chosen.emit(_pick))
