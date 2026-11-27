class_name CharacterSelect
extends Control
## Choose who walks the Starfall. The title screen's live stage stays behind:
## the camera comes in close to Lyra — the very model the game spawns —
## sitting on the isle's rim with her legs swinging; drag to circle her.
## A glass panel on the right gives her name, story, weapon, element and
## stats. Kael is shown locked: his model and animations are not in this
## build. Emits `chosen(id)` after Account stores the choice, or `back`.

signal chosen(id: String)
signal back

const ROSTER := [
	{"id": "heroine", "name": "Lyra", "title": "Starbound Mage-Knight",
		"story": "Found as a child where a star fell, Lyra carries its violet light in her blood and in the Moonblade that answered her. She drifts on her own magic when she rests, and wakes the old Starstones with a touch.",
		"weapon": "Violet Moonblade", "element": "Arcana", "style": "Swift combos, a charged heavy, arts that open as she grows",
		"stats": [["Health", 0.62], ["Power", 0.7], ["Arcana", 0.92], ["Speed", 0.78]]},
	{"id": "hero", "name": "Kael", "title": "Ember Lancer",
		"story": "A wandering lancer from the burning south. His model and animations are not in this build yet.",
		"weapon": "Spear", "element": "Ember", "style": "—", "stats": []},
]

var stage: MenuStage
var _own_stage := false
var _info: VBoxContainer
var _select: Button
var _index := 0
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if stage == null:
		stage = MenuStage.new()
		add_child(stage)
		_own_stage = true
	stage.focus("hero")
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """shader_type canvas_item;
void fragment() { COLOR = vec4(0.01, 0.01, 0.03, (1.0 - smoothstep(0.0, 0.55, UV.x)) * 0.6 + (1.0 - smoothstep(0.0, 0.2, UV.y)) * 0.3); }"""
	shade.material = sm
	add_child(shade)
	var head := UiKit.label("CHOOSE YOUR HERO", 40, UiKit.GOLD, "bold")
	head.position = Vector2(80, 54)
	add_child(head)
	var row := HBoxContainer.new()
	row.position = Vector2(80, 120)
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	for i in ROSTER.size():
		var c: Dictionary = ROSTER[i]
		var playable: bool = Account.CHARACTERS[c.id].playable
		var b := UiKit.button(c.name if playable else c.name + "  ·  locked", _show.bind(i), "primary" if playable else "normal", 240, 60)
		row.add_child(b)
	var hint := UiKit.label("Drag to turn her", 22, UiKit.DIM, "italic")
	hint.position = Vector2(1200, 1010)
	add_child(hint)
	var p := UiKit.panel(Vector2(660, 700))
	p.position = Vector2(80, 200)
	add_child(p)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 14)
	p.add_child(_info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	buttons.position = Vector2(80, 940)
	add_child(buttons)
	buttons.add_child(UiKit.button("Back", _back, "normal", 260))
	_select = UiKit.button("Select", _confirm, "primary", 382)
	buttons.add_child(_select)
	_show(0)
	UiKit.appear(p)


func _show(i: int) -> void:
	_index = i
	var c: Dictionary = ROSTER[i]
	var playable: bool = Account.CHARACTERS[c.id].playable
	for child in _info.get_children():
		child.queue_free()
	_info.add_child(UiKit.label(c.name.to_upper(), 56, UiKit.PALE, "title"))
	_info.add_child(UiKit.label(c.title, 28, UiKit.GOLD, "italic"))
	_info.add_child(UiKit.divider(560))
	var story := UiKit.label(c.story, 24, Color(0.85, 0.85, 0.9))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(560, 0)
	_info.add_child(story)
	for kv in [["Weapon", c.weapon], ["Element", c.element], ["Style", c.style]]:
		var line := HBoxContainer.new()
		var k := UiKit.label(String(kv[0]).to_upper(), 20, UiKit.DIM, "bold")
		k.custom_minimum_size = Vector2(150, 0)
		line.add_child(k)
		var v := UiKit.label(kv[1], 22, UiKit.PALE)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(410, 0)
		line.add_child(v)
		_info.add_child(line)
	for s in c.stats:
		var line := HBoxContainer.new()
		var k := UiKit.label(String(s[0]).to_upper(), 20, UiKit.DIM, "bold")
		k.custom_minimum_size = Vector2(150, 0)
		line.add_child(k)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(410, 26)
		var v: float = s[1]
		bar.draw.connect(func():
			bar.draw_rect(Rect2(0, 12, 410, 2), Color(1, 1, 1, 0.14))
			bar.draw_rect(Rect2(0, 11, 410 * v, 4), UiKit.GOLD)
			var x := 410.0 * v
			bar.draw_colored_polygon(PackedVector2Array([Vector2(x, 7), Vector2(x + 6, 13), Vector2(x, 19), Vector2(x - 6, 13)]), Color(1, 0.95, 0.82)))
		line.add_child(bar)
		_info.add_child(line)
	if not playable:
		_info.add_child(UiKit.label("Coming in a later update", 24, UiKit.ERROR, "bold"))
	_select.disabled = not playable
	if stage and stage.model:
		stage.model.visible = playable


func _back() -> void:
	if stage and not _own_stage:
		stage.focus("menu")
		stage.turn = 0.0
		if stage.model:
			stage.model.visible = true
	back.emit()


func _confirm() -> void:
	var id: String = ROSTER[_index].id
	if Account.set_character(id):
		_select.disabled = true
		if stage and not _own_stage:
			stage.focus("menu")
			stage.turn = 0.0
		var t := create_tween()
		t.tween_property(self, "modulate:a", 0.0, 0.3)
		t.tween_callback(func(): chosen.emit(id))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and event.position.x > 800
	elif event is InputEventScreenTouch:
		_dragging = event.pressed and event.position.x > 800
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _dragging and stage:
		stage.turn = clampf(stage.turn + event.relative.x * 0.006, -0.9, 0.9)
