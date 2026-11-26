class_name SparesDrawer
extends Node
## Shows the spare breakers left. The first N of [member slots] are visible, N being the power
## system's `spares_remaining` readout clamped to the slot count; the rest are hidden. Display only.

## Slot nodes, in the order they fill (a spare sitting in each).
@export var slots: Array[Node3D] = []
## Node with `readout` (a [PowerSystem]). Unset: the first node in the power group.
@export var power: Node
@export var readout: StringName = &"spares_remaining"


func _ready() -> void:
	if power == null and is_inside_tree():
		power = get_tree().get_first_node_in_group(PowerSystem.GROUP)
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Spares now (0 when there is no power system to ask).
func spare_count() -> int:
	if power == null or not power.has_method(&"readout"):
		return 0
	return int(power.call(&"readout", readout))


## Slots that should show: the readout clamped to the slot count.
func shown_count() -> int:
	return clampi(spare_count(), 0, slots.size())


func refresh() -> void:
	var n: int = shown_count()
	for i: int in slots.size():
		if slots[i] != null:
			slots[i].visible = i < n
