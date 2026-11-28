class_name WarmUp
extends Node3D
## A short, controlled warm-up behind a veil when the world opens, so play
## does not hitch the first time something new appears:
##   - every scenery kind's parts are baked (FoliageLib: up to ~150 ms each on
##     a phone, otherwise paid while walking into a new biome),
##   - the starting island's foes (and its guardian) are loaded and drawn
##     once (their files stay cached in CharacterKit),
##   - each kind of spell effect is fired once,
## and everything is drawn a frame or two in front of the camera, so the
## GPU driver compiles those shaders now rather than mid-fight. Only what
## this island needs: other foes warm up the first time they appear.
## Work is time-sliced (a few ms a frame) and the veil shows real progress.

signal finished

## True while a warm-up runs (the bench ignores those frames).
static var running := false

const SLICE_MS := 10.0

var game: Node
var _jobs: Array[Callable] = []
var _total := 0
var _stage: Node3D
var _shown: Array[Node] = []   ## drawn this frame, freed two frames later
var _ttl := {}
var _veil: CanvasLayer
var _label: Label
var _bar: ColorRect
var _done := false


static func wanted(args: Dictionary) -> bool:
	return DisplayServer.get_name() != "headless" and not args.has("shot") and not args.has("nowarm")


func start(g: Node) -> void:
	game = g
	running = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cam: Camera3D = get_viewport().get_camera_3d()
	_stage = Node3D.new()
	_stage.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_stage)
	if cam:
		_stage.global_transform = cam.global_transform.translated_local(Vector3(0, 0, -4.0))
	_build_veil()
	for kind in FoliageLib.SIZES.keys():
		if ResourceLoader.exists(FoliageLib.DIR + String(kind).trim_suffix("_Basalt") + ".gltf"):
			_jobs.append(_foliage.bind(String(kind)))
	for kind in FoliageLib.EXT.keys():
		_jobs.append(_foliage.bind("X:" + String(kind)))
	for model in _island_models():
		_jobs.append(_character.bind(model))
	_jobs.append(_effects)
	# Last: the land beyond the nearest chunks finishes streaming in.
	_jobs.append(_world_streamed)
	_total = _jobs.size()
	get_tree().paused = true
	# The land keeps streaming in behind the veil.
	_world_mode = game.world.process_mode
	game.world.process_mode = Node.PROCESS_MODE_ALWAYS


## The foes of the starting island's biomes and its guardian (their models).
func _island_models() -> Array:
	var models := {}
	var biomes := {}
	var p: Vector3 = game.player.global_position
	for dx in [-60.0, 0.0, 60.0]:
		for dz in [-60.0, 0.0, 60.0]:
			biomes[game.world.biome_at(p + Vector3(dx, 0, dz))] = true
	for b in biomes:
		for kind in Play3D.ZONE_FOES.get(b, ["zombie"]):
			var spec: Dictionary = Enemy3D.SPECS.get(kind, {})
			if spec.has("model"):
				models[String(spec.model)] = true
	var site: Dictionary = IslandBosses.ARENAS.get(String(game.start_island), {})
	var boss: Dictionary = Enemy3D.BOSS_SPECS.get(String(site.get("kind", "")), {})
	if boss.has("model"):
		models[String(boss.model)] = true
	return models.keys()


func _process(_delta: float) -> void:
	# Free what was shown two frames ago (it has been drawn by now).
	for n in _shown.duplicate():
		_ttl[n] = int(_ttl.get(n, 2)) - 1
		if int(_ttl[n]) <= 0:
			_shown.erase(n)
			_ttl.erase(n)
			if is_instance_valid(n):
				n.queue_free()
	if _done:
		return
	var t0 := Time.get_ticks_usec()
	while not _jobs.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < SLICE_MS:
		var job: Callable = _jobs.pop_front()
		if job.call() == false:
			# Not finished (waiting on threads): try again next frame.
			_jobs.push_front(job)
			break
	var frac := 1.0 - float(_jobs.size()) / maxf(_total, 1.0)
	_label.text = "Preparing the world…  %d%%" % int(frac * 100.0)
	_bar.size.x = 420.0 * frac
	if _jobs.is_empty() and _shown.is_empty():
		_finish()


func _show(n: Node3D, at: Vector3) -> void:
	_stage.add_child(n)
	n.position = at
	_shown.append(n)
	_ttl[n] = 2


func _foliage(kind: String) -> void:
	var parts := FoliageLib.parts(kind)
	var i := 0
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var size := maxf((part[0] as Mesh).get_aabb().get_longest_axis_size(), 0.01)
		_show(mi, Vector3((i % 5 - 2) * 0.5, 0, 0))
		mi.scale = Vector3.ONE * (0.4 / size)
		i += 1


func _character(model: String) -> void:
	var m := CharacterKit.build(model)
	_show(m, Vector3(0, -0.8, 0))
	m.scale = Vector3.ONE * 0.4


var _stream_wait := 0.0
var _world_mode := Node.PROCESS_MODE_INHERIT


func _world_streamed() -> bool:
	# The world streams by itself (its _process runs while paused for this).
	_stream_wait += get_process_delta_time()
	return not game.world.busy() or _stream_wait > 20.0


func _effects() -> void:
	var host := Node3D.new()
	_show(host, Vector3.ZERO)
	var at := _stage.global_position
	Arcana.sparks(host, at, Arcana.VIOLET, 6)
	Arcana.flash(host, at, Arcana.VIOLET, 1.0, 2.0, 0.2)
	Arcana.circle(host, at, 0.5, Arcana.VIOLET, 0.3)
	Arcana.pillar(host, at, 0.3, 1.0, Arcana.VIOLET, 0.3)
	_ttl[host] = 4


func _build_veil() -> void:
	_veil = CanvasLayer.new()
	_veil.layer = 120
	_veil.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_veil)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.position = Vector2(-210, -30)
	_veil.add_child(box)
	_label = UiKit.label("Preparing the world…", 26, UiKit.PALE, "italic")
	box.add_child(_label)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.custom_minimum_size = Vector2(420, 3)
	box.add_child(track)
	_bar = ColorRect.new()
	_bar.color = Color(0.96, 0.84, 0.56)
	_bar.size = Vector2(0, 3)
	track.add_child(_bar)


func _finish() -> void:
	_done = true
	running = false
	get_tree().paused = false
	game.world.process_mode = _world_mode
	var t := create_tween()
	t.tween_property(_veil.get_child(0), "modulate:a", 0.0, 0.35)
	t.parallel().tween_property(_label, "modulate:a", 0.0, 0.25)
	t.tween_callback(func():
		finished.emit()
		queue_free())
