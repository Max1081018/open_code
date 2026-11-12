extends SceneTree
## Dev tool: writes every procedural sound out as a .wav so you can listen to
## them, or measure them, without launching the game. Run it headlessly:
##   godot --headless --path fishing --script res://tools/dump_sfx.gd -- /tmp/sfx
## Prints peak, RMS and the loop seam (how far the last sample is from the
## first) for each one: a big seam on a looping sound means an audible click.

const Sfx := preload("res://sfx.gd")

const ONESHOTS := ["splash", "bite", "whoosh", "click", "caught", "snap", "bonk",
	"hurt", "coins", "pickup", "step_soft", "step_wood", "gull", "gunshot", "reload"]
const LOOPS := ["surf_loop", "wind_loop", "rain_loop", "engine_loop", "music_loop"]


func _initialize() -> void:
	var out := "/tmp/sfx"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var maker: Object = Sfx.new()
	for name in ONESHOTS + LOOPS:
		if not maker.has_method(name):
			print("%-12s MISSING" % name)
			continue
		var w: AudioStreamWAV = maker.call(name)
		var n := w.data.size() / 2
		var peak := 0.0
		var sum := 0.0
		var first := 0.0
		var last := 0.0
		for i in n:
			var v := float(w.data.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(v))
			sum += v * v
			if i == 0:
				first = v
			if i == n - 1:
				last = v
		var rms := sqrt(sum / maxf(float(n), 1.0))
		var seam: String = "  seam=%.3f" % absf(last - first) if name in LOOPS else ""
		print("%-12s %6.2fs  peak=%.3f  rms=%.3f%s" % [name, float(n) / float(w.mix_rate), peak, rms, seam])
		w.save_to_wav("%s/%s.wav" % [out, name])
	quit()
