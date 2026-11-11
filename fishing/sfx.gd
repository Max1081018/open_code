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


static func _from(samples: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Crossfades the end of a loop back over its start and trims it, so the join
## is continuous. Without this, a filter that started from silence but is still
## ringing at the end leaves an audible tick every time round.
static func _seam(s: PackedFloat32Array, fade := 1600) -> PackedFloat32Array:
	var n := s.size()
	var f: int = mini(fade, n / 4)
	if f < 8:
		return s
	var out := PackedFloat32Array()
	out.resize(n - f)
	for i in n - f:
		out[i] = s[i]
	for i in f:
		var a := float(i) / float(f)
		out[i] = s[i] * a + s[n - f + i] * (1.0 - a)
	return out


static func _loop(samples: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var w := _from(samples, rate)
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


## Sets a buffer's loudest sample to `peak` and then runs the lot through the
## soft clip. Doing it in that order matters for the hits, which are built by
## whacking a resonant body with a burst of noise: how loud that burst comes out
## depends on the dice, so left to itself the same sound arrives anywhere over a
## 3:1 range from one launch to the next, and the loud draws get squashed flat
## against the clipper. Setting the level first means every launch sounds the
## same, and the clip is left doing what it is good at — adding a little warmth —
## rather than catching overshoots.
static func _voice(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m < 0.000001:
		return s
	var g := peak / m
	for i in s.size():
		s[i] = _soft(s[i] * g)
	return s


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

## One tooth of the reel's ratchet: a soft wooden tick. This one plays over and
## over while you reel, so it is deliberately blunt — the strike is rolled off
## before it reaches the body, the bright resonance sits low and dies inside a
## few milliseconds, and the whole thing is left well short of the clipper.
static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.075)
	var s := PackedFloat32Array()
	s.resize(n)
	var body := Res.new(1150.0, 0.962)
	var low := Res.new(540.0, 0.983)
	var mallet := LP.new(0.28)
	for i in n:
		var t := float(i) / RATE
		# a felt-tipped strike: ramped over ~2 ms and low-passed, so there is no
		# instant edge for the ear to catch
		var imp := mallet.run((randf() * 2.0 - 1.0) * _hit(t, 0.0018, 0.0065))
		# weighted towards the low body, so it reads as wood rather than metal
		var tick := body.run(imp) * 0.35 + low.run(imp) * 0.65
		s[i] = tick * exp(-t * 32.0)
	return _from(_voice(s, 0.70))


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


## A whack landing: a wooden thud with a wet edge. Rounded rather than sharp —
## the strike is softened and the wood is given longer to ring out, so it reads
## as a thump against a plank instead of a crack.
static func bonk() -> AudioStreamWAV:
	var n := int(RATE * 0.20)
	var s := PackedFloat32Array()
	s.resize(n)
	var wood := Res.new(190.0, 0.9955)
	var knock := Res.new(430.0, 0.986)
	var lp := LP.new(0.16)
	var mallet := LP.new(0.35)
	for i in n:
		var t := float(i) / RATE
		var imp := mallet.run((randf() * 2.0 - 1.0) * _hit(t, 0.0025, 0.008))
		var wet := lp.run(randf() * 2.0 - 1.0) * _hit(t, 0.012, 0.08) * 0.16
		s[i] = wood.run(imp) * 0.075 + knock.run(imp) * 0.05 + wet
	return _from(_voice(s, 0.70))


## Taking a hit: a low, dull thump. The old one drove its 105 Hz body so hard
## that the soft clip squared it off into a buzz; now the body is struck gently
## and dropped an octave's worth of brightness, so what is left is weight.
static func hurt() -> AudioStreamWAV:
	var n := int(RATE * 0.34)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := Res.new(98.0, 0.9965)
	var mallet := LP.new(0.22)
	var muffle := LP.new(0.35)
	var lp := LP.new(0.07)
	for i in n:
		var t := float(i) / RATE
		var imp := mallet.run((randf() * 2.0 - 1.0) * _hit(t, 0.004, 0.013))
		var air := lp.run(randf() * 2.0 - 1.0) * _hit(t, 0.02, 0.1) * 0.10
		s[i] = muffle.run(low.run(imp) * 0.055 + air)
	return _from(_voice(s, 0.70))


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


## A footfall on the jetty: a soft knock on a hollow plank. Barefoot, not boots
## — the strike is ramped and rolled off, and the plank is left to settle.
static func step_wood() -> AudioStreamWAV:
	var n := int(RATE * 0.15)
	var s := PackedFloat32Array()
	s.resize(n)
	var plank := Res.new(250.0, 0.9925)
	var hollow := Res.new(520.0, 0.982)
	var sole := LP.new(0.3)
	for i in n:
		var t := float(i) / RATE
		var imp := sole.run((randf() * 2.0 - 1.0) * _hit(t, 0.002, 0.007))
		var knock := plank.run(imp) * 0.075 + hollow.run(imp) * 0.055
		s[i] = knock * exp(-t * 11.0)
	return _from(_voice(s, 0.70))


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
	return _loop(_seam(s))


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
	return _loop(_seam(s))


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
	return _loop(_seam(s))


## A small outboard motor idling: a low chug with a rough edge, built so the
## loop point lands on a whole number of firing cycles.
static func engine_loop() -> AudioStreamWAV:
	var cycles := 40
	var f := 26.0                       # firings per second at idle
	var n := int(RATE * cycles / f)
	var s := PackedFloat32Array()
	s.resize(n)
	var body := Res.new(150.0, 0.986)
	var lp := LP.new(0.16)
	var rough := LP.new(0.06)
	var muffle := LP.new(0.3)
	for i in n:
		var t := float(i) / RATE
		var phase := fmod(t * f, 1.0)
		# Each firing is a short thump, not a smooth wave — but it swells into
		# place over a couple of milliseconds instead of snapping on, so there
		# is no hard edge 26 times a second.
		var fire: float = (1.0 - exp(-phase * 13.0)) * exp(-phase * 10.0)
		# The excitation has to swing both ways. A one-sided pulse train is
		# almost all DC, and a 150 Hz body with a high q amplifies DC several
		# hundred times over — that is what pinned the old loop against the
		# soft clip and turned a chug into a wall of noise.
		var pulse := (randf() * 2.0 - 1.0) * fire
		var grit := lp.run(randf() * 2.0 - 1.0) * 0.4 * fire
		var chug := body.run(pulse * 0.3 + grit * 0.3)
		# a faint hum under it all, as if heard from the far end of the boat
		var wobble := rough.run(randf() * 2.0 - 1.0) * 0.25
		s[i] = muffle.run(chug + wobble)
	return _loop(_seam(_voice(s, 0.58)))


# --- music --------------------------------------------------------------------

## A slow, warm loop to sit under the surf: a plucked arpeggio over a soft pad,
## four friendly chords in F, no drums and no melody to get stuck in your head.
## Everything wraps around the loop point so there's no seam.
static func music_loop() -> AudioStreamWAV:
	# Nothing here goes above about 1.6 kHz, so it is built at half rate: the
	# same loop for half the work, which matters because this is generated on
	# the player's phone while the game starts.
	var rate := RATE / 2
	var bar := 2.6                                   # seconds per chord
	var n := int(float(rate) * bar * 4.0)
	var s := PackedFloat32Array()
	s.resize(n)
	# F - C - Dm - Bb, the friendliest four chords there are.
	var chords := [
		[174.61, 220.00, 261.63],
		[130.81, 164.81, 196.00],
		[146.83, 174.61, 220.00],
		[116.54, 174.61, 233.08]]
	var order := [0, 1, 2, 1, 0, 2]

	# One ringing note per pitch, rendered once and then stamped wherever it
	# is needed - far cheaper than running the oscillators 24 times over.
	var ring := int(float(rate) * 1.6)
	var voices := {}
	for c in 4:
		for step in order.size():
			var f: float = float((chords[c] as Array)[int(order[step])])
			if step == 2 or step == 5:
				f *= 2.0
			var key := int(round(f * 100.0))
			if voices.has(key):
				continue
			var v := PackedFloat32Array()
			v.resize(ring)
			for i in ring:
				var t := float(i) / float(rate)
				var env: float = exp(-t * 2.4) * (1.0 - exp(-t * 150.0))
				v[i] = (sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.17
					+ sin(TAU * f * 3.01 * t + 0.4) * 0.06) * env * 0.3
			voices[key] = v

	for c in 4:
		var notes: Array = chords[c]
		var base := int(float(rate) * bar * float(c))
		# Plucks: a little ukulele figure, each note ringing into the next and
		# wrapping round the loop point so there is no seam.
		for step in order.size():
			var f: float = float(notes[int(order[step])])
			if step == 2 or step == 5:
				f *= 2.0
			var v: PackedFloat32Array = voices[int(round(f * 100.0))]
			var at := base + int(float(rate) * 0.42 * float(step))
			for i in ring:
				s[(at + i) % n] += v[i]
		# Pad: the same chord an octave down, swelling in and out so the chord
		# change never clicks.
		var padn := int(float(rate) * bar)
		for i in padn:
			var k := base + i
			if k >= n:
				break
			var tt := float(k) / float(rate)
			var swell: float = sin(PI * float(i) / float(padn))
			var pad := 0.0
			for f2 in notes:
				pad += sin(TAU * (float(f2) * 0.5) * tt)
			s[k] += pad * 0.05 * swell * swell
	var warm := LP.new(0.5)
	for i in n:
		s[i] = _soft(warm.run(s[i]) * 0.95)
	return _loop(s, rate)


## Thunder: a crack that rolls away into a long, low rumble. Built at a low
## rate because there is nothing up high in it worth the samples.
static func thunder() -> AudioStreamWAV:
	var rate := RATE / 2
	var n := int(float(rate) * 3.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := LP.new(0.05)
	var body := LP.new(0.13)
	var crack := HP.new(0.5)
	var boom := Res.new(48.0, 0.9992)
	for i in n:
		var t := float(i) / float(rate)
		var noise := randf() * 2.0 - 1.0
		# the initial crack, only in the first fraction of a second
		var snap: float = crack.run(noise) * exp(-t * 11.0) * 0.5
		# the rumble: noise dragged through two slow filters, swelling and
		# fading in waves as it bounces around the sky
		var roll: float = low.run(body.run(noise))
		var swell: float = 0.55 + 0.45 * sin(t * 2.3) * sin(t * 0.9 + 1.1)
		var tail: float = roll * swell * exp(-t * 0.75) * 6.0
		var deep: float = boom.run(noise * 0.02 * exp(-t * 2.0)) * 0.5
		s[i] = _soft((snap + tail + deep) * 0.8)
	return _from(s, rate)
