class_name Story
extends RefCounted
## The spoken script: assets/story/dialogue.json, the same file the voice
## baker reads (tools/bake_voices.py), so subtitles and audio cannot drift.

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open("res://assets/story/dialogue.json", FileAccess.READ)
		if file:
			_data = JSON.parse_string(file.get_as_text())
	return _data


static func line(id: String) -> Dictionary:
	return data().get("lines", {}).get(id, {})


static func speaker(id: String) -> Dictionary:
	return data().get("speakers", {}).get(id, {})


## The voiced recording of a line, or null if it has not been baked.
static func audio(id: String) -> AudioStream:
	var path := "res://assets/voice/%s.ogg" % id
	return load(path) if ResourceLoader.exists(path) else null


## A speaker's face for the dialogue box.
static func portrait(speaker_id: String) -> Texture2D:
	var path := "res://assets/characters/%s/parts/head.png" % speaker_id
	return load(path) if ResourceLoader.exists(path) else null
