class_name Sfx
extends RefCounted
## Procedurally generated sound effects — no audio files to ship. Each function
## returns an AudioStreamWAV built from raw 16-bit samples. (They are silent in
## this headless container because it has no audio device, but play on a phone.)

const RATE := 22050


static func _from(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _env(i: int, n: int, attack := 0.02) -> float:
	# Simple attack/decay envelope, 0..1.
	var a := int(n * attack)
	if i < a:
		return float(i) / maxi(a, 1)
	return 1.0 - float(i - a) / maxi(n - a, 1)


static func whoosh() -> AudioStreamWAV:
	# Filtered noise that rises then falls — the rod casting out.
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var noise := randf() * 2.0 - 1.0
		prev = lerpf(prev, noise, 0.25)  # cheap low-pass
		var swell: float = sin(PI * float(i) / n)
		s[i] = prev * swell * 0.5
	return _from(s)


static func splash() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var noise := randf() * 2.0 - 1.0
		prev = lerpf(prev, noise, 0.5)
		s[i] = prev * _env(i, n, 0.01) * 0.6
	return _from(s)


static func bite() -> AudioStreamWAV:
	# Two quick bright blips.
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gate := 1.0 if (fmod(t, 0.11) < 0.055) else 0.0
		s[i] = sin(TAU * 950.0 * t) * gate * _env(i, n, 0.01) * 0.4
	return _from(s)


static func click() -> AudioStreamWAV:
	# Tiny ratchet tick played repeatedly while reeling.
	var n := int(RATE * 0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = (randf() * 2.0 - 1.0) * (1.0 - float(i) / n) * 0.35
	return _from(s)


static func caught() -> AudioStreamWAV:
	# Happy little arpeggio.
	var freqs := [523.25, 659.25, 783.99, 1046.5]
	var seg := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(seg * freqs.size())
	for k in freqs.size():
		for i in seg:
			var t := float(i) / RATE
			s[k * seg + i] = sin(TAU * float(freqs[k]) * t) * _env(i, seg, 0.02) * 0.4
	return _from(s)


static func snap() -> AudioStreamWAV:
	# Descending twang — the line gave out.
	var n := int(RATE * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(420.0, 120.0, float(i) / n)
		# Mild sawtooth for a sproing.
		var saw := fmod(f * t, 1.0) * 2.0 - 1.0
		s[i] = saw * _env(i, n, 0.005) * 0.4
	return _from(s)


static func bonk() -> AudioStreamWAV:
	# Wooden thump with a little squelch: the whack landing.
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(190.0, 70.0, float(i) / n)
		prev = lerpf(prev, randf() * 2.0 - 1.0, 0.35)
		s[i] = (sin(TAU * f * t) * 0.8 + prev * 0.35) * pow(1.0 - float(i) / n, 2.0) * 0.7
	return _from(s)


static func hurt() -> AudioStreamWAV:
	# Low "oof" thud when something hits you.
	var n := int(RATE * 0.26)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(150.0, 85.0, float(i) / n)
		var tri := absf(fmod(f * t, 1.0) * 4.0 - 2.0) - 1.0
		s[i] = tri * _env(i, n, 0.03) * 0.55
	return _from(s)


static func coins() -> AudioStreamWAV:
	# Bright double "ching" for a sale.
	var n := int(RATE * 0.38)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var a := sin(TAU * 1567.98 * t) * exp(-t * 14.0)
		var b := sin(TAU * 2093.0 * maxf(t - 0.09, 0.0)) * exp(-maxf(t - 0.09, 0.0) * 12.0) if t > 0.09 else 0.0
		s[i] = (a + b) * 0.32
	return _from(s)


static func step_soft() -> AudioStreamWAV:
	# Footstep on sand or grass: a short muffled scuff.
	var n := int(RATE * 0.09)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		prev = lerpf(prev, randf() * 2.0 - 1.0, 0.12)
		s[i] = prev * _env(i, n, 0.15) * 0.55
	return _from(s)


static func step_wood() -> AudioStreamWAV:
	# Footstep on the jetty boards: a hollow knock.
	var n := int(RATE * 0.11)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 210.0 * t) + 0.4 * sin(TAU * 470.0 * t)) * exp(-t * 38.0) * 0.45
	return _from(s)


static func gull() -> AudioStreamWAV:
	# A seagull's "kyow": a falling, nasal squeal, twice.
	var n := int(RATE * 0.62)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var local := fmod(t, 0.31)
		var f: float = lerpf(1650.0, 900.0, local / 0.31)
		ph += TAU * f / RATE
		var gate := sin(PI * clampf(local / 0.27, 0.0, 1.0))
		var tone := sin(ph) + 0.45 * sin(ph * 2.0) + 0.2 * sin(ph * 3.0)
		s[i] = tone * gate * 0.18
	return _from(s)


static func surf_loop() -> AudioStreamWAV:
	# 6 s of shore wash that loops: low-passed noise with two slow swells.
	var n := RATE * 6
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var u := float(i) / n
		var swell := 0.35 + 0.65 * pow(0.5 - 0.5 * cos(TAU * 2.0 * u), 1.6)
		lp = lerpf(lp, randf() * 2.0 - 1.0, 0.08 + 0.10 * swell)
		lp2 = lerpf(lp2, lp, 0.5)
		s[i] = lp2 * swell * 0.55
	var w := _from(s)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
