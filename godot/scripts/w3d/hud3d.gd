class_name Hud3D
extends CanvasLayer
## The on-screen layer of the open world: health and stamina bars, the region
## name as you enter it, a crosshair in first person, and touch controls
## (move stick, look by dragging the right half, action buttons) on phones.

var game: Node
var _health: ProgressBar
var _stamina: ProgressBar
var _region: Label
var _region_time := 0.0
var _last_biome := -1
var _crosshair: Control


func setup(the_game: Node) -> void:
	game = the_game
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_health = _bar(Color(0.86, 0.22, 0.2), Vector2(40, 36))
	root.add_child(_health)
	_stamina = _bar(Color(0.95, 0.78, 0.3), Vector2(40, 72))
	_stamina.custom_minimum_size = Vector2(300, 14)
	root.add_child(_stamina)
	_region = Label.new()
	_region.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_region.position = Vector2(-400, 90)
	_region.size = Vector2(800, 80)
	_region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region.add_theme_font_size_override("font_size", 54)
	_region.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8))
	_region.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_region.add_theme_constant_override("shadow_offset_y", 3)
	var font = load("res://assets/fonts/LilitaOne-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/LilitaOne-Regular.ttf") else null
	if font:
		_region.add_theme_font_override("font", font)
	root.add_child(_region)
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.draw.connect(func():
		_crosshair.draw_circle(Vector2.ZERO, 3.0, Color(1, 1, 1, 0.85))
		_crosshair.draw_arc(Vector2.ZERO, 11.0, 0, TAU, 24, Color(1, 1, 1, 0.35), 2.0))
	root.add_child(_crosshair)


func _bar(colour: Color, at: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = at
	bar.custom_minimum_size = Vector2(380, 24)
	bar.size = bar.custom_minimum_size
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.07, 0.6)
	back.set_corner_radius_all(6)
	back.border_color = Color(1, 1, 1, 0.25)
	back.set_border_width_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _process(delta: float) -> void:
	var p: Player3D = game.player
	if p == null:
		return
	_health.value = p.health / p.max_health * 100.0
	_stamina.value = p.stamina / p.max_stamina * 100.0
	_stamina.modulate.a = 1.0 if p.stamina < p.max_stamina - 0.5 else 0.35
	_crosshair.visible = game.cam.first_person
	var b: int = game.world.biome_at(p.global_position)
	if b != _last_biome:
		_last_biome = b
		_region.text = game.world.gen.biome_name(b)
		_region_time = 3.5
	_region_time -= delta
	_region.modulate.a = clampf(_region_time, 0.0, 1.0)
