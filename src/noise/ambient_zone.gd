class_name AmbientZone
extends Node3D

const FADE_FRACTION: float = 0.4
## A background noise source in the world (vent, current, rockslide). Adds to
## the ocean level the sub hears, which can mask the sub's own noise. Lives
## under the world root; its position is in world space.

## Level at 1 m from the source.
@export var source_db: float = 110.0
## Beyond this distance the zone contributes nothing; it fades out over the
## last [constant FADE_FRACTION] of the range so there's no hard edge.
@export var max_range: float = 300.0
## Optional on/off for triggered events like rockslides.
@export var active: bool = true


func _ready() -> void:
	add_to_group(&"ambient_zones")
	add_to_group(&"outside_sources")


## Outside-audio hook: the sonar operator can hear (and be blinded by) it.
func outside_db() -> float:
	return source_db if active else -INF


func outside_stream() -> AudioStream:
	return ProceduralSounds.vent()


func intensity_at(world_point: Vector3) -> float:
	if not active:
		return 0.0
	var d: float = position.distance_to(world_point)
	if d > max_range:
		return 0.0
	var fade: float = 1.0 - smoothstep(max_range * (1.0 - FADE_FRACTION), max_range, d)
	return NoiseLevel.attenuate(NoiseLevel.from_db(source_db), d) * fade
