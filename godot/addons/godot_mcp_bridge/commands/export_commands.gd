@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## export category (SPEC §6, specs/B13) — 3 tools.
## Every handler is editor-side and needs no open scene: never call error_no_scene() here.
## Nothing here mutates a scene, so no EditorUndoRedoManager is used.
##
## SPEC §9.3: export_project deliberately returns the headless CLI command string instead of
## exporting in-process — the caller runs it in a terminal.

const PRESETS_PATH := "res://export_presets.cfg"


func get_commands() -> Dictionary:
	return {
		"list_export_presets": _list_export_presets,
		"export_project": _export_project,
		"get_export_info": _get_export_info,
	}


# ---------------------------------------------------------------------------
# list_export_presets
# ---------------------------------------------------------------------------


func _list_export_presets(_params: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(PRESETS_PATH):
		return success(
			{
				"presets": [],
				"count": 0,
				"hint": "configure presets in Project > Export",
			}
		)

	var cfg := ConfigFile.new()
	var err: int = cfg.load(PRESETS_PATH)
	if err != OK:
		return error(
			-32603,
			"Failed to load %s: %s" % [PRESETS_PATH, error_string(err)],
			{"path": PRESETS_PATH}
		)

	var presets: Array = _read_presets(cfg)
	return success({"presets": presets, "count": presets.size()})


## Reads sections preset.0, preset.1, … while they exist.
func _read_presets(cfg: ConfigFile) -> Array:
	var out: Array = []
	var i: int = 0
	while cfg.has_section("preset.%d" % i):
		out.append(_read_preset(cfg, i))
		i += 1
	return out


func _read_preset(cfg: ConfigFile, index: int) -> Dictionary:
	var section: String = "preset.%d" % index
	return {
		"index": index,
		"name": str(cfg.get_value(section, "name", "")),
		"platform": str(cfg.get_value(section, "platform", "")),
		"runnable": bool(cfg.get_value(section, "runnable", false)),
		"export_path": str(cfg.get_value(section, "export_path", "")),
	}


# ---------------------------------------------------------------------------
# export_project — builds the headless CLI command, does NOT export (SPEC §9.3)
# ---------------------------------------------------------------------------


func _export_project(params: Dictionary) -> Dictionary:
	var preset_index: int = optional_int(params, "preset_index", -1)
	var preset_name: String = optional_string(params, "preset_name", "")
	var debug: bool = optional_bool(params, "debug", true)

	if not FileAccess.file_exists(PRESETS_PATH):
		return error(
			-32000,
			"No export_presets.cfg — configure presets in Project > Export first",
			{"path": PRESETS_PATH}
		)

	var cfg := ConfigFile.new()
	var err: int = cfg.load(PRESETS_PATH)
	if err != OK:
		return error(
			-32603,
			"Failed to load %s: %s" % [PRESETS_PATH, error_string(err)],
			{"path": PRESETS_PATH}
		)

	var presets: Array = _read_presets(cfg)
	var match_preset: Dictionary = _select_preset(presets, preset_name, preset_index)
	if match_preset.is_empty():
		if not preset_name.is_empty():
			return error_not_found("Export preset: %s" % preset_name)
		if preset_index >= 0:
			return error_not_found("Export preset at index %d" % preset_index)
		return error_not_found("Runnable export preset")

	var export_path: String = str(match_preset.get("export_path", ""))
	if export_path.is_empty():
		return error(
			-32000,
			"Export preset '%s' has no export_path — set it in Project > Export"
			% str(match_preset.get("name", "")),
			{"preset": str(match_preset.get("name", ""))}
		)

	var export_path_abs: String = export_path
	if export_path_abs.begins_with("res://"):
		export_path_abs = ProjectSettings.globalize_path(export_path_abs)

	var godot_executable: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var flag: String = "--export-debug" if debug else "--export-release"
	var name: String = str(match_preset.get("name", ""))

	var command: String = (
		'"%s" --headless --path "%s" %s "%s" "%s"'
		% [godot_executable, project_path, flag, name, export_path_abs]
	)

	return success(
		{
			"command": command,
			"preset": name,
			"export_path": export_path_abs,
			"note": "run this command in a terminal; export templates must be installed",
		}
	)


## Name match wins, then index, then the first runnable preset. {} when nothing matches.
func _select_preset(presets: Array, preset_name: String, preset_index: int) -> Dictionary:
	if not preset_name.is_empty():
		for preset: Dictionary in presets:
			if str(preset.get("name", "")) == preset_name:
				return preset
		return {}

	if preset_index >= 0:
		for preset: Dictionary in presets:
			if int(preset.get("index", -1)) == preset_index:
				return preset
		return {}

	for preset: Dictionary in presets:
		if bool(preset.get("runnable", false)):
			return preset
	return {}


# ---------------------------------------------------------------------------
# get_export_info
# ---------------------------------------------------------------------------


func _get_export_info(_params: Dictionary) -> Dictionary:
	var templates_dir: String = _export_templates_dir()
	return success(
		{
			"has_export_presets": FileAccess.file_exists(PRESETS_PATH),
			"godot_executable": OS.get_executable_path(),
			"project_path": ProjectSettings.globalize_path("res://"),
			"export_templates_dir": templates_dir,
			"export_templates_dir_exists": (
				not templates_dir.is_empty() and DirAccess.dir_exists_absolute(templates_dir)
			),
		}
	)


## <editor data dir>/export_templates/<version>, version like "4.3.stable" / "4.4.1.stable".
func _export_templates_dir() -> String:
	var paths: EditorPaths = EditorInterface.get_editor_paths()
	if paths == null:
		return ""
	return paths.get_data_dir().path_join("export_templates").path_join(_template_version())


func _template_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	var major: int = int(info.get("major", 0))
	var minor: int = int(info.get("minor", 0))
	var patch: int = int(info.get("patch", 0))
	var status: String = str(info.get("status", "stable"))
	if patch > 0:
		return "%d.%d.%d.%s" % [major, minor, patch, status]
	return "%d.%d.%s" % [major, minor, status]
