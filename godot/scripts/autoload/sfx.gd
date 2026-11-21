extends Node
## Sound effects and music.
##
## Effects play through a fixed pool of players so a busy fight cannot
## allocate nodes every frame; music crossfades between two players.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const POOL_SIZE := 12

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current := ""
var _last_played := {}  ## name -> msec, to stop machine-gun repeats


func _ready() -> void:
	_ensure_buses()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_load_dir(SFX_DIR)


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _make_music_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "Music"
	player.volume_db = -80.0
	add_child(player)
	return player


func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		# In an exported build the originals are gone and only the
		# .import/.remap entries are listed; strip those to find the name.
		var source := file.trim_suffix(".import").trim_suffix(".remap")
		if not (source.ends_with(".wav") or source.ends_with(".ogg") or source.ends_with(".mp3")):
			continue
		var name := source.get_basename()
		if not _streams.has(name) and ResourceLoader.exists(path + source):
			_streams[name] = load(path + source)


func has(name: String) -> bool:
	return _streams.has(name)


## Play an effect. `jitter` varies pitch so repeats do not sound robotic.
func play(name: String, volume_db := 0.0, jitter := 0.08, pitch := 1.0) -> void:
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_played.get(name, -1000) < 40:
		return
	_last_played[name] = now

	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch + randf_range(-jitter, jitter)
	player.play()


func play_music(track: String, fade := 1.6) -> void:
	if track == _music_current:
		return
	_music_current = track
	var path := MUSIC_DIR + track + ".ogg"
	if not ResourceLoader.exists(path):
		path = MUSIC_DIR + track + ".mp3"
	if not ResourceLoader.exists(path):
		return

	var incoming := _music_b if _music_a.playing else _music_a
	var outgoing := _music_a if incoming == _music_b else _music_b
	var stream: AudioStream = load(path)
	if "loop" in stream:
		stream.loop = true  # every track here is a seamless loop
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()

	var tween := create_tween().set_parallel()
	tween.tween_property(incoming, "volume_db", 0.0, fade)
	tween.tween_property(outgoing, "volume_db", -60.0, fade)
	tween.chain().tween_callback(outgoing.stop)


func stop_music(fade := 1.0) -> void:
	_music_current = ""
	var tween := create_tween().set_parallel()
	for player in [_music_a, _music_b]:
		tween.tween_property(player, "volume_db", -60.0, fade)


var _duck_tween: Tween


## Music dips while someone speaks, so the voice sits on top.
func duck_music(on: bool) -> void:
	var music := AudioServer.get_bus_index("Music")
	if music < 0:
		return
	var target := linear_to_db(maxf(Settings.music_volume, 0.0001)) + (-9.0 if on else 0.0)
	if _duck_tween:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(v): AudioServer.set_bus_volume_db(music, v),
		AudioServer.get_bus_volume_db(music), target, 0.4)
