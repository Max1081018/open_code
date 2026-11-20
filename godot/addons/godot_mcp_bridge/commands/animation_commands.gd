@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B08 — animation commands (6 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4).

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## Only the default (unnamed) animation library is in scope for v1.
const DEFAULT_LIBRARY := ""


func get_commands() -> Dictionary:
	return {
		"list_animations": _list_animations,
		"create_animation": _create_animation,
		"add_animation_track": _add_animation_track,
		"set_animation_keyframe": _set_animation_keyframe,
		"get_animation_info": _get_animation_info,
		"remove_animation": _remove_animation,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Target-node gate. Returns [AnimationPlayer, null] or [null, error_dict].
func _get_player(node_path: String) -> Array:
	var node: Node = find_node_by_path(node_path)
	if node == null:
		return [null, error_not_found("Node at '%s'" % node_path)]
	if not (node is AnimationPlayer):
		return [
			null,
			error(
				-32602,
				"'%s' is not an AnimationPlayer (got %s)" % [node_path, node.get_class()]
			)
		]
	return [node as AnimationPlayer, null]


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


## Index of the key on `track_index` whose time is approximately `time`, or -1.
func _find_key_at(anim: Animation, track_index: int, time: float) -> int:
	for i: int in range(anim.track_get_key_count(track_index)):
		if is_equal_approx(anim.track_get_key_time(track_index, i), time):
			return i
	return -1


## Undo-action helper: upsert a key (replace the value/easing of the key at `time`, else insert).
func _apply_keyframe(
	anim: Animation, track_index: int, time: float, value: Variant, easing: float
) -> void:
	if anim == null or track_index < 0 or track_index >= anim.get_track_count():
		return
	var idx: int = _find_key_at(anim, track_index, time)
	if idx >= 0:
		anim.track_set_key_value(track_index, idx, value)
		anim.track_set_key_transition(track_index, idx, easing)
	else:
		anim.track_insert_key(track_index, time, value, easing)


## Undo-action helper: restore the exact prior state of the key slot at `time`.
func _restore_keyframe(
	anim: Animation,
	track_index: int,
	time: float,
	had_key: bool,
	old_value: Variant,
	old_easing: float
) -> void:
	if anim == null or track_index < 0 or track_index >= anim.get_track_count():
		return
	var idx: int = _find_key_at(anim, track_index, time)
	if had_key:
		if idx >= 0:
			anim.track_set_key_value(track_index, idx, old_value)
			anim.track_set_key_transition(track_index, idx, old_easing)
		else:
			anim.track_insert_key(track_index, time, old_value, old_easing)
	elif idx >= 0:
		anim.track_remove_key(track_index, idx)


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _list_animations(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var animations: Array = []
	if player.has_animation_library(DEFAULT_LIBRARY):
		var lib: AnimationLibrary = player.get_animation_library(DEFAULT_LIBRARY)
		for anim_name: StringName in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			if anim == null:
				continue
			animations.append(
				{
					"name": String(anim_name),
					"length": anim.length,
					"loop_mode": int(anim.loop_mode),
					"track_count": anim.get_track_count(),
				}
			)

	return success(
		{"node_path": String(np[0]), "animations": animations, "count": animations.size()}
	)


func _create_animation(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var anim_name: String = name_res[0]
	var length: float = optional_float(params, "length", 1.0)
	var loop_mode: int = optional_int(params, "loop_mode", 0)
	if loop_mode < 0 or loop_mode > 2:
		return error(
			-32602,
			"loop_mode must be 0 (none), 1 (linear) or 2 (pingpong), got %d" % loop_mode
		)

	var lib: AnimationLibrary = null
	var lib_created: bool = false
	if player.has_animation_library(DEFAULT_LIBRARY):
		lib = player.get_animation_library(DEFAULT_LIBRARY)
		if lib.has_animation(StringName(anim_name)):
			return error(-32000, "Animation '%s' already exists" % anim_name)
	else:
		lib = AnimationLibrary.new()
		lib_created = true

	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = loop_mode as Animation.LoopMode

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: create_animation", UndoRedo.MERGE_DISABLE, player)
	if lib_created:
		ur.add_do_method(player, "add_animation_library", DEFAULT_LIBRARY, lib)
		ur.add_do_reference(lib)
	ur.add_do_method(lib, "add_animation", StringName(anim_name), anim)
	ur.add_do_reference(anim)
	ur.add_undo_method(lib, "remove_animation", StringName(anim_name))
	if lib_created:
		ur.add_undo_method(player, "remove_animation_library", DEFAULT_LIBRARY)
	ur.commit_action()

	return success(
		{
			"name": anim_name,
			"length": length,
			"loop_mode": loop_mode,
			"library": DEFAULT_LIBRARY,
			"created": true,
		}
	)


func _add_animation_track(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var anim_res: Array = require_string(params, "animation")
	if anim_res[1] != null:
		return anim_res[1]
	var path_res: Array = require_string(params, "track_path")
	if path_res[1] != null:
		return path_res[1]
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var anim_name: String = anim_res[0]
	if not player.has_animation(StringName(anim_name)):
		return error_not_found("Animation '%s'" % anim_name)
	var anim: Animation = player.get_animation(StringName(anim_name))

	var track_path: String = path_res[0]
	var track_type: String = optional_string(params, "track_type", "value")

	# Deliberate deviation (spec §B08): 2D position/rotation/scale are VALUE tracks on the
	# matching property — TYPE_POSITION_3D & friends are ignored by AnimationMixer for 2D nodes.
	var godot_type: Animation.TrackType = Animation.TYPE_VALUE
	match track_type:
		"value":
			godot_type = Animation.TYPE_VALUE
		"position_2d":
			godot_type = Animation.TYPE_VALUE
			if not track_path.contains(":"):
				track_path += ":position"
		"rotation_2d":
			godot_type = Animation.TYPE_VALUE
			if not track_path.contains(":"):
				track_path += ":rotation"
		"scale_2d":
			godot_type = Animation.TYPE_VALUE
			if not track_path.contains(":"):
				track_path += ":scale"
		"method":
			godot_type = Animation.TYPE_METHOD
		"bezier":
			godot_type = Animation.TYPE_BEZIER
		"blend_shape":
			godot_type = Animation.TYPE_BLEND_SHAPE
		_:
			return error(
				-32602,
				(
					"Unknown track_type '%s' (value|position_2d|rotation_2d|scale_2d|method|bezier|blend_shape)"
					% track_type
				)
			)

	var has_update_mode: bool = params.has("update_mode") and params["update_mode"] != null
	var update_mode: String = optional_string(params, "update_mode", "")
	var godot_update: Animation.UpdateMode = Animation.UPDATE_CONTINUOUS
	if has_update_mode:
		match update_mode:
			"continuous":
				godot_update = Animation.UPDATE_CONTINUOUS
			"discrete":
				godot_update = Animation.UPDATE_DISCRETE
			"capture":
				godot_update = Animation.UPDATE_CAPTURE
			_:
				return error(
					-32602,
					"Unknown update_mode '%s' (continuous|discrete|capture)" % update_mode
				)

	var track_index: int = anim.get_track_count()

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: add_animation_track", UndoRedo.MERGE_DISABLE, player)
	ur.add_do_method(anim, "add_track", godot_type, track_index)
	ur.add_do_method(anim, "track_set_path", track_index, NodePath(track_path))
	if has_update_mode and godot_type == Animation.TYPE_VALUE:
		ur.add_do_method(anim, "value_track_set_update_mode", track_index, godot_update)
	ur.add_undo_method(anim, "remove_track", track_index)
	ur.commit_action()

	var out: Dictionary = {
		"animation": anim_name,
		"track_index": track_index,
		"track_path": track_path,
		"track_type": track_type,
	}
	# update_mode is a value-track-only setting; report it only when it was actually applied.
	if has_update_mode and godot_type == Animation.TYPE_VALUE:
		out["update_mode"] = update_mode
	return success(out)


func _set_animation_keyframe(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var anim_res: Array = require_string(params, "animation")
	if anim_res[1] != null:
		return anim_res[1]
	if not params.has("value") or params["value"] == null:
		return error(-32602, "Missing required parameter: value")
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var anim_name: String = anim_res[0]
	if not player.has_animation(StringName(anim_name)):
		return error_not_found("Animation '%s'" % anim_name)
	var anim: Animation = player.get_animation(StringName(anim_name))

	var track_index: int = optional_int(params, "track_index", 0)
	if track_index < 0 or track_index >= anim.get_track_count():
		return error(
			-32602,
			(
				"track_index %d is out of range [0, %d) for animation '%s'"
				% [track_index, anim.get_track_count(), anim_name]
			)
		)

	var time: float = optional_float(params, "time", 0.0)
	var easing: float = optional_float(params, "easing", 1.0)

	var value: Variant = PropertyParser.parse_value(params["value"], TYPE_NIL)
	if anim.track_get_type(track_index) == Animation.TYPE_METHOD:
		# Method-track keys are dicts; property_parser leaves a JSON object as a plain string.
		if typeof(value) == TYPE_STRING and String(value).strip_edges().begins_with("{"):
			var decoded: Variant = JSON.parse_string(String(value))
			if typeof(decoded) == TYPE_DICTIONARY:
				value = decoded
		if typeof(value) != TYPE_DICTIONARY:
			return error(
				-32602,
				'Method track keys need a dict value, e.g. {"method": "fire", "args": []}'
			)

	var prev_index: int = _find_key_at(anim, track_index, time)
	var had_key: bool = prev_index >= 0
	var old_value: Variant = (
		anim.track_get_key_value(track_index, prev_index) if had_key else null
	)
	var old_easing: float = (
		anim.track_get_key_transition(track_index, prev_index) if had_key else 1.0
	)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_animation_keyframe", UndoRedo.MERGE_DISABLE, player)
	ur.add_do_method(self, "_apply_keyframe", anim, track_index, time, value, easing)
	ur.add_undo_method(
		self, "_restore_keyframe", anim, track_index, time, had_key, old_value, old_easing
	)
	ur.commit_action()

	var key_index: int = _find_key_at(anim, track_index, time)
	var read_back: Variant = (
		anim.track_get_key_value(track_index, key_index) if key_index >= 0 else null
	)
	var read_easing: float = (
		anim.track_get_key_transition(track_index, key_index) if key_index >= 0 else easing
	)

	return success(
		{
			"animation": anim_name,
			"track_index": track_index,
			"time": time,
			"key_index": key_index,
			"value": PropertyParser.serialize_value(read_back),
			"easing": read_easing,
		}
	)


func _get_animation_info(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var anim_res: Array = require_string(params, "animation")
	if anim_res[1] != null:
		return anim_res[1]
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var anim_name: String = anim_res[0]
	if not player.has_animation(StringName(anim_name)):
		return error_not_found("Animation '%s'" % anim_name)
	var anim: Animation = player.get_animation(StringName(anim_name))

	var tracks: Array = []
	for i: int in range(anim.get_track_count()):
		var keys: Array = []
		for k: int in range(anim.track_get_key_count(i)):
			keys.append(
				{
					"time": anim.track_get_key_time(i, k),
					"value": PropertyParser.serialize_value(anim.track_get_key_value(i, k)),
					"easing": anim.track_get_key_transition(i, k),
				}
			)
		tracks.append(
			{
				"index": i,
				"path": String(anim.track_get_path(i)),
				"type": int(anim.track_get_type(i)),
				"key_count": anim.track_get_key_count(i),
				"keys": keys,
			}
		)

	return success(
		{
			"name": anim_name,
			"length": anim.length,
			"loop_mode": int(anim.loop_mode),
			"step": anim.step,
			"tracks": tracks,
		}
	)


func _remove_animation(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var gate: Array = _get_player(np[0])
	if gate[1] != null:
		return gate[1]
	var player: AnimationPlayer = gate[0]

	var anim_name: String = name_res[0]
	if not player.has_animation_library(DEFAULT_LIBRARY):
		return error_not_found("Animation '%s'" % anim_name)
	var lib: AnimationLibrary = player.get_animation_library(DEFAULT_LIBRARY)
	if not lib.has_animation(StringName(anim_name)):
		return error_not_found("Animation '%s'" % anim_name)
	var anim: Animation = lib.get_animation(StringName(anim_name))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: remove_animation", UndoRedo.MERGE_DISABLE, player)
	ur.add_do_method(lib, "remove_animation", StringName(anim_name))
	ur.add_undo_method(lib, "add_animation", StringName(anim_name), anim)
	ur.add_undo_reference(anim)
	ur.commit_action()

	return success({"name": anim_name, "library": DEFAULT_LIBRARY, "removed": true})
