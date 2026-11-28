extends SceneTree
## Rewrites animation libraries with plain (uncompressed) keyframes.
##
## Godot 4.4 prints `Condition "!compression.enabled" is true` once for every
## compressed Animation it loads (the loader reads `_compression` before it is
## restored). The shared humanoid library and the heroine's own were packed
## compressed, so every launch logged ~80 errors. The source clips are not
## shipped, so each track is resampled here through the engine's own
## interpolation at 60 fps, thinned with optimize(), checked against the
## original, and saved over it.
##   godot --headless --path . -s res://tools/decompress_anims.gd -- <lib.res>...

const FPS := 60.0
const MAX_ANGLE := 0.02    ## radians: the largest rotation error allowed
const MAX_MOVE := 0.004    ## metres (or scale units)


func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = ["res://assets/models/heroes/anim/humanoid.res", "res://assets/models/heroes/anim/heroine.res"]
	for path in paths:
		_convert(path)
	quit()


func _convert(path: String) -> void:
	var lib: AnimationLibrary = load(path)
	var out := AnimationLibrary.new()
	var worst_angle := 0.0
	var worst_move := 0.0
	for name in lib.get_animation_list():
		var src: Animation = lib.get_animation(name)
		var dst := _resample(src)
		var err := _compare(src, dst)
		worst_angle = maxf(worst_angle, err[0])   # share off
		worst_move = maxf(worst_move, err[2] - err[1])   # extra jump
		if err[0] > 0.02 or err[2] > err[1] + 0.01:
			print("CHECK %s %s off=%.4f jump src=%.3f copy=%.3f" % [path, name, err[0], err[1], err[2]])
		if err[0] > 0.08 or err[2] > err[1] + 0.01:
			push_error("%s %s: the copy does not match its source" % [path, name])
			return
		out.add_animation(name, dst)
	if OS.get_environment("DRY") != "":
		print("DRY %s worst_share_off=%.4f worst_extra_jump=%.4f" % [path, worst_angle, worst_move])
		return
	var result := ResourceSaver.save(out, path, ResourceSaver.FLAG_COMPRESS)
	print("DECOMPRESSED %s clips=%d worst_share_off=%.4f worst_extra_jump=%.4f save=%d" % [path, out.get_animation_list().size(), worst_angle, worst_move, result])


func _resample(src: Animation) -> Animation:
	var a := Animation.new()
	a.resource_name = src.resource_name
	a.length = src.length
	a.loop_mode = src.loop_mode
	a.step = src.step
	var steps := maxi(1, ceili(src.length * FPS))
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		var i := a.add_track(type)
		a.track_set_path(i, src.track_get_path(t))
		a.track_set_enabled(i, src.track_is_enabled(t))
		a.track_set_imported(i, src.track_is_imported(t))
		a.track_set_interpolation_type(i, src.track_get_interpolation_type(t))
		a.track_set_interpolation_loop_wrap(i, src.track_get_interpolation_loop_wrap(t))
		# Copy the keys themselves (readable by index even from compressed
		# tracks): exact times and values, so hard cuts in a clip survive.
		# (Resampling at a fixed rate smoothed instant jumps; see the history.)
		var n := src.track_get_key_count(t)
		for k in n:
			var time := src.track_get_key_time(t, k)
			var value = src.track_get_key_value(t, k)
			match type:
				Animation.TYPE_POSITION_3D:
					a.position_track_insert_key(i, time, value)
				Animation.TYPE_ROTATION_3D:
					a.rotation_track_insert_key(i, time, value)
				Animation.TYPE_SCALE_3D:
					a.scale_track_insert_key(i, time, value)
				Animation.TYPE_BLEND_SHAPE:
					a.blend_shape_track_insert_key(i, time, value)
				_:
					a.track_insert_key(i, time, value, src.track_get_key_transition(t, k))
		if n == 0 and type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
			# No readable keys: fall back to sampling at FPS.
			for k in steps + 1:
				var time := minf(k / FPS, src.length)
				match type:
					Animation.TYPE_POSITION_3D:
						a.position_track_insert_key(i, time, src.position_track_interpolate(t, time))
					Animation.TYPE_ROTATION_3D:
						a.rotation_track_insert_key(i, time, src.rotation_track_interpolate(t, time))
					Animation.TYPE_SCALE_3D:
						a.scale_track_insert_key(i, time, src.scale_track_interpolate(t, time))
					Animation.TYPE_BLEND_SHAPE:
						a.blend_shape_track_insert_key(i, time, src.blend_shape_track_interpolate(t, time))
	return a


## Checks a copy against its source, sampled at 120 fps: [share of samples
## (all tracks) off by more than MAX_ANGLE / MAX_MOVE, the source's largest
## frame-to-frame jump, the copy's]. Compressed clips can hold a bone still
## and then snap it at a page boundary (a finger by 0.9 rad, the hips by
## 0.5 m in one frame); the copy moves smoothly there instead, so a copy is
## good when it agrees almost everywhere and never jumps more than its source.
func _compare(a: Animation, b: Animation) -> Array:
	var off := 0
	var total := 0
	var jump_a := 0.0
	var jump_b := 0.0
	var steps := maxi(1, ceili(a.length * 120.0))
	for t in a.get_track_count():
		var type := a.track_get_type(t)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var pa = null
		var pb = null
		for k in steps + 1:
			var time := minf(k / 120.0, a.length)
			var va
			var vb
			var err := 0.0
			if type == Animation.TYPE_ROTATION_3D:
				va = a.rotation_track_interpolate(t, time).normalized()
				vb = b.rotation_track_interpolate(t, time).normalized()
				err = (va as Quaternion).angle_to(vb) / MAX_ANGLE
				if pa != null:
					jump_a = maxf(jump_a, (va as Quaternion).angle_to(pa))
					jump_b = maxf(jump_b, (vb as Quaternion).angle_to(pb))
			else:
				va = a.position_track_interpolate(t, time)
				vb = b.position_track_interpolate(t, time)
				err = (va as Vector3).distance_to(vb) / MAX_MOVE
			pa = va
			pb = vb
			total += 1
			if err > 1.0:
				off += 1
	return [float(off) / maxf(1.0, total), jump_a, jump_b]
