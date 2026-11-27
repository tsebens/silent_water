class_name ProceduralSounds
extends RefCounted
## Placeholder sounds synthesized at startup, so the prototype has a mix
## before any audio assets exist. Loops are whole numbers of cycles so they
## repeat without clicks. Results are cached.

const RATE: int = 22050

static var _cache: Dictionary = {}


## Machinery hum with a rhythmic pulse. Regular, mechanical rhythm is what
## passive sonar listens for.
static func engine_hum() -> AudioStreamWAV:
	return _cached(&"engine_hum", func() -> AudioStreamWAV:
		var n: int = RATE  # 1 s loop: 48 Hz and 4 Hz both fit exactly.
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(1)
		for i: int in range(n):
			var t: float = float(i) / RATE
			var pulse: float = 0.65 + 0.35 * pow(0.5 + 0.5 * sin(TAU * 4.0 * t), 3.0)
			var tone: float = 0.55 * sin(TAU * 48.0 * t) + 0.3 * sin(TAU * 96.0 * t) + 0.12 * sin(TAU * 144.0 * t + 0.4)
			s[i] = (tone * pulse + rng.randf_range(-0.04, 0.04)) * 0.8
		return _wav(s, true))


## Broadband hiss: compressed air, a jet of water through a leak.
static func hiss() -> AudioStreamWAV:
	return _cached(&"hiss", func() -> AudioStreamWAV:
		var n: int = RATE
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(2)
		var prev: float = 0.0
		for i: int in range(n):
			var white: float = rng.randf_range(-1.0, 1.0)
			s[i] = (white - prev * 0.6) * 0.45  # Tilt toward high frequencies.
			prev = white
		_fade_loop_edges(s, 200)
		return _wav(s, true))


## Electrical crackle: irregular sharp pops over a faint buzz. Sparking wiring.
static func crackle() -> AudioStreamWAV:
	return _cached(&"crackle", func() -> AudioStreamWAV:
		var n: int = RATE
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(21)
		var pop: float = 0.0
		for i: int in range(n):
			if rng.randf() < 0.0012:
				pop = rng.randf_range(0.5, 1.0)
			pop *= 0.992
			var t: float = float(i) / RATE
			s[i] = pop * rng.randf_range(-1.0, 1.0) + 0.06 * sin(TAU * 100.0 * t)
		_fade_loop_edges(s, 200)
		return _wav(s, true))


## Low gurgle with bubble blips: flooding ballast, bilge pump.
static func gurgle() -> AudioStreamWAV:
	return _cached(&"gurgle", func() -> AudioStreamWAV:
		var n: int = RATE * 2
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(3)
		var low: float = 0.0
		var bubble_t: float = -1.0
		var bubble_f: float = 300.0
		for i: int in range(n):
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.05)
			if bubble_t < 0.0 and rng.randf() < 0.0009:
				bubble_t = 0.0
				bubble_f = rng.randf_range(250.0, 700.0)
			var b: float = 0.0
			if bubble_t >= 0.0:
				b = sin(TAU * bubble_f * (1.0 + bubble_t * 3.0) * bubble_t) * exp(-bubble_t * 40.0)
				bubble_t += 1.0 / RATE
				if bubble_t > 0.15:
					bubble_t = -1.0
			s[i] = low * 0.9 + b * 0.5
		_fade_loop_edges(s, 400)
		return _wav(s, true))


## Metal-on-metal clank for a control slammed home.
static func clank() -> AudioStreamWAV:
	return _cached(&"clank", func() -> AudioStreamWAV:
		var n: int = int(RATE * 0.5)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(4)
		for i: int in range(n):
			var t: float = float(i) / RATE
			var ring: float = 0.5 * sin(TAU * 523.0 * t) + 0.35 * sin(TAU * 1187.0 * t) + 0.25 * sin(TAU * 2240.0 * t)
			var hit: float = rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
			s[i] = (ring * exp(-t * 9.0) + hit) * 0.7
		return _wav(s, false))


## Deep thud through the hull.
static func thud() -> AudioStreamWAV:
	return _cached(&"thud", func() -> AudioStreamWAV:
		var n: int = int(RATE * 1.2)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(5)
		var low: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
			s[i] = (sin(TAU * (55.0 - t * 15.0) * t) * 0.8 + low * 0.6) * exp(-t * 3.5)
		return _wav(s, false))


## A boot on a steel deck.
static func step() -> AudioStreamWAV:
	return _cached(&"step", func() -> AudioStreamWAV:
		var n: int = int(RATE * 0.12)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(6)
		var low: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.3)
			s[i] = (low * exp(-t * 60.0) + 0.3 * sin(TAU * 880.0 * t) * exp(-t * 40.0)) * 0.9
		return _wav(s, false))


# --- Outside the hull ---------------------------------------------------------

## A huge body moving water: slow tail-beat swells of low noise.
static func swim() -> AudioStreamWAV:
	return _cached(&"swim", func() -> AudioStreamWAV:
		var n: int = RATE * 4  # 0.5 Hz tail beat: two beats per loop.
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(7)
		var low: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.02)
			var beat: float = pow(0.5 + 0.5 * sin(TAU * 0.5 * t), 2.0)
			s[i] = low * (0.25 + 0.75 * beat) * 2.5
		_fade_loop_edges(s, 800)
		return _wav(s, true))


## Long, falling moan: the apex calling in the distance.
static func moan() -> AudioStreamWAV:
	return _cached(&"moan", func() -> AudioStreamWAV:
		var dur: float = 4.5
		var n: int = int(RATE * dur)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var phase: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			var f: float = lerpf(95.0, 52.0, t / dur) + 4.0 * sin(TAU * 0.7 * t)
			phase += TAU * f / RATE
			var env: float = sin(PI * t / dur)
			s[i] = (sin(phase) * 0.7 + sin(phase * 2.01) * 0.25 + sin(phase * 3.03) * 0.1) * env * 0.9
		return _wav(s, false))


## A short train of low pulses: it is listening hard (Hunting).
static func pulse() -> AudioStreamWAV:
	return _cached(&"pulse", func() -> AudioStreamWAV:
		var n: int = int(RATE * 1.6)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		for i: int in range(n):
			var t: float = float(i) / RATE
			var local: float = fmod(t, 0.4)
			s[i] = sin(TAU * 70.0 * local) * exp(-local * 18.0) * 0.95
		return _wav(s, false))


## Grunting clicks: something has caught its attention (Curious).
static func grunt() -> AudioStreamWAV:
	return _cached(&"grunt", func() -> AudioStreamWAV:
		var n: int = int(RATE * 1.0)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(8)
		var low: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.06)
			var g: float = exp(-pow((t - 0.15) * 14.0, 2.0)) + 0.7 * exp(-pow((t - 0.55) * 14.0, 2.0))
			s[i] = (low * 1.6 + sin(TAU * 110.0 * t) * 0.4) * g
		return _wav(s, false))


## The charge: a rising, rough roar.
static func roar() -> AudioStreamWAV:
	return _cached(&"roar", func() -> AudioStreamWAV:
		var dur: float = 3.0
		var n: int = int(RATE * dur)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(9)
		var phase: float = 0.0
		var low: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			var f: float = lerpf(45.0, 85.0, t / dur)
			phase += TAU * f / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.1)
			var env: float = minf(t * 3.0, 1.0) * minf((dur - t) * 2.0, 1.0)
			var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			s[i] = (saw * 0.5 + low * 0.6) * env
		return _wav(s, false))


## Hydrothermal vent: a broadband rumble with bubbling.
static func vent() -> AudioStreamWAV:
	return _cached(&"vent", func() -> AudioStreamWAV:
		var n: int = RATE * 2
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(10)
		var low: float = 0.0
		var mid: float = 0.0
		for i: int in range(n):
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.03)
			mid = lerpf(mid, rng.randf_range(-1.0, 1.0), 0.3)
			s[i] = low * 1.5 + mid * 0.3
		_fade_loop_edges(s, 600)
		return _wav(s, true))


## Felt more than heard: a sub-bass drone for when something huge is near.
static func rumble() -> AudioStreamWAV:
	return _cached(&"rumble", func() -> AudioStreamWAV:
		var n: int = RATE * 2  # 30 Hz and 0.5 Hz both fit in 2 s.
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		for i: int in range(n):
			var t: float = float(i) / RATE
			s[i] = (sin(TAU * 30.0 * t) * 0.8 + sin(TAU * 45.0 * t) * 0.3) * (0.7 + 0.3 * sin(TAU * 0.5 * t))
		return _wav(s, true))


## The hull groaning under strain, and loose fittings rattling.
static func creak() -> AudioStreamWAV:
	return _cached(&"creak", func() -> AudioStreamWAV:
		var dur: float = 1.8
		var n: int = int(RATE * dur)
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(11)
		var phase: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			var f: float = 180.0 + 60.0 * sin(TAU * 0.8 * t) + rng.randf_range(-20.0, 20.0)
			phase += TAU * f / RATE
			var env: float = sin(PI * t / dur)
			var rattle: float = rng.randf_range(-1.0, 1.0) * (0.5 + 0.5 * sin(TAU * 23.0 * t)) * 0.3
			s[i] = (sin(phase) * 0.5 + rattle) * env
		return _wav(s, false))


## Water washing and slapping against the hull: a slow swell of low-passed
## noise with sharp slaps. An 8 s loop; the swell is 0.25 Hz, so it tiles.
static func surface_wash() -> AudioStreamWAV:
	return _cached(&"surface_wash", func() -> AudioStreamWAV:
		var n: int = RATE * 8
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		var rng: RandomNumberGenerator = _rng(12)
		var low: float = 0.0
		var slap: float = 0.0
		for i: int in range(n):
			var t: float = float(i) / RATE
			low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.08)
			var swell: float = 0.55 + 0.45 * sin(TAU * 0.25 * t)
			if rng.randf() < 0.00012:
				slap = 1.0
			slap *= 0.9992
			s[i] = low * 1.6 * swell + rng.randf_range(-1.0, 1.0) * slap * 0.5
		_fade_loop_edges(s, 2000)
		var peak: float = 0.0
		for v: float in s:
			peak = maxf(peak, absf(v))
		for i: int in range(n):
			s[i] = s[i] / peak * 0.9
		return _wav(s, true))


## Acoustic pinger on a Raindrop instrument: a clean tone burst every 2 s.
static func pinger() -> AudioStreamWAV:
	return _cached(&"pinger", func() -> AudioStreamWAV:
		var n: int = RATE * 2
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		for i: int in range(n):
			var t: float = float(i) / RATE
			var env: float = exp(-t * 18.0) if t < 0.3 else 0.0
			s[i] = sin(TAU * 1500.0 * t) * env * 0.9
		return _wav(s, true))


## The scanner sweeping: a rising whirr with a ticking pulse.
static func scanner() -> AudioStreamWAV:
	return _cached(&"scanner", func() -> AudioStreamWAV:
		var n: int = RATE  # 1 s: 220 Hz, 440 Hz and 8 Hz all fit.
		var s: PackedFloat32Array = PackedFloat32Array()
		s.resize(n)
		for i: int in range(n):
			var t: float = float(i) / RATE
			var tick: float = pow(0.5 + 0.5 * sin(TAU * 8.0 * t), 6.0)
			s[i] = (sin(TAU * 220.0 * t) * 0.4 + sin(TAU * 440.0 * t) * 0.25 + tick * sin(TAU * 1760.0 * t) * 0.3) * 0.9
		return _wav(s, true))


static func _cached(key: StringName, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key] as AudioStreamWAV


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _fade_loop_edges(s: PackedFloat32Array, n: int) -> void:
	# Crossfade the loop seam: blend the tail into the head.
	for i: int in range(n):
		var w: float = float(i) / n
		s[i] = s[i] * w + s[s.size() - n + i] * (1.0 - w)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
