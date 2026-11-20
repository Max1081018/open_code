@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B11 — particle commands (5 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4).
##
## THE FOOTGUN THIS MODULE MUST NOT REPRODUCE: a ParticleProcessMaterial is a Resource and is very
## often shared between emitters (and always shared when a scene is instanced). Mutating it in place
## silently rewrites every sibling that references it. So every mutator DUPLICATES the material
## first and undo-sets `process_material` to the new resource; undo restores the previous reference.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## Node params written by create_particles / apply_particle_preset.
const NODE_PROPS := [
	"amount", "lifetime", "one_shot", "explosiveness", "randomness", "emitting"
]

## Every ParticleProcessMaterial property set_particle_material can write, in report order.
const MATERIAL_PROPS := [
	"direction",
	"spread",
	"initial_velocity_min",
	"initial_velocity_max",
	"gravity",
	"scale_min",
	"scale_max",
	"color",
	"angular_velocity_min",
	"angular_velocity_max",
	"orbit_velocity_min",
	"orbit_velocity_max",
	"damping_min",
	"damping_max",
	"attractor_interaction_enabled",
]

const SPHERE_PARAMS := ["emission_sphere_radius"]
const BOX_PARAMS := ["emission_box_extents"]
const RING_PARAMS := [
	"emission_ring_radius", "emission_ring_inner_radius", "emission_ring_height"
]

const PRESETS := [
	"explosion", "fire", "smoke", "sparks", "rain", "snow", "magic", "dust"
]


func get_commands() -> Dictionary:
	return {
		"create_particles": _create_particles,
		"set_particle_material": _set_particle_material,
		"set_particle_color_gradient": _set_particle_color_gradient,
		"apply_particle_preset": _apply_particle_preset,
		"get_particle_info": _get_particle_info,
	}


# ---------------------------------------------------------------------------
# Shared helpers (private to this module — base_command.gd stays frozen)
# ---------------------------------------------------------------------------


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


func _rel(node: Node) -> String:
	var root: Node = get_edited_root()
	if root == null or node == null:
		return ""
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return String(root.get_path_to(node))
	return String(node.name)


## Resolve node_path to a GPUParticles2D/3D. Returns [node, is_3d, null] or [null, false, error].
func _get_particles(params: Dictionary) -> Array:
	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return [null, false, np[1]]
	var node_path: String = np[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return [null, false, error_not_found("Node: %s" % node_path)]
	if node is GPUParticles3D:
		return [node, true, null]
	if node is GPUParticles2D:
		return [node, false, null]
	return [
		null,
		false,
		error(
			-32602,
			(
				"'%s' is a %s — this tool needs a GPUParticles2D or GPUParticles3D"
				% [node_path, node.get_class()]
			)
		)
	]


## NEVER mutate the live material: duplicate it (deep, so the color_ramp comes along) or make a
## fresh one. The caller undo-sets `process_material` to whatever this returns.
func _ensure_material(node: Node) -> ParticleProcessMaterial:
	var current: ParticleProcessMaterial = node.get("process_material") as ParticleProcessMaterial
	if current != null:
		return current.duplicate(true) as ParticleProcessMaterial
	return ParticleProcessMaterial.new()


func _emission_shape_from_name(shape_name: String) -> int:
	match shape_name.strip_edges().to_lower():
		"point":
			return ParticleProcessMaterial.EMISSION_SHAPE_POINT
		"sphere":
			return ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		"sphere_surface":
			return ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		"box":
			return ParticleProcessMaterial.EMISSION_SHAPE_BOX
		"ring":
			return ParticleProcessMaterial.EMISSION_SHAPE_RING
		_:
			return -1


func _emission_shape_name(shape: int) -> String:
	match shape:
		ParticleProcessMaterial.EMISSION_SHAPE_POINT:
			return "point"
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE:
			return "sphere"
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			return "sphere_surface"
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			return "box"
		ParticleProcessMaterial.EMISSION_SHAPE_RING:
			return "ring"
		_:
			return "other"


## Params that only make sense for the given emission shape.
func _shape_param_names(shape: int) -> Array:
	match shape:
		ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE:
			return SPHERE_PARAMS
		ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			return BOX_PARAMS
		ParticleProcessMaterial.EMISSION_SHAPE_RING:
			return RING_PARAMS
		_:
			return []


## Parse a vector param into a Vector3 (ParticleProcessMaterial direction/gravity/extents are
## always Vector3, even on a GPUParticles2D — z simply stays 0).
func _parse_vec3(raw: Variant, key: String) -> Array:
	var parsed: Variant = PropertyParser.parse_value(raw, TYPE_VECTOR3)
	if typeof(parsed) == TYPE_VECTOR3:
		return [parsed, null]
	if typeof(parsed) == TYPE_VECTOR2:
		var v2: Vector2 = parsed
		return [Vector3(v2.x, v2.y, 0.0), null]
	return [
		Vector3.ZERO,
		error(
			-32602,
			(
				"%s must be a vector: \"Vector3(x, y, z)\", [x, y, z] or {x, y, z} (got %s)"
				% [key, str(raw)]
			)
		)
	]


func _parse_color(raw: Variant, key: String) -> Array:
	var parsed: Variant = PropertyParser.parse_value(raw, TYPE_COLOR)
	if typeof(parsed) != TYPE_COLOR:
		return [
			Color.WHITE,
			error(
				-32602,
				'%s must be "#rrggbb", "#rrggbbaa" or "Color(r, g, b, a)" (got %s)' % [key, str(raw)]
			)
		]
	return [parsed, null]


## The full material payload get_particle_info reports (also used as the `applied` echo shape).
func _material_payload(mat: ParticleProcessMaterial) -> Dictionary:
	var out: Dictionary = {}
	for prop: String in MATERIAL_PROPS:
		out[prop] = PropertyParser.serialize_value(mat.get(prop))
	return out


func _emission_payload(mat: ParticleProcessMaterial) -> Dictionary:
	var shape: int = int(mat.emission_shape)
	var shape_params: Dictionary = {}
	for prop: String in _shape_param_names(shape):
		shape_params[prop] = PropertyParser.serialize_value(mat.get(prop))
	return {"shape": _emission_shape_name(shape), "shape_params": shape_params}


func _gradient_payload(mat: ParticleProcessMaterial) -> Variant:
	var ramp: Texture2D = mat.color_ramp
	if ramp == null:
		return null
	var grad: Gradient = ramp.get("gradient") as Gradient
	if grad == null:
		return null
	var stops: Array = []
	for i: int in range(grad.get_point_count()):
		stops.append(
			{
				"offset": grad.get_offset(i),
				"color": PropertyParser.serialize_value(grad.get_color(i)),
			}
		)
	return stops


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _create_particles(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var pp: Array = require_string(params, "parent_path")
	if pp[1] != null:
		return pp[1]
	var parent_path: String = pp[0]

	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Node: %s" % parent_path)

	var amount: int = optional_int(params, "amount", 16)
	if amount < 1:
		return error(-32602, "amount must be at least 1 (got %d)" % amount)
	var lifetime: float = optional_float(params, "lifetime", 1.0)
	if lifetime <= 0.0:
		return error(-32602, "lifetime must be greater than 0 (got %s)" % str(lifetime))

	var is_3d: bool = optional_bool(params, "is_3d", false)
	var explosiveness: float = clampf(optional_float(params, "explosiveness", 0.0), 0.0, 1.0)
	var randomness: float = clampf(optional_float(params, "randomness", 0.0), 0.0, 1.0)
	var one_shot: bool = optional_bool(params, "one_shot", false)
	var emitting: bool = optional_bool(params, "emitting", true)

	var node: Node = GPUParticles3D.new() if is_3d else GPUParticles2D.new()
	node.name = unique_child_name(parent, optional_string(params, "name", "Particles"), node.get_class())
	node.set("amount", amount)
	node.set("lifetime", lifetime)
	node.set("one_shot", one_shot)
	node.set("explosiveness", explosiveness)
	node.set("randomness", randomness)
	node.set("emitting", emitting)
	node.set("process_material", ParticleProcessMaterial.new())

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		node.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: create_particles")
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()

	return success(
		{
			"node_path": _rel(node),
			"class": node.get_class(),
			"is_3d": is_3d,
			"amount": amount,
			"lifetime": lifetime,
			"one_shot": one_shot,
			"explosiveness": explosiveness,
			"randomness": randomness,
			"emitting": emitting,
		}
	)


func _set_particle_material(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var gate: Array = _get_particles(params)
	if gate[2] != null:
		return gate[2]
	var node: Node = gate[0]
	var node_path: String = String(params.get("node_path", ""))

	var old_mat: ParticleProcessMaterial = (
		node.get("process_material") as ParticleProcessMaterial
	)
	var mat: ParticleProcessMaterial = _ensure_material(node)

	var applied: Dictionary = {}
	var ignored: Array[String] = []

	# Resolve the effective emission shape first: shape-specific params are judged against it.
	var shape_provided: bool = params.has("emission_shape") and params["emission_shape"] != null
	var shape: int = int(mat.emission_shape)
	if shape_provided:
		var resolved: int = _emission_shape_from_name(optional_string(params, "emission_shape", ""))
		if resolved < 0:
			return error(
				-32602,
				(
					"Unknown emission_shape '%s' (point|sphere|sphere_surface|box|ring)"
					% optional_string(params, "emission_shape", "")
				)
			)
		shape = resolved
		mat.emission_shape = shape as ParticleProcessMaterial.EmissionShape
		applied["emission_shape"] = _emission_shape_name(shape)

	for prop: String in MATERIAL_PROPS:
		if not params.has(prop) or params[prop] == null:
			continue
		match prop:
			"direction", "gravity":
				var vec: Array = _parse_vec3(params[prop], prop)
				if vec[1] != null:
					return vec[1]
				mat.set(prop, vec[0])
			"color":
				var col: Array = _parse_color(params[prop], prop)
				if col[1] != null:
					return col[1]
				mat.color = col[0] as Color
			"spread":
				# ParticleProcessMaterial.spread is exposed and stored in DEGREES (0-180),
				# unlike CharacterBody's radian angles — assign it straight through.
				mat.spread = clampf(optional_float(params, prop, 45.0), 0.0, 180.0)
			"attractor_interaction_enabled":
				mat.attractor_interaction_enabled = optional_bool(params, prop, true)
			_:
				mat.set(prop, optional_float(params, prop, float(mat.get(prop))))
		applied[prop] = PropertyParser.serialize_value(mat.get(prop))

	var relevant: Array = _shape_param_names(shape)
	var all_shape_params: Array = []
	all_shape_params.append_array(SPHERE_PARAMS)
	all_shape_params.append_array(BOX_PARAMS)
	all_shape_params.append_array(RING_PARAMS)

	for prop: String in all_shape_params:
		if not params.has(prop) or params[prop] == null:
			continue
		if not relevant.has(prop):
			# Passed for a different emission_shape — report it, do not error.
			ignored.append(prop)
			continue
		if prop == "emission_box_extents":
			var ext: Array = _parse_vec3(params[prop], prop)
			if ext[1] != null:
				return ext[1]
			mat.emission_box_extents = ext[0] as Vector3
		else:
			mat.set(prop, optional_float(params, prop, float(mat.get(prop))))
		applied[prop] = PropertyParser.serialize_value(mat.get(prop))

	# Params meant for a different emission_shape land in `ignored`, not an error (spec B11).
	# Only a call that supplied nothing at all is a param error.
	if applied.is_empty() and ignored.is_empty():
		return error(-32602, "No material properties were provided")

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_particle_material")
	ur.add_do_property(node, "process_material", mat)
	ur.add_do_reference(mat)
	ur.add_undo_property(node, "process_material", old_mat)
	ur.commit_action()

	return success(
		{
			"node_path": node_path,
			"class": node.get_class(),
			"applied": applied,
			"ignored": ignored,
			"emission_shape": _emission_shape_name(shape),
		}
	)


func _set_particle_color_gradient(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var gate: Array = _get_particles(params)
	if gate[2] != null:
		return gate[2]
	var node: Node = gate[0]
	var node_path: String = String(params.get("node_path", ""))

	var raw: Variant = params.get("stops", null)
	if typeof(raw) != TYPE_ARRAY:
		return error(-32602, "stops must be an array of {offset, color} objects")
	var raw_stops: Array = raw
	if raw_stops.size() < 2:
		return error(-32602, "stops needs at least 2 entries (got %d)" % raw_stops.size())

	var parsed: Array = []
	for entry: Variant in raw_stops:
		if typeof(entry) != TYPE_DICTIONARY:
			return error(-32602, "each stop must be an object with offset and color")
		var stop: Dictionary = entry
		if not stop.has("offset") or not stop.has("color"):
			return error(-32602, "each stop needs both an offset and a color")
		var col: Array = _parse_color(stop["color"], "stop color")
		if col[1] != null:
			return col[1]
		parsed.append(
			{
				"offset": clampf(float(stop["offset"]), 0.0, 1.0),
				"color": col[0] as Color,
			}
		)

	parsed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["offset"]) < float(b["offset"])
	)

	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var reported: Array = []
	for stop: Dictionary in parsed:
		offsets.append(float(stop["offset"]))
		colors.append(stop["color"] as Color)
		reported.append(
			{
				"offset": float(stop["offset"]),
				"color": PropertyParser.serialize_value(stop["color"]),
			}
		)

	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors

	var texture := GradientTexture1D.new()
	texture.gradient = gradient

	var old_mat: ParticleProcessMaterial = (
		node.get("process_material") as ParticleProcessMaterial
	)
	var mat: ParticleProcessMaterial = _ensure_material(node)
	mat.color_ramp = texture

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_particle_color_gradient")
	ur.add_do_property(node, "process_material", mat)
	ur.add_do_reference(mat)
	ur.add_undo_property(node, "process_material", old_mat)
	ur.commit_action()

	return success(
		{
			"node_path": node_path,
			"class": node.get_class(),
			"stops": reported,
			"stop_count": reported.size(),
		}
	)


func _apply_particle_preset(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var gate: Array = _get_particles(params)
	if gate[2] != null:
		return gate[2]
	var node: Node = gate[0]
	var is_3d: bool = gate[1]
	var node_path: String = String(params.get("node_path", ""))

	var preset_res: Array = require_string(params, "preset")
	if preset_res[1] != null:
		return preset_res[1]
	var preset: String = String(preset_res[0]).strip_edges().to_lower()
	if not PRESETS.has(preset):
		return error(-32602, "Unknown preset '%s' (valid: %s)" % [preset, ", ".join(PRESETS)])

	var data: Dictionary = _preset_data(preset, is_3d)
	var node_spec: Dictionary = data["node"]
	var mat_spec: Dictionary = data["material"]

	# Fresh material — a preset fully defines the look, and this can never touch a shared resource.
	var mat := ParticleProcessMaterial.new()
	for prop: String in mat_spec:
		mat.set(prop, mat_spec[prop])

	var old_mat: ParticleProcessMaterial = (
		node.get("process_material") as ParticleProcessMaterial
	)

	var node_writes: Dictionary = {}
	var node_olds: Dictionary = {}
	var node_applied: Dictionary = {}
	for prop: String in NODE_PROPS:
		if not node_spec.has(prop):
			continue
		node_writes[prop] = node_spec[prop]
		node_olds[prop] = node.get(prop)
		node_applied[prop] = PropertyParser.serialize_value(node_spec[prop])

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	# One action writes the node params AND swaps in the fresh material; undo restores both.
	ur.create_action("MCP: apply_particle_preset")
	for prop: String in node_writes:
		ur.add_do_property(node, prop, node_writes[prop])
	ur.add_do_property(node, "process_material", mat)
	ur.add_do_reference(mat)
	for prop: String in node_olds:
		ur.add_undo_property(node, prop, node_olds[prop])
	ur.add_undo_property(node, "process_material", old_mat)
	ur.commit_action()

	var mat_applied: Dictionary = {}
	for prop: String in mat_spec:
		mat_applied[prop] = (
			_emission_shape_name(int(mat_spec[prop]))
			if prop == "emission_shape"
			else PropertyParser.serialize_value(mat_spec[prop])
		)

	return success(
		{
			"node_path": node_path,
			"class": node.get_class(),
			"is_3d": is_3d,
			"preset": preset,
			"applied": {"node": node_applied, "material": mat_applied},
		}
	)


func _get_particle_info(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var gate: Array = _get_particles(params)
	if gate[2] != null:
		return gate[2]
	var node: Node = gate[0]
	var is_3d: bool = gate[1]
	var node_path: String = String(params.get("node_path", ""))

	var node_info: Dictionary = {
		"amount": int(node.get("amount")),
		"lifetime": float(node.get("lifetime")),
		"one_shot": bool(node.get("one_shot")),
		"explosiveness": float(node.get("explosiveness")),
		"randomness": float(node.get("randomness")),
		"emitting": bool(node.get("emitting")),
		"speed_scale": float(node.get("speed_scale")),
		"preprocess": float(node.get("preprocess")),
	}

	var mat: ParticleProcessMaterial = node.get("process_material") as ParticleProcessMaterial
	if mat == null:
		# No process material is a normal state, not an error.
		return success(
			{
				"node_path": node_path,
				"class": node.get_class(),
				"is_3d": is_3d,
				"node": node_info,
				"material": null,
				"emission": null,
				"gradient": null,
			}
		)

	return success(
		{
			"node_path": node_path,
			"class": node.get_class(),
			"is_3d": is_3d,
			"node": node_info,
			"material": _material_payload(mat),
			"emission": _emission_payload(mat),
			"gradient": _gradient_payload(mat),
		}
	)


# ---------------------------------------------------------------------------
# Preset table (2D works in pixels with +Y down; 3D in metres with +Y up)
# ---------------------------------------------------------------------------


func _preset_data(preset: String, is_3d: bool) -> Dictionary:
	var up := Vector3(0, 1, 0) if is_3d else Vector3(0, -1, 0)
	var down := Vector3(0, -1, 0) if is_3d else Vector3(0, 1, 0)

	match preset:
		"explosion":
			return {
				"node":
				{
					"amount": 64,
					"lifetime": 0.6,
					"one_shot": true,
					"explosiveness": 1.0,
					"randomness": 0.4,
					"emitting": true,
				},
				"material":
				{
					"direction": Vector3.ZERO,
					"spread": 180.0,
					"initial_velocity_min": 3.0 if is_3d else 150.0,
					"initial_velocity_max": 8.0 if is_3d else 400.0,
					"gravity": Vector3.ZERO,
					"scale_min": 0.5,
					"scale_max": 1.5,
					"color": Color.html("#ffb733"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_POINT,
				},
			}
		"fire":
			return {
				"node":
				{
					"amount": 48,
					"lifetime": 1.2,
					"one_shot": false,
					"explosiveness": 0.0,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": up,
					"spread": 20.0,
					"initial_velocity_min": 1.0 if is_3d else 40.0,
					"initial_velocity_max": 2.5 if is_3d else 90.0,
					"gravity": Vector3(0, 1.5, 0) if is_3d else Vector3(0, -60, 0),
					"scale_min": 0.6,
					"scale_max": 1.2,
					"color": Color.html("#ff5a1e"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
					"emission_sphere_radius": 0.2 if is_3d else 8.0,
				},
			}
		"smoke":
			return {
				"node":
				{
					"amount": 32,
					"lifetime": 3.0,
					"one_shot": false,
					"explosiveness": 0.0,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": up,
					"spread": 25.0,
					"initial_velocity_min": 0.4 if is_3d else 15.0,
					"initial_velocity_max": 1.0 if is_3d else 40.0,
					"gravity": Vector3(0, 0.5, 0) if is_3d else Vector3(0, -20, 0),
					"scale_min": 1.0,
					"scale_max": 3.0,
					"color": Color.html("#9a9a9a"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,
					"emission_sphere_radius": 0.25 if is_3d else 10.0,
				},
			}
		"sparks":
			return {
				"node":
				{
					"amount": 40,
					"lifetime": 0.8,
					"one_shot": true,
					"explosiveness": 0.9,
					"randomness": 0.4,
					"emitting": true,
				},
				"material":
				{
					"direction": Vector3.ZERO,
					"spread": 180.0,
					"initial_velocity_min": 4.0 if is_3d else 200.0,
					"initial_velocity_max": 7.0 if is_3d else 350.0,
					"gravity": Vector3(0, -9.8, 0) if is_3d else Vector3(0, 600, 0),
					"scale_min": 0.2,
					"scale_max": 0.5,
					"color": Color.html("#fff2a8"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_POINT,
				},
			}
		"rain":
			return {
				"node":
				{
					"amount": 200,
					"lifetime": 1.5,
					"one_shot": false,
					"explosiveness": 0.0,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": down,
					"spread": 2.0,
					"initial_velocity_min": 12.0 if is_3d else 400.0,
					"initial_velocity_max": 16.0 if is_3d else 500.0,
					"gravity": Vector3(0, -20, 0) if is_3d else Vector3(0, 900, 0),
					"scale_min": 0.3,
					"scale_max": 0.6,
					"color": Color.html("#8fb8ff"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX,
					"emission_box_extents": (
						Vector3(10, 0.5, 10) if is_3d else Vector3(400, 10, 0)
					),
				},
			}
		"snow":
			return {
				"node":
				{
					"amount": 120,
					"lifetime": 5.0,
					"one_shot": false,
					"explosiveness": 0.0,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": down,
					"spread": 15.0,
					"initial_velocity_min": 0.8 if is_3d else 30.0,
					"initial_velocity_max": 1.6 if is_3d else 70.0,
					"gravity": Vector3(0, -1.2, 0) if is_3d else Vector3(0, 60, 0),
					"scale_min": 0.4,
					"scale_max": 1.0,
					"color": Color.html("#ffffff"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX,
					"emission_box_extents": (
						Vector3(10, 0.5, 10) if is_3d else Vector3(400, 10, 0)
					),
				},
			}
		"magic":
			return {
				"node":
				{
					"amount": 56,
					"lifetime": 1.6,
					"one_shot": false,
					"explosiveness": 0.2,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": up,
					"spread": 45.0,
					"initial_velocity_min": 0.8 if is_3d else 30.0,
					"initial_velocity_max": 2.0 if is_3d else 80.0,
					"gravity": Vector3(0, 0.6, 0) if is_3d else Vector3(0, -30, 0),
					"scale_min": 0.4,
					"scale_max": 1.1,
					"color": Color.html("#b06cff"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_RING,
					"emission_ring_radius": 0.6 if is_3d else 24.0,
					"emission_ring_inner_radius": 0.2 if is_3d else 8.0,
					"emission_ring_height": 0.05 if is_3d else 2.0,
				},
			}
		_:  # dust
			return {
				"node":
				{
					"amount": 24,
					"lifetime": 4.0,
					"one_shot": false,
					"explosiveness": 0.0,
					"randomness": 0.2,
					"emitting": true,
				},
				"material":
				{
					"direction": Vector3.ZERO,
					"spread": 180.0,
					"initial_velocity_min": 0.1 if is_3d else 5.0,
					"initial_velocity_max": 0.4 if is_3d else 20.0,
					"gravity": Vector3(0, 0.05, 0) if is_3d else Vector3(0, -5, 0),
					"scale_min": 0.2,
					"scale_max": 0.6,
					"color": Color.html("#d8cbb0"),
					"emission_shape": ParticleProcessMaterial.EMISSION_SHAPE_BOX,
					"emission_box_extents": Vector3(4, 2, 4) if is_3d else Vector3(200, 120, 0),
				},
			}
