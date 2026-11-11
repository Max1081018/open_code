class_name Sfx
extends RefCounted
## Procedurally generated sound — no audio files to ship. Everything is built
## from noise and sine waves run through small filters, so it lands somewhere
## warmer and more natural than raw beeps: water has a splash transient and a
## wet tail, the reel has a body resonance, bells have overtones that decay at
## different rates, and the loops drift so they never sound like a stuck tape.
##
## (They are silent in the headless test container, which has no audio device,
## but play on a phone.)

const RATE := 22050


# --- tiny DSP toolkit ---------------------------------------------------------

## One-pole low-pass. `k` 0..1: smaller is duller.
class LP:
	var y := 0.0
	var k := 0.3
	func _init(cut := 0.3) -> void:
		k = cut
	func run(x: float) -> float:
		y += (x - y) * k
		return y


## One-pole high-pass (drops the rumble, keeps the hiss).
class HP:
	var y := 0.0
	var prev := 0.0
	var k := 0.6
	func _init(cut := 0.6) -> void:
		k = cut
	func run(x: float) -> float:
		y = k * (y + x - prev)
		prev = x
		return y


## A resonant body — struck, it rings at `f` Hz. `q` nearer 1 rings longer.
class Res:
	var a := 0.0
	var b := 0.0
	var c1 := 0.0
	var c2 := 0.0
	func _init(f: float, q := 0.995) -> void:
		c1 = 2.0 * cos(TAU * f / RATE) * q
		c2 = -q * q
	func run(x: float) -> float:
		var y := x + c1 * a + c2 * b
		b = a
		a = y
		return y


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


static func _loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := _from(samples)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w


## Attack, then exponential decay — how most real hits behave.
static func _hit(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / maxf(decay, 0.0001))


## Soft clip: keeps peaks from crackling and adds a little warmth.
static func _soft(x: float) -> float:
	return tanh(x * 1.3) * 0.92


# --- water --------------------------------------------------------------------

## A bobber or a fish hitting water: a bright "plip", then a wet, darkening
## tail as the water closes over it.
static func splash() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var bright := HP.new(0.55)
	var body := LP.new(0.45)
	var tail := LP.new(0.10)
	var ring := Res.new(760.0, 0.985)
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		var impact := bright.run(noise) * _hit(t, 0.004, 0.045)
		var wet := tail.run(body.run(noise)) * _hit(t, 0.03, 0.22) * 0.9
		var hollow := ring.run(impact * 0.5) * 0.25 * exp(-t * 9.0)
		s[i] = _soft((impact * 0.55 + wet * 0.8 + hollow) * 0.9)
	return _from(s)


## A fish nosing the bait: a droplet, its pitch falling fast — that quick fall
## is what makes the ear hear water.
static func bite() -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := LP.new(0.5)
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(1500.0, 420.0, clampf(t / 0.09, 0.0, 1.0))
		ph += TAU * f / RATE
		var drop := sin(ph) * _hit(t, 0.002, 0.05)
		var fizz := lp.run(randf() * 2.0 - 1.0) * _hit(t, 0.004, 0.09) * 0.25
		s[i] = _soft((drop * 0.8 + fizz) * 0.55)
	return _from(s)


## Line zipping off the rod on a cast: band-passed air, swelling then gone.
static func whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp := HP.new(0.35)
	var lp := LP.new(0.35)
	for i in n:
		var u := float(i) / n
		var air := lp.run(hp.run(randf() * 2.0 - 1.0))
		s[i] = _soft(air * pow(sin(PI * u), 1.6) * 0.75)
	return _from(s)


# --- gear ---------------------------------------------------------------------

## One tooth of the reel's ratchet: a tick with a little metal body.
static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.055)
	var s := PackedFloat32Array()
	s.resize(n)
	var body := Res.new(2300.0, 0.976)
	var low := Res.new(640.0, 0.986)
	for i in n:
		var t := float(i) / RATE
		var imp := (randf() * 2.0 - 1.0) * _hit(t, 0.0005, 0.004)
		s[i] = _soft((body.run(imp) * 0.5 + low.run(imp) * 0.35) * 0.5)
	return _from(s)


## Landed it: a warm bell phrase, each note ringing on under the next.
static func caught() -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		var f: float = notes[k]
		var start := int(RATE * 0.09 * k)
		for i in range(start, n):
			var t := float(i - start) / RATE
			var e := _hit(t, 0.006, 0.42)
			# a bell is the note plus quieter overtones that fade faster
			var v := sin(TAU * f * t) * e
			v += sin(TAU * f * 2.0 * t) * e * e * 0.3
			v += sin(TAU * f * 3.0 * t) * e * e * e * 0.12
			s[i] += v * 0.2
	for i in n:
		s[i] = _soft(s[i])
	return _from(s)


## The line gave out: a crack, then a twang falling away.
static func snap() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp := HP.new(0.5)
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(520.0, 110.0, clampf(t / 0.3, 0.0, 1.0))
		var twang := sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.01 * t) * 0.2
		var crack := hp.run(randf() * 2.0 - 1.0) * _hit(t, 0.001, 0.012) * 0.6
		s[i] = _soft((twang * _hit(t, 0.003, 0.16) + crack) * 0.55)
	return _from(s)


## A whack landing: a wooden thud with a wet edge.
static func bonk() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	var wood := Res.new(190.0, 0.9935)
	var knock := Res.new(430.0, 0.988)
	var lp := LP.new(0.25)
	for i in n:
		var t := float(i) / RATE
		var imp := (randf() * 2.0 - 1.0) * _hit(t, 0.001, 0.006)
		var wet := lp.run(randf() * 2.0 - 1.0) * _hit(t, 0.004, 0.05) * 0.35
		s[i] = _soft((wood.run(imp) * 0.55 + knock.run(imp) * 0.3 + wet) * 0.8)
	return _from(s)


## Taking a hit: a low, dull thump.
static func hurt() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := Res.new(105.0, 0.996)
	var lp := LP.new(0.12)
	for i in n:
		var t := float(i) / RATE
		var imp := (randf() * 2.0 - 1.0) * _hit(t, 0.002, 0.01)
		var air := lp.run(randf() * 2.0 - 1.0) * _hit(t, 0.01, 0.12) * 0.4
		s[i] = _soft((low.run(imp) * 0.8 + air) * 0.75)
	return _from(s)


## Paid: coins chinking, three bright strikes a moment apart. The inharmonic
## overtone is what makes it metal rather than a flute.
static func coins() -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var s := PackedFloat32Array()
	s.resize(n)
	for pr in [[0.0, 2093.0, 1.0], [0.055, 2637.0, 0.85], [0.12, 3136.0, 0.6]]:
		var start := int(RATE * float(pr[0]))
		var f: float = pr[1]
		var amp: float = pr[2]
		for i in range(start, n):
			var t := float(i - start) / RATE
			var e := _hit(t, 0.001, 0.13)
			var v := sin(TAU * f * t) * e + sin(TAU * f * 1.47 * t) * e * e * 0.35
			s[i] += v * 0.18 * amp
	for i in n:
		s[i] = _soft(s[i])
	return _from(s)


## Picking something up: a soft, friendly pop.
static func pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.14)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f: float = lerpf(430.0, 880.0, clampf(t / 0.07, 0.0, 1.0))
		ph += TAU * f / RATE
		s[i] = _soft(sin(ph) * _hit(t, 0.004, 0.045) * 0.5)
	return _from(s)


# --- footsteps ----------------------------------------------------------------

static func step_soft() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := LP.new(0.09)
	var grit := HP.new(0.75)
	for i in n:
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		var pad := lp.run(noise) * _hit(t, 0.008, 0.05)
		var sand := grit.run(noise) * _hit(t, 0.004, 0.03) * 0.22
		s[i] = _soft((pad * 1.4 + sand) * 0.6)
	return _from(s)


static func step_wood() -> AudioStreamWAV:
	var n := int(RATE * 0.14)
	var s := PackedFloat32Array()
	s.resize(n)
	var plank := Res.new(260.0, 0.991)
	var hollow := Res.new(520.0, 0.985)
	for i in n:
		var t := float(i) / RATE
		var imp := (randf() * 2.0 - 1.0) * _hit(t, 0.001, 0.005)
		s[i] = _soft((plank.run(imp) * 0.6 + hollow.run(imp) * 0.3) * 0.55)
	return _from(s)


# --- wildlife and ambience ----------------------------------------------------

## A gull's cry: two falling calls with a reedy edge and a little vibrato. The
## odd harmonics are what make it nasal rather than flute-like.
static func gull() -> AudioStreamWAV:
	var n := int(RATE * 0.72)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var lp := LP.new(0.45)
	for i in n:
		var t := float(i) / RATE
		var u := fmod(t, 0.36) / 0.33
		if u > 1.0:
			continue
		var f: float = lerpf(1750.0, 820.0, pow(u, 0.7)) * (1.0 + sin(t * 46.0) * 0.035)
		ph += TAU * f / RATE
		var tone := sin(ph) + 0.5 * sin(ph * 2.0) + 0.28 * sin(ph * 3.0) + 0.12 * sin(ph * 5.0)
		var breath := lp.run(randf() * 2.0 - 1.0) * 0.12
		s[i] = _soft((tone * 0.25 + breath) * sin(PI * clampf(u * 1.05, 0.0, 1.0)) * 0.75)
	return _from(s)


## Shore wash that loops: a low rumble under a bright wash, with two swells at
## different rates so the crests never land in the same place twice.
static func surf_loop() -> AudioStreamWAV:
	var n := RATE * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var deep := LP.new(0.012)
	var mid := LP.new(0.05)
	var foam := HP.new(0.35)
	var foam_lp := LP.new(0.25)
	for i in n:
		var u := float(i) / n
		var swell_a := 0.5 - 0.5 * cos(TAU * 2.0 * u)
		var swell_b := 0.5 - 0.5 * cos(TAU * 3.0 * u + 1.1)
		var swell: float = pow(swell_a * 0.65 + swell_b * 0.35, 1.5)
		var noise := randf() * 2.0 - 1.0
		var low := deep.run(noise) * 2.2
		var body := mid.run(noise) * (0.5 + swell)
		var hiss := foam_lp.run(foam.run(noise)) * swell * swell * 0.5
		s[i] = _soft((low * 0.5 + body * 0.6 + hiss * 0.5) * 0.5)
	return _loop(s)


## Wind through the palms: a soft hiss that breathes in and out.
static func wind_loop() -> AudioStreamWAV:
	var n := RATE * 7
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := LP.new(0.06)
	var lp2 := LP.new(0.22)
	var hp := HP.new(0.25)
	for i in n:
		var u := float(i) / n
		var gust: float = 0.35 + 0.65 * pow(0.5 - 0.5 * cos(TAU * u), 1.3) * (0.7 + 0.3 * sin(TAU * 3.0 * u))
		var noise := randf() * 2.0 - 1.0
		var air := lp2.run(hp.run(noise)) * 0.45 + lp.run(noise) * 0.9
		s[i] = _soft(air * gust * 0.4)
	return _loop(s)


## Rain on the water and the boards: a steady hiss with fatter drops on top.
static func rain_loop() -> AudioStreamWAV:
	var n := RATE * 6
	var s := PackedFloat32Array()
	s.resize(n)
	var hiss_hp := HP.new(0.45)
	var hiss_lp := LP.new(0.55)
	var drop_lp := LP.new(0.4)
	for i in n:
		var u := float(i) / n
		var noise := randf() * 2.0 - 1.0
		var hiss := hiss_lp.run(hiss_hp.run(noise)) * (0.8 + 0.2 * sin(TAU * 2.0 * u))
		var drop := 1.0 if randf() < 0.0016 else 0.0
		var patter := drop_lp.run(drop * (randf() * 2.0 - 1.0) * 6.0)
		s[i] = _soft((hiss * 0.5 + patter * 0.5) * 0.42)
	return _loop(s)
