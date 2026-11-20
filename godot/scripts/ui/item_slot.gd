class_name ItemSlot
extends Button
## One inventory square: the item's icon, its count, and a selection ring.

var item_id := ""
var count := 0
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()

var _icon: Texture2D
var _count_label: Label


func _init(size_px := 112.0) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	focus_mode = Control.FOCUS_NONE
	add_theme_stylebox_override("normal", UITheme.box("panel_brown_dark", 24, 6))
	add_theme_stylebox_override("hover", UITheme.box("panel_brown_dark", 24, 6))
	add_theme_stylebox_override("pressed", UITheme.box("panel_brown", 24, 6))
	_count_label = Label.new()
	_count_label.add_theme_font_override("font", UITheme.title_font())
	_count_label.add_theme_font_size_override("font_size", int(size_px * 0.28))
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	_count_label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.04))
	_count_label.add_theme_constant_override("outline_size", 9)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count_label.offset_right = -10
	_count_label.offset_bottom = -4
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)


func set_item(id: String, amount: int) -> void:
	item_id = id
	count = amount
	_icon = Items.icon(id) if id != "" else null
	_count_label.text = str(amount) if amount > 1 else ""
	tooltip_text = Items.item_name(id) if id != "" else ""
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _icon:
		var longest: float = max(_icon.get_width(), _icon.get_height())
		var scale := size.x * 0.72 / longest
		var icon_size := Vector2(_icon.get_width(), _icon.get_height()) * scale
		draw_texture_rect(_icon, Rect2((size - icon_size) * 0.5, icon_size), false,
			Color(1, 1, 1, 0.4 if dimmed else 1.0))
	if selected:
		draw_rect(rect.grow(-3), UITheme.GOLD, false, 7.0)
		draw_rect(rect.grow(-11), Color(UITheme.GOLD, 0.25), false, 3.0)
