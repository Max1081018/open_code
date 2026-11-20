@tool
extends EditorPlugin

## Godot MCP Bridge — EditorPlugin entry point (SPEC §3.4).

const CommandRouter := preload("res://addons/godot_mcp_bridge/command_router.gd")
const WebSocketClient := preload("res://addons/godot_mcp_bridge/websocket_client.gd")
const StatusPanelScene := preload("res://addons/godot_mcp_bridge/ui/status_panel.tscn")

const AUTOLOADS := {
	"MCPScreenshot": "res://addons/godot_mcp_bridge/services/mcp_screenshot_service.gd",
	"MCPInputService": "res://addons/godot_mcp_bridge/services/mcp_input_service.gd",
	"MCPGameInspector": "res://addons/godot_mcp_bridge/services/mcp_game_inspector_service.gd",
}

const IPC_FILES := [
	"mcp_game_request",
	"mcp_game_response",
	"mcp_input_commands",
	"mcp_screenshot_request",
	"mcp_screenshot.png",
	"mcp_debugger_continue",
]

const DEBUGGER_CONTINUE_FILE := "mcp_debugger_continue"
const DISMISS_SCAN_INTERVAL := 0.5

## Toggled by the `set_auto_dismiss` tool (B05) through `editor_plugin`.
var auto_dismiss_dialogs: bool = false

var command_router: Node
var websocket_client: Node

var _status_panel: Control
var _session_injected: Array[String] = []
var _dismiss_timer: float = 0.0


func _enter_tree() -> void:
	command_router = CommandRouter.new()
	command_router.name = "MCPCommandRouter"
	command_router.editor_plugin = self
	add_child(command_router)

	websocket_client = WebSocketClient.new()
	websocket_client.name = "MCPWebSocketClient"
	websocket_client.command_router = command_router
	add_child(websocket_client)

	_status_panel = StatusPanelScene.instantiate()
	add_control_to_bottom_panel(_status_panel, "MCP Bridge")
	_status_panel.setup.call_deferred(websocket_client, command_router)

	_inject_autoloads()
	websocket_client.start()
	set_process(true)
	print("[MCP] Godot MCP Bridge plugin enabled")


func _exit_tree() -> void:
	set_process(false)
	_remove_session_autoloads()
	_cleanup_ipc_files()

	if websocket_client != null:
		websocket_client.stop()
		websocket_client.queue_free()
		websocket_client = null
	if command_router != null:
		command_router.queue_free()
		command_router = null
	if _status_panel != null:
		remove_control_from_bottom_panel(_status_panel)
		_status_panel.queue_free()
		_status_panel = null
	print("[MCP] Godot MCP Bridge plugin disabled")


func _process(delta: float) -> void:
	_check_debugger_continue()
	if auto_dismiss_dialogs:
		_dismiss_timer += delta
		if _dismiss_timer >= DISMISS_SCAN_INTERVAL:
			_dismiss_timer = 0.0
			_auto_dismiss_dialogs()


# ---------------------------------------------------------------------------
# Autoloads
# ---------------------------------------------------------------------------


func _inject_autoloads() -> void:
	var changed: bool = false
	for autoload_name: String in AUTOLOADS.keys():
		var key: String = "autoload/%s" % autoload_name
		if ProjectSettings.has_setting(key):
			continue
		ProjectSettings.set_setting(key, "*%s" % AUTOLOADS[autoload_name])
		_session_injected.append(autoload_name)
		changed = true
	if changed:
		ProjectSettings.save()
		print("[MCP] injected autoloads: %s" % ", ".join(_session_injected))


func _remove_session_autoloads() -> void:
	var changed: bool = false
	for autoload_name: String in _session_injected:
		var key: String = "autoload/%s" % autoload_name
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, null)
			changed = true
	_session_injected.clear()
	if changed:
		ProjectSettings.save()


# ---------------------------------------------------------------------------
# IPC housekeeping
# ---------------------------------------------------------------------------


func _cleanup_ipc_files() -> void:
	var dir: String = OS.get_user_data_dir()
	for file_name: String in IPC_FILES:
		var path: String = "%s/%s" % [dir, file_name]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Debugger "Continue" (game paused after a runtime error while a tool awaits it)
# ---------------------------------------------------------------------------


func _check_debugger_continue() -> void:
	var path: String = "%s/%s" % [OS.get_user_data_dir(), DEBUGGER_CONTINUE_FILE]
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)
	if _press_debugger_continue():
		print("[MCP] pressed debugger Continue")
	else:
		push_warning("[MCP] could not find the debugger Continue button")


func _press_debugger_continue() -> bool:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return false
	var continue_icon: Texture2D = null
	if base.has_theme_icon("DebugContinue", "EditorIcons"):
		continue_icon = base.get_theme_icon("DebugContinue", "EditorIcons")
	var button: Button = _find_continue_button(base, continue_icon)
	if button == null:
		return false
	button.emit_signal("pressed")
	return true


## Icon match first — the editor UI may be translated, so English text is only a fallback.
func _find_continue_button(node: Node, continue_icon: Texture2D) -> Button:
	if node is Button:
		var button: Button = node
		if continue_icon != null and button.icon == continue_icon:
			return button
		if button.text == "Continue" or button.tooltip_text.begins_with("Continue"):
			return button
	for child: Node in node.get_children():
		var found: Button = _find_continue_button(child, continue_icon)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Auto-dismiss exclusive modal dialogs (they would otherwise block every tool)
# ---------------------------------------------------------------------------


func _auto_dismiss_dialogs() -> void:
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return
	var dialog: AcceptDialog = _find_blocking_dialog(base)
	if dialog == null:
		return
	push_warning(
		"[MCP] auto-dismissed dialog: %s — %s" % [dialog.title, dialog.dialog_text]
	)
	var ok: Button = dialog.get_ok_button()
	if ok != null:
		ok.emit_signal("pressed")
	else:
		dialog.hide()


func _find_blocking_dialog(node: Node) -> AcceptDialog:
	if node is AcceptDialog and not (node is FileDialog):
		var dialog: AcceptDialog = node
		if dialog.visible and dialog.exclusive:
			return dialog
	for child: Node in node.get_children():
		var found: AcceptDialog = _find_blocking_dialog(child)
		if found != null:
			return found
	return null
