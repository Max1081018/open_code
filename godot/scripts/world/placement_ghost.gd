class_name PlacementGhost
extends Node2D
## A see-through preview of what you are about to build, on the cell it
## will go in: green where it can go, red (with the reason) where it can't.

const TILE := 128.0

var _icon: Sprite2D
var _reason: Label
var _ok := true


func _ready() -> void:
	z_as_relative = false
	z_index = 70
	visible = false
	_icon = Sprite2D.new()
	_icon.position = Vector2(TILE, TILE) * 0.5
	add_child(_icon)
	_reason = Label.new()
	_reason.position = Vector2(-60, -54)
	_reason.size = Vector2(TILE + 120, 40)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.add_theme_font_size_override("font_size", 26)
	_reason.add_theme_color_override("font_color", Color(1, 0.75, 0.7))
	_reason.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.03))
	_reason.add_theme_constant_override("outline_size", 8)
	add_child(_reason)


func show_at(cell: Vector2i, texture: Texture2D, problem: String) -> void:
	visible = true
	position = Vector2(cell) * TILE
	_icon.texture = texture
	if texture:
		var k := TILE * 0.8 / maxf(texture.get_width(), texture.get_height())
		_icon.scale = Vector2(k, k)
	_ok = problem == ""
	_icon.modulate = Color(0.75, 1.0, 0.8, 0.55) if _ok else Color(1.0, 0.55, 0.55, 0.45)
	_reason.text = problem
	queue_redraw()


func hide_ghost() -> void:
	visible = false


func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	var colour := Color(0.5, 1.0, 0.6, 0.85 * pulse) if _ok else Color(1.0, 0.4, 0.35, 0.8)
	draw_rect(Rect2(Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), Color(colour, 0.12))
	draw_rect(Rect2(Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), colour, false, 5.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
