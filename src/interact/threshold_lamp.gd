class_name ThresholdLamp
extends Node
## Lights an [IndicatorLamp] when a readout from a source group crosses a threshold. The threshold is
## [member threshold] (absolute), or, if [member threshold_of] names a readout, [member threshold] times that
## readout (BILGE: 0.25 of `bilge_limit`). With no `readout`, no source in the group, or a source that lacks
## the readout, the lamp stays unlit: some alarms (CO2, low O2) have nothing simulating them yet.

@export var lamp: IndicatorLamp
@export var source_group: StringName = &"sub_readouts"
@export var readout: StringName = &""
@export var threshold: float = 0.0
@export var threshold_of: StringName = &""
## True: lit above the threshold. False: lit below it.
@export var above: bool = true


func _process(_delta: float) -> void:
	update()


func update() -> void:
	if lamp != null:
		lamp.set_lit(is_alarm())


func is_alarm() -> bool:
	if readout == &"":
		return false
	var source: Node = get_tree().get_first_node_in_group(source_group) if is_inside_tree() else null
	if source == null or not source.has_method(&"readout"):
		return false
	var limit: float = threshold
	if threshold_of != &"":
		limit *= float(source.call(&"readout", threshold_of))
	var value: float = float(source.call(&"readout", readout))
	return value > limit if above else value < limit
