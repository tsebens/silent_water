class_name SoundType
extends Resource
## A shared kind of sound. Emitters reference one of these (one .tres per kind
## in src/noise/sound_types/); changing it changes every emitter that uses it.

## Linear intensity at 1 m.
@export var intensity: float = 0.001
@export var kind: StringName = &"mechanical"
## Seconds between events for a continuous source; 0 means a one-off.
@export var period: float = 1.0

## Optional sound played to players at the emitter. Null means silent.
@export var stream: AudioStream
@export var volume_db: float = 0.0
@export var attenuation_model: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
## Matches SubAudio.UNIT_SIZE (a literal: referencing SubAudio would make a script cycle).
@export var unit_size: float = 4.0
@export var bus: StringName = AudioBuses.INSIDE

## Bounds on the per-emitter scale passed to [method Acoustics.emit_event].
const SCALE_MIN: float = 0.25
const SCALE_MAX: float = 4.0


func is_one_off() -> bool:
	return period <= 0.0


## Emitted intensity for an emitter-specific scale, clamped to the bounds.
func scaled_intensity(scale: float = 1.0) -> float:
	return intensity * clampf(scale, SCALE_MIN, SCALE_MAX)


func has_stream() -> bool:
	return stream != null


## Copies this type's playback settings onto [param p]. Called at play time
## (and refreshed while looping) so edits to the type take effect everywhere.
func apply_to(p: AudioStreamPlayer3D) -> void:
	p.stream = stream
	p.volume_db = volume_db
	p.attenuation_model = attenuation_model
	p.unit_size = unit_size
	p.bus = bus
