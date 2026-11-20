@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## shader category (SPEC §6, specs/B04-script-shader.md) — 6 tools.
##
## create_shader, read_shader, edit_shader, assign_shader_material,
## set_shader_param, get_shader_params.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

const SHADER_PARAM_PREFIX := "shader_parameter/"

const SHADER_TYPES: PackedStringArray = ["spatial", "canvas_item", "particles", "sky"]

const TEMPLATES: Dictionary = {
	"spatial": "shader_type spatial;\n\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n",
	"canvas_item": "shader_type canvas_item;\n\nvoid fragment() {\n\tCOLOR = vec4(1.0);\n}\n",
	"particles":
	(
		"shader_type particles;\n\nvoid start() {\n\t// Runs when a particle spawns.\n}\n\n"
		+ "void process() {\n\t// Runs every frame per particle.\n}\n"
	),
	"sky": "shader_type sky;\n\nvoid sky() {\n\tCOLOR = vec3(0.3, 0.5, 0.8);\n}\n",
}


func get_commands() -> Dictionary:
	return {
		"create_shader": _create_shader,
		"read_shader": _read_shader,
		"edit_shader": _edit_shader,
		"assign_shader_material": _assign_shader_material,
		"set_shader_param": _set_shader_param,
		"get_shader_params": _get_shader_params,
	}


# ---------------------------------------------------------------------------
# Shared private helpers
# ---------------------------------------------------------------------------


## Hot-swap the cached Shader resource so future loads resolve to the new code without an
## editor restart, then re-import the file.
func _refresh_cached_shader(path: String, content: String) -> void:
	if ResourceLoader.has_cached(path):
		# Mutate the CACHED instance in place: every live ShaderMaterial already points at it, so
		# they pick up the new code and keep their resource_path. Creating a replacement Shader and
		# calling take_over_path() would blank the old instance's resource_path (the scene would
		# then save the shader as an embedded sub_resource) and the replacement — a bare local ref —
		# would be freed on return, leaving no cache entry at all.
		var cached: Shader = (
			ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REUSE) as Shader
		)
		if cached != null:
			cached.code = content
			cached.emit_changed()
	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)


## Which property carries a material on this node: "material", "material_override", or "".
func _material_property(node: Node) -> String:
	if node is CanvasItem:
		return "material"
	if node is MeshInstance3D:
		return "material_override"
	if "material" in node:
		return "material"
	return ""


## {"material": ShaderMaterial, "property": String} — EMPTY Dictionary when the node holds no
## ShaderMaterial. Callers check .is_empty(), never != null (SPEC §9.1).
func _find_shader_material(node: Node) -> Dictionary:
	var prop: String = _material_property(node)
	if prop.is_empty():
		return {}
	var mat: ShaderMaterial = node.get(prop) as ShaderMaterial
	if mat == null:
		return {}
	return {"material": mat, "property": prop}


func _error_no_shader_material(node: Node) -> Dictionary:
	return error(
		-32000,
		"Node has no ShaderMaterial",
		{"node_class": node.get_class(), "suggestion": "assign_shader_material"}
	)


func _write_file(path: String, content: String) -> Dictionary:
	var base_dir: String = path.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		DirAccess.make_dir_recursive_absolute(base_dir)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return error(
			-32603,
			"Could not open file for writing: %s" % path,
			{"path": path, "error": error_string(FileAccess.get_open_error())}
		)
	file.store_string(content)
	file.close()
	return {}


func _read_file(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [
			null,
			error(
				-32603,
				"Could not read file: %s" % path,
				{"path": path, "error": error_string(FileAccess.get_open_error())}
			)
		]
	var text: String = file.get_as_text()
	file.close()
	return [text, null]


func _relative_node_path(node: Node) -> String:
	var root: Node = get_edited_root()
	if node == null:
		return ""
	if root == null:
		return str(node.name)
	if node == root:
		return "."
	return str(root.get_path_to(node))


## [node, error_or_null] — resolves the edited scene + node for the [E+S] tools.
func _resolve_scene_node(params: Dictionary) -> Array:
	var res: Array = require_string(params, "node_path")
	if res[1] != null:
		return [null, res[1]]
	var node_path: String = res[0]
	if get_edited_root() == null:
		return [null, error_no_scene()]
	var node: Node = find_node_by_path(node_path)
	if node == null:
		return [null, error_not_found("Node: %s" % node_path)]
	return [node, null]


# ---------------------------------------------------------------------------
# create_shader
# ---------------------------------------------------------------------------


func _create_shader(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var force: bool = optional_bool(params, "force", false)
	var write_guard: Dictionary = guard_text_resource_write(path, force)
	if not write_guard.is_empty():
		return write_guard

	var shader_type: String = optional_string(params, "shader_type", "spatial")
	if not TEMPLATES.has(shader_type):
		return error(
			-32602,
			"Unknown shader_type: %s" % shader_type,
			{"shader_type": shader_type, "allowed": SHADER_TYPES}
		)

	var content: String = optional_string(params, "content", "")
	var template_used: bool = content.is_empty()
	if template_used:
		content = str(TEMPLATES[shader_type])

	var write_err: Dictionary = _write_file(path, content)
	if not write_err.is_empty():
		return write_err

	_refresh_cached_shader(path, content)

	return success(
		{
			"path": path,
			"shader_type": shader_type,
			"created": true,
			"template_used": template_used,
		}
	)


# ---------------------------------------------------------------------------
# read_shader
# ---------------------------------------------------------------------------


func _read_shader(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	if not FileAccess.file_exists(path):
		return error_not_found("Shader: %s" % path)

	var read: Array = _read_file(path)
	if read[1] != null:
		return read[1]
	var content: String = read[0]

	return success({"path": path, "content": content, "size": content.length()})


# ---------------------------------------------------------------------------
# edit_shader
# ---------------------------------------------------------------------------


func _edit_shader(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var has_content: bool = params.has("content")
	var has_replacements: bool = params.has("replacements")
	if has_content == has_replacements:
		return error(
			-32602,
			"edit_shader requires exactly one of `content` (full replace) or `replacements`",
			{"path": path, "content": has_content, "replacements": has_replacements}
		)

	if not FileAccess.file_exists(path):
		return error_not_found("Shader: %s" % path)

	var force: bool = optional_bool(params, "force", false)
	var write_guard: Dictionary = guard_text_resource_write(path, force)
	if not write_guard.is_empty():
		return write_guard

	var read: Array = _read_file(path)
	if read[1] != null:
		return read[1]
	var original: String = read[0]

	var mode: String = "full"
	var new_content: String = original
	var changes_made: int = 1

	if has_content:
		new_content = optional_string(params, "content", "")
	else:
		mode = "replacements"
		var applied: Dictionary = _apply_replacements(original, params["replacements"])
		if applied.has("error"):
			return applied
		new_content = str(applied["content"])
		changes_made = int(applied["changes_made"])

	var write_err: Dictionary = _write_file(path, new_content)
	if not write_err.is_empty():
		return write_err

	_refresh_cached_shader(path, new_content)

	return success(
		{
			"path": path,
			"mode": mode,
			"changes_made": changes_made,
			"size": new_content.length(),
		}
	)


## All-or-nothing literal replace-all. Returns {"content", "changes_made"} or an error dict.
func _apply_replacements(original: String, raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return error(-32602, "replacements must be an array of {search, replace} objects")
	var items: Array = raw
	if items.is_empty():
		return error(-32602, "replacements must contain at least one {search, replace} item")

	var content: String = original
	var applied: int = 0
	var index: int = 0

	for item: Variant in items:
		index += 1
		if typeof(item) != TYPE_DICTIONARY:
			return error(
				-32602,
				"replacements[%d] must be an object with search/replace" % (index - 1),
				{"attempted": index, "total": items.size(), "applied": applied}
			)
		var entry: Dictionary = item
		var search: String = str(entry.get("search", ""))
		var replace: String = str(entry.get("replace", ""))
		if search.is_empty():
			return error(
				-32602,
				"replacements[%d].search must not be empty" % (index - 1),
				{"attempted": index, "total": items.size(), "applied": applied}
			)
		if content.count(search) == 0:
			return error(
				-32001,
				"search text not found: %s" % search,
				{"attempted": index, "total": items.size(), "applied": applied}
			)
		content = content.replace(search, replace)
		applied += 1

	return {"content": content, "changes_made": applied}


# ---------------------------------------------------------------------------
# assign_shader_material  [E+S]
# ---------------------------------------------------------------------------


func _assign_shader_material(params: Dictionary) -> Dictionary:
	var resolved: Array = _resolve_scene_node(params)
	if resolved[1] != null:
		return resolved[1]
	var node: Node = resolved[0]

	var shader_res: Array = require_string(params, "shader_path")
	if shader_res[1] != null:
		return shader_res[1]
	var shader_path: String = shader_res[0]

	if not ResourceLoader.exists(shader_path):
		return error_not_found("Shader: %s" % shader_path)

	var loaded: Resource = load(shader_path)
	var shader: Shader = loaded as Shader
	if shader == null:
		return error(
			-32602,
			"Resource is not a Shader: %s" % shader_path,
			{
				"path": shader_path,
				"resource_class": loaded.get_class() if loaded != null else "null",
			}
		)

	var prop: String = _material_property(node)
	if prop.is_empty():
		return error(
			-32000,
			"node type does not support materials",
			{"node_class": node.get_class(), "node_path": _relative_node_path(node)}
		)

	var material := ShaderMaterial.new()
	material.shader = shader

	var previous: Variant = node.get(prop)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return error(-32603, "EditorUndoRedoManager unavailable")

	ur.create_action("MCP: assign_shader_material")
	ur.add_do_property(node, prop, material)
	ur.add_undo_property(node, prop, previous)
	ur.commit_action()

	return success(
		{
			"node_path": _relative_node_path(node),
			"shader_path": shader_path,
			"property": prop,
			"assigned": true,
		}
	)


# ---------------------------------------------------------------------------
# set_shader_param  [E+S] — resource mutation, deliberately NOT an undo action
# ---------------------------------------------------------------------------


func _set_shader_param(params: Dictionary) -> Dictionary:
	var resolved: Array = _resolve_scene_node(params)
	if resolved[1] != null:
		return resolved[1]
	var node: Node = resolved[0]

	var param_res: Array = require_string(params, "param")
	if param_res[1] != null:
		return param_res[1]
	var param_name: String = param_res[0]

	if not params.has("value"):
		return error(-32602, "Missing required parameter: value")

	var found: Dictionary = _find_shader_material(node)
	if found.is_empty():
		return _error_no_shader_material(node)
	var material: ShaderMaterial = found["material"]

	var prop_path: String = SHADER_PARAM_PREFIX + param_name
	var target_type: int = _shader_param_type(material, prop_path)
	var old_value: Variant = material.get(prop_path)
	var new_value: Variant = PropertyParser.parse_value(params["value"], target_type)

	material.set(prop_path, new_value)
	material.emit_changed()
	# No undo action (SPEC: resource mutation, not a scene-tree change), but a built-in material is
	# a sub-resource of the edited scene — without the dirty flag Ctrl+S is a no-op and the value is
	# lost on close.
	if get_edited_root() != null:
		EditorInterface.mark_scene_as_unsaved()

	return success(
		{
			"node_path": _relative_node_path(node),
			"param": param_name,
			"old_value": PropertyParser.serialize_value(old_value),
			"new_value": PropertyParser.serialize_value(material.get(prop_path)),
		}
	)


func _shader_param_type(material: ShaderMaterial, prop_path: String) -> int:
	for prop: Dictionary in material.get_property_list():
		if str(prop.get("name", "")) == prop_path:
			return int(prop.get("type", TYPE_NIL))
	return TYPE_NIL


# ---------------------------------------------------------------------------
# get_shader_params  [E+S]
# ---------------------------------------------------------------------------


func _get_shader_params(params: Dictionary) -> Dictionary:
	var resolved: Array = _resolve_scene_node(params)
	if resolved[1] != null:
		return resolved[1]
	var node: Node = resolved[0]

	var found: Dictionary = _find_shader_material(node)
	if found.is_empty():
		return _error_no_shader_material(node)
	var material: ShaderMaterial = found["material"]

	var out: Dictionary = {}
	for prop: Dictionary in material.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with(SHADER_PARAM_PREFIX):
			continue
		var short_name: String = prop_name.substr(SHADER_PARAM_PREFIX.length())
		out[short_name] = PropertyParser.serialize_value(material.get(prop_name))

	var shader_path: String = ""
	if material.shader != null:
		shader_path = material.shader.resource_path

	return success(
		{
			"node_path": _relative_node_path(node),
			"shader": shader_path,
			"params": out,
			"count": out.size(),
		}
	)
