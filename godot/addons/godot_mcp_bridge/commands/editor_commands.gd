@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B05 — editor commands (13 tools).
##
## Diagnostics, screenshots (editor + running game), arbitrary editor script execution,
## signal introspection, screenshot diffing and 3D editor camera control.
## Nothing here mutates the edited scene, so no EditorUndoRedoManager actions are used.

const LOG_PATH := "user://logs/godot.log"
const LOG_SCAN_LINES := 2000
const ERROR_MARKERS: Array[String] = ["ERROR", "SCRIPT ERROR", "Parse Error", "WARNING"]

const SCREENSHOT_REQUEST_FILE := "mcp_screenshot_request"
const SCREENSHOT_FILE := "mcp_screenshot.png"
const SCREENSHOT_POLL_STEP := 0.1
const SCREENSHOT_POLL_COUNT := 30  # 30 * 0.1s = 3s, well under the 60s bridge timeout.

const UI_SEARCH_MAX_DEPTH := 12
const UNSAFE_SUGGESTION := (
	"use dedicated MCP tools (edit_resource, save_scene, set_project_setting)"
	+ " or pass allow_unsafe_editor_io=true"
)


func get_commands() -> Dictionary:
	return {
		"get_editor_errors": _get_editor_errors,
		"get_output_log": _get_output_log,
		"get_editor_screenshot": _get_editor_screenshot,
		"get_game_screenshot": _get_game_screenshot,
		"execute_editor_script": _execute_editor_script,
		"clear_output": _clear_output,
		"reload_plugin": _reload_plugin,
		"reload_project": _reload_project,
		"get_signals": _get_signals,
		"compare_screenshots": _compare_screenshots,
		"set_auto_dismiss": _set_auto_dismiss,
		"get_editor_camera": _get_editor_camera,
		"set_editor_camera": _set_editor_camera,
	}


# ---------------------------------------------------------------------------
# get_editor_errors
# ---------------------------------------------------------------------------


## Diagnostic tool: always succeeds, even when every source is unavailable.
func _get_editor_errors(params: Dictionary) -> Dictionary:
	var max_lines: int = maxi(1, optional_int(params, "max_lines", 50))

	var errors: Array[String] = []
	var sources: Array[String] = []

	var from_log: Array[String] = _collect_log_errors(max_lines)
	if not from_log.is_empty():
		errors.append_array(from_log)
		sources.append("log_file")

	var from_script_editor: Array[String] = _collect_script_editor_errors()
	if not from_script_editor.is_empty():
		errors.append_array(from_script_editor)
		sources.append("script_editor")

	var from_debugger: Array[String] = _collect_debugger_errors()
	if not from_debugger.is_empty():
		errors.append_array(from_debugger)
		sources.append("debugger")

	return success({"errors": errors, "count": errors.size(), "sources": sources})


func _collect_log_errors(max_lines: int) -> Array[String]:
	var out: Array[String] = []
	var lines: Array[String] = _read_log_tail(LOG_SCAN_LINES)
	for line: String in lines:
		for marker: String in ERROR_MARKERS:
			if line.contains(marker):
				out.append(line.strip_edges())
				break
	if out.size() > max_lines:
		out = out.slice(out.size() - max_lines)
	return out


## Scrapes the script editor's CodeEdit for red-ish line backgrounds (compile markers).
## Editor internals: any absence or API drift contributes nothing.
func _collect_script_editor_errors() -> Array[String]:
	var out: Array[String] = []
	var script_editor: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor == null:
		return out

	var script_path: String = "<unsaved>"
	var current: Script = script_editor.get_current_script()
	if current != null and not current.resource_path.is_empty():
		script_path = current.resource_path

	var editor_base: ScriptEditorBase = script_editor.get_current_editor()
	if editor_base == null:
		return out

	var code_edit: CodeEdit = _find_node_of_class(
		editor_base, "CodeEdit", UI_SEARCH_MAX_DEPTH
	) as CodeEdit
	if code_edit == null:
		return out

	for i: int in range(code_edit.get_line_count()):
		var bg: Color = code_edit.get_line_background_color(i)
		if bg.a > 0.0 and bg.r > 0.8:
			out.append(
				(
					"COMPILE ERROR: %s:%d - %s"
					% [script_path, i + 1, code_edit.get_line(i).strip_edges()]
				)
			)
	return out


## Scrapes the debugger Errors tab Tree. Editor internals: absence contributes nothing.
func _collect_debugger_errors() -> Array[String]:
	var out: Array[String] = []
	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return out

	var debugger: Node = _find_node_of_class(base, "ScriptEditorDebugger", UI_SEARCH_MAX_DEPTH)
	if debugger == null:
		return out

	var tree: Tree = _find_node_of_class(debugger, "Tree", UI_SEARCH_MAX_DEPTH) as Tree
	if tree == null:
		return out

	var root_item: TreeItem = tree.get_root()
	if root_item == null:
		return out

	var columns: int = tree.columns
	for item: TreeItem in root_item.get_children():
		var text: String = _tree_item_text(item, columns)
		if not text.is_empty():
			out.append("DEBUGGER: %s" % text)
		for child: TreeItem in item.get_children():
			var child_text: String = _tree_item_text(child, columns)
			if not child_text.is_empty():
				out.append("DEBUGGER: %s" % child_text)
	return out


func _tree_item_text(item: TreeItem, columns: int) -> String:
	if item == null:
		return ""
	var col0: String = item.get_text(0).strip_edges()
	var col1: String = ""
	if columns > 1:
		col1 = item.get_text(1).strip_edges()
	return ("%s %s" % [col0, col1]).strip_edges()


## Breadth-first, depth-capped search for a node of class `cls`. Null when not found.
func _find_node_of_class(root: Node, cls: String, max_depth: int) -> Node:
	if root == null:
		return null
	var frontier: Array[Node] = [root]
	var depth: int = 0
	while not frontier.is_empty() and depth <= max_depth:
		var next_level: Array[Node] = []
		for node: Node in frontier:
			if node.get_class() == cls or node.is_class(cls):
				return node
			for child: Node in node.get_children():
				next_level.append(child)
		frontier = next_level
		depth += 1
	return null


# ---------------------------------------------------------------------------
# get_output_log
# ---------------------------------------------------------------------------


func _get_output_log(params: Dictionary) -> Dictionary:
	var max_lines: int = maxi(1, optional_int(params, "max_lines", 100))
	var filter: String = optional_string(params, "filter", "")

	if not FileAccess.file_exists(LOG_PATH):
		return error(
			-32000,
			"Log file not found",
			{
				"log_path": ProjectSettings.globalize_path(LOG_PATH),
				"suggestion":
				"enable debug/file_logging/enable_file_logging in project settings",
			}
		)

	var scanned: Array[String] = _read_log_tail(LOG_SCAN_LINES)
	var matched: Array[String] = []
	for line: String in scanned:
		if filter.is_empty() or line.contains(filter):
			matched.append(line)
	if matched.size() > max_lines:
		matched = matched.slice(matched.size() - max_lines)

	return success(
		{
			"lines": matched,
			"count": matched.size(),
			"log_path": ProjectSettings.globalize_path(LOG_PATH),
		}
	)


## Last `limit` lines of the EDITOR's log file; empty when missing/unreadable.
func _read_log_tail(limit: int) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(LOG_PATH):
		return out
	var file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		return out
	while true:
		var line: String = file.get_line()
		# get_line() trips eof AFTER handing back the final line, and the read that trips it
		# yields "". Appending it unconditionally would put a junk empty entry on every log read
		# and inflate `count` by one.
		if file.eof_reached() and line.is_empty():
			break
		out.append(line)
		if file.eof_reached():
			break
	file.close()
	if out.size() > limit:
		out = out.slice(out.size() - limit)
	return out


# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------


func _get_editor_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = optional_string(params, "save_path", "")

	var base: Control = EditorInterface.get_base_control()
	if base == null:
		return error(-32603, "Editor base control is unavailable")
	var viewport: Viewport = base.get_viewport()
	if viewport == null:
		return error(-32603, "Editor viewport is unavailable")
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		return error(-32603, "Editor viewport texture is unavailable")
	var image: Image = texture.get_image()
	if image == null:
		return error(-32603, "Could not read the editor viewport image")

	return _finish_image(image, save_path)


## Editor side of the frozen screenshot file IPC (SPEC §3.4). Total wait <= 3s.
func _get_game_screenshot(params: Dictionary) -> Dictionary:
	var save_path: String = optional_string(params, "save_path", "")

	if not EditorInterface.is_playing_scene():
		return error(-32000, "Game is not running — use play_scene first")

	var dir: String = get_game_user_dir()
	var png_path: String = "%s/%s" % [dir, SCREENSHOT_FILE]
	var request_path: String = "%s/%s" % [dir, SCREENSHOT_REQUEST_FILE]

	# Drop a stale PNG so we can never hand back a previous capture.
	if FileAccess.file_exists(png_path):
		DirAccess.remove_absolute(png_path)

	var req: FileAccess = FileAccess.open(request_path, FileAccess.WRITE)
	if req == null:
		return error(
			-32603,
			"Could not write the screenshot request file",
			{"path": request_path, "error_string": error_string(FileAccess.get_open_error())}
		)
	req.close()

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var captured: bool = false
	for _i: int in range(SCREENSHOT_POLL_COUNT):
		if tree != null:
			await tree.create_timer(SCREENSHOT_POLL_STEP).timeout
		else:
			await Engine.get_main_loop().process_frame
		if FileAccess.file_exists(png_path):
			captured = true
			break

	if not captured:
		if FileAccess.file_exists(request_path):
			DirAccess.remove_absolute(request_path)
		return error(
			-32000,
			"Screenshot timed out",
			{
				"suggestion":
				"ensure the game is running and the MCPScreenshot autoload is active",
			}
		)

	var image: Image = Image.new()
	var err: int = image.load(png_path)
	if err != OK:
		return error(
			-32603,
			"Could not load the captured screenshot",
			{"path": png_path, "error_string": error_string(err)}
		)
	DirAccess.remove_absolute(png_path)

	return _finish_image(image, save_path)


## Shared save_path semantics for both screenshot tools:
## "" -> base64 PNG under `image`; otherwise write to disk and report `path` (no `image` key,
## the bridge's image formatter then degrades to text — designed behavior, SPEC §3.3).
func _finish_image(image: Image, save_path: String) -> Dictionary:
	var width: int = image.get_width()
	var height: int = image.get_height()

	if save_path.is_empty():
		var buffer: PackedByteArray = image.save_png_to_buffer()
		if buffer.is_empty():
			return error(-32603, "Failed to PNG-encode the captured image")
		return success(
			{"image": Marshalls.raw_to_base64(buffer), "width": width, "height": height}
		)

	var target: String = _resolve_save_path(save_path)
	var err: int = image.save_png(target)
	if err != OK:
		return error(
			-32603,
			"Failed to save the image",
			{"path": target, "error_string": error_string(err)}
		)
	return success({"path": save_path, "width": width, "height": height})


func _resolve_save_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


# ---------------------------------------------------------------------------
# execute_editor_script
# ---------------------------------------------------------------------------


func _execute_editor_script(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "code")
	if res[1] != null:
		return res[1]
	var code: String = res[0]
	var allow_unsafe: bool = optional_bool(params, "allow_unsafe_editor_io", false)

	if not allow_unsafe:
		var unsafe: Array[String] = _scan_unsafe_patterns(code)
		if not unsafe.is_empty():
			return error(
				-32009,
				"Refusing to execute editor script with direct file/resource write APIs",
				{"unsafe_patterns": unsafe, "suggestion": UNSAFE_SUGGESTION}
			)

	var wrapped: String = _wrap_editor_script(code)

	var script := GDScript.new()
	script.source_code = wrapped
	var err: int = script.reload()
	if err != OK:
		return error(
			-32002,
			"Script compilation failed",
			{"error": error_string(err), "script": wrapped}
		)

	var node := Node.new()
	node.set_script(script)
	add_child(node)

	var ret: Variant = await node.run()

	var output: Array[String] = []
	var raw_output: Variant = node.get("_mcp_output")
	if typeof(raw_output) == TYPE_ARRAY:
		for entry: Variant in (raw_output as Array):
			output.append(str(entry))

	node.queue_free()

	var return_value: Variant = null
	if ret != null:
		return_value = str(ret)

	return success({"output": output, "return_value": return_value})


## FROZEN wrapper contract (mirrored in the tool description): the user's code becomes the
## body of run(), every line indented by exactly one tab.
func _wrap_editor_script(code: String) -> String:
	var body: String = ""
	var normalized: String = code.replace("\r\n", "\n").replace("\r", "\n")
	for line: String in normalized.split("\n"):
		body += "\t%s\n" % line

	return (
		"@tool\n"
		+ "extends Node\n"
		+ "\n"
		+ "var _mcp_output: Array = []\n"
		+ "\n"
		+ "func _mcp_print(value: Variant) -> void:\n"
		+ "\t_mcp_output.append(str(value))\n"
		+ "\n"
		+ "func run() -> Variant:\n"
		+ body
		+ "\treturn null\n"
	)


## SPEC §8 banned-API scan. Whitespace is stripped first, so `FileAccess . open (` cannot
## slip past. Returns the label of every pattern that hit; empty means clean.
func _scan_unsafe_patterns(code: String) -> Array[String]:
	var s: String = code.replace(" ", "").replace("\t", "").replace("\n", "").replace("\r", "")
	var hits: Array[String] = []

	if s.contains("ResourceSaver.save("):
		hits.append("ResourceSaver.save")
	if s.contains("ProjectSettings.save("):
		hits.append("ProjectSettings.save")
	if s.contains("ConfigFile.save("):
		hits.append("ConfigFile.save")

	if s.contains("FileAccess.open("):
		var write_modes: Array[String] = [
			"FileAccess.WRITE",
			"FileAccess.READ_WRITE",
			"FileAccess.WRITE_READ",
		]
		for mode: String in write_modes:
			if s.contains(mode):
				hits.append("FileAccess.open WRITE")
				break

	var dir_mutations: Array[String] = [
		"DirAccess.remove_absolute(",
		"DirAccess.rename_absolute(",
		"DirAccess.copy_absolute(",
		"DirAccess.make_dir_absolute(",
		"DirAccess.make_dir_recursive_absolute(",
	]
	for pattern: String in dir_mutations:
		if s.contains(pattern):
			hits.append("DirAccess filesystem mutation")
			break

	return hits


# ---------------------------------------------------------------------------
# clear_output / reload_plugin / reload_project
# ---------------------------------------------------------------------------


func _clear_output(_params: Dictionary) -> Dictionary:
	# Cosmetic only: nothing is deleted, old content is just pushed out of view.
	print("\n".repeat(50))
	return success({"cleared": true})


func _reload_plugin(_params: Dictionary) -> Dictionary:
	# Reply FIRST — toggling the plugin tears down this very WebSocket connection.
	_deferred_reload_plugin.call_deferred()
	return success(
		{
			"reloading": true,
			"message": "Plugin will reload; connection drops briefly and auto-reconnects",
		}
	)


func _deferred_reload_plugin() -> void:
	# Let the router/WS client flush the response frame before the plugin disappears.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.create_timer(0.5).timeout
	EditorInterface.set_plugin_enabled("godot_mcp_bridge", false)
	EditorInterface.set_plugin_enabled("godot_mcp_bridge", true)


func _reload_project(_params: Dictionary) -> Dictionary:
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs == null:
		return error(-32603, "Editor resource filesystem is unavailable")
	# Returns as soon as the scan has started; completion is not awaited.
	fs.scan()
	return success({"scanning": true})


# ---------------------------------------------------------------------------
# get_signals
# ---------------------------------------------------------------------------


func _get_signals(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "node_path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var node: Node = find_node_by_path(path)
	if node == null:
		return error_not_found("Node '%s'" % path)

	var signals: Array = []
	for sig: Dictionary in node.get_signal_list():
		var sig_name: String = str(sig.get("name", ""))
		if sig_name.is_empty():
			continue

		var args: Array = []
		var raw_args: Variant = sig.get("args", [])
		if typeof(raw_args) == TYPE_ARRAY:
			for arg: Variant in (raw_args as Array):
				if typeof(arg) != TYPE_DICTIONARY:
					continue
				var arg_dict: Dictionary = arg
				args.append(
					{
						"name": str(arg_dict.get("name", "")),
						"type": type_string(int(arg_dict.get("type", TYPE_NIL))),
					}
				)

		var connections: Array = []
		for conn: Dictionary in node.get_signal_connection_list(sig_name):
			var callable: Callable = conn.get("callable", Callable())
			connections.append(
				{
					"target": _describe_callable_target(callable, root),
					"method": str(callable.get_method()),
				}
			)

		signals.append({"name": sig_name, "args": args, "connections": connections})

	return success(
		{
			"node_path": "." if node == root else str(root.get_path_to(node)),
			"type": node.get_class(),
			"signals": signals,
			"count": signals.size(),
		}
	)


## Scene-relative path when the target is a node in the edited scene, else str(callable).
func _describe_callable_target(callable: Callable, root: Node) -> String:
	var target: Node = callable.get_object() as Node
	if target != null and (target == root or root.is_ancestor_of(target)):
		return str(root.get_path_to(target))
	return str(callable)


# ---------------------------------------------------------------------------
# compare_screenshots
# ---------------------------------------------------------------------------


func _compare_screenshots(params: Dictionary) -> Dictionary:
	var res_a: Array = require_string(params, "image_a")
	if res_a[1] != null:
		return res_a[1]
	var res_b: Array = require_string(params, "image_b")
	if res_b[1] != null:
		return res_b[1]
	var threshold: int = clampi(optional_int(params, "threshold", 10), 0, 255)

	var loaded_a: Array = _load_image_from_param(res_a[0], "image_a")
	if loaded_a[1] != null:
		return loaded_a[1]
	var loaded_b: Array = _load_image_from_param(res_b[0], "image_b")
	if loaded_b[1] != null:
		return loaded_b[1]

	var image_a: Image = loaded_a[0]
	var image_b: Image = loaded_b[0]

	var width: int = image_a.get_width()
	var height: int = image_a.get_height()
	if width != image_b.get_width() or height != image_b.get_height():
		return error(
			-32000,
			(
				"Image sizes differ: image_a is %dx%d, image_b is %dx%d"
				% [width, height, image_b.get_width(), image_b.get_height()]
			),
			{
				"image_a": {"width": width, "height": height},
				"image_b": {"width": image_b.get_width(), "height": image_b.get_height()},
			}
		)

	image_a.convert(Image.FORMAT_RGBA8)
	image_b.convert(Image.FORMAT_RGBA8)

	var diff: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var changed: int = 0

	for y: int in range(height):
		for x: int in range(width):
			var ca: Color = image_a.get_pixel(x, y)
			var cb: Color = image_b.get_pixel(x, y)
			var dr: int = absi(int(roundf(ca.r * 255.0)) - int(roundf(cb.r * 255.0)))
			var dg: int = absi(int(roundf(ca.g * 255.0)) - int(roundf(cb.g * 255.0)))
			var db: int = absi(int(roundf(ca.b * 255.0)) - int(roundf(cb.b * 255.0)))
			var max_delta: int = maxi(dr, maxi(dg, db))
			if max_delta > threshold:
				changed += 1
				var alpha: float = clampf(float(max_delta) / 255.0, 0.3, 1.0)
				diff.set_pixel(x, y, Color(1.0, 0.0, 0.0, alpha))
			else:
				diff.set_pixel(x, y, Color(ca.r * 0.3, ca.g * 0.3, ca.b * 0.3, 1.0))

	var total: int = width * height
	var diff_percent: float = 0.0
	if total > 0:
		diff_percent = snappedf(float(changed) / float(total) * 100.0, 0.01)

	var buffer: PackedByteArray = diff.save_png_to_buffer()
	if buffer.is_empty():
		return error(-32603, "Failed to PNG-encode the diff image")

	return success(
		{
			"changed_pixels": changed,
			"total_pixels": total,
			"diff_percent": diff_percent,
			"identical": changed == 0,
			"width": width,
			"height": height,
			"diff_image": Marshalls.raw_to_base64(buffer),
		}
	)


## [Image, null] on success, [null, error_dict] on failure. Accepts a res://user:// path
## or a raw base64 PNG payload.
func _load_image_from_param(value: String, param_name: String) -> Array:
	var image: Image = Image.new()

	if value.begins_with("res://") or value.begins_with("user://"):
		var err: int = image.load(value)
		if err != OK:
			return [
				null,
				error(
					-32602,
					(
						"Invalid parameter %s: could not load image '%s' (%s)"
						% [param_name, value, error_string(err)]
					)
				)
			]
		return [image, null]

	var raw: PackedByteArray = Marshalls.base64_to_raw(value)
	if raw.is_empty():
		return [
			null,
			error(
				-32602,
				(
					"Invalid parameter %s: not a res:// or user:// path and not valid base64"
					% param_name
				)
			)
		]

	var png_err: int = image.load_png_from_buffer(raw)
	if png_err != OK:
		return [
			null,
			error(
				-32602,
				(
					"Invalid parameter %s: base64 payload is not a valid PNG (%s)"
					% [param_name, error_string(png_err)]
				)
			)
		]
	return [image, null]


# ---------------------------------------------------------------------------
# set_auto_dismiss
# ---------------------------------------------------------------------------


func _set_auto_dismiss(params: Dictionary) -> Dictionary:
	var enabled: bool = optional_bool(params, "enabled", true)
	if editor_plugin == null:
		return error(-32603, "Editor plugin is unavailable")
	editor_plugin.set("auto_dismiss_dialogs", enabled)
	return success({"auto_dismiss": enabled})


# ---------------------------------------------------------------------------
# Editor 3D camera
# ---------------------------------------------------------------------------


func _get_editor_camera(_params: Dictionary) -> Dictionary:
	var cam: Camera3D = _get_3d_camera()
	if cam == null:
		return _error_no_camera()
	return success(_camera_state(cam, true))


func _set_editor_camera(params: Dictionary) -> Dictionary:
	var cam: Camera3D = _get_3d_camera()
	if cam == null:
		return _error_no_camera()

	# Order matters: position -> rotation_degrees -> look_at (overrides rotation) -> fov.
	var position_values: Dictionary = _dict_param(params, "position")
	if not position_values.is_empty():
		cam.global_position = _apply_vec3(cam.global_position, position_values)

	var rotation_values: Dictionary = _dict_param(params, "rotation_degrees")
	if not rotation_values.is_empty():
		cam.global_rotation_degrees = _apply_vec3(cam.global_rotation_degrees, rotation_values)

	var look_at_values: Dictionary = _dict_param(params, "look_at")
	if not look_at_values.is_empty():
		var target: Vector3 = _apply_vec3(Vector3.ZERO, look_at_values)
		if target.is_equal_approx(cam.global_position):
			return error(
				-32602,
				"Invalid parameter look_at: target must differ from the camera position",
				{"look_at": {"x": target.x, "y": target.y, "z": target.z}}
			)
		cam.look_at(target, Vector3.UP)

	if params.has("fov") and params["fov"] != null:
		cam.fov = optional_float(params, "fov", cam.fov)

	return success(_camera_state(cam, false))


func _get_3d_camera() -> Camera3D:
	var viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _error_no_camera() -> Dictionary:
	return error(
		-32000, "No 3D editor camera found", {"suggestion": "open a 3D scene in the editor"}
	)


func _camera_state(cam: Camera3D, include_clip: bool) -> Dictionary:
	var pos: Vector3 = cam.global_position
	var rot: Vector3 = cam.global_rotation_degrees
	var out: Dictionary = {
		"position": {"x": pos.x, "y": pos.y, "z": pos.z},
		"rotation_degrees": {"x": rot.x, "y": rot.y, "z": rot.z},
		"fov": cam.fov,
	}
	if include_clip:
		out["near"] = cam.near
		out["far"] = cam.far
	return out


## Empty Dictionary when the param is absent, null, or not an object.
func _dict_param(params: Dictionary, key: String) -> Dictionary:
	if not params.has(key) or params[key] == null:
		return {}
	if typeof(params[key]) != TYPE_DICTIONARY:
		return {}
	return params[key]


## Overlays whichever of x/y/z are present in `values` onto `base`; missing keys keep theirs.
func _apply_vec3(base: Vector3, values: Dictionary) -> Vector3:
	var out: Vector3 = base
	if values.has("x") and values["x"] != null:
		out.x = float(values["x"])
	if values.has("y") and values["y"] != null:
		out.y = float(values["y"])
	if values.has("z") and values["z"] != null:
		out.z = float(values["z"])
	return out
