class_name SoundEmitterPreset
extends Resource
## Tuning for one sound source: how loud, what kind, how often.

## Linear intensity at 1 m.
@export var base_intensity: float = 0.001
@export var kind: StringName = &"mechanical"
## Seconds between events for a continuous source; 0 means a one-off.
@export var period: float = 1.0


func is_one_off() -> bool:
	return period <= 0.0
