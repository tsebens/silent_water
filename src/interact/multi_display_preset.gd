class_name MultiDisplayPreset
extends Resource
## A whole [MultiDisplay] configuration as a Resource: the four slots, the centre
## chevron column and the edge ring. [method MultiDisplay.apply_preset] copies it onto a display.

@export var slots: Array[MultiDisplaySlot] = []
@export var chevrons_enabled: bool = false
@export var chevron_readout: StringName = &""
@export var chevron_count: int = 3
@export var chevron_step: float = 1.0
@export var ring_enabled: bool = false
@export var ring_readout: StringName = &""
@export var ring_segments: int = 24
@export_range(0.0, 1.0) var ring_warn_below: float = 0.5
@export_range(0.0, 1.0) var ring_alarm_below: float = 0.2
