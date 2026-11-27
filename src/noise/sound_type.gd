class_name SoundType
extends Resource
## A shared kind of sound. Emitters reference one of these (one .tres per kind
## in src/noise/sound_types/); changing it changes every emitter that uses it.

## Linear intensity at 1 m.
@export var intensity: float = 0.001
@export var kind: StringName = &"mechanical"
## Seconds between events for a continuous source; 0 means a one-off.
@export var period: float = 1.0

## Bounds on the per-emitter scale passed to [method Acoustics.emit_event].
const SCALE_MIN: float = 0.25
const SCALE_MAX: float = 4.0


func is_one_off() -> bool:
	return period <= 0.0


## Emitted intensity for an emitter-specific scale, clamped to the bounds.
func scaled_intensity(scale: float = 1.0) -> float:
	return intensity * clampf(scale, SCALE_MIN, SCALE_MAX)
