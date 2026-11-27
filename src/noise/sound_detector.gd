class_name SoundDetector
extends Node
## Registers a listener with [Acoustics]. Receives only the events that stand at
## least [member threshold_db] above the background at [member world_position].
## The owner keeps [member world_position] current (world space).

signal heard(event: SoundEvent)

## How far above the background (dB) a sound must be to be heard.
@export var threshold_db: float = 0.0
var world_position: Vector3 = Vector3.ZERO


func _enter_tree() -> void:
	add_to_group(&"sound_detectors")


func receive(event: SoundEvent) -> void:
	heard.emit(event)
