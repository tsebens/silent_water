class_name SoundEvent
extends RefCounted
## One sound as one detector receives it. Built by [method Acoustics.emit_event],
## handed to the detector synchronously and dropped; nothing keeps it alive
## unless the listener copies it into a [SoundMemory].

## Where the sound really came from (world space).
var true_position: Vector3 = Vector3.ZERO
## Where it seems to come from: the true position plus an error within [member uncertainty].
var perceived_position: Vector3 = Vector3.ZERO
## Intensity at the emitter, 1 m reference (linear).
var emitted_intensity: float = 0.0
## Intensity at the detector after spreading and occlusion (linear).
var intensity: float = 0.0
## Radius (m) of the error in the perceived position.
var uncertainty: float = 0.0
## Distance emitter to detector at emission (m).
var distance: float = 0.0
## Emission time plus distance / speed of sound (s, on the acoustics clock).
var timestamp: float = 0.0
var kind: StringName = &""
var source: Object = null
var occluded: bool = false
