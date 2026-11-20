@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B10 — theme commands (7 tools).
##
## `create_theme` is [E]: editor-only, writes a resource file, creates no undo action.
## Every other tool is [E+S]: it resolves `node_path` against the edited scene root and requires a
## Control. Each mutating tool commits exactly ONE EditorUndoRedoManager action labeled
## "MCP: <tool_name>" (SPEC §3.4).
##
## SPEC §9.1: conflict guards return an EMPTY Dictionary when OK — check with `.is_empty()`.
## A Dictionary is never null, so `guard != null` is always true and would make the save dead
## code. That is the reference product's bug; it is fixed here.
## SPEC §9.2: the reference product's dead `theme` type-name param on set_theme_color is dropped.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## Theme override kind -> the Control property group it lives in.
const OVERRIDE_GROUPS := {
	"color": "theme_override_colors",
	"constant": "theme_override_constants",
	"font_size": "theme_override_font_sizes",
	"stylebox": "theme_override_styles",
}

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

const SIZE_FLAGS := {
	"fill": Control.SIZE_FILL,
	"expand": Control.SIZE_EXPAND,
	"fill_expand": Control.SIZE_EXPAND_FILL,
	"shrink_center": Control.SIZE_SHRINK_CENTER,
	"shrink_end": Control.SIZE_SHRINK_END,
}

const GROW_DIRECTIONS := {
	"begin": Control.GROW_DIRECTION_BEGIN,
	"end": Control.GROW_DIRECTION_END,
	"both": Control.GROW_DIRECTION_BOTH,
}

## Layout properties whose old/new values setup_control captures for its single undo action.
const LAYOUT_PROPERTIES: PackedStringArray = [
	"anchor_left",
	"anchor_top",
	"anchor_right",
	"anchor_bottom",
	"offset_left",
	"offset_top",
	"offset_right",
	"offset_bottom",
	"custom_minimum_size",
	"size_flags_horizontal",
	"size_flags_vertical",
	"grow_horizontal",
	"grow_vertical",
]

const MARGIN_CONSTANTS := {
	"left": "margin_left",
	"top": "margin_top",
	"right": "margin_right",
	"bottom": "margin_bottom",
}


func get_commands() -> Dictionary:
	return {
		"create_theme": _create_theme,
		"set_theme_color": _set_theme_color,
		"set_theme_constant": _set_theme_constant,
		"set_theme_font_size": _set_theme_font_size,
		"set_theme_stylebox": _set_theme_stylebox,
		"setup_control": _setup_control,
		"get_theme_info": _get_theme_info,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Control gate for the [E+S] tools. Returns [Control, null] or [null, error_dict].
func _get_control(node_path: String) -> Array:
	var node: Node = find_node_by_path(node_path)
	if node == null:
		return [null, error_not_found("Node at '%s'" % node_path)]
	if not (node is Control):
		return [null, error_not_found("Control at '%s'" % node_path)]
	return [node as Control, null]


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


func _has_override(control: Control, kind: String, override_name: String) -> bool:
	if control == null:
		return false
	var sn := StringName(override_name)
	match kind:
		"color":
			return control.has_theme_color_override(sn)
		"constant":
			return control.has_theme_constant_override(sn)
		"font_size":
			return control.has_theme_font_size_override(sn)
		"stylebox":
			return control.has_theme_stylebox_override(sn)
	return false


## Current override value, or null when the Control carries no override of that name.
func _get_override(control: Control, kind: String, override_name: String) -> Variant:
	if control == null or not OVERRIDE_GROUPS.has(kind):
		return null
	return control.get("%s/%s" % [String(OVERRIDE_GROUPS[kind]), override_name])


## Shared undo-side restore (also used do-side by setup_control's constants):
## re-add the prior override when `had`, otherwise drop the override entirely.
func _restore_override(
	control: Control, kind: String, override_name: String, had: bool, old: Variant
) -> void:
	if control == null:
		return
	var sn := StringName(override_name)
	match kind:
		"color":
			if had and typeof(old) == TYPE_COLOR:
				control.add_theme_color_override(sn, old)
			else:
				control.remove_theme_color_override(sn)
		"constant":
			if had:
				control.add_theme_constant_override(sn, int(old))
			else:
				control.remove_theme_constant_override(sn)
		"font_size":
			if had:
				control.add_theme_font_size_override(sn, int(old))
			else:
				control.remove_theme_font_size_override(sn)
		"stylebox":
			if had and old is StyleBox:
				control.add_theme_stylebox_override(sn, old as StyleBox)
			else:
				control.remove_theme_stylebox_override(sn)


## Returns [Color, null] or [null, error_dict].
func _parse_color(raw: Variant, key: String) -> Array:
	var parsed: Variant = PropertyParser.parse_value(raw, TYPE_COLOR)
	if typeof(parsed) != TYPE_COLOR:
		return [
			null,
			error(
				-32602,
				(
					"Invalid %s: expected '#rrggbb[aa]' or 'Color(r, g, b, a)', got '%s'"
					% [key, str(raw)]
				)
			)
		]
	return [parsed as Color, null]


func _hex(color: Color) -> String:
	return "#" + color.to_html()


func _stylebox_info(box: StyleBox) -> Dictionary:
	if box == null:
		return {}
	var info: Dictionary = {"class": box.get_class()}
	if box is StyleBoxFlat:
		var flat: StyleBoxFlat = box
		info["bg_color"] = _hex(flat.bg_color)
		info["border_color"] = _hex(flat.border_color)
		info["border_widths"] = [
			flat.border_width_left,
			flat.border_width_top,
			flat.border_width_right,
			flat.border_width_bottom,
		]
		info["corner_radii"] = [
			flat.corner_radius_top_left,
			flat.corner_radius_top_right,
			flat.corner_radius_bottom_right,
			flat.corner_radius_bottom_left,
		]
		info["content_margins"] = [
			int(flat.content_margin_left),
			int(flat.content_margin_top),
			int(flat.content_margin_right),
			int(flat.content_margin_bottom),
		]
	return info


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _create_theme(params: Dictionary) -> Dictionary:
	var path_res: Array = require_string(params, "path")
	if path_res[1] != null:
		return path_res[1]
	var path: String = path_res[0]

	var default_font_size: int = optional_int(params, "default_font_size", 0)

	var theme := Theme.new()
	if default_font_size > 0:
		theme.default_font_size = default_font_size

	# SPEC §9.1 — guards return {} when OK. NEVER compare a guard Dictionary to null.
	var guard: Dictionary = guard_offline_scene_save(path)
	if not guard.is_empty():
		return guard

	var err: int = ResourceSaver.save(theme, path)
	if err != OK:
		return error(-32603, "Failed to save theme: %s" % error_string(err))
	EditorInterface.get_resource_filesystem().scan()

	return success(
		{
			"path": path,
			"created": true,
			"default_font_size": maxi(default_font_size, 0),
		}
	)


func _set_theme_color(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	if not params.has("color") or params["color"] == null:
		return error(-32602, "Missing required parameter: color")

	var color_res: Array = _parse_color(params["color"], "color")
	if color_res[1] != null:
		return color_res[1]

	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var override_name: String = name_res[0]
	var color: Color = color_res[0]
	var had: bool = _has_override(control, "color", override_name)
	var old: Variant = _get_override(control, "color", override_name) if had else null

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_theme_color", UndoRedo.MERGE_DISABLE, control)
	ur.add_do_method(control, "add_theme_color_override", StringName(override_name), color)
	ur.add_undo_method(self, "_restore_override", control, "color", override_name, had, old)
	ur.commit_action()

	return success(
		{
			"node_path": String(np[0]),
			"name": override_name,
			"color": _hex(color),
			"had_previous_override": had,
		}
	)


func _set_theme_constant(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]

	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var override_name: String = name_res[0]
	var value: int = optional_int(params, "value", 0)
	var had: bool = _has_override(control, "constant", override_name)
	var old: Variant = _get_override(control, "constant", override_name) if had else null

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_theme_constant", UndoRedo.MERGE_DISABLE, control)
	ur.add_do_method(control, "add_theme_constant_override", StringName(override_name), value)
	ur.add_undo_method(self, "_restore_override", control, "constant", override_name, had, old)
	ur.commit_action()

	return success(
		{
			"node_path": String(np[0]),
			"name": override_name,
			"value": value,
			"had_previous_override": had,
		}
	)


func _set_theme_font_size(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]

	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var override_name: String = name_res[0]
	var size: int = optional_int(params, "size", 16)
	var had: bool = _has_override(control, "font_size", override_name)
	var old: Variant = _get_override(control, "font_size", override_name) if had else null

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_theme_font_size", UndoRedo.MERGE_DISABLE, control)
	ur.add_do_method(control, "add_theme_font_size_override", StringName(override_name), size)
	ur.add_undo_method(self, "_restore_override", control, "font_size", override_name, had, old)
	ur.commit_action()

	return success(
		{
			"node_path": String(np[0]),
			"name": override_name,
			"size": size,
			"had_previous_override": had,
		}
	)


func _set_theme_stylebox(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]

	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var override_name: String = name_res[0]
	var box := StyleBoxFlat.new()
	var applied: Array[String] = []

	if params.has("bg_color") and params["bg_color"] != null:
		var bg_res: Array = _parse_color(params["bg_color"], "bg_color")
		if bg_res[1] != null:
			return bg_res[1]
		box.bg_color = bg_res[0]
		applied.append("bg_color")

	if params.has("border_color") and params["border_color"] != null:
		var border_res: Array = _parse_color(params["border_color"], "border_color")
		if border_res[1] != null:
			return border_res[1]
		box.border_color = border_res[0]
		applied.append("border_color")

	if params.has("border_width") and params["border_width"] != null:
		var width: int = optional_int(params, "border_width", 0)
		box.border_width_left = width
		box.border_width_top = width
		box.border_width_right = width
		box.border_width_bottom = width
		applied.append("border_width")

	if params.has("corner_radius") and params["corner_radius"] != null:
		var radius: int = optional_int(params, "corner_radius", 0)
		box.corner_radius_top_left = radius
		box.corner_radius_top_right = radius
		box.corner_radius_bottom_right = radius
		box.corner_radius_bottom_left = radius
		applied.append("corner_radius")

	if params.has("padding") and params["padding"] != null:
		var padding: float = float(optional_int(params, "padding", 0))
		box.content_margin_left = padding
		box.content_margin_top = padding
		box.content_margin_right = padding
		box.content_margin_bottom = padding
		applied.append("padding")

	var had: bool = _has_override(control, "stylebox", override_name)
	var old: Variant = _get_override(control, "stylebox", override_name) if had else null

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_theme_stylebox", UndoRedo.MERGE_DISABLE, control)
	ur.add_do_method(control, "add_theme_stylebox_override", StringName(override_name), box)
	ur.add_do_reference(box)
	ur.add_undo_method(self, "_restore_override", control, "stylebox", override_name, had, old)
	if old is Resource:
		ur.add_undo_reference(old as Resource)
	ur.commit_action()

	return success(
		{
			"node_path": String(np[0]),
			"name": override_name,
			"stylebox": "StyleBoxFlat",
			"applied": applied,
			"had_previous_override": had,
		}
	)


func _setup_control(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var applied: Array[String] = []
	var skipped: Array[String] = []
	## theme constant name -> new value (old state is captured from the live Control).
	var constants: Dictionary = {}

	# Compute every layout change on a detached duplicate, then commit old -> new atomically.
	var work: Control = control.duplicate() as Control
	if work == null:
		return error(-32603, "Could not duplicate the Control at '%s'" % String(np[0]))

	if params.has("anchor_preset") and params["anchor_preset"] != null:
		var preset_name: String = optional_string(params, "anchor_preset", "")
		if not ANCHOR_PRESETS.has(preset_name):
			work.free()
			return error(
				-32602,
				(
					"Invalid anchor_preset '%s'. Valid: %s"
					% [preset_name, ", ".join(PackedStringArray(ANCHOR_PRESETS.keys()))]
				)
			)
		work.set_anchors_and_offsets_preset(ANCHOR_PRESETS[preset_name] as Control.LayoutPreset)
		applied.append("anchor_preset=%s" % preset_name)

	if params.has("min_size") and params["min_size"] != null:
		var min_size: Variant = PropertyParser.parse_value(params["min_size"], TYPE_VECTOR2)
		if typeof(min_size) != TYPE_VECTOR2:
			work.free()
			return error(
				-32602,
				(
					"Invalid min_size: expected 'Vector2(w, h)' or {x, y}, got '%s'"
					% str(params["min_size"])
				)
			)
		work.custom_minimum_size = min_size as Vector2
		applied.append("min_size=%s" % str(PropertyParser.serialize_value(min_size)))

	for axis: String in ["h", "v"]:
		var key: String = "size_flags_%s" % axis
		if not params.has(key) or params[key] == null:
			continue
		var flag_name: String = optional_string(params, key, "")
		if not SIZE_FLAGS.has(flag_name):
			work.free()
			return error(
				-32602,
				(
					"Invalid %s '%s'. Valid: %s"
					% [key, flag_name, ", ".join(PackedStringArray(SIZE_FLAGS.keys()))]
				)
			)
		var flag: int = int(SIZE_FLAGS[flag_name])
		if axis == "h":
			work.size_flags_horizontal = flag as Control.SizeFlags
		else:
			work.size_flags_vertical = flag as Control.SizeFlags
		applied.append("%s=%s" % [key, flag_name])

	for axis: String in ["h", "v"]:
		var key: String = "grow_%s" % axis
		if not params.has(key) or params[key] == null:
			continue
		var grow_name: String = optional_string(params, key, "")
		if not GROW_DIRECTIONS.has(grow_name):
			work.free()
			return error(
				-32602,
				(
					"Invalid %s '%s'. Valid: %s"
					% [key, grow_name, ", ".join(PackedStringArray(GROW_DIRECTIONS.keys()))]
				)
			)
		var grow: int = int(GROW_DIRECTIONS[grow_name])
		if axis == "h":
			work.grow_horizontal = grow as Control.GrowDirection
		else:
			work.grow_vertical = grow as Control.GrowDirection
		applied.append("%s=%s" % [key, grow_name])

	if params.has("margins") and params["margins"] != null:
		if typeof(params["margins"]) != TYPE_DICTIONARY:
			work.free()
			return error(-32602, "margins must be an object of {left, top, right, bottom} ints")
		if control is MarginContainer:
			var margins: Dictionary = params["margins"]
			for side: String in ["left", "top", "right", "bottom"]:
				if not margins.has(side) or margins[side] == null:
					continue
				var value: int = optional_int(margins, side, 0)
				constants[String(MARGIN_CONSTANTS[side])] = value
				applied.append("margins.%s=%d" % [side, value])
		else:
			skipped.append(
				(
					"margins: '%s' is a %s, not a MarginContainer"
					% [String(np[0]), control.get_class()]
				)
			)

	if params.has("separation") and params["separation"] != null:
		if control is BoxContainer:
			var separation: int = optional_int(params, "separation", 0)
			constants["separation"] = separation
			applied.append("separation=%d" % separation)
		else:
			skipped.append(
				(
					"separation: '%s' is a %s, not a BoxContainer"
					% [String(np[0]), control.get_class()]
				)
			)

	# Nothing to do — no undo action is created.
	if applied.is_empty():
		work.free()
		return success(
			{"node_path": String(np[0]), "applied": applied, "skipped": skipped, "count": 0}
		)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		work.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: setup_control", UndoRedo.MERGE_DISABLE, control)
	for prop: String in LAYOUT_PROPERTIES:
		ur.add_do_property(control, prop, work.get(prop))
		ur.add_undo_property(control, prop, control.get(prop))
	for constant_name: String in constants:
		var had: bool = _has_override(control, "constant", constant_name)
		var old: Variant = _get_override(control, "constant", constant_name) if had else null
		ur.add_do_method(
			self,
			"_restore_override",
			control,
			"constant",
			constant_name,
			true,
			int(constants[constant_name])
		)
		ur.add_undo_method(self, "_restore_override", control, "constant", constant_name, had, old)
	ur.commit_action()

	work.free()

	return success(
		{
			"node_path": String(np[0]),
			"applied": applied,
			"skipped": skipped,
			"count": applied.size(),
		}
	)


func _get_theme_info(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var gate: Array = _get_control(np[0])
	if gate[1] != null:
		return gate[1]
	var control: Control = gate[0]

	var out: Dictionary = {"node_path": String(np[0]), "class": control.get_class()}

	var theme: Theme = control.theme
	if theme != null:
		out["theme_path"] = theme.resource_path
		var type_list: Array[String] = []
		for type_name: StringName in theme.get_type_list():
			type_list.append(String(type_name))
		out["type_list"] = type_list

	var colors: Dictionary = {}
	var constants: Dictionary = {}
	var font_sizes: Dictionary = {}
	var styleboxes: Dictionary = {}

	for prop: Dictionary in control.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with("theme_override_"):
			continue
		var slash: int = prop_name.find("/")
		if slash < 0:
			continue
		var group: String = prop_name.substr(0, slash)
		var key: String = prop_name.substr(slash + 1)
		var value: Variant = control.get(prop_name)
		match group:
			"theme_override_colors":
				if control.has_theme_color_override(StringName(key)):
					colors[key] = _hex(value as Color)
			"theme_override_constants":
				if control.has_theme_constant_override(StringName(key)):
					constants[key] = int(value)
			"theme_override_font_sizes":
				if control.has_theme_font_size_override(StringName(key)):
					font_sizes[key] = int(value)
			"theme_override_styles":
				if control.has_theme_stylebox_override(StringName(key)):
					styleboxes[key] = _stylebox_info(value as StyleBox)

	out["overrides"] = {
		"colors": colors,
		"constants": constants,
		"font_sizes": font_sizes,
		"styleboxes": styleboxes,
	}
	return success(out)
