@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## node category (SPEC §6, specs/B03-node.md) — 17 tools.
##
## Every handler needs an open edited scene ([E+S]): null root -> error_no_scene().
## Node paths in results are always root-relative (root itself serializes as ".").
## Every scene mutation is exactly one EditorUndoRedoManager action "MCP: <tool_name>".

const NodeUtils := preload("res://addons/godot_mcp_bridge/utils/node_utils.gd")
const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## Control.LayoutPreset, keyed by the wire enum names (zod enum, 16 values).
const ANCHOR_PRESETS := {
	"top_left": Control.PRESET_TOP_LEFT,
	"top_right": Control.PRESET_TOP_RIGHT,
	"bottom_left": Control.PRESET_BOTTOM_LEFT,
	"bottom_right": Control.PRESET_BOTTOM_RIGHT,
	"center_left": Control.PRESET_CENTER_LEFT,
	"center_top": Control.PRESET_CENTER_TOP,
	"center_right": Control.PRESET_CENTER_RIGHT,
	"center_bottom": Control.PRESET_CENTER_BOTTOM,
	"center": Control.PRESET_CENTER,
	"left_wide": Control.PRESET_LEFT_WIDE,
	"top_wide": Control.PRESET_TOP_WIDE,
	"right_wide": Control.PRESET_RIGHT_WIDE,
	"bottom_wide": Control.PRESET_BOTTOM_WIDE,
	"vcenter_wide": Control.PRESET_VCENTER_WIDE,
	"hcenter_wide": Control.PRESET_HCENTER_WIDE,
	"full_rect": Control.PRESET_FULL_RECT,
}

const ANCHOR_PROPERTIES: Array[String] = [
	"anchor_left",
	"anchor_top",
	"anchor_right",
	"anchor_bottom",
	"offset_left",
	"offset_top",
	"offset_right",
	"offset_bottom",
]

const SELECT_MODES: Array[String] = ["replace", "add", "remove"]


func get_commands() -> Dictionary:
	return {
		"add_node": _add_node,
		"delete_node": _delete_node,
		"duplicate_node": _duplicate_node,
		"move_node": _move_node,
		"update_property": _update_property,
		"get_node_properties": _get_node_properties,
		"add_resource": _add_resource,
		"set_anchor_preset": _set_anchor_preset,
		"rename_node": _rename_node,
		"connect_signal": _connect_signal,
		"disconnect_signal": _disconnect_signal,
		"get_node_groups": _get_node_groups,
		"set_node_groups": _set_node_groups,
		"find_nodes_in_group": _find_nodes_in_group,
		"get_editor_selection": _get_editor_selection,
		"select_nodes": _select_nodes,
		"clear_editor_selection": _clear_editor_selection,
	}


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _add_node(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var type_res: Array = require_string(params, "type")
	if type_res[1] != null:
		return type_res[1]
	var type_name: String = type_res[0]

	var parent_path: String = optional_string(params, "parent_path", ".")
	var node_name: String = optional_string(params, "name", "")

	var props_res: Array = _require_dict(params, "properties")
	if props_res[1] != null:
		return props_res[1]
	var properties: Dictionary = props_res[0]

	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Node '%s'" % parent_path)

	var made: Array = _instantiate_node_type(type_name)
	if made[1] != null:
		return made[1]
	var node: Node = made[0]

	# Always resolve a name: leaving it empty makes Godot fall back to "@Sprite2D@18537".
	node.name = unique_child_name(parent, node_name, node.get_class())

	var applied: Array[String] = _apply_properties(node, properties)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		node.free()
		return _error_no_undo()

	ur.create_action("MCP: add_node")
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()

	return success(
		{
			"node_path": _rel(root, node),
			"type": type_name,
			"name": str(node.name),
			"properties_applied": applied,
		}
	)


func _delete_node(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)
	if node == root:
		return error(-32000, "Cannot delete the root node")

	var parent: Node = node.get_parent()
	if parent == null:
		return error(-32000, "Node '%s' has no parent" % node_path)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	var node_name: String = str(node.name)
	var parent_path: String = _rel(root, parent)

	ur.create_action("MCP: delete_node")
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node, true)
	ur.add_undo_method(node, "set_owner", root)
	ur.add_undo_reference(node)
	ur.commit_action()

	return success({"deleted": node_name, "parent": parent_path})


func _duplicate_node(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)
	if node == root:
		return error(-32000, "Cannot duplicate the root node")

	var parent: Node = node.get_parent()
	if parent == null:
		return error(-32000, "Node '%s' has no parent" % node_path)

	var original_name: String = str(node.name)
	var new_name: String = optional_string(params, "name", "")
	if new_name.is_empty():
		new_name = "%s_copy" % original_name

	var dup: Node = node.duplicate()
	if dup == null:
		return error(-32603, "Could not duplicate node '%s'" % node_path)
	dup.name = unique_child_name(node.get_parent(), new_name, dup.get_class())

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		dup.free()
		return _error_no_undo()

	ur.create_action("MCP: duplicate_node")
	ur.add_do_method(parent, "add_child", dup, true)
	ur.add_do_method(dup, "set_owner", root)
	ur.add_do_reference(dup)
	ur.add_undo_method(parent, "remove_child", dup)
	ur.commit_action()

	# Duplicated children need owners too, or they never reach the .tscn.
	NodeUtils.set_owner_recursive(dup, root)

	return success(
		{
			"original": _rel(root, node),
			"duplicate": _rel(root, dup),
			"name": str(dup.name),
		}
	)


func _move_node(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var parent_res: Array = require_string(params, "new_parent_path")
	if parent_res[1] != null:
		return parent_res[1]
	var new_parent_path: String = parent_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)
	if node == root:
		return error(-32000, "Cannot move the root node")

	var new_parent: Node = find_node_by_path(new_parent_path)
	if new_parent == null:
		return error_not_found("Node '%s'" % new_parent_path)
	if new_parent == node or node.is_ancestor_of(new_parent):
		return error(-32000, "Cannot move a node into its own subtree")

	var old_parent: Node = node.get_parent()
	if old_parent == null:
		return error(-32000, "Node '%s' has no parent" % node_path)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	var moved_from: String = _rel(root, node)
	var old_parent_path: String = _rel(root, old_parent)

	ur.create_action("MCP: move_node")
	ur.add_do_method(old_parent, "remove_child", node)
	ur.add_do_method(new_parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_undo_method(new_parent, "remove_child", node)
	ur.add_undo_method(old_parent, "add_child", node, true)
	ur.add_undo_method(node, "set_owner", root)
	ur.commit_action()

	NodeUtils.set_owner_recursive(node, root)

	return success(
		{
			"node": moved_from,
			"old_parent": old_parent_path,
			"new_parent": _rel(root, new_parent),
			"new_path": _rel(root, node),
		}
	)


func _update_property(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var prop_res: Array = require_string(params, "property")
	if prop_res[1] != null:
		return prop_res[1]
	var property: String = prop_res[0]

	if not params.has("value"):
		return error(-32602, "Missing required parameter: value")
	var raw_value: Variant = params["value"]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var entry: Dictionary = _find_property_entry(node, property)
	if entry.is_empty():
		return error(
			-32001,
			"Property '%s' on %s not found" % [property, node.get_class()],
			{"available": _visible_property_names(node, 20)}
		)

	var old_raw: Variant = node.get(property)
	var new_raw: Variant

	var hint: int = int(entry.get("hint", PROPERTY_HINT_NONE))
	var value_is_string: bool = (
		typeof(raw_value) == TYPE_STRING or typeof(raw_value) == TYPE_STRING_NAME
	)
	if value_is_string and hint == PROPERTY_HINT_NODE_TYPE:
		# Typed node export: typeof() reads TYPE_NIL when unset, so the hint must drive this.
		var ref_path: String = String(raw_value)
		var target: Node = node.get_node_or_null(NodePath(ref_path))
		if target == null:
			target = root.get_node_or_null(NodePath(ref_path))
		if target == null:
			return error_not_found("Node '%s'" % ref_path)
		new_raw = target
	else:
		new_raw = PropertyParser.parse_value(raw_value, typeof(old_raw))

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	ur.create_action("MCP: update_property")
	ur.add_do_property(node, property, new_raw)
	ur.add_undo_property(node, property, old_raw)
	ur.commit_action()

	return success(
		{
			"node_path": _rel(root, node),
			"property": property,
			"old_value": PropertyParser.serialize_value(old_raw),
			"new_value": PropertyParser.serialize_value(node.get(property)),
		}
	)


func _get_node_properties(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var category: String = optional_string(params, "category", "")

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	return success(
		{
			"node_path": _rel(root, node),
			"type": node.get_class(),
			"properties": NodeUtils.get_node_properties_dict(node, category),
		}
	)


func _add_resource(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var prop_res: Array = require_string(params, "property")
	if prop_res[1] != null:
		return prop_res[1]
	var property: String = prop_res[0]

	var type_res: Array = require_string(params, "resource_type")
	if type_res[1] != null:
		return type_res[1]
	var resource_type: String = type_res[0]

	var props_res: Array = _require_dict(params, "resource_properties")
	if props_res[1] != null:
		return props_res[1]
	var resource_properties: Dictionary = props_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	# A missing target property makes add_do_property a silent no-op (Object::set fails),
	# which would return success while nothing was assigned. Guard like _update_property.
	if _find_property_entry(node, property).is_empty():
		return error(
			-32001,
			"Property '%s' on %s not found" % [property, node.get_class()],
			{"available": _visible_property_names(node, 20)}
		)

	if not ClassDB.class_exists(resource_type):
		return error(-32602, "Unknown resource type '%s'" % resource_type)
	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return error(-32602, "Type '%s' is not a Resource" % resource_type)

	var made: Variant = ClassDB.instantiate(resource_type)
	var resource: Resource = made as Resource
	if resource == null:
		return error(-32603, "Could not instantiate resource type '%s'" % resource_type)

	var applied: Array[String] = _apply_properties(resource, resource_properties)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	var previous: Variant = node.get(property)

	# No add_do_reference() here: UndoRedo explicitly forbids it for Resources, and the
	# do/undo property pair already holds the Ref on both sides of the action.
	ur.create_action("MCP: add_resource")
	ur.add_do_property(node, property, resource)
	ur.add_undo_property(node, property, previous)
	ur.commit_action()

	return success(
		{
			"node_path": _rel(root, node),
			"property": property,
			"resource_type": resource_type,
			"properties_applied": applied,
		}
	)


func _set_anchor_preset(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var preset_res: Array = require_string(params, "preset")
	if preset_res[1] != null:
		return preset_res[1]
	var preset: String = preset_res[0]

	var keep_offsets: bool = optional_bool(params, "keep_offsets", false)

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var control: Control = node as Control
	if control == null:
		return error(
			-32602, "Node '%s' is a %s, not a Control" % [node_path, node.get_class()]
		)
	if not ANCHOR_PRESETS.has(preset):
		return error(
			-32602,
			"Unknown anchor preset '%s'" % preset,
			{"available": ANCHOR_PRESETS.keys()}
		)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	# Never mutate the live node outside the undo action: compute on a scratch copy.
	var scratch: Control = control.duplicate() as Control
	if scratch == null:
		return error(-32603, "Could not duplicate Control '%s'" % node_path)

	# The scratch MUST be in the tree while the preset is computed: an orphaned Control
	# has get_parent_anchorable_rect() == Rect2() and size 0x0 (size/position are
	# editor-usage only, so duplicate() never copies them), which would collapse a
	# stretched Control to 0x0 under PRESET_MODE_KEEP_SIZE. Parent it to the real node's
	# parent so it resolves the same anchorable rect, then detach before freeing.
	var scratch_parent: Node = control.get_parent()
	if scratch_parent != null:
		scratch_parent.add_child(scratch, true)

	var mode: int = (
		Control.PRESET_MODE_KEEP_SIZE if keep_offsets else Control.PRESET_MODE_MINSIZE
	)
	scratch.set_anchors_and_offsets_preset(int(ANCHOR_PRESETS[preset]), mode)

	var computed: Dictionary = {}
	for prop: String in ANCHOR_PROPERTIES:
		computed[prop] = scratch.get(prop)

	if scratch_parent != null:
		scratch_parent.remove_child(scratch)
	scratch.free()

	ur.create_action("MCP: set_anchor_preset")
	for prop: String in ANCHOR_PROPERTIES:
		ur.add_do_property(control, prop, computed[prop])
		ur.add_undo_property(control, prop, control.get(prop))
	ur.commit_action()

	return success(
		{
			"node_path": _rel(root, control),
			"preset": preset,
			"keep_offsets": keep_offsets,
		}
	)


func _rename_node(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var name_res: Array = require_string(params, "new_name")
	if name_res[1] != null:
		return name_res[1]
	var new_name: String = name_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var old_name: String = str(node.name)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	ur.create_action("MCP: rename_node")
	ur.add_do_property(node, "name", new_name)
	ur.add_undo_property(node, "name", old_name)
	ur.commit_action()

	# Godot de-duplicates names against siblings — report what actually landed.
	return success(
		{"old_name": old_name, "new_name": str(node.name), "node_path": _rel(root, node)}
	)


func _connect_signal(params: Dictionary) -> Dictionary:
	var resolved: Array = _resolve_signal_params(params)
	if resolved[1] != null:
		return resolved[1]
	var ctx: Dictionary = resolved[0]

	var root: Node = ctx["root"]
	var source: Node = ctx["source"]
	var target: Node = ctx["target"]
	var signal_name: String = ctx["signal_name"]
	var method_name: String = ctx["method_name"]
	var callable := Callable(target, method_name)

	if source.is_connected(signal_name, callable):
		return success(
			{
				"source": _rel(root, source),
				"signal": signal_name,
				"target": _rel(root, target),
				"method": method_name,
				"already_connected": true,
			}
		)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	ur.create_action("MCP: connect_signal")
	# CONNECT_PERSIST is what serializes the connection into the .tscn.
	ur.add_do_method(source, "connect", signal_name, callable, Object.CONNECT_PERSIST)
	ur.add_undo_method(source, "disconnect", signal_name, callable)
	ur.commit_action()

	return success(
		{
			"source": _rel(root, source),
			"signal": signal_name,
			"target": _rel(root, target),
			"method": method_name,
			"connected": true,
		}
	)


func _disconnect_signal(params: Dictionary) -> Dictionary:
	var resolved: Array = _resolve_signal_params(params)
	if resolved[1] != null:
		return resolved[1]
	var ctx: Dictionary = resolved[0]

	var root: Node = ctx["root"]
	var source: Node = ctx["source"]
	var target: Node = ctx["target"]
	var signal_name: String = ctx["signal_name"]
	var method_name: String = ctx["method_name"]
	var callable := Callable(target, method_name)

	if not source.is_connected(signal_name, callable):
		return success(
			{
				"source": _rel(root, source),
				"signal": signal_name,
				"target": _rel(root, target),
				"method": method_name,
				"was_connected": false,
			}
		)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	ur.create_action("MCP: disconnect_signal")
	ur.add_do_method(source, "disconnect", signal_name, callable)
	ur.add_undo_method(source, "connect", signal_name, callable, Object.CONNECT_PERSIST)
	ur.commit_action()

	return success(
		{
			"source": _rel(root, source),
			"signal": signal_name,
			"target": _rel(root, target),
			"method": method_name,
			"disconnected": true,
		}
	)


func _get_node_groups(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var groups: Array[String] = _public_groups(node)
	return success({"node_path": _rel(root, node), "groups": groups, "count": groups.size()})


func _set_node_groups(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var path_res: Array = require_string(params, "node_path")
	if path_res[1] != null:
		return path_res[1]
	var node_path: String = path_res[0]

	if not params.has("groups") or typeof(params["groups"]) != TYPE_ARRAY:
		return error(-32602, "Parameter 'groups' must be an array of strings")

	var desired: Array[String] = []
	for raw: Variant in (params["groups"] as Array):
		if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:
			return error(-32602, "Parameter 'groups' must be an array of strings")
		var g: String = String(raw).strip_edges()
		if g.is_empty() or g.begins_with("_"):
			continue
		if not desired.has(g):
			desired.append(g)

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node '%s'" % node_path)

	var current: Array[String] = _public_groups(node)

	var removed: Array[String] = []
	for g: String in current:
		if not desired.has(g):
			removed.append(g)

	var added: Array[String] = []
	for g: String in desired:
		if not current.has(g):
			added.append(g)

	if removed.is_empty() and added.is_empty():
		return success(
			{"node_path": _rel(root, node), "groups": desired, "added": added, "removed": removed}
		)

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return _error_no_undo()

	ur.create_action("MCP: set_node_groups")
	for g: String in removed:
		ur.add_do_method(node, "remove_from_group", g)
		# persistent = true is mandatory — without it membership never reaches the .tscn.
		ur.add_undo_method(node, "add_to_group", g, true)
	for g: String in added:
		ur.add_do_method(node, "add_to_group", g, true)
		ur.add_undo_method(node, "remove_from_group", g)
	ur.commit_action()

	return success(
		{"node_path": _rel(root, node), "groups": desired, "added": added, "removed": removed}
	)


func _find_nodes_in_group(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var group_res: Array = require_string(params, "group")
	if group_res[1] != null:
		return group_res[1]
	var group: String = group_res[0]

	var nodes: Array[Dictionary] = []
	_collect_group_members(root, root, group, nodes)
	return success({"group": group, "nodes": nodes, "count": nodes.size()})


func _get_editor_selection(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var top_only: bool = optional_bool(params, "top_only", false)

	var selection: EditorSelection = EditorInterface.get_selection()
	if selection == null:
		return error(-32603, "Editor selection is unavailable")

	# get_top_selected_nodes() only exists on 4.4+; on 4.3 the same list is
	# get_transformable_selected_nodes(). Probe through call() so the static analyzer
	# never hard-fails this file on the minimum supported version (SPEC: Godot 4.3+).
	var raw: Array[Node] = []
	if top_only:
		if selection.has_method("get_top_selected_nodes"):
			raw.assign(selection.call("get_top_selected_nodes"))
		else:
			raw.assign(selection.call("get_transformable_selected_nodes"))
	else:
		raw = selection.get_selected_nodes()

	var nodes: Array[Dictionary] = _serialize_scene_nodes(root, raw)
	return success({"nodes": nodes, "count": nodes.size(), "top_only": top_only})


func _select_nodes(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var paths_res: Array = _extract_node_paths(params)
	if paths_res[1] != null:
		return paths_res[1]
	var paths: Array[String] = paths_res[0]

	var mode: String = optional_string(params, "mode", "replace")
	if not SELECT_MODES.has(mode):
		return error(
			-32602, "Invalid mode '%s'" % mode, {"available": SELECT_MODES.duplicate()}
		)

	var inspect: bool = optional_bool(params, "inspect", true)
	var focus: bool = optional_bool(params, "focus", inspect)
	var inspector_only: bool = optional_bool(params, "inspector_only", false)
	var for_property: String = optional_string(params, "for_property", "")

	# Resolve everything BEFORE touching the selection — failures leave it unchanged.
	var nodes: Array[Node] = []
	for p: String in paths:
		var node: Node = find_node_by_path(p)
		if node == null:
			return error_not_found("Node '%s'" % p)
		nodes.append(node)

	var selection: EditorSelection = EditorInterface.get_selection()
	if selection == null:
		return error(-32603, "Editor selection is unavailable")

	match mode:
		"replace":
			selection.clear()
			for node: Node in nodes:
				selection.add_node(node)
		"add":
			for node: Node in nodes:
				selection.add_node(node)
		"remove":
			for node: Node in nodes:
				selection.remove_node(node)

	# edit_node / inspect_object collapse the selection to one node — only safe for a single target.
	if mode != "remove" and nodes.size() == 1:
		if focus:
			EditorInterface.edit_node(nodes[0])
		if inspect:
			EditorInterface.inspect_object(nodes[0], for_property, inspector_only)

	var selected: Array[Dictionary] = _serialize_scene_nodes(
		root, selection.get_selected_nodes()
	)
	return success({"mode": mode, "selected": selected, "count": selected.size()})


func _clear_editor_selection(_params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var selection: EditorSelection = EditorInterface.get_selection()
	if selection == null:
		return error(-32603, "Editor selection is unavailable")

	var before: int = selection.get_selected_nodes().size()
	selection.clear()
	return success({"cleared": before, "count": 0})


# ---------------------------------------------------------------------------
# Local helpers
# ---------------------------------------------------------------------------


func _error_no_undo() -> Dictionary:
	return error(-32603, "EditorUndoRedoManager is unavailable")


## Root-relative path of a node ("." for the root itself).
func _rel(root: Node, node: Node) -> String:
	if root == null or node == null:
		return ""
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return str(root.get_path_to(node))
	return str(node.name)


func _node_info(root: Node, node: Node) -> Dictionary:
	return {"name": str(node.name), "path": _rel(root, node), "type": node.get_class()}


func _serialize_scene_nodes(root: Node, nodes: Array[Node]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in nodes:
		if node == null:
			continue
		if node != root and not root.is_ancestor_of(node):
			continue
		out.append(_node_info(root, node))
	return out


## [Dictionary, null] on success, [null, error_dict] when the key is present but not an object.
func _require_dict(params: Dictionary, key: String) -> Array:
	if not params.has(key) or params[key] == null:
		return [{}, null]
	if typeof(params[key]) != TYPE_DICTIONARY:
		return [null, error(-32602, "Parameter '%s' must be an object" % key)]
	return [params[key] as Dictionary, null]


## [Node, null] on success, [null, error_dict] otherwise. Handles ClassDB classes and
## project `class_name` scripts.
func _instantiate_node_type(type_name: String) -> Array:
	if ClassDB.class_exists(type_name):
		if not ClassDB.can_instantiate(type_name):
			return [null, error(-32602, "Node type '%s' cannot be instantiated" % type_name)]
		var made: Variant = ClassDB.instantiate(type_name)
		var node: Node = made as Node
		if node == null:
			return [null, error(-32602, "Type '%s' is not a Node" % type_name)]
		return [node, null]

	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) != type_name:
			continue
		var script_path: String = str(entry.get("path", ""))
		var script: Script = load(script_path) as Script
		if script == null:
			return [
				null,
				error(
					-32602,
					"Could not load script for class '%s' (%s)" % [type_name, script_path]
				)
			]
		var base: String = script.get_instance_base_type()
		if base.is_empty() or not ClassDB.class_exists(base):
			return [
				null,
				error(
					-32602,
					"Script class '%s' has an unknown base type '%s'" % [type_name, base]
				)
			]
		if not ClassDB.can_instantiate(base):
			return [
				null,
				error(-32602, "Base type '%s' of '%s' cannot be instantiated" % [base, type_name])
			]
		var base_made: Variant = ClassDB.instantiate(base)
		var script_node: Node = base_made as Node
		if script_node == null:
			return [null, error(-32602, "Script class '%s' does not extend Node" % type_name)]
		script_node.set_script(script)
		return [script_node, null]

	return [null, error(-32602, "Unknown node type '%s'" % type_name)]


## Applies props that exist on the object, coerced against the current value's type.
## Unknown keys are silently skipped. Returns the names actually applied.
func _apply_properties(obj: Object, props: Dictionary) -> Array[String]:
	var applied: Array[String] = []
	if obj == null or props.is_empty():
		return applied

	var known: Dictionary = {}
	for entry: Dictionary in obj.get_property_list():
		var prop_name: String = str(entry.get("name", ""))
		if not prop_name.is_empty():
			known[prop_name] = true

	for key: Variant in props:
		var key_name: String = str(key)
		if not known.has(key_name):
			continue
		var current: Variant = obj.get(key_name)
		obj.set(key_name, PropertyParser.parse_value(props[key], typeof(current)))
		applied.append(key_name)
	return applied


## Shared resolution for connect_signal / disconnect_signal.
## [{root, source, target, signal_name, method_name}, null] or [null, error_dict].
func _resolve_signal_params(params: Dictionary) -> Array:
	var root: Node = get_edited_root()
	if root == null:
		return [null, error_no_scene()]

	var source_res: Array = require_string(params, "source_path")
	if source_res[1] != null:
		return [null, source_res[1]]
	var source_path: String = source_res[0]

	var signal_res: Array = require_string(params, "signal_name")
	if signal_res[1] != null:
		return [null, signal_res[1]]
	var signal_name: String = signal_res[0]

	var target_res: Array = require_string(params, "target_path")
	if target_res[1] != null:
		return [null, target_res[1]]
	var target_path: String = target_res[0]

	var method_res: Array = require_string(params, "method_name")
	if method_res[1] != null:
		return [null, method_res[1]]
	var method_name: String = method_res[0]

	var source: Node = find_node_by_path(source_path)
	if source == null:
		return [null, error_not_found("Node '%s'" % source_path)]

	var target: Node = find_node_by_path(target_path)
	if target == null:
		return [null, error_not_found("Node '%s'" % target_path)]

	if not source.has_signal(signal_name):
		return [
			null,
			error(
				-32602,
				"Signal '%s' does not exist on %s" % [signal_name, source.get_class()]
			)
		]

	return [
		{
			"root": root,
			"source": source,
			"target": target,
			"signal_name": signal_name,
			"method_name": method_name,
		},
		null,
	]


func _find_property_entry(node: Node, property: String) -> Dictionary:
	for entry: Dictionary in node.get_property_list():
		if str(entry.get("name", "")) == property:
			return entry
	return {}


func _visible_property_names(node: Node, limit: int) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in node.get_property_list():
		if out.size() >= limit:
			break
		var usage: int = int(entry.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY) != 0:
			continue
		var prop_name: String = str(entry.get("name", ""))
		if not prop_name.is_empty():
			out.append(prop_name)
	return out


## Groups minus editor bookkeeping ("_"-prefixed internal groups).
func _public_groups(node: Node) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in node.get_groups():
		var g: String = String(raw)
		if g.begins_with("_"):
			continue
		out.append(g)
	return out


## Recursive walk of the EDITED scene only — SceneTree.get_nodes_in_group() would leak
## editor-internal nodes.
func _collect_group_members(
	root: Node, node: Node, group: String, out: Array[Dictionary]
) -> void:
	if node.is_in_group(group):
		out.append(_node_info(root, node))
	for child: Node in node.get_children():
		_collect_group_members(root, child, group, out)


## select_nodes one-of extractor: node_paths wins over node_path; neither → -32602.
func _extract_node_paths(params: Dictionary) -> Array:
	var out: Array[String] = []

	if params.has("node_paths") and params["node_paths"] != null:
		if typeof(params["node_paths"]) != TYPE_ARRAY:
			return [null, error(-32602, "Parameter 'node_paths' must be an array of strings")]
		for raw: Variant in (params["node_paths"] as Array):
			if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:
				return [null, error(-32602, "Parameter 'node_paths' must be an array of strings")]
			var p: String = String(raw).strip_edges()
			if p.is_empty():
				return [null, error(-32602, "Parameter 'node_paths' contains an empty path")]
			out.append(p)
		return [out, null]

	if params.has("node_path") and params["node_path"] != null:
		var single: Array = require_string(params, "node_path")
		if single[1] != null:
			return [null, single[1]]
		out.append(String(single[0]))
		return [out, null]

	return [null, error(-32602, "provide node_path or node_paths")]
