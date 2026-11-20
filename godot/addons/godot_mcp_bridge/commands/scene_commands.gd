@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## scene — 10 tools (SPEC §6, specs/B02).
## Scene files: inspect, create, open, delete, instance, play/stop, save, exports.

const NodeUtils := preload("res://addons/godot_mcp_bridge/utils/node_utils.gd")
const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## IPC temp files stop_scene removes from the game's user:// dir (SPEC §3.4).
const IPC_TEMP_FILES := [
	"mcp_screenshot_request",
	"mcp_screenshot.png",
	"mcp_input_commands",
	"mcp_game_request",
	"mcp_game_response",
]


func get_commands() -> Dictionary:
	return {
		"get_scene_tree": _get_scene_tree,
		"get_scene_file_content": _get_scene_file_content,
		"create_scene": _create_scene,
		"open_scene": _open_scene,
		"delete_scene": _delete_scene,
		"add_scene_instance": _add_scene_instance,
		"play_scene": _play_scene,
		"stop_scene": _stop_scene,
		"save_scene": _save_scene,
		"get_scene_exports": _get_scene_exports,
	}


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _get_scene_tree(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()
	var max_depth: int = optional_int(params, "max_depth", -1)
	return success(
		{
			"scene_path": root.scene_file_path,
			"tree": NodeUtils.get_node_tree(root, max_depth),
		}
	)


func _get_scene_file_content(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]
	if not FileAccess.file_exists(path):
		return error_not_found("Scene file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return error(
			-32603,
			"Could not open scene file: %s" % path,
			{"error": error_string(FileAccess.get_open_error())}
		)
	var content: String = file.get_as_text()
	file.close()
	return success({"path": path, "content": content, "size": content.length()})


func _create_scene(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var guard: Dictionary = guard_offline_scene_save(path)
	if not guard.is_empty():
		return guard

	var root_type: String = optional_string(params, "root_type", "Node2D")
	if root_type.is_empty():
		root_type = "Node2D"
	if not ClassDB.class_exists(root_type) or not ClassDB.is_parent_class(root_type, "Node"):
		return error(-32602, "Invalid root_type: %s (must be a Node-derived class)" % root_type)

	var root_name: String = optional_string(params, "root_name", "")
	if root_name.is_empty():
		root_name = path.get_file().get_basename()
	if root_name.is_empty():
		root_name = root_type

	var root: Node = ClassDB.instantiate(root_type) as Node
	if root == null:
		return error(-32603, "Could not instantiate root type: %s" % root_type)
	root.name = root_name

	var scene := PackedScene.new()
	var pack_err: int = scene.pack(root)
	root.free()
	if pack_err != OK:
		return error(-32603, "Could not pack scene: %s" % error_string(pack_err))

	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return error(
				-32603, "Could not create directory %s: %s" % [dir_path, error_string(mk_err)]
			)

	var save_err: int = ResourceSaver.save(scene, path)
	if save_err != OK:
		return error(-32603, "Could not save scene %s: %s" % [path, error_string(save_err)])

	EditorInterface.get_resource_filesystem().scan()
	return success({"path": path, "root_type": root_type, "root_name": root_name})


func _open_scene(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]
	if not FileAccess.file_exists(path):
		return error_not_found("Scene file: %s" % path)
	EditorInterface.open_scene_from_path(path)
	return success({"path": path, "opened": true})


func _delete_scene(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]
	if not FileAccess.file_exists(path):
		return error_not_found("Scene file: %s" % path)

	var err: int = DirAccess.remove_absolute(path)
	if err != OK:
		return error(-32603, "Could not delete scene %s: %s" % [path, error_string(err)])

	var import_path: String = "%s.import" % path
	if FileAccess.file_exists(import_path):
		DirAccess.remove_absolute(import_path)

	EditorInterface.get_resource_filesystem().scan()
	return success({"path": path, "deleted": true})


func _add_scene_instance(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var res: Array = require_string(params, "scene_path")
	if res[1] != null:
		return res[1]
	var scene_path: String = res[0]
	if not FileAccess.file_exists(scene_path):
		return error_not_found("Scene file: %s" % scene_path)

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node: %s" % parent_path)

	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return error(-32603, "Resource is not a PackedScene: %s" % scene_path)
	# GEN_EDIT_STATE_INSTANCE keeps the sub-scene an instance reference. Its descendants
	# must stay owned by the instance root — re-owning them to the edited root would bake
	# the whole sub-scene into the outer .tscn on save instead of linking it.
	var instance: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if instance == null:
		return error(-32603, "Could not instantiate scene: %s" % scene_path)

	var new_name: String = optional_string(params, "name", "")
	if not new_name.is_empty():
		instance.name = unique_child_name(parent, new_name, instance.get_class())

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		instance.free()
		return error(-32603, "Undo/redo manager is unavailable")

	ur.create_action("MCP: add_scene_instance")
	ur.add_do_method(parent, "add_child", instance, true)
	ur.add_do_method(instance, "set_owner", root)
	ur.add_do_reference(instance)
	ur.add_undo_method(parent, "remove_child", instance)
	ur.commit_action()

	return success(
		{
			"node_path": str(root.get_path_to(instance)),
			"scene_path": scene_path,
			"name": str(instance.name),
		}
	)


func _play_scene(params: Dictionary) -> Dictionary:
	var mode: String = optional_string(params, "mode", "main")
	if mode.is_empty():
		mode = "main"
	var lower: String = mode.strip_edges().to_lower()

	if lower == "main":
		EditorInterface.play_main_scene()
	elif lower == "current":
		EditorInterface.play_current_scene()
	else:
		if not FileAccess.file_exists(mode):
			return error_not_found("Scene file: %s" % mode)
		EditorInterface.play_custom_scene(mode)

	return success({"playing": true, "mode": mode})


func _stop_scene(_params: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return success({"stopped": false, "message": "No scene is currently playing"})
	EditorInterface.stop_playing_scene()
	_cleanup_ipc_files()
	return success({"stopped": true})


func _save_scene(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var requested: String = optional_string(params, "path", "")
	var current: String = _normalize_res_path(root.scene_file_path)
	var target: String = _normalize_res_path(requested) if not requested.is_empty() else current
	if target.is_empty():
		return error(-32602, "No save path specified and scene has no existing path")

	var open_scenes: Array[String] = []
	for open_path: String in EditorInterface.get_open_scenes():
		open_scenes.append(_normalize_res_path(open_path))

	if open_scenes.has(target) and target != current:
		return error(
			-32009,
			"Target scene is open in another editor tab — saving over it would discard that buffer",
			{
				"path": target,
				"active_scene": current,
				"open_scenes": open_scenes,
				"suggestion": "Open the target scene tab before saving it",
			}
		)

	var dir_path: String = target.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		var mk_err: int = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return error(
				-32603, "Could not create directory %s: %s" % [dir_path, error_string(mk_err)]
			)

	var method: String = ""
	if current.is_empty() or current != target:
		EditorInterface.save_scene_as(target)
		method = "save_scene_as"
	else:
		var err: int = EditorInterface.save_scene()
		if err != OK:
			return error(-32603, "Could not save scene %s: %s" % [target, error_string(err)])
		method = "save_scene"

	return success({"path": target, "saved": true, "method": method})


func _get_scene_exports(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]
	if not FileAccess.file_exists(path):
		return error_not_found("Scene file: %s" % path)

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return error(-32603, "Resource is not a PackedScene: %s" % path)
	var root: Node = packed.instantiate()
	if root == null:
		return error(-32603, "Could not instantiate scene: %s" % path)

	var nodes: Array = []
	_collect_exports(root, root, nodes)
	root.queue_free()

	return success({"path": path, "nodes": nodes, "count": nodes.size()})


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


func _collect_exports(node: Node, root: Node, out: Array) -> void:
	var scr: Script = node.get_script() as Script
	if scr != null:
		var exports: Dictionary = {}
		for prop: Dictionary in scr.get_script_property_list():
			var usage: int = int(prop.get("usage", 0))
			if usage & PROPERTY_USAGE_EDITOR == 0:
				continue
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var prop_name: String = str(prop.get("name", ""))
			if prop_name.is_empty():
				continue
			exports[prop_name] = {
				"value": PropertyParser.serialize_value(node.get(prop_name)),
				"type": int(prop.get("type", TYPE_NIL)),
				"hint": int(prop.get("hint", 0)),
				"hint_string": str(prop.get("hint_string", "")),
			}
		if not exports.is_empty():
			out.append(
				{
					"node_path": "." if node == root else str(root.get_path_to(node)),
					"node_name": str(node.name),
					"node_type": node.get_class(),
					"script_path": scr.resource_path,
					"exports": exports,
				}
			)

	for child: Node in node.get_children():
		_collect_exports(child, root, out)


## Canonical res:// form so open-scene comparisons never miss on path spelling.
func _normalize_res_path(path: String) -> String:
	if path.is_empty():
		return ""
	return ProjectSettings.localize_path(path.strip_edges()).simplify_path()


func _cleanup_ipc_files() -> void:
	var dir: String = get_game_user_dir()
	if dir.is_empty():
		return
	for file_name: String in IPC_TEMP_FILES:
		var file_path: String = "%s/%s" % [dir, file_name]
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)
