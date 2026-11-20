@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B11 — physics commands (6 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4).
##
## Dimension resolution (DIM-RES): 2D vs 3D is decided by the node (Node3D -> 3d, Node2D -> 2d);
## the `dimension` param is only consulted when the node is neither.
## Angle params arrive in degrees; CharacterBody floor_max_angle / wall_min_slide_angle are stored
## by Godot in radians, so they are converted with deg_to_rad on write and rad_to_deg on read.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

const SHAPES_2D := ["rectangle", "rect", "circle", "capsule", "segment", "custom"]
const SHAPES_3D := ["box", "sphere", "capsule", "cylinder", "convex", "custom"]

## Angles Godot stores in radians but this API takes/returns in degrees.
const ANGLE_PROPS := ["floor_max_angle", "wall_min_slide_angle"]

const CHARACTER_PROPS := [
	"floor_stop_on_slope",
	"floor_max_angle",
	"floor_snap_length",
	"wall_min_slide_angle",
	"motion_mode",
	"max_slides",
	"slide_on_ceiling",
]

const RIGID_PROPS := [
	"mass",
	"gravity_scale",
	"linear_damp",
	"angular_damp",
	"freeze",
	"freeze_mode",
	"continuous_cd",
	"contact_monitor",
	"max_contacts_reported",
]


func get_commands() -> Dictionary:
	return {
		"setup_collision": _setup_collision,
		"set_physics_layers": _set_physics_layers,
		"get_physics_layers": _get_physics_layers,
		"add_raycast": _add_raycast,
		"setup_physics_body": _setup_physics_body,
		"get_collision_info": _get_collision_info,
	}


# ---------------------------------------------------------------------------
# Shared helpers (private to this module — base_command.gd stays frozen)
# ---------------------------------------------------------------------------


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


## Path of `node` relative to the edited scene root ("." for the root itself).
func _rel(node: Node) -> String:
	var root: Node = get_edited_root()
	if root == null or node == null:
		return ""
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return String(root.get_path_to(node))
	return String(node.name)


## DIM-RES: the node decides; `dimension` is only a fallback for a bare Node.
func _resolve_dimension(node: Node, params: Dictionary) -> String:
	if node is Node3D:
		return "3d"
	if node is Node2D:
		return "2d"
	var dim: String = optional_string(params, "dimension", "2d").strip_edges().to_lower()
	if dim != "2d" and dim != "3d":
		return "2d"
	return dim


static func _has_prop(obj: Object, prop_name: String) -> bool:
	if obj == null:
		return false
	for p: Dictionary in obj.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false


## Layer number list -> bitmask. Returns [mask, null] or [0, error_dict].
func _decode_layers(raw: Variant, key: String) -> Array:
	match typeof(raw):
		TYPE_INT, TYPE_FLOAT:
			var mask: int = int(roundf(float(raw)))
			if mask < 0:
				return [0, error(-32602, "%s bitmask must not be negative (got %d)" % [key, mask])]
			return [mask, null]
		TYPE_ARRAY:
			var bits: int = 0
			for entry: Variant in (raw as Array):
				if typeof(entry) != TYPE_INT and typeof(entry) != TYPE_FLOAT:
					return [
						0,
						error(
							-32602,
							(
								"%s list entries must be layer numbers 1-32 (got %s)"
								% [key, type_string(typeof(entry))]
							)
						)
					]
				var n: int = int(roundf(float(entry)))
				if n < 1 or n > 32:
					return [0, error(-32602, "%s layer number %d is out of range 1-32" % [key, n])]
				bits |= 1 << (n - 1)
			return [bits, null]
		_:
			return [
				0,
				error(
					-32602,
					(
						"%s must be a bitmask int or a list of layer numbers 1-32 (got %s)"
						% [key, type_string(typeof(raw))]
					)
				)
			]


## [{bit, name, enabled}] for the 32 physics layers of `dimension`.
func _decode_bits(mask: int, dimension: String) -> Array:
	var out: Array = []
	var prefix: String = "layer_names/%s_physics/layer_" % dimension
	for n: int in range(1, 33):
		var setting: Variant = ProjectSettings.get_setting("%s%d" % [prefix, n], "")
		out.append(
			{
				"bit": n,
				"name": String(setting) if setting != null else "",
				"enabled": (mask & (1 << (n - 1))) != 0,
			}
		)
	return out


## The get_physics_layers payload for `node`, or [null, error_dict] when it has no layer props.
func _layers_payload(node: Node, dimension: String) -> Array:
	var has_layer: bool = _has_prop(node, "collision_layer")
	var has_mask: bool = _has_prop(node, "collision_mask")
	if not has_layer and not has_mask:
		return [
			null,
			error(
				-32602,
				(
					"'%s' (%s) exposes neither collision_layer nor collision_mask"
					% [String(node.name), node.get_class()]
				)
			)
		]

	var layer_value: int = int(node.get("collision_layer")) if has_layer else 0
	var mask_value: int = int(node.get("collision_mask")) if has_mask else 0
	return [
		{
			"collision_layer": layer_value,
			"collision_mask": mask_value,
			"dimension": dimension,
			"layers": _decode_bits(layer_value, dimension) if has_layer else [],
			"mask": _decode_bits(mask_value, dimension) if has_mask else [],
		},
		null
	]


## points: [[x, y(, z)], ...] -> PackedVector2Array / PackedVector3Array.
## Returns [packed_array, null] or [null, error_dict].
func _parse_points(params: Dictionary, dimension: String) -> Array:
	var min_count: int = 3 if dimension == "2d" else 4
	var raw: Variant = params.get("points", null)
	if typeof(raw) != TYPE_ARRAY:
		return [
			null,
			error(
				-32602,
				(
					"points is required for this shape: an array of at least %d [x, y%s] entries"
					% [min_count, "" if dimension == "2d" else ", z"]
				)
			)
		]

	var entries: Array = raw
	if entries.size() < min_count:
		return [
			null,
			error(
				-32602,
				(
					"points needs at least %d entries for a %s convex shape (got %d)"
					% [min_count, dimension.to_upper(), entries.size()]
				)
			)
		]

	var need: int = 2 if dimension == "2d" else 3
	var pts_2d := PackedVector2Array()
	var pts_3d := PackedVector3Array()
	for entry: Variant in entries:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() < need:
			return [
				null,
				error(-32602, "each points entry must be an array of %d numbers" % need)
			]
		var comps: Array = entry
		if dimension == "2d":
			pts_2d.append(Vector2(float(comps[0]), float(comps[1])))
		else:
			pts_3d.append(Vector3(float(comps[0]), float(comps[1]), float(comps[2])))

	return [pts_2d if dimension == "2d" else pts_3d, null]


## Build the shape resource for `shape` in `dimension`.
## Returns [Shape, applied_dict, null] or [null, {}, error_dict].
func _build_shape(shape: String, dimension: String, params: Dictionary) -> Array:
	var applied: Dictionary = {}

	if dimension == "2d":
		match shape:
			"rectangle", "rect":
				var rect := RectangleShape2D.new()
				rect.size = Vector2(
					optional_float(params, "width", 32.0), optional_float(params, "height", 32.0)
				)
				applied["size"] = PropertyParser.serialize_value(rect.size)
				return [rect, applied, null]
			"circle":
				var circle := CircleShape2D.new()
				circle.radius = optional_float(params, "radius", 16.0)
				applied["radius"] = circle.radius
				return [circle, applied, null]
			"capsule":
				var capsule := CapsuleShape2D.new()
				capsule.radius = optional_float(params, "radius", 16.0)
				capsule.height = optional_float(params, "height", 32.0)
				applied["radius"] = capsule.radius
				applied["height"] = capsule.height
				return [capsule, applied, null]
			"segment":
				var segment := SegmentShape2D.new()
				segment.a = Vector2(
					optional_float(params, "ax", 0.0), optional_float(params, "ay", 0.0)
				)
				segment.b = Vector2(
					optional_float(params, "bx", 0.0), optional_float(params, "by", 0.0)
				)
				applied["a"] = PropertyParser.serialize_value(segment.a)
				applied["b"] = PropertyParser.serialize_value(segment.b)
				return [segment, applied, null]
			"custom":
				var pts: Array = _parse_points(params, "2d")
				if pts[1] != null:
					return [null, {}, pts[1]]
				var poly := ConvexPolygonShape2D.new()
				poly.points = pts[0] as PackedVector2Array
				applied["point_count"] = poly.points.size()
				return [poly, applied, null]
			_:
				return [
					null,
					{},
					error(
						-32602,
						(
							"Unknown 2D shape '%s' (valid: %s)"
							% [shape, ", ".join(SHAPES_2D)]
						)
					)
				]

	match shape:
		"box":
			var box := BoxShape3D.new()
			box.size = Vector3(
				optional_float(params, "width", 1.0),
				optional_float(params, "height", 1.0),
				optional_float(params, "depth", 1.0)
			)
			applied["size"] = PropertyParser.serialize_value(box.size)
			return [box, applied, null]
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = optional_float(params, "radius", 0.5)
			applied["radius"] = sphere.radius
			return [sphere, applied, null]
		"capsule":
			var capsule3 := CapsuleShape3D.new()
			capsule3.radius = optional_float(params, "radius", 0.5)
			capsule3.height = optional_float(params, "height", 2.0)
			applied["radius"] = capsule3.radius
			applied["height"] = capsule3.height
			return [capsule3, applied, null]
		"cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = optional_float(params, "radius", 0.5)
			cylinder.height = optional_float(params, "height", 2.0)
			applied["radius"] = cylinder.radius
			applied["height"] = cylinder.height
			return [cylinder, applied, null]
		"convex", "custom":
			var pts3: Array = _parse_points(params, "3d")
			if pts3[1] != null:
				return [null, {}, pts3[1]]
			var poly3 := ConvexPolygonShape3D.new()
			poly3.points = pts3[0] as PackedVector3Array
			applied["point_count"] = poly3.points.size()
			return [poly3, applied, null]
		_:
			return [
				null,
				{},
				error(
					-32602,
					"Unknown 3D shape '%s' (valid: %s)" % [shape, ", ".join(SHAPES_3D)]
				)
			]


## Simulation properties of a Character/RigidBody, degrees for the angle props. {} for other classes.
func _body_props(node: Node) -> Dictionary:
	var out: Dictionary = {}
	var names: Array = []
	if node is CharacterBody2D or node is CharacterBody3D:
		names = CHARACTER_PROPS
	elif node is RigidBody2D or node is RigidBody3D:
		names = RIGID_PROPS
	else:
		return out

	for prop: String in names:
		if not _has_prop(node, prop):
			continue
		var value: Variant = node.get(prop)
		if ANGLE_PROPS.has(prop):
			out[prop] = rad_to_deg(float(value))
		else:
			out[prop] = PropertyParser.serialize_value(value)
	return out


## Shape-class-specific measurements for get_collision_info.
func _shape_dimensions(shape: Shape2D, shape3: Shape3D) -> Dictionary:
	if shape is RectangleShape2D:
		return {"size": PropertyParser.serialize_value((shape as RectangleShape2D).size)}
	if shape is CircleShape2D:
		return {"radius": (shape as CircleShape2D).radius}
	if shape is CapsuleShape2D:
		var c2: CapsuleShape2D = shape
		return {"radius": c2.radius, "height": c2.height}
	if shape is SegmentShape2D:
		var s2: SegmentShape2D = shape
		return {
			"a": PropertyParser.serialize_value(s2.a),
			"b": PropertyParser.serialize_value(s2.b),
		}
	if shape is ConvexPolygonShape2D:
		return {"point_count": (shape as ConvexPolygonShape2D).points.size()}
	if shape3 is BoxShape3D:
		return {"size": PropertyParser.serialize_value((shape3 as BoxShape3D).size)}
	if shape3 is SphereShape3D:
		return {"radius": (shape3 as SphereShape3D).radius}
	if shape3 is CapsuleShape3D:
		var c3: CapsuleShape3D = shape3
		return {"radius": c3.radius, "height": c3.height}
	if shape3 is CylinderShape3D:
		var cy3: CylinderShape3D = shape3
		return {"radius": cy3.radius, "height": cy3.height}
	if shape3 is ConvexPolygonShape3D:
		return {"point_count": (shape3 as ConvexPolygonShape3D).points.size()}
	return {}


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _setup_collision(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var shape_res: Array = require_string(params, "shape")
	if shape_res[1] != null:
		return shape_res[1]

	var node_path: String = np[0]
	var shape_name: String = String(shape_res[0]).strip_edges().to_lower()

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)
	if not (node is CollisionObject2D or node is CollisionObject3D):
		return error(
			-32602,
			(
				"'%s' is a %s — setup_collision needs a CollisionObject2D/3D (physics body or Area)"
				% [node_path, node.get_class()]
			)
		)

	var dimension: String = _resolve_dimension(node, params)
	var built: Array = _build_shape(shape_name, dimension, params)
	if built[2] != null:
		return built[2]

	var disabled: bool = optional_bool(params, "disabled", false)
	var one_way: bool = optional_bool(params, "one_way_collision", false)
	var applied: Dictionary = built[1]
	applied["disabled"] = disabled

	var child: Node = null
	var shape_class: String = ""
	if dimension == "2d":
		var cs2 := CollisionShape2D.new()
		cs2.shape = built[0] as Shape2D
		cs2.disabled = disabled
		cs2.one_way_collision = one_way
		applied["one_way_collision"] = one_way
		shape_class = (built[0] as Shape2D).get_class()
		child = cs2
	else:
		var cs3 := CollisionShape3D.new()
		cs3.shape = built[0] as Shape3D
		cs3.disabled = disabled
		shape_class = (built[0] as Shape3D).get_class()
		child = cs3
		if one_way:
			# CollisionShape3D has no one_way_collision — echo it back as ignored, do not error.
			applied["ignored"] = ["one_way_collision"]

	child.name = unique_child_name(node, optional_string(params, "name", "CollisionShape"), child.get_class())

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		child.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: setup_collision")
	ur.add_do_method(node, "add_child", child, true)
	ur.add_do_method(child, "set_owner", root)
	ur.add_do_reference(child)
	ur.add_undo_method(node, "remove_child", child)
	ur.commit_action()

	return success(
		{
			"node_path": node_path,
			"shape_node": _rel(child),
			"shape_class": shape_class,
			"dimension": dimension,
			"params_applied": applied,
		}
	)


func _set_physics_layers(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node_path: String = np[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)

	var wants_layer: bool = params.has("collision_layer") and params["collision_layer"] != null
	var wants_mask: bool = params.has("collision_mask") and params["collision_mask"] != null
	if not wants_layer and not wants_mask:
		return error(-32602, "At least one of collision_layer or collision_mask is required")

	var dimension: String = _resolve_dimension(node, params)
	var probe: Array = _layers_payload(node, dimension)
	if probe[1] != null:
		return probe[1]

	var old_layer: int = int(node.get("collision_layer")) if _has_prop(node, "collision_layer") else 0
	var old_mask: int = int(node.get("collision_mask")) if _has_prop(node, "collision_mask") else 0

	var new_layer: int = old_layer
	var new_mask: int = old_mask

	if wants_layer:
		if not _has_prop(node, "collision_layer"):
			return error(
				-32602,
				(
					"'%s' (%s) has no collision_layer property"
					% [node_path, node.get_class()]
				)
			)
		var dec: Array = _decode_layers(params["collision_layer"], "collision_layer")
		if dec[1] != null:
			return dec[1]
		new_layer = dec[0]

	if wants_mask:
		if not _has_prop(node, "collision_mask"):
			return error(
				-32602,
				"'%s' (%s) has no collision_mask property" % [node_path, node.get_class()]
			)
		var dec_mask: Array = _decode_layers(params["collision_mask"], "collision_mask")
		if dec_mask[1] != null:
			return dec_mask[1]
		new_mask = dec_mask[0]

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_physics_layers")
	if wants_layer:
		ur.add_do_property(node, "collision_layer", new_layer)
	if wants_mask:
		ur.add_do_property(node, "collision_mask", new_mask)
	# Undo restores BOTH values, so a partial write cannot leave a half-reverted node.
	if _has_prop(node, "collision_layer"):
		ur.add_undo_property(node, "collision_layer", old_layer)
	if _has_prop(node, "collision_mask"):
		ur.add_undo_property(node, "collision_mask", old_mask)
	ur.commit_action()

	var after: Array = _layers_payload(node, dimension)
	if after[1] != null:
		return after[1]
	var out: Dictionary = after[0]
	out["node_path"] = node_path
	out["old_layer"] = old_layer
	out["old_mask"] = old_mask
	return success(out)


func _get_physics_layers(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node_path: String = np[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)

	var payload: Array = _layers_payload(node, _resolve_dimension(node, params))
	if payload[1] != null:
		return payload[1]

	var out: Dictionary = payload[0]
	out["node_path"] = node_path
	out["class"] = node.get_class()
	return success(out)


func _add_raycast(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var parent_path: String = np[0]

	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Node: %s" % parent_path)

	var dimension: String = _resolve_dimension(parent, params)
	var enabled: bool = optional_bool(params, "enabled", true)
	var collision_mask: int = optional_int(params, "collision_mask", 1)
	var collide_areas: bool = optional_bool(params, "collide_with_areas", false)
	var collide_bodies: bool = optional_bool(params, "collide_with_bodies", true)
	var hit_from_inside: bool = optional_bool(params, "hit_from_inside", false)
	var target_x: float = optional_float(params, "target_x", 0.0)

	var child: Node = null
	var target: Variant = null
	if dimension == "2d":
		# 2D rays point down the screen by default (Godot's +Y is down).
		var target_y_2d: float = optional_float(params, "target_y", 50.0)
		var rc2 := RayCast2D.new()
		rc2.enabled = enabled
		rc2.collision_mask = collision_mask
		rc2.collide_with_areas = collide_areas
		rc2.collide_with_bodies = collide_bodies
		rc2.hit_from_inside = hit_from_inside
		rc2.target_position = Vector2(target_x, target_y_2d)
		target = rc2.target_position
		child = rc2
	else:
		# 3D rays point down -Z (forward) by default.
		var target_y_3d: float = optional_float(params, "target_y", -1.0)
		var rc3 := RayCast3D.new()
		rc3.enabled = enabled
		rc3.collision_mask = collision_mask
		rc3.collide_with_areas = collide_areas
		rc3.collide_with_bodies = collide_bodies
		rc3.hit_from_inside = hit_from_inside
		rc3.target_position = Vector3(
			target_x, target_y_3d, optional_float(params, "target_z", 0.0)
		)
		target = rc3.target_position
		child = rc3

	child.name = unique_child_name(parent, optional_string(params, "name", "RayCast"), child.get_class())

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		child.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: add_raycast")
	ur.add_do_method(parent, "add_child", child, true)
	ur.add_do_method(child, "set_owner", root)
	ur.add_do_reference(child)
	ur.add_undo_method(parent, "remove_child", child)
	ur.commit_action()

	return success(
		{
			"node_path": parent_path,
			"raycast_node": _rel(child),
			"dimension": dimension,
			"target_position": PropertyParser.serialize_value(target),
			"enabled": enabled,
			"collision_mask": collision_mask,
		}
	)


func _setup_physics_body(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node_path: String = np[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)

	# StaticBody2D/3D is also AnimatableBody's base class, so this catches both.
	if node is StaticBody2D or node is StaticBody3D:
		return error(
			-32602,
			"StaticBody/AnimatableBody has no simulation properties",
			{
				"class": node.get_class(),
				"suggestion": (
					"use update_property for constant_linear_velocity / physics_material_override"
				),
			}
		)

	var is_3d: bool = node is Node3D
	var kind: String = ""
	var own_props: Array = []
	if node is CharacterBody2D or node is CharacterBody3D:
		kind = "character"
		own_props = CHARACTER_PROPS
	elif node is RigidBody2D or node is RigidBody3D:
		kind = "rigid"
		own_props = RIGID_PROPS
	else:
		return error(
			-32602,
			(
				"'%s' is a %s — setup_physics_body needs a CharacterBody2D/3D or RigidBody2D/3D"
				% [node_path, node.get_class()]
			)
		)

	var writes: Dictionary = {}  # prop -> new stored value
	var olds: Dictionary = {}  # prop -> previous stored value (captured before commit)
	var applied: Dictionary = {}  # prop -> {old, new} in API units
	var ignored: Array[String] = []

	var all_props: Array = []
	all_props.append_array(CHARACTER_PROPS)
	all_props.append_array(RIGID_PROPS)

	for prop: String in all_props:
		if not params.has(prop) or params[prop] == null:
			continue
		if not own_props.has(prop) or not _has_prop(node, prop):
			ignored.append(prop)
			continue

		var raw: Variant = params[prop]
		var old_stored: Variant = node.get(prop)
		var new_stored: Variant = null
		var api_old: Variant = null
		var api_new: Variant = null

		match prop:
			"floor_max_angle", "wall_min_slide_angle":
				var degrees: float = optional_float(params, prop, rad_to_deg(float(old_stored)))
				new_stored = deg_to_rad(degrees)
				api_old = rad_to_deg(float(old_stored))
				api_new = degrees
			"motion_mode":
				var mm: Array = _enum_value(raw, prop, {"grounded": 0, "floating": 1})
				if mm[1] != null:
					return mm[1]
				new_stored = int(mm[0])
				api_old = int(old_stored)
				api_new = int(mm[0])
			"freeze_mode":
				var fm: Array = _enum_value(raw, prop, {"static": 0, "kinematic": 1})
				if fm[1] != null:
					return fm[1]
				new_stored = int(fm[0])
				api_old = int(old_stored)
				api_new = int(fm[0])
			"continuous_cd":
				if is_3d:
					# RigidBody3D.continuous_cd is a plain bool.
					new_stored = optional_bool(params, prop, false)
					api_old = bool(old_stored)
					api_new = bool(new_stored)
				else:
					var cd: Array = _enum_value(
						raw, prop, {"disabled": 0, "cast_ray": 1, "cast_shape": 2}
					)
					if cd[1] != null:
						return cd[1]
					new_stored = int(cd[0])
					api_old = int(old_stored)
					api_new = int(cd[0])
			"mass":
				var mass: float = optional_float(params, prop, 1.0)
				if mass <= 0.0:
					return error(-32602, "mass must be greater than 0 (got %s)" % str(mass))
				new_stored = mass
				api_old = float(old_stored)
				api_new = mass
			"max_contacts_reported":
				var contacts: int = optional_int(params, prop, 0)
				if contacts < 0:
					return error(
						-32602, "max_contacts_reported must be >= 0 (got %d)" % contacts
					)
				new_stored = contacts
				api_old = int(old_stored)
				api_new = contacts
			"max_slides":
				new_stored = optional_int(params, prop, int(old_stored))
				api_old = int(old_stored)
				api_new = int(new_stored)
			"floor_stop_on_slope", "slide_on_ceiling", "freeze", "contact_monitor":
				new_stored = optional_bool(params, prop, bool(old_stored))
				api_old = bool(old_stored)
				api_new = bool(new_stored)
			_:
				new_stored = optional_float(params, prop, float(old_stored))
				api_old = float(old_stored)
				api_new = float(new_stored)

		writes[prop] = new_stored
		olds[prop] = old_stored
		applied[prop] = {"old": api_old, "new": api_new}

	if writes.is_empty():
		return success(
			{
				"node_path": node_path,
				"body_class": node.get_class(),
				"kind": kind,
				"applied": {},
				"ignored": ignored,
			}
		)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: setup_physics_body")
	for prop: String in writes:
		ur.add_do_property(node, prop, writes[prop])
	# Undo values were captured BEFORE the do-actions run, so every touched property is restored.
	for prop: String in olds:
		ur.add_undo_property(node, prop, olds[prop])
	ur.commit_action()

	return success(
		{
			"node_path": node_path,
			"body_class": node.get_class(),
			"kind": kind,
			"applied": applied,
			"ignored": ignored,
		}
	)


func _get_collision_info(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var node_path: String = np[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)

	var include_children: bool = optional_bool(params, "include_children", true)
	var dimension: String = _resolve_dimension(node, params)

	var layers: Variant = null
	var payload: Array = _layers_payload(node, dimension)
	if payload[1] == null:
		layers = payload[0]

	var targets: Array[Node] = [node]
	if include_children:
		_collect_descendants(node, targets)

	var shapes: Array = []
	var polygons: Array = []
	var raycasts: Array = []

	for n: Node in targets:
		if n is CollisionShape2D:
			var cs2: CollisionShape2D = n
			shapes.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"shape_class": cs2.shape.get_class() if cs2.shape != null else "",
					"disabled": cs2.disabled,
					"dimensions": _shape_dimensions(cs2.shape, null),
				}
			)
		elif n is CollisionShape3D:
			var cs3: CollisionShape3D = n
			shapes.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"shape_class": cs3.shape.get_class() if cs3.shape != null else "",
					"disabled": cs3.disabled,
					"dimensions": _shape_dimensions(null, cs3.shape),
				}
			)
		elif n is CollisionPolygon2D:
			var cp2: CollisionPolygon2D = n
			polygons.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"point_count": cp2.polygon.size(),
					"build_mode": int(cp2.build_mode),
				}
			)
		elif n is CollisionPolygon3D:
			var cp3: CollisionPolygon3D = n
			polygons.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"point_count": cp3.polygon.size(),
				}
			)
		elif n is RayCast2D:
			var rc2: RayCast2D = n
			raycasts.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"enabled": rc2.enabled,
					"target_position": PropertyParser.serialize_value(rc2.target_position),
					"collision_mask": rc2.collision_mask,
				}
			)
		elif n is RayCast3D:
			var rc3: RayCast3D = n
			raycasts.append(
				{
					"path": _rel(n),
					"node_class": n.get_class(),
					"enabled": rc3.enabled,
					"target_position": PropertyParser.serialize_value(rc3.target_position),
					"collision_mask": rc3.collision_mask,
				}
			)

	var body: Dictionary = _body_props(node)

	return success(
		{
			"node_path": node_path,
			"class": node.get_class(),
			"dimension": dimension,
			"include_children": include_children,
			"layers": layers,
			"body": body,
			"shapes": shapes,
			"polygons": polygons,
			"raycasts": raycasts,
		}
	)


# ---------------------------------------------------------------------------
# Small internals
# ---------------------------------------------------------------------------


## Accepts an enum name or its int value. Returns [int, null] or [0, error_dict].
func _enum_value(raw: Variant, key: String, names: Dictionary) -> Array:
	match typeof(raw):
		TYPE_INT, TYPE_FLOAT:
			var v: int = int(roundf(float(raw)))
			if not names.values().has(v):
				return [
					0,
					error(
						-32602,
						"%s int value %d is out of range (valid: %s)" % [key, v, str(names)]
					)
				]
			return [v, null]
		TYPE_BOOL:
			return [1 if bool(raw) else 0, null]
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = String(raw).strip_edges().to_lower()
			if names.has(s):
				return [int(names[s]), null]
			return [
				0,
				error(
					-32602,
					"Unknown %s '%s' (valid: %s)" % [key, s, ", ".join(names.keys())]
				)
			]
		_:
			return [
				0,
				error(-32602, "%s must be a string or int (got %s)" % [key, type_string(typeof(raw))])
			]


func _collect_descendants(node: Node, out: Array[Node]) -> void:
	for child: Node in node.get_children():
		out.append(child)
		_collect_descendants(child, out)
