@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B08 — animation_tree commands (8 tools).
##
## All handlers are [E+S]: they need the editor AND an open scene. Every mutating tool commits
## exactly one EditorUndoRedoManager action labeled "MCP: <tool_name>" (SPEC §3.4).
##
## AnimationNodeStateMachine / AnimationNodeBlendTree expose no public child-list API in
## Godot 4.x, so children are enumerated off get_property_list() ("states/<n>/node" and
## "nodes/<n>/node").

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

const STATES_PREFIX := "states/"
const NODES_PREFIX := "nodes/"
const NODE_SUFFIX := "/node"
const OUTPUT_NODE := "output"


func get_commands() -> Dictionary:
	return {
		"create_animation_tree": _create_animation_tree,
		"get_animation_tree_structure": _get_animation_tree_structure,
		"add_state_machine_state": _add_state_machine_state,
		"remove_state_machine_state": _remove_state_machine_state,
		"add_state_machine_transition": _add_state_machine_transition,
		"remove_state_machine_transition": _remove_state_machine_transition,
		"set_blend_tree_node": _set_blend_tree_node,
		"set_tree_parameter": _set_tree_parameter,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Target-node gate. Returns [AnimationTree, null] or [null, error_dict].
func _get_tree_node(node_path: String) -> Array:
	var node: Node = find_node_by_path(node_path)
	if node == null:
		return [null, error_not_found("Node at '%s'" % node_path)]
	if not (node is AnimationTree):
		return [
			null,
			error(-32602, "'%s' is not an AnimationTree (got %s)" % [node_path, node.get_class()])
		]
	return [node as AnimationTree, null]


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


## Walk a slash-separated path of nested state machines. Returns [sm, null] or [null, error_dict].
func _resolve_state_machine(tree: AnimationTree, state_machine_path: String) -> Array:
	var root: AnimationNode = tree.tree_root
	if root == null or not (root is AnimationNodeStateMachine):
		return [null, error(-32000, "AnimationTree root is not an AnimationNodeStateMachine")]

	var sm: AnimationNodeStateMachine = root as AnimationNodeStateMachine
	var path: String = state_machine_path.strip_edges()
	if path.is_empty() or path == ".":
		return [sm, null]

	for segment: String in path.split("/", false):
		if not sm.has_node(StringName(segment)):
			return [
				null,
				error_not_found(
					"State machine node '%s' in path '%s'" % [segment, state_machine_path]
				)
			]
		var child: AnimationNode = sm.get_node(StringName(segment))
		if not (child is AnimationNodeStateMachine):
			return [null, error(-32602, "'%s' is not a state machine" % segment)]
		sm = child as AnimationNodeStateMachine
	return [sm, null]


## User-defined state names of a state machine (built-in Start/End omitted).
func _state_names(sm: AnimationNodeStateMachine) -> Array[String]:
	var out: Array[String] = []
	for prop: Dictionary in sm.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with(STATES_PREFIX) or not prop_name.ends_with(NODE_SUFFIX):
			continue
		var state: String = prop_name.substr(
			STATES_PREFIX.length(),
			prop_name.length() - STATES_PREFIX.length() - NODE_SUFFIX.length()
		)
		if state.is_empty() or state == "Start" or state == "End":
			continue
		out.append(state)
	return out


## Node names of a blend tree ("output" included — it is a real AnimationNodeOutput).
func _blend_tree_node_names(bt: AnimationNodeBlendTree) -> Array[String]:
	# AnimationNodeBlendTree deliberately omits "nodes/output/node" from its property list, so
	# the loop below can never see the output node. It always exists — seed it, or the dumped
	# `nodes` array is missing the very node every connection points at.
	var out: Array[String] = [OUTPUT_NODE]
	for prop: Dictionary in bt.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if not prop_name.begins_with(NODES_PREFIX) or not prop_name.ends_with(NODE_SUFFIX):
			continue
		var node_name: String = prop_name.substr(
			NODES_PREFIX.length(),
			prop_name.length() - NODES_PREFIX.length() - NODE_SUFFIX.length()
		)
		if node_name.is_empty() or node_name == OUTPUT_NODE:
			continue
		out.append(node_name)
	return out


func _switch_mode_name(mode: int) -> String:
	match mode:
		AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE:
			return "immediate"
		AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC:
			return "sync"
		AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END:
			return "at_end"
		_:
			return "immediate"


func _advance_mode_name(mode: int) -> String:
	match mode:
		AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED:
			return "disabled"
		AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED:
			return "enabled"
		AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO:
			return "auto"
		_:
			return "enabled"


## Breadth-first search for the first AnimationPlayer among a node's descendants.
func _find_animation_player(parent: Node) -> AnimationPlayer:
	var queue: Array[Node] = []
	for child: Node in parent.get_children():
		queue.append(child)
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child: Node in node.get_children():
			queue.append(child)
	return null


## Recursive graph dump used by get_animation_tree_structure.
func _dump_animation_node(node: AnimationNode) -> Dictionary:
	if node == null:
		return {}

	if node is AnimationNodeStateMachine:
		var sm: AnimationNodeStateMachine = node as AnimationNodeStateMachine

		var states: Array = []
		for state: String in _state_names(sm):
			var state_pos: Vector2 = sm.get_node_position(StringName(state))
			var state_entry: Dictionary = {
				"name": state,
				"position": {"x": state_pos.x, "y": state_pos.y},
			}
			var child_shape: Dictionary = _dump_animation_node(sm.get_node(StringName(state)))
			for key: String in child_shape:
				state_entry[key] = child_shape[key]
			states.append(state_entry)

		var transitions: Array = []
		for i: int in range(sm.get_transition_count()):
			var t: AnimationNodeStateMachineTransition = sm.get_transition(i)
			var t_entry: Dictionary = {
				"from": String(sm.get_transition_from(i)),
				"to": String(sm.get_transition_to(i)),
				"switch_mode": _switch_mode_name(int(t.switch_mode)),
				"advance_mode": _advance_mode_name(int(t.advance_mode)),
				"xfade_time": t.xfade_time,
			}
			var expr: String = String(t.advance_expression)
			if not expr.is_empty():
				t_entry["advance_expression"] = expr
			transitions.append(t_entry)

		return {
			"type": "AnimationNodeStateMachine",
			"states": states,
			"transitions": transitions,
		}

	if node is AnimationNodeBlendTree:
		var bt: AnimationNodeBlendTree = node as AnimationNodeBlendTree

		var nodes: Array = []
		for bt_name: String in _blend_tree_node_names(bt):
			var bt_child: AnimationNode = bt.get_node(StringName(bt_name))
			var bt_pos: Vector2 = bt.get_node_position(StringName(bt_name))
			var bt_entry: Dictionary = {
				"name": bt_name,
				"type": bt_child.get_class() if bt_child != null else "",
				"position": {"x": bt_pos.x, "y": bt_pos.y},
			}
			if bt_child is AnimationNodeAnimation:
				bt_entry["animation"] = String((bt_child as AnimationNodeAnimation).animation)
			nodes.append(bt_entry)

		# node_connections is a FLAT array of (input_node, input_port, output_node) triplets.
		var connections: Array = []
		var raw: Variant = bt.get("node_connections")
		if typeof(raw) == TYPE_ARRAY:
			var flat: Array = raw
			var i: int = 0
			while i + 2 < flat.size():
				connections.append(
					{
						"to": String(flat[i]),
						"to_port": int(flat[i + 1]),
						"from": String(flat[i + 2]),
					}
				)
				i += 3

		return {
			"type": "AnimationNodeBlendTree",
			"nodes": nodes,
			"connections": connections,
		}

	if node is AnimationNodeAnimation:
		return {
			"type": "AnimationNodeAnimation",
			"animation": String((node as AnimationNodeAnimation).animation),
		}

	return {"type": node.get_class()}


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _create_animation_tree(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var parent_path: String = np[0]
	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Node at '%s'" % parent_path)

	var tree_name: String = optional_string(params, "name", "AnimationTree")
	if tree_name.is_empty():
		tree_name = "AnimationTree"
	var anim_player_path: String = optional_string(params, "anim_player", "")

	var player: AnimationPlayer = null
	if not anim_player_path.is_empty():
		var found: Node = find_node_by_path(anim_player_path)
		if found == null:
			return error_not_found("Node at '%s'" % anim_player_path)
		if not (found is AnimationPlayer):
			return error(
				-32602,
				(
					"'%s' is not an AnimationPlayer (got %s)"
					% [anim_player_path, found.get_class()]
				)
			)
		player = found as AnimationPlayer
	else:
		# Auto-find: first AnimationPlayer under the parent. None found is not an error.
		player = _find_animation_player(parent)

	var tree := AnimationTree.new()
	tree.name = unique_child_name(parent, tree_name, "AnimationTree")
	tree.tree_root = AnimationNodeStateMachine.new()
	tree.active = true

	# Parent and player are already in the scene, so the path is computable before add_child;
	# the tree will sit one level below `parent`, hence the "../" prefix.
	var wired_player: String = ""
	if player != null:
		wired_player = "../" + String(parent.get_path_to(player))
		tree.anim_player = NodePath(wired_player)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: create_animation_tree", UndoRedo.MERGE_DISABLE, parent)
	ur.add_do_method(parent, "add_child", tree, true)
	ur.add_do_method(tree, "set_owner", root)
	ur.add_do_reference(tree)
	ur.add_undo_method(parent, "remove_child", tree)
	ur.commit_action()

	# Read the name back: Godot auto-renames on a sibling collision.
	return success(
		{
			"name": String(tree.name),
			"node_path": String(root.get_path_to(tree)),
			"root_type": "AnimationNodeStateMachine",
			"anim_player": wired_player,
			"anim_player_found": player != null,
			"created": true,
		}
	)


func _get_animation_tree_structure(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var root_dump: Variant = null
	if tree.tree_root != null:
		root_dump = _dump_animation_node(tree.tree_root)

	return success(
		{
			"node_path": String(np[0]),
			"active": tree.active,
			"anim_player": String(tree.anim_player),
			"root": root_dump,
		}
	)


func _add_state_machine_state(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "state_name")
	if name_res[1] != null:
		return name_res[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var sm_path: String = optional_string(params, "state_machine_path", "")
	var sm_res: Array = _resolve_state_machine(tree, sm_path)
	if sm_res[1] != null:
		return sm_res[1]
	var sm: AnimationNodeStateMachine = sm_res[0]

	var state_name: String = name_res[0]
	if sm.has_node(StringName(state_name)):
		return error(-32000, "State '%s' already exists" % state_name)

	var state_type: String = optional_string(params, "state_type", "animation")
	var animation: String = optional_string(params, "animation", "")
	var position_x: float = optional_float(params, "position_x", 0.0)
	var position_y: float = optional_float(params, "position_y", 0.0)

	var state_node: AnimationNode = null
	match state_type:
		"animation":
			var anim_node := AnimationNodeAnimation.new()
			if not animation.is_empty():
				anim_node.animation = StringName(animation)
			state_node = anim_node
		"blend_tree":
			state_node = AnimationNodeBlendTree.new()
		"state_machine":
			state_node = AnimationNodeStateMachine.new()
		_:
			return error(
				-32602,
				"Unknown state_type '%s' (animation|blend_tree|state_machine)" % state_type
			)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: add_state_machine_state", UndoRedo.MERGE_DISABLE, tree)
	ur.add_do_method(
		sm, "add_node", StringName(state_name), state_node, Vector2(position_x, position_y)
	)
	ur.add_do_reference(state_node)
	ur.add_undo_method(sm, "remove_node", StringName(state_name))
	ur.commit_action()

	return success(
		{
			"state_name": state_name,
			"state_type": state_type,
			"state_machine_path": sm_path,
			"position": {"x": position_x, "y": position_y},
			"added": true,
		}
	)


func _remove_state_machine_state(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "state_name")
	if name_res[1] != null:
		return name_res[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var sm_path: String = optional_string(params, "state_machine_path", "")
	var sm_res: Array = _resolve_state_machine(tree, sm_path)
	if sm_res[1] != null:
		return sm_res[1]
	var sm: AnimationNodeStateMachine = sm_res[0]

	var state_name: String = name_res[0]
	if not sm.has_node(StringName(state_name)):
		return error_not_found("State '%s'" % state_name)

	# Caveat (reference-compatible): Godot silently drops every transition touching the removed
	# state. Undo re-adds the state node at its old position but NOT those transitions.
	var state_node: AnimationNode = sm.get_node(StringName(state_name))
	var position: Vector2 = sm.get_node_position(StringName(state_name))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: remove_state_machine_state", UndoRedo.MERGE_DISABLE, tree)
	ur.add_do_method(sm, "remove_node", StringName(state_name))
	ur.add_undo_method(sm, "add_node", StringName(state_name), state_node, position)
	ur.add_undo_reference(state_node)
	ur.commit_action()

	return success(
		{
			"state_name": state_name,
			"state_machine_path": sm_path,
			"removed": true,
			"note": "transitions touching this state were dropped; undo does not restore them",
		}
	)


func _add_state_machine_transition(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var from_res: Array = require_string(params, "from_state")
	if from_res[1] != null:
		return from_res[1]
	var to_res: Array = require_string(params, "to_state")
	if to_res[1] != null:
		return to_res[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var sm_path: String = optional_string(params, "state_machine_path", "")
	var sm_res: Array = _resolve_state_machine(tree, sm_path)
	if sm_res[1] != null:
		return sm_res[1]
	var sm: AnimationNodeStateMachine = sm_res[0]

	var from_state: String = from_res[0]
	var to_state: String = to_res[0]
	for state: String in [from_state, to_state]:
		if state == "Start" or state == "End":
			continue
		if not sm.has_node(StringName(state)):
			return error_not_found("State '%s'" % state)

	# add_transition() ERR_FAIL_CONDs on these three, adding nothing — without the guard the
	# handler would still commit an empty undo action and report added: true.
	if from_state == to_state:
		return error(-32602, "from_state and to_state must differ (no self-transitions)")
	if from_state == "End":
		return error(-32602, "'End' cannot be a transition source")
	if to_state == "Start":
		return error(-32602, "'Start' cannot be a transition target")

	if sm.has_transition(StringName(from_state), StringName(to_state)):
		return error(-32000, "Transition already exists")

	# Deliberate deviation (spec B08): "sync" maps to the real SWITCH_MODE_SYNC — the reference
	# product mapped it to SWITCH_MODE_AT_END because its enum comment had the wrong order.
	var switch_mode: String = optional_string(params, "switch_mode", "immediate")
	var godot_switch: AnimationNodeStateMachineTransition.SwitchMode = (
		AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	)
	match switch_mode:
		"immediate":
			godot_switch = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		"sync":
			godot_switch = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
		"at_end":
			godot_switch = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		_:
			return error(-32602, "Unknown switch_mode '%s' (at_end|immediate|sync)" % switch_mode)

	var advance_mode: String = optional_string(params, "advance_mode", "enabled")
	var godot_advance: AnimationNodeStateMachineTransition.AdvanceMode = (
		AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	)
	match advance_mode:
		"disabled":
			godot_advance = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
		"enabled":
			godot_advance = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		"auto":
			godot_advance = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		_:
			return error(
				-32602, "Unknown advance_mode '%s' (disabled|enabled|auto)" % advance_mode
			)

	var advance_expression: String = optional_string(params, "advance_expression", "")
	var has_xfade: bool = params.has("xfade_time") and params["xfade_time"] != null
	var xfade_time: float = optional_float(params, "xfade_time", 0.0)

	var transition := AnimationNodeStateMachineTransition.new()
	transition.switch_mode = godot_switch
	transition.advance_mode = godot_advance
	if not advance_expression.is_empty():
		transition.advance_expression = advance_expression
	if has_xfade:
		transition.xfade_time = xfade_time

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: add_state_machine_transition", UndoRedo.MERGE_DISABLE, tree)
	ur.add_do_method(
		sm, "add_transition", StringName(from_state), StringName(to_state), transition
	)
	ur.add_do_reference(transition)
	ur.add_undo_method(sm, "remove_transition", StringName(from_state), StringName(to_state))
	ur.commit_action()

	var out: Dictionary = {
		"from": from_state,
		"to": to_state,
		"state_machine_path": sm_path,
		"switch_mode": switch_mode,
		"advance_mode": advance_mode,
		"advance_expression": advance_expression,
		"added": true,
	}
	if has_xfade:
		out["xfade_time"] = xfade_time
	if not advance_expression.is_empty():
		out["note"] = (
			"advance_expression is only evaluated when advance_expression_base_node is set on the AnimationTree"
		)
	return success(out)


func _remove_state_machine_transition(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var from_res: Array = require_string(params, "from_state")
	if from_res[1] != null:
		return from_res[1]
	var to_res: Array = require_string(params, "to_state")
	if to_res[1] != null:
		return to_res[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var sm_path: String = optional_string(params, "state_machine_path", "")
	var sm_res: Array = _resolve_state_machine(tree, sm_path)
	if sm_res[1] != null:
		return sm_res[1]
	var sm: AnimationNodeStateMachine = sm_res[0]

	var from_state: String = from_res[0]
	var to_state: String = to_res[0]

	var transition: AnimationNodeStateMachineTransition = null
	for i: int in range(sm.get_transition_count()):
		if (
			String(sm.get_transition_from(i)) == from_state
			and String(sm.get_transition_to(i)) == to_state
		):
			transition = sm.get_transition(i)
			break
	if transition == null:
		return error_not_found("Transition '%s' -> '%s'" % [from_state, to_state])

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: remove_state_machine_transition", UndoRedo.MERGE_DISABLE, tree)
	ur.add_do_method(sm, "remove_transition", StringName(from_state), StringName(to_state))
	ur.add_undo_method(
		sm, "add_transition", StringName(from_state), StringName(to_state), transition
	)
	ur.add_undo_reference(transition)
	ur.commit_action()

	return success(
		{"from": from_state, "to": to_state, "state_machine_path": sm_path, "removed": true}
	)


func _set_blend_tree_node(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var state_res: Array = require_string(params, "blend_tree_state")
	if state_res[1] != null:
		return state_res[1]
	var bt_name_res: Array = require_string(params, "bt_node_name")
	if bt_name_res[1] != null:
		return bt_name_res[1]
	var bt_type_res: Array = require_string(params, "bt_node_type")
	if bt_type_res[1] != null:
		return bt_type_res[1]
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var sm_path: String = optional_string(params, "state_machine_path", "")
	var sm_res: Array = _resolve_state_machine(tree, sm_path)
	if sm_res[1] != null:
		return sm_res[1]
	var sm: AnimationNodeStateMachine = sm_res[0]

	var blend_tree_state: String = state_res[0]
	if not sm.has_node(StringName(blend_tree_state)):
		return error_not_found("State '%s'" % blend_tree_state)
	var state_node: AnimationNode = sm.get_node(StringName(blend_tree_state))
	if not (state_node is AnimationNodeBlendTree):
		return error(
			-32602,
			(
				"'%s' is not an AnimationNodeBlendTree (got %s)"
				% [blend_tree_state, state_node.get_class()]
			)
		)
	var bt: AnimationNodeBlendTree = state_node as AnimationNodeBlendTree

	var bt_node_name: String = bt_name_res[0]
	if bt_node_name == OUTPUT_NODE:
		return error(-32602, "'output' is a reserved blend tree node and cannot be overwritten")

	var bt_node_type: String = bt_type_res[0]
	var animation: String = optional_string(params, "animation", "")
	var new_node: AnimationNode = null
	match bt_node_type:
		"Animation":
			var anim_node := AnimationNodeAnimation.new()
			if not animation.is_empty():
				anim_node.animation = StringName(animation)
			new_node = anim_node
		"Add2":
			new_node = AnimationNodeAdd2.new()
		"Blend2":
			new_node = AnimationNodeBlend2.new()
		"Add3":
			new_node = AnimationNodeAdd3.new()
		"Blend3":
			new_node = AnimationNodeBlend3.new()
		"TimeScale":
			new_node = AnimationNodeTimeScale.new()
		"TimeSeek":
			new_node = AnimationNodeTimeSeek.new()
		"Transition":
			new_node = AnimationNodeTransition.new()
		"OneShot":
			new_node = AnimationNodeOneShot.new()
		"Sub2":
			new_node = AnimationNodeSub2.new()
		_:
			return error(
				-32602,
				(
					"Unknown bt_node_type '%s' (Animation|Add2|Blend2|Add3|Blend3|TimeScale|TimeSeek|Transition|OneShot|Sub2)"
					% bt_node_type
				)
			)

	var position_x: float = optional_float(params, "position_x", 0.0)
	var position_y: float = optional_float(params, "position_y", 0.0)
	var position := Vector2(position_x, position_y)

	var connect_to: String = optional_string(params, "connect_to", "")
	var connect_port: int = optional_int(params, "connect_port", 0)
	if not connect_to.is_empty():
		if not bt.has_node(StringName(connect_to)):
			return error_not_found("Blend tree node '%s'" % connect_to)
		var target: AnimationNode = bt.get_node(StringName(connect_to))
		if connect_port < 0 or connect_port >= target.get_input_count():
			return error(
				-32602,
				(
					"connect_port %d is out of range [0, %d) for '%s'"
					% [connect_port, target.get_input_count(), connect_to]
				)
			)

	# Add-or-replace. Connections into a replaced node are dropped by Godot and are NOT restored
	# by undo (documented caveat); undo does restore the old node and its graph position.
	var replaced: bool = bt.has_node(StringName(bt_node_name))
	var old_node: AnimationNode = null
	var old_position := Vector2.ZERO
	if replaced:
		old_node = bt.get_node(StringName(bt_node_name))
		old_position = bt.get_node_position(StringName(bt_node_name))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_blend_tree_node", UndoRedo.MERGE_DISABLE, tree)
	if replaced:
		ur.add_do_method(bt, "remove_node", StringName(bt_node_name))
	ur.add_do_method(bt, "add_node", StringName(bt_node_name), new_node, position)
	ur.add_do_reference(new_node)
	if not connect_to.is_empty():
		# connect_node(input_node, input_index, output_node) wires the NEW node's output into
		# connect_to's input port — e.g. connect_to "output" routes it to the blend tree result.
		ur.add_do_method(
			bt, "connect_node", StringName(connect_to), connect_port, StringName(bt_node_name)
		)
	ur.add_undo_method(bt, "remove_node", StringName(bt_node_name))
	if replaced:
		ur.add_undo_method(bt, "add_node", StringName(bt_node_name), old_node, old_position)
		ur.add_undo_reference(old_node)
	ur.commit_action()

	var connected_to: Variant = null
	if not connect_to.is_empty():
		connected_to = connect_to

	return success(
		{
			"blend_tree_state": blend_tree_state,
			"bt_node_name": bt_node_name,
			"bt_node_type": bt_node_type,
			"state_machine_path": sm_path,
			"position": {"x": position_x, "y": position_y},
			"connected_to": connected_to,
			"connect_port": connect_port,
			"replaced": replaced,
			"added": true,
		}
	)


func _set_tree_parameter(params: Dictionary) -> Dictionary:
	if get_edited_root() == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var param_res: Array = require_string(params, "parameter")
	if param_res[1] != null:
		return param_res[1]
	if not params.has("value") or params["value"] == null:
		return error(-32602, "Missing required parameter: value")
	var gate: Array = _get_tree_node(np[0])
	if gate[1] != null:
		return gate[1]
	var tree: AnimationTree = gate[0]

	var full_key: String = param_res[0]
	if not full_key.begins_with("parameters/"):
		full_key = "parameters/" + full_key

	var exists: bool = false
	for prop: Dictionary in tree.get_property_list():
		if str(prop.get("name", "")) == full_key:
			exists = true
			break
	if not exists:
		return error_not_found("Parameter '%s'" % full_key)

	var old_value: Variant = tree.get(full_key)
	var new_value: Variant = PropertyParser.parse_value(params["value"], TYPE_NIL)

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: set_tree_parameter", UndoRedo.MERGE_DISABLE, tree)
	ur.add_do_property(tree, full_key, new_value)
	ur.add_undo_property(tree, full_key, old_value)
	ur.commit_action()

	return success(
		{
			"parameter": full_key,
			"old_value": PropertyParser.serialize_value(old_value),
			"value": PropertyParser.serialize_value(tree.get(full_key)),
			"set": true,
		}
	)
