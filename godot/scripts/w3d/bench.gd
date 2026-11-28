class_name Bench
extends Node
## A repeatable performance probe. Attached by a scene when it is started
## with --bench[=frames]; it waits for the scene to settle, samples every
## frame, prints one machine-readable line and quits:
##   BENCH {"scene":..., "avg_ms":..., "p99_ms":..., "low1_fps":..., ...}
## Wall-clock frame times on this container's software renderer say little
## about a phone's GPU; the CPU-side numbers (script, physics), draw calls,
## primitives, memory and load/hitch times are what carry over.
##   godot --path . res://scenes/main3d.tscn -- --start=jungle --bench=300 --tag=jungle

var label := ""
var frames := 300
var settle := 90
var ready_ms := 0.0   ## how long the scene's _ready took (set by the scene)
var warm_ms := 0.0    ## how long the shader/asset warm-up ran
var _n := 0
var _last := 0
var _times: Array[float] = []
var _hitch := 0.0      ## the worst frame while settling (shader compiles, streaming)
var _proc: Array[float] = []
var _phys: Array[float] = []
var _draws: Array[float] = []
var _prims: Array[float] = []
var _objs: Array[float] = []


static func attach(parent: Node, tag: String, ready_time_ms := 0.0) -> Bench:
	var frames_arg := 0
	var settle_arg := 90
	var name := tag
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench"):
			frames_arg = int(a.get_slice("=", 1)) if a.contains("=") else 300
		elif a.begins_with("--tag="):
			name = a.substr(6)
		elif a.begins_with("--settle="):
			settle_arg = int(a.substr(9))
	if frames_arg <= 0:
		return null
	var b := Bench.new()
	b.label = name
	b.frames = frames_arg
	b.settle = settle_arg
	b.ready_ms = ready_time_ms
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(b)
	return b


var _uncapped := false


func _process(_delta: float) -> void:
	if not _uncapped:
		# Without a renderer the frame cap is all there is to measure: lift it
		# so frame time is the game's own CPU work.
		_uncapped = true
		if DisplayServer.get_name() == "headless":
			Engine.max_fps = 0
	var now := Time.get_ticks_usec()
	if WarmUp.running:
		# The warm-up's own frames (behind its veil) are load time, not play.
		warm_ms += (now - _last) / 1000.0 if _last != 0 else 0.0
		_last = now
		return
	if _last != 0:
		var ms := (now - _last) / 1000.0
		if _n < settle:
			_hitch = maxf(_hitch, ms)
		else:
			_times.append(ms)
			_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_last = now
	_n += 1
	if _n >= settle + frames:
		_report()


func _report() -> void:
	set_process(false)
	var sorted := _times.duplicate()
	sorted.sort()
	var avg := _mean(_times)
	var p99: float = sorted[int(sorted.size() * 0.99) - 1] if sorted.size() > 1 else avg
	# 1% low: the mean of the slowest 1% of frames, as frames per second.
	var worst := sorted.slice(int(sorted.size() * 0.99))
	var low1 := 1000.0 / maxf(_mean(worst), 0.001)
	var out := {
		"scene": label,
		"frames": _times.size(),
		"avg_ms": snappedf(avg, 0.01),
		"avg_fps": snappedf(1000.0 / maxf(avg, 0.001), 0.1),
		"p99_ms": snappedf(p99, 0.01),
		"low1_fps": snappedf(low1, 0.1),
		"settle_hitch_ms": snappedf(_hitch, 0.1),
		"ready_ms": snappedf(ready_ms, 0.1),
		"warm_ms": snappedf(warm_ms, 0.1),
		"script_ms": snappedf(_mean(_proc), 0.01),
		"physics_ms": snappedf(_mean(_phys), 0.01),
		"draw_calls": int(_mean(_draws)),
		"primitives": int(_mean(_prims)),
		"objects": int(_mean(_objs)),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects_total": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"slowest": _slowest(),
	}
	print("BENCH ", JSON.stringify(out))
	get_tree().quit()


## The five slowest sampled frames: [frame index, ms].
func _slowest() -> Array:
	var idx := range(_times.size())
	idx.sort_custom(func(a, b): return _times[a] > _times[b])
	return idx.slice(0, 5).map(func(i): return [i + settle, snappedf(_times[i], 0.1)])


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()
