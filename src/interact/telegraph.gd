class_name Telegraph
extends Lever
## Engine order telegraph. A lever with detents from Full Astern (-3) to Full
## Ahead (+3); it snaps to the nearest order when released. Engineering works
## it on the pilot's spoken calls.

const ORDER_NAMES: PackedStringArray = [
	"FULL ASTERN", "HALF ASTERN", "SLOW ASTERN", "STOP", "SLOW AHEAD", "HALF AHEAD", "FULL AHEAD",
]


func _init() -> void:
	super._init()
	min_value = -3.0
	max_value = 3.0
	initial_value = 0.0


## Current order as an integer, -3..3.
func order() -> int:
	return roundi(get_value())


## Order as engine output, -1..1.
func engine_order() -> float:
	return float(order()) / 3.0


static func order_name(o: int) -> String:
	return ORDER_NAMES[clampi(o + 3, 0, ORDER_NAMES.size() - 1)]


func _release_value(current: float) -> float:
	return roundf(current)


@export var order_label: Label3D


func _apply_visual(v: float) -> void:
	super._apply_visual(v)
	if order_label != null:
		order_label.text = order_name(roundi(v))
