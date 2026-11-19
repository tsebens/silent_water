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
