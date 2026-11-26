class_name SwitchLever
extends Lever
## An on/off lever. A click (press and release) throws it to the other end; dragging does nothing.
## Optionally drives an [IndicatorLamp]: lit while the lever is nearer its on
## (max) end.

## Lamp that follows the lever. Unset: the switch has no lamp.
@export var indicator: IndicatorLamp


func _apply_visual(v: float) -> void:
	super._apply_visual(v)
	if indicator != null:
		indicator.set_lit(v >= (min_value + max_value) * 0.5)


func _drag_to_value(current: float, _relative: Vector2) -> float:
	return current


func click_action() -> void:
	var on: bool = get_value() >= (min_value + max_value) * 0.5
	drive_to(min_value if on else max_value)


func interaction_hint() -> String:
	return "click to switch"
