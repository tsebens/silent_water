class_name SoundEmitter
extends Node
## A non-sub sound source. References a shared [SoundType] (never inline sound
## parameters): a continuous type (period > 0) emits one event per period while
## [member active]; a one-off type emits only through [method fire].
## The owner keeps [member world_position] current (world space).

@export var sound_type: SoundType
@export var active: bool = true
## Bounded per-emitter multiplier on the type's intensity (see [SoundType]).
@export var scale: float = 1.0
var world_position: Vector3 = Vector3.ZERO

var _accum: float = 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## Advances the emitter's clock by [param delta] and emits every event that
## falls due. Returns how many were emitted. Frame-rate independent: the count
## over a span depends only on the type's period.
func advance(delta: float) -> int:
	if not active or sound_type == null or sound_type.is_one_off():
		return 0
	_accum += delta
	var n: int = 0
	while _accum >= sound_type.period:
		_accum -= sound_type.period
		Acoustics.emit_event(sound_type, world_position, self, scale)
		n += 1
	return n


## Emits once, now, at [member world_position].
func fire() -> void:
	if sound_type != null:
		Acoustics.emit_event(sound_type, world_position, self, scale)
