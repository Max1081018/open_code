@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## android category (SPEC §6, specs/B13) — 3 tools.
## Every handler is editor-side and needs no open scene: never call error_no_scene() here.
## Nothing here mutates a scene, so no EditorUndoRedoManager is used.
##
## WARNING: OS.execute() is BLOCKING — the editor (and this addon's ping loop) freezes for the
## duration of the child process. Accepted for v1; the per-tool timeoutMs covers the silence.
## Never use OS.create_process here: results must be captured synchronously.

const PRESETS_PATH := "res://export_presets.cfg"
const ANDROID_SDK_SETTING := "export/android/android_sdk_path"
const OUTPUT_TAIL_CHARS := 2000


func get_commands() -> Dictionary:
	return {
		"list_android_devices": _list_android_devices,
		"get_android_preset_info": _get_android_preset_info,
		"deploy_to_android": _deploy_to_android,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Absolute adb from the editor's Android SDK setting when usable, else the literal "adb"
## (OS.execute resolves it from PATH).
func _resolve_adb() -> String:
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	if settings != null and settings.has_setting(ANDROID_SDK_SETTING):
		var sdk_path: String = str(settings.get_setting(ANDROID_SDK_SETTING)).strip_edges()
		if not sdk_path.is_empty():
			var exe: String = "adb.exe" if OS.get_name() == "Windows" else "adb"
			var candidate: String = sdk_path.path_join("platform-tools").path_join(exe)
			if FileAccess.file_exists(candidate):
				return candidate
	return "adb"


## Blocking child process. Returns {"exit_code": int, "output": String} with stdout+stderr merged.
func _run(cmd: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var exit_code: int = OS.execute(cmd, args, output, true)
	var text: String = ""
	for chunk: Variant in output:
		text += str(chunk)
	return {"exit_code": exit_code, "output": text}


## Splits on any run of whitespace (adb pads with spaces in -l mode but uses a TAB as the
## serial/state separator in short format), dropping empty tokens.
func _whitespace_split(line: String) -> Array:
	var normalized: String = line
	for ws: String in ["\t", "\r", "\v", "\f"]:
		normalized = normalized.replace(ws, " ")
	var tokens: Array = []
	for part: String in normalized.split(" ", false):
		var token: String = part.strip_edges()
		if not token.is_empty():
			tokens.append(token)
	return tokens


func _tail(text: String) -> String:
	if text.length() <= OUTPUT_TAIL_CHARS:
		return text
	return text.substr(text.length() - OUTPUT_TAIL_CHARS)


## Resolves an Android export preset. Returns [preset_dict, null] or [null, error_dict].
## Name match wins, then index, then the first preset whose platform is "Android".
func _find_android_preset(preset_name: String, preset_index: int) -> Array:
	if not FileAccess.file_exists(PRESETS_PATH):
		return [null, error_not_found("Android export preset")]

	var cfg := ConfigFile.new()
	var err: int = cfg.load(PRESETS_PATH)
	if err != OK:
		return [
			null,
			error(
				-32603,
				"Failed to load %s: %s" % [PRESETS_PATH, error_string(err)],
				{"path": PRESETS_PATH}
			)
		]

	var found: Dictionary = {}
	var explicit: bool = not preset_name.is_empty() or preset_index >= 0
	var i: int = 0
	while cfg.has_section("preset.%d" % i):
		var section: String = "preset.%d" % i
		var name: String = str(cfg.get_value(section, "name", ""))
		var platform: String = str(cfg.get_value(section, "platform", ""))
		var matched: bool = false
		if not preset_name.is_empty():
			matched = name == preset_name
		elif preset_index >= 0:
			matched = i == preset_index
		else:
			matched = platform == "Android"

		if matched:
			found = {
				"name": name,
				"index": i,
				"platform": platform,
				"export_path": str(cfg.get_value(section, "export_path", "")),
				"package_unique_name": str(
					cfg.get_value("%s.options" % section, "package/unique_name", "")
				),
			}
			break
		i += 1

	if found.is_empty():
		return [null, error_not_found("Android export preset")]

	if explicit and str(found.get("platform", "")) != "Android":
		return [
			null,
			error(
				-32000,
				(
					"Export preset '%s' is not an Android preset (platform: %s)"
					% [str(found.get("name", "")), str(found.get("platform", ""))]
				),
				{"preset": str(found.get("name", "")), "platform": str(found.get("platform", ""))}
			)
		]

	return [found, null]


# ---------------------------------------------------------------------------
# list_android_devices
# ---------------------------------------------------------------------------


func _list_android_devices(_params: Dictionary) -> Dictionary:
	var adb: String = _resolve_adb()
	var run: Dictionary = _run(adb, PackedStringArray(["devices", "-l"]))
	var exit_code: int = int(run["exit_code"])
	var output: String = str(run["output"])

	if exit_code != 0:
		return error(
			-32000,
			"adb failed (exit %d)" % exit_code,
			{
				"adb_path": adb,
				"output": _tail(output),
				"suggestion": (
					"install Android platform-tools or set editor setting %s" % ANDROID_SDK_SETTING
				),
			}
		)

	var devices: Array = []
	for raw_line: String in output.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("List of devices"):
			continue
		if line.begins_with("*"):
			continue

		# adb separates serial and state with a TAB, and the -l detail tokens with spaces.
		# Splitting on " " alone drops every tab-delimited row on the floor.
		var parts: PackedStringArray = line.replace("\t", " ").split(" ", false)
		# A whitespace-split row needs at least "<serial> <state>".
		var tokens: Array = []
		for part: String in parts:
			var token: String = part.strip_edges()
			if not token.is_empty():
				tokens.append(token)
		if tokens.size() < 2:
			continue

		var device: Dictionary = {"serial": str(tokens[0]), "state": str(tokens[1])}
		for idx: int in range(2, tokens.size()):
			var token: String = str(tokens[idx])
			var sep: int = token.find(":")
			if sep <= 0:
				continue
			var key: String = token.substr(0, sep)
			if key == "product" or key == "model" or key == "device":
				device[key] = token.substr(sep + 1)
		devices.append(device)

	return success({"devices": devices, "count": devices.size(), "adb_path": adb})


# ---------------------------------------------------------------------------
# get_android_preset_info
# ---------------------------------------------------------------------------


func _get_android_preset_info(params: Dictionary) -> Dictionary:
	var preset_name: String = optional_string(params, "preset_name", "")
	var preset_index: int = optional_int(params, "preset_index", -1)

	var res: Array = _find_android_preset(preset_name, preset_index)
	if res[1] != null:
		return res[1]
	var preset: Dictionary = res[0]

	return success(
		{
			"name": str(preset.get("name", "")),
			"index": int(preset.get("index", -1)),
			"export_path": str(preset.get("export_path", "")),
			"package_unique_name": str(preset.get("package_unique_name", "")),
		}
	)


# ---------------------------------------------------------------------------
# deploy_to_android — export (headless), adb install, adb launch. BLOCKING.
# ---------------------------------------------------------------------------


func _deploy_to_android(params: Dictionary) -> Dictionary:
	var preset_name: String = optional_string(params, "preset_name", "")
	var preset_index: int = optional_int(params, "preset_index", -1)
	var device_serial: String = optional_string(params, "device_serial", "")
	var debug: bool = optional_bool(params, "debug", true)
	var launch: bool = optional_bool(params, "launch", true)
	var skip_export: bool = optional_bool(params, "skip_export", false)

	var res: Array = _find_android_preset(preset_name, preset_index)
	if res[1] != null:
		return res[1]
	var preset: Dictionary = res[0]

	var name: String = str(preset.get("name", ""))
	var package_unique_name: String = str(preset.get("package_unique_name", ""))
	var export_path: String = str(preset.get("export_path", ""))
	if export_path.is_empty():
		return error(
			-32000,
			"Export preset '%s' has no export_path — set it in Project > Export" % name,
			{"preset": name}
		)

	var apk_abs: String = export_path
	if apk_abs.begins_with("res://"):
		apk_abs = ProjectSettings.globalize_path(apk_abs)

	var steps: Array = []

	# 1. export
	if not skip_export:
		var godot_executable: String = OS.get_executable_path()
		var project_path: String = ProjectSettings.globalize_path("res://")
		var flag: String = "--export-debug" if debug else "--export-release"
		var export_args := PackedStringArray(
			["--headless", "--path", project_path, flag, name, apk_abs]
		)
		var export_run: Dictionary = _run(godot_executable, export_args)
		var export_exit: int = int(export_run["exit_code"])
		var export_out: String = _tail(str(export_run["output"]))
		steps.append({"step": "export", "ok": export_exit == 0, "output": export_out})
		if export_exit != 0:
			return error(
				-32000,
				"step 'export' failed (exit %d)" % export_exit,
				{"preset": name, "steps": steps}
			)

	if not FileAccess.file_exists(apk_abs):
		return error(
			-32000,
			"APK not found at %s" % apk_abs,
			{"preset": name, "apk_path": apk_abs, "steps": steps}
		)

	var adb: String = _resolve_adb()
	var serial_args := PackedStringArray()
	if not device_serial.is_empty():
		serial_args = PackedStringArray(["-s", device_serial])

	# 2. install
	var install_args := PackedStringArray(serial_args)
	install_args.append_array(PackedStringArray(["install", "-r", apk_abs]))
	var install_run: Dictionary = _run(adb, install_args)
	var install_exit: int = int(install_run["exit_code"])
	var install_out: String = _tail(str(install_run["output"]))
	steps.append({"step": "install", "ok": install_exit == 0, "output": install_out})
	if install_exit != 0:
		return error(
			-32000,
			"step 'install' failed (exit %d)" % install_exit,
			{"preset": name, "adb_path": adb, "steps": steps}
		)

	# 3. launch
	if launch:
		if package_unique_name.is_empty():
			steps.append(
				{
					"step": "launch",
					"ok": true,
					"skipped": true,
					"output": "package/unique_name not set in preset options",
				}
			)
		else:
			# -s <serial> is a global adb flag: it must precede "shell".
			var launch_args := PackedStringArray(serial_args)
			launch_args.append_array(
				PackedStringArray(
					[
						"shell",
						"monkey",
						"-p",
						package_unique_name,
						"-c",
						"android.intent.category.LAUNCHER",
						"1",
					]
				)
			)
			var launch_run: Dictionary = _run(adb, launch_args)
			var launch_exit: int = int(launch_run["exit_code"])
			var launch_out: String = _tail(str(launch_run["output"]))
			steps.append({"step": "launch", "ok": launch_exit == 0, "output": launch_out})
			if launch_exit != 0:
				return error(
					-32000,
					"step 'launch' failed (exit %d)" % launch_exit,
					{"preset": name, "adb_path": adb, "steps": steps}
				)

	return success(
		{
			"preset": name,
			"apk_path": apk_abs,
			"device": device_serial if not device_serial.is_empty() else "default",
			"package_unique_name": package_unique_name,
			"steps": steps,
		}
	)
