@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## B10 — audio commands (6 tools).
##
## Bus ops (`add_audio_bus`, `set_audio_bus`, `add_audio_bus_effect`) mutate the editor's LIVE
## AudioServer directly: DELIBERATELY no EditorUndoRedoManager action and no write to
## default_bus_layout.tres. Editor undo will not revert them and they are lost on editor restart
## unless the user saves the bus layout from the Audio panel. Their tool descriptions say so.
##
## `get_audio_bus_layout` is [E] read-only. `add_audio_player` is an [E+S] scene edit with one
## undo action "MCP: add_audio_player" (SPEC §3.4). `get_audio_info` is [E+S] read-only.

## effect_type -> the params it recognizes, and the Variant type each is coerced to.
const EFFECT_PARAM_TYPES := {
	"reverb":
	{
		"room_size": TYPE_FLOAT,
		"damping": TYPE_FLOAT,
		"wet": TYPE_FLOAT,
		"dry": TYPE_FLOAT,
		"spread": TYPE_FLOAT,
	},
	"chorus": {"voice_count": TYPE_INT, "dry": TYPE_FLOAT, "wet": TYPE_FLOAT},
	"delay":
	{
		"tap1_active": TYPE_BOOL,
		"tap1_delay_ms": TYPE_FLOAT,
		"tap1_level_db": TYPE_FLOAT,
		"tap2_active": TYPE_BOOL,
		"tap2_delay_ms": TYPE_FLOAT,
		"tap2_level_db": TYPE_FLOAT,
	},
	"compressor":
	{
		"threshold": TYPE_FLOAT,
		"ratio": TYPE_FLOAT,
		"attack_us": TYPE_FLOAT,
		"release_ms": TYPE_FLOAT,
		"gain": TYPE_FLOAT,
		"mix": TYPE_FLOAT,
	},
	"limiter":
	{
		"ceiling_db": TYPE_FLOAT,
		"threshold_db": TYPE_FLOAT,
		"soft_clip_db": TYPE_FLOAT,
		"soft_clip_ratio": TYPE_FLOAT,
	},
	"phaser":
	{
		"range_min_hz": TYPE_FLOAT,
		"range_max_hz": TYPE_FLOAT,
		"rate_hz": TYPE_FLOAT,
		"feedback": TYPE_FLOAT,
		"depth": TYPE_FLOAT,
	},
	"distortion":
	{
		"mode": TYPE_INT,
		"pre_gain": TYPE_FLOAT,
		"post_gain": TYPE_FLOAT,
		"keep_hf_hz": TYPE_FLOAT,
		"drive": TYPE_FLOAT,
	},
	"lowpass": {"cutoff_hz": TYPE_FLOAT, "resonance": TYPE_FLOAT},
	"highpass": {"cutoff_hz": TYPE_FLOAT, "resonance": TYPE_FLOAT},
	"bandpass": {"cutoff_hz": TYPE_FLOAT, "resonance": TYPE_FLOAT},
	"amplify": {"volume_db": TYPE_FLOAT},
	# Band gains are edited in the Audio panel; `params` is ignored for EQ.
	"eq": {},
}

const PLAYER_TYPES: PackedStringArray = [
	"AudioStreamPlayer",
	"AudioStreamPlayer2D",
	"AudioStreamPlayer3D",
]


func get_commands() -> Dictionary:
	return {
		"get_audio_bus_layout": _get_audio_bus_layout,
		"add_audio_bus": _add_audio_bus,
		"set_audio_bus": _set_audio_bus,
		"add_audio_bus_effect": _add_audio_bus_effect,
		"add_audio_player": _add_audio_player,
		"get_audio_info": _get_audio_info,
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _require_undo() -> Array:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return [null, error(-32603, "Undo/redo manager is unavailable")]
	return [ur, null]


## Read-side view of an effect's interesting properties. Subclasses are matched BEFORE
## AudioEffectFilter, which is the base of the low/high/band-pass filters.
func _effect_params(effect: AudioEffect) -> Dictionary:
	if effect == null:
		return {}

	if effect is AudioEffectReverb:
		var reverb: AudioEffectReverb = effect
		return {
			"room_size": reverb.room_size,
			"damping": reverb.damping,
			"wet": reverb.wet,
			"dry": reverb.dry,
			"spread": reverb.spread,
		}

	if effect is AudioEffectChorus:
		var chorus: AudioEffectChorus = effect
		return {"voice_count": chorus.voice_count, "dry": chorus.dry, "wet": chorus.wet}

	if effect is AudioEffectDelay:
		var delay: AudioEffectDelay = effect
		return {
			"tap1_active": delay.tap1_active,
			"tap1_delay_ms": delay.tap1_delay_ms,
			"tap1_level_db": delay.tap1_level_db,
			"tap2_active": delay.tap2_active,
			"tap2_delay_ms": delay.tap2_delay_ms,
			"tap2_level_db": delay.tap2_level_db,
		}

	if effect is AudioEffectCompressor:
		var comp: AudioEffectCompressor = effect
		return {
			"threshold": comp.threshold,
			"ratio": comp.ratio,
			"attack_us": comp.attack_us,
			"release_ms": comp.release_ms,
			"gain": comp.gain,
			"mix": comp.mix,
			"sidechain": String(comp.sidechain),
		}

	if effect is AudioEffectLimiter:
		var limiter: AudioEffectLimiter = effect
		return {
			"ceiling_db": limiter.ceiling_db,
			"threshold_db": limiter.threshold_db,
			"soft_clip_db": limiter.soft_clip_db,
			"soft_clip_ratio": limiter.soft_clip_ratio,
		}

	if effect is AudioEffectPhaser:
		var phaser: AudioEffectPhaser = effect
		return {
			"range_min_hz": phaser.range_min_hz,
			"range_max_hz": phaser.range_max_hz,
			"rate_hz": phaser.rate_hz,
			"feedback": phaser.feedback,
			"depth": phaser.depth,
		}

	if effect is AudioEffectDistortion:
		var dist: AudioEffectDistortion = effect
		return {
			"mode": int(dist.mode),
			"pre_gain": dist.pre_gain,
			"post_gain": dist.post_gain,
			"keep_hf_hz": dist.keep_hf_hz,
			"drive": dist.drive,
		}

	if effect is AudioEffectFilter:
		var filter: AudioEffectFilter = effect
		return {
			"cutoff_hz": filter.cutoff_hz,
			"resonance": filter.resonance,
			"gain": filter.gain,
			"db": int(filter.db),
		}

	if effect is AudioEffectAmplify:
		var amplify: AudioEffectAmplify = effect
		return {"volume_db": amplify.volume_db}

	return {}


func _make_effect(effect_type: String) -> AudioEffect:
	match effect_type:
		"reverb":
			return AudioEffectReverb.new()
		"chorus":
			return AudioEffectChorus.new()
		"delay":
			return AudioEffectDelay.new()
		"compressor":
			return AudioEffectCompressor.new()
		"limiter":
			return AudioEffectLimiter.new()
		"phaser":
			return AudioEffectPhaser.new()
		"distortion":
			return AudioEffectDistortion.new()
		"lowpass":
			return AudioEffectLowPassFilter.new()
		"highpass":
			return AudioEffectHighPassFilter.new()
		"bandpass":
			return AudioEffectBandPassFilter.new()
		"amplify":
			return AudioEffectAmplify.new()
		"eq":
			return AudioEffectEQ.new()
		_:
			return null


func _bus_state(index: int) -> Dictionary:
	return {
		"volume_db": AudioServer.get_bus_volume_db(index),
		"solo": AudioServer.is_bus_solo(index),
		"mute": AudioServer.is_bus_mute(index),
		"bypass_effects": AudioServer.is_bus_bypassing_effects(index),
		"send": String(AudioServer.get_bus_send(index)),
	}


func _scene_relative_path(root: Node, node: Node) -> String:
	if root == null or node == null:
		return ""
	if node == root:
		return "."
	return String(root.get_path_to(node))


func _is_audio_player(node: Node) -> bool:
	return (
		node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D
	)


func _describe_player(root: Node, node: Node) -> Dictionary:
	var info: Dictionary = {
		"name": String(node.name),
		"path": _scene_relative_path(root, node),
		"type": node.get_class(),
	}
	if node is AudioStreamPlayer:
		var p: AudioStreamPlayer = node
		info["stream"] = p.stream.resource_path if p.stream != null else ""
		info["bus"] = String(p.bus)
		info["volume_db"] = p.volume_db
		info["autoplay"] = p.autoplay
		info["playing"] = p.playing
	elif node is AudioStreamPlayer2D:
		var p2: AudioStreamPlayer2D = node
		info["stream"] = p2.stream.resource_path if p2.stream != null else ""
		info["bus"] = String(p2.bus)
		info["volume_db"] = p2.volume_db
		info["autoplay"] = p2.autoplay
		info["playing"] = p2.playing
		info["max_distance"] = p2.max_distance
		info["attenuation"] = p2.attenuation
	elif node is AudioStreamPlayer3D:
		var p3: AudioStreamPlayer3D = node
		info["stream"] = p3.stream.resource_path if p3.stream != null else ""
		info["bus"] = String(p3.bus)
		info["volume_db"] = p3.volume_db
		info["autoplay"] = p3.autoplay
		info["playing"] = p3.playing
		info["max_distance"] = p3.max_distance
		info["attenuation_model"] = int(p3.attenuation_model)
		info["unit_size"] = p3.unit_size
	return info


func _collect_players(root: Node, node: Node, out: Array) -> void:
	if node == null:
		return
	if _is_audio_player(node):
		out.append(_describe_player(root, node))
	for child: Node in node.get_children():
		_collect_players(root, child, out)


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


func _get_audio_bus_layout(_params: Dictionary) -> Dictionary:
	var buses: Array = []
	for i: int in range(AudioServer.bus_count):
		var effects: Array = []
		for j: int in range(AudioServer.get_bus_effect_count(i)):
			var effect: AudioEffect = AudioServer.get_bus_effect(i, j)
			if effect == null:
				continue
			effects.append(
				{
					"index": j,
					"class": effect.get_class(),
					"enabled": AudioServer.is_bus_effect_enabled(i, j),
					"params": _effect_params(effect),
				}
			)
		var bus: Dictionary = {"index": i, "name": String(AudioServer.get_bus_name(i))}
		bus.merge(_bus_state(i))
		bus["effects"] = effects
		buses.append(bus)

	return success({"bus_count": AudioServer.bus_count, "buses": buses})


func _add_audio_bus(params: Dictionary) -> Dictionary:
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var bus_name: String = name_res[0]

	if AudioServer.get_bus_index(bus_name) >= 0:
		return error(-32000, "Audio bus '%s' already exists" % bus_name)

	var at_position: int = optional_int(params, "at_position", -1)
	# Index 0 IS the Master bus: inserting there makes the new bus the master, demotes the real
	# Master to index 1, and set_bus_name() then silently refuses to rename index 0.
	if at_position == 0:
		return error(
			-32000, "at_position 0 is the Master bus — insert new buses at index 1 or higher"
		)
	var send: String = optional_string(params, "send", "Master")
	if AudioServer.get_bus_index(send) < 0:
		return error(-32000, "Send target bus '%s' does not exist" % send)

	AudioServer.add_bus(at_position)
	var index: int = at_position if at_position >= 0 else AudioServer.bus_count - 1
	index = clampi(index, 0, AudioServer.bus_count - 1)
	AudioServer.set_bus_name(index, bus_name)

	if params.has("volume_db") and params["volume_db"] != null:
		AudioServer.set_bus_volume_db(index, optional_float(params, "volume_db", 0.0))
	AudioServer.set_bus_send(index, send)
	if params.has("solo") and params["solo"] != null:
		AudioServer.set_bus_solo(index, optional_bool(params, "solo", false))
	if params.has("mute") and params["mute"] != null:
		AudioServer.set_bus_mute(index, optional_bool(params, "mute", false))

	return success(
		{
			"name": String(AudioServer.get_bus_name(index)),
			"index": index,
			"volume_db": AudioServer.get_bus_volume_db(index),
			"send": String(AudioServer.get_bus_send(index)),
			"bus_count": AudioServer.bus_count,
		}
	)


func _set_audio_bus(params: Dictionary) -> Dictionary:
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]
	var bus_name: String = name_res[0]

	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return error_not_found("Audio bus '%s'" % bus_name)

	var rename: String = optional_string(params, "rename", "")
	var wants_rename: bool = not rename.is_empty()
	if wants_rename and index == 0:
		return error(-32000, "Master bus cannot be renamed")

	var send: String = optional_string(params, "send", "")
	var wants_send: bool = not send.is_empty()
	if wants_send and AudioServer.get_bus_index(send) < 0:
		return error(-32000, "Send target bus '%s' does not exist" % send)

	var changed: Array[String] = []

	if params.has("volume_db") and params["volume_db"] != null:
		AudioServer.set_bus_volume_db(index, optional_float(params, "volume_db", 0.0))
		changed.append("volume_db")
	if params.has("solo") and params["solo"] != null:
		AudioServer.set_bus_solo(index, optional_bool(params, "solo", false))
		changed.append("solo")
	if params.has("mute") and params["mute"] != null:
		AudioServer.set_bus_mute(index, optional_bool(params, "mute", false))
		changed.append("mute")
	if params.has("bypass_effects") and params["bypass_effects"] != null:
		AudioServer.set_bus_bypass_effects(index, optional_bool(params, "bypass_effects", false))
		changed.append("bypass_effects")
	if wants_send:
		AudioServer.set_bus_send(index, send)
		changed.append("send")
	if wants_rename:
		AudioServer.set_bus_name(index, rename)
		changed.append("rename")

	var out: Dictionary = {
		"name": String(AudioServer.get_bus_name(index)),
		"index": index,
		"changed": changed,
		"count": changed.size(),
		"state": _bus_state(index),
	}
	return success(out)


func _add_audio_bus_effect(params: Dictionary) -> Dictionary:
	var bus_res: Array = require_string(params, "bus")
	if bus_res[1] != null:
		return bus_res[1]
	var bus_name: String = bus_res[0]

	var type_res: Array = require_string(params, "effect_type")
	if type_res[1] != null:
		return type_res[1]
	var effect_type: String = type_res[0]

	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return error_not_found("Audio bus '%s'" % bus_name)

	var effect: AudioEffect = _make_effect(effect_type)
	if effect == null:
		return error(
			-32602,
			(
				"Invalid effect_type '%s'. Valid: %s"
				% [effect_type, ", ".join(PackedStringArray(EFFECT_PARAM_TYPES.keys()))]
			)
		)

	var effect_params: Dictionary = {}
	if params.has("params") and typeof(params["params"]) == TYPE_DICTIONARY:
		effect_params = params["params"]

	var recognized: Dictionary = EFFECT_PARAM_TYPES[effect_type]
	var applied: Array[String] = []
	for key: String in recognized:
		if not effect_params.has(key) or effect_params[key] == null:
			continue
		var kind: int = int(recognized[key])
		match kind:
			TYPE_INT:
				var ivalue: int = optional_int(effect_params, key, 0)
				if key == "mode" and (ivalue < 0 or ivalue > 4):
					return error(-32602, "distortion mode must be 0-4, got %d" % ivalue)
				effect.set(key, ivalue)
			TYPE_BOOL:
				effect.set(key, optional_bool(effect_params, key, false))
			_:
				effect.set(key, optional_float(effect_params, key, 0.0))
		applied.append(key)

	var at_position: int = optional_int(params, "at_position", -1)
	AudioServer.add_bus_effect(bus_index, effect, at_position)
	var effect_index: int = (
		at_position if at_position >= 0 else AudioServer.get_bus_effect_count(bus_index) - 1
	)
	effect_index = clampi(effect_index, 0, maxi(AudioServer.get_bus_effect_count(bus_index) - 1, 0))

	return success(
		{
			"bus": bus_name,
			"bus_index": bus_index,
			"effect_class": effect.get_class(),
			"effect_index": effect_index,
			"applied": applied,
		}
	)


func _add_audio_player(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]
	var name_res: Array = require_string(params, "name")
	if name_res[1] != null:
		return name_res[1]

	var parent: Node = find_node_by_path(np[0])
	if parent == null:
		return error_not_found("Node at '%s'" % String(np[0]))

	var player_type: String = optional_string(params, "type", "AudioStreamPlayer")
	if not PLAYER_TYPES.has(player_type):
		return error(
			-32602,
			"Invalid type '%s'. Valid: %s" % [player_type, ", ".join(PLAYER_TYPES)]
		)

	var player: Node = null
	match player_type:
		"AudioStreamPlayer2D":
			player = AudioStreamPlayer2D.new()
		"AudioStreamPlayer3D":
			player = AudioStreamPlayer3D.new()
		_:
			player = AudioStreamPlayer.new()
	player.name = unique_child_name(parent, String(name_res[0]), player.get_class())

	# Fully configure BEFORE the undo action; on any failure the orphan is freed.
	var stream_path: String = optional_string(params, "stream", "")
	var stream: AudioStream = null
	if not stream_path.is_empty():
		if not ResourceLoader.exists(stream_path):
			player.free()
			return error_not_found("Audio stream '%s'" % stream_path)
		var res: Resource = load(stream_path)
		if res == null or not (res is AudioStream):
			player.free()
			return error(
				-32602,
				(
					"'%s' is not an AudioStream (got %s)"
					% [stream_path, res.get_class() if res != null else "nothing"]
				)
			)
		stream = res as AudioStream
		player.set("stream", stream)

	if params.has("volume_db") and params["volume_db"] != null:
		player.set("volume_db", optional_float(params, "volume_db", 0.0))
	var bus: String = optional_string(params, "bus", "")
	if not bus.is_empty():
		player.set("bus", StringName(bus))
	if params.has("autoplay") and params["autoplay"] != null:
		player.set("autoplay", optional_bool(params, "autoplay", false))

	# Type-specific params on the wrong player type are silently skipped.
	if params.has("max_distance") and params["max_distance"] != null:
		if player is AudioStreamPlayer2D or player is AudioStreamPlayer3D:
			player.set("max_distance", optional_float(params, "max_distance", 0.0))
	if params.has("attenuation") and params["attenuation"] != null:
		if player is AudioStreamPlayer2D:
			player.set("attenuation", optional_float(params, "attenuation", 1.0))
	if params.has("attenuation_model") and params["attenuation_model"] != null:
		if player is AudioStreamPlayer3D:
			var model: int = optional_int(params, "attenuation_model", 0)
			if model < 0 or model > 3:
				player.free()
				return error(-32602, "attenuation_model must be 0-3, got %d" % model)
			player.set("attenuation_model", model)
	if params.has("unit_size") and params["unit_size"] != null:
		if player is AudioStreamPlayer3D:
			player.set("unit_size", optional_float(params, "unit_size", 10.0))

	var ur_res: Array = _require_undo()
	if ur_res[1] != null:
		player.free()
		return ur_res[1]
	var ur: EditorUndoRedoManager = ur_res[0]

	ur.create_action("MCP: add_audio_player", UndoRedo.MERGE_DISABLE, parent)
	ur.add_do_method(parent, "add_child", player, true)
	ur.add_do_method(player, "set_owner", root)
	ur.add_do_reference(player)
	ur.add_undo_method(parent, "remove_child", player)
	ur.commit_action()

	return success(
		{
			"name": String(player.name),
			"type": player_type,
			"parent": String(np[0]),
			"stream": stream.resource_path if stream != null else "",
			"bus": String(player.get("bus")),
			"volume_db": float(player.get("volume_db")),
			"autoplay": bool(player.get("autoplay")),
		}
	)


func _get_audio_info(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var np: Array = require_string(params, "node_path")
	if np[1] != null:
		return np[1]

	var node: Node = find_node_by_path(np[0])
	if node == null:
		return error_not_found("Node at '%s'" % String(np[0]))

	var players: Array = []
	_collect_players(root, node, players)

	return success(
		{
			"node_path": String(np[0]),
			"audio_player_count": players.size(),
			"players": players,
		}
	)
