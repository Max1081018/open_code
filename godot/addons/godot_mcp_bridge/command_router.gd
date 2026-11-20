@tool
extends Node

## Dispatches wire methods to command modules (SPEC §3.4).
##
## Every category module is preloaded here at Phase A and NEVER edited again — Phase B
## packages only replace the body of their own commands/<category>_commands.gd.

const CONFIG_PATH := "user://mcp_tool_config.cfg"
const CONFIG_SECTION := "disabled_tools"

const ProjectCommands := preload("res://addons/godot_mcp_bridge/commands/project_commands.gd")
const ResourceCommands := preload("res://addons/godot_mcp_bridge/commands/resource_commands.gd")
const SceneCommands := preload("res://addons/godot_mcp_bridge/commands/scene_commands.gd")
const Scene3DCommands := preload("res://addons/godot_mcp_bridge/commands/scene_3d_commands.gd")
const NodeCommands := preload("res://addons/godot_mcp_bridge/commands/node_commands.gd")
const ScriptCommands := preload("res://addons/godot_mcp_bridge/commands/script_commands.gd")
const ShaderCommands := preload("res://addons/godot_mcp_bridge/commands/shader_commands.gd")
const EditorCommands := preload("res://addons/godot_mcp_bridge/commands/editor_commands.gd")
const InputCommands := preload("res://addons/godot_mcp_bridge/commands/input_commands.gd")
const InputMapCommands := preload("res://addons/godot_mcp_bridge/commands/input_map_commands.gd")
const TestCommands := preload("res://addons/godot_mcp_bridge/commands/test_commands.gd")
const RuntimeCommands := preload("res://addons/godot_mcp_bridge/commands/runtime_commands.gd")
const AnimationCommands := preload("res://addons/godot_mcp_bridge/commands/animation_commands.gd")
const AnimationTreeCommands := preload(
	"res://addons/godot_mcp_bridge/commands/animation_tree_commands.gd"
)
const TilemapCommands := preload("res://addons/godot_mcp_bridge/commands/tilemap_commands.gd")
const NavigationCommands := preload("res://addons/godot_mcp_bridge/commands/navigation_commands.gd")
const ThemeCommands := preload("res://addons/godot_mcp_bridge/commands/theme_commands.gd")
const AudioCommands := preload("res://addons/godot_mcp_bridge/commands/audio_commands.gd")
const PhysicsCommands := preload("res://addons/godot_mcp_bridge/commands/physics_commands.gd")
const ParticleCommands := preload("res://addons/godot_mcp_bridge/commands/particle_commands.gd")
const BatchCommands := preload("res://addons/godot_mcp_bridge/commands/batch_commands.gd")
const AnalysisCommands := preload("res://addons/godot_mcp_bridge/commands/analysis_commands.gd")
const ProfilingCommands := preload("res://addons/godot_mcp_bridge/commands/profiling_commands.gd")
const ExportCommands := preload("res://addons/godot_mcp_bridge/commands/export_commands.gd")
const AndroidCommands := preload("res://addons/godot_mcp_bridge/commands/android_commands.gd")

var editor_plugin: EditorPlugin

var _handlers: Dictionary = {}  # method:String -> Callable
var _modules: Array[Node] = []
var _disabled: Dictionary = {}  # method:String -> true


func _ready() -> void:
	_load_tool_config()
	_register_commands()


func _register_commands() -> void:
	var scripts: Array[GDScript] = [
		ProjectCommands,
		ResourceCommands,
		SceneCommands,
		Scene3DCommands,
		NodeCommands,
		ScriptCommands,
		ShaderCommands,
		EditorCommands,
		InputCommands,
		InputMapCommands,
		TestCommands,
		RuntimeCommands,
		AnimationCommands,
		AnimationTreeCommands,
		TilemapCommands,
		NavigationCommands,
		ThemeCommands,
		AudioCommands,
		PhysicsCommands,
		ParticleCommands,
		BatchCommands,
		AnalysisCommands,
		ProfilingCommands,
		ExportCommands,
		AndroidCommands,
	]

	for script: GDScript in scripts:
		var module: Node = script.new()
		module.editor_plugin = editor_plugin
		module.name = script.resource_path.get_file().get_basename()
		add_child(module)
		_modules.append(module)
		var commands: Dictionary = module.get_commands()
		for method: String in commands.keys():
			if _handlers.has(method):
				push_warning("[MCP] duplicate command registration: %s" % method)
			_handlers[method] = commands[method]

	print(
		(
			"[MCP] registered %d commands from %d modules"
			% [_handlers.size(), _modules.size()]
		)
	)


func get_command_names() -> Array[String]:
	var out: Array[String] = []
	for method: String in _handlers.keys():
		out.append(method)
	out.sort()
	return out


func get_command_count() -> int:
	return _handlers.size()


func has_command(method: String) -> bool:
	return _handlers.has(method)


func execute(method: String, params: Dictionary) -> Dictionary:
	if not _handlers.has(method):
		return {
			"error":
			{
				"code": -32601,
				"message": "Method not found: %s" % method,
				"data": {"available_methods": get_command_names()},
			}
		}
	if is_tool_disabled(method):
		return {"error": {"code": -32603, "message": "Tool '%s' is disabled" % method}}

	var handler: Callable = _handlers[method]
	var out: Variant = await handler.call(params)
	if typeof(out) != TYPE_DICTIONARY:
		return {
			"error":
			{"code": -32603, "message": "Handler for '%s' returned a non-Dictionary" % method}
		}
	return out


# ---------------------------------------------------------------------------
# Per-tool disable list (persisted at user://mcp_tool_config.cfg)
# ---------------------------------------------------------------------------


func is_tool_disabled(method: String) -> bool:
	return bool(_disabled.get(method, false))


func set_tool_disabled(method: String, disabled: bool) -> void:
	if disabled:
		_disabled[method] = true
	else:
		_disabled.erase(method)
	_save_tool_config()


func set_all_tools_disabled(disabled: bool) -> void:
	_disabled.clear()
	if disabled:
		for method: String in _handlers.keys():
			_disabled[method] = true
	_save_tool_config()


func _load_tool_config() -> void:
	_disabled.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.has_section(CONFIG_SECTION):
		return
	for method: String in cfg.get_section_keys(CONFIG_SECTION):
		if bool(cfg.get_value(CONFIG_SECTION, method, false)):
			_disabled[method] = true


func _save_tool_config() -> void:
	var cfg := ConfigFile.new()
	for method: String in _disabled.keys():
		cfg.set_value(CONFIG_SECTION, method, true)
	var err: int = cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("[MCP] could not save tool config: %s" % error_string(err))
