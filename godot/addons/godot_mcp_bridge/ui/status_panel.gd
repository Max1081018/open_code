@tool
extends Control

## Minimal bottom-panel UI: per-port connection dots, tool count, per-tool enable list.

const BASE_PORT := 6505
const MAX_PORT := 6509
const COLOR_ON := Color(0.3, 0.85, 0.4)
const COLOR_OFF := Color(0.4, 0.4, 0.4)

@onready var _ports_box: HBoxContainer = $VBox/Header/Ports
@onready var _tool_count_label: Label = $VBox/Header/ToolCount
@onready var _tool_list: Tree = $VBox/ToolList

var _ws_client: Node
var _router: Node
var _dots: Dictionary = {}  # port:int -> ColorRect


func setup(ws_client: Node, router: Node) -> void:
	_ws_client = ws_client
	_router = router

	_build_dots()

	if _ws_client != null:
		_ws_client.port_connected.connect(_on_port_connected)
		_ws_client.port_disconnected.connect(_on_port_disconnected)
		for port: int in _ws_client.get_connected_ports():
			_set_dot(port, true)

	_populate_tools()


func _build_dots() -> void:
	for child: Node in _ports_box.get_children():
		child.queue_free()
	_dots.clear()
	for port: int in range(BASE_PORT, MAX_PORT + 1):
		var box := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.color = COLOR_OFF
		dot.tooltip_text = "Port %d" % port
		var label := Label.new()
		label.text = str(port)
		box.add_child(dot)
		box.add_child(label)
		_ports_box.add_child(box)
		_dots[port] = dot


func _set_dot(port: int, on: bool) -> void:
	var dot: ColorRect = _dots.get(port)
	if dot != null:
		dot.color = COLOR_ON if on else COLOR_OFF


func _on_port_connected(port: int) -> void:
	_set_dot(port, true)


func _on_port_disconnected(port: int) -> void:
	_set_dot(port, false)


func _populate_tools() -> void:
	_tool_list.clear()
	if _router == null:
		return
	var names: Array[String] = _router.get_command_names()
	_tool_count_label.text = "%d tools" % names.size()

	_tool_list.columns = 1
	_tool_list.hide_root = true
	var root: TreeItem = _tool_list.create_item()
	for method: String in names:
		var item: TreeItem = _tool_list.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_text(0, method)
		item.set_checked(0, not bool(_router.is_tool_disabled(method)))
		item.set_metadata(0, method)

	if not _tool_list.item_edited.is_connected(_on_tool_toggled):
		_tool_list.item_edited.connect(_on_tool_toggled)


func _on_tool_toggled() -> void:
	var item: TreeItem = _tool_list.get_edited()
	if item == null or _router == null:
		return
	var method: String = str(item.get_metadata(0))
	_router.set_tool_disabled(method, not item.is_checked(0))
