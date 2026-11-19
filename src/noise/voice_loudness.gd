class_name VoiceLoudness
extends RefCounted
## Turns raw mono voice samples into noise intensity. Kept free of any audio
## or network code so it can move from each player's machine to the host
## unchanged once in-game voice exists (decision #8).

## Maps mic RMS² to noise intensity. Tuned so normal speech (RMS ≈ 0.07)
## lands near 75 dB, a whisper (RMS ≈ 0.01) near 58 dB (under the ocean),
## and a shout (RMS ≈ 0.3) near 87 dB. Uncalibrated per mic for now (#17).
const VOICE_GAIN: float = 0.6
## Below this RMS the input is treated as silence (mic hiss, fans).
const NOISE_GATE_RMS: float = 0.004


## [param samples]: mono samples in -1..1.
static func intensity_from_samples(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum_sq: float = 0.0
	for x: float in samples:
		sum_sq += x * x
	var mean_sq: float = sum_sq / float(samples.size())
	if mean_sq < NOISE_GATE_RMS * NOISE_GATE_RMS:
		return 0.0
	return VOICE_GAIN * mean_sq


## Downmixes stereo frames (as delivered by AudioEffectCapture) to mono.
static func to_mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(frames.size())
	for i: int in range(frames.size()):
		out[i] = (frames[i].x + frames[i].y) * 0.5
	return out
