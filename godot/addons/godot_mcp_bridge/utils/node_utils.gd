@tool
extends RefCounted

## Node tree / property helpers shared by the command modules.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")


## {name, type, path (relative to the scene root), script (path or null), children: [...]}
static func get_node_tree(node: Node, max_depth: int = -1, depth: int = 0) -> Dictionary:
	if node == null:
		return {}

	var script_path: Variant = null
	var scr: Script = node.get_script() as Script
	if scr != null and not scr.resource_path.is_empty():
		script_path = scr.resource_path

	var out: Dictionary = {
		"name": str(node.name),
		"type": node.get_class(),
		"path": _relative_path(node),
		"script": script_path,
		"children": [],
	}

	if max_depth >= 0 and depth >= max_depth:
		out["truncated"] = node.get_child_count() > 0
		return out

	var children: Array = []
	for child: Node in node.get_children():
		children.append(get_node_tree(child, max_depth, depth + 1))
	out["children"] = children
	return out


static func _relative_path(node: Node) -> String:
	var root: Node = EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
	if root == null:
		root = node.get_tree().current_scene if node.is_inside_tree() else null
	if root == null:
		return str(node.name)
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return str(root.get_path_to(node))
	return str(node.name)


static func set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null or owner == null:
		return
	if node != owner:
		node.owner = owner
	for child: Node in node.get_children():
		set_owner_recursive(child, owner)


## Editor-visible properties of a node, serialized with property_parser.serialize_value.
static func get_node_properties_dict(node: Node, prefix_filter: String = "") -> Dictionary:
	var out: Dictionary = {}
	if node == null:
		return out
	for prop: Dictionary in node.get_property_list():
		var usage: int = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if usage & PROPERTY_USAGE_GROUP != 0 or usage & PROPERTY_USAGE_CATEGORY != 0:
			continue
		if usage & PROPERTY_USAGE_SUBGROUP != 0:
			continue
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty():
			continue
		if not prefix_filter.is_empty() and not prop_name.begins_with(prefix_filter):
			continue
		out[prop_name] = PropertyParser.serialize_value(node.get(prop_name))
	return out
