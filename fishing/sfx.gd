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
