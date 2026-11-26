class_name SwitchLever
extends Lever
## An on/off lever (bilge pump). Snaps to the nearer end when released.
## Optionally drives an [IndicatorLamp]: lit while the lever is nearer its on
## (max) end.

## Lamp that follows the lever. Unset: the switch has no lamp.
@export var indicator: IndicatorLamp


func _apply_visual(v: float) -> void:
	super._apply_visual(v)
	if indicator != null:
		indicator.set_lit(v >= (min_value + max_value) * 0.5)


func _release_value(current: float) -> float:
	return max_value if current >= (min_value + max_value) * 0.5 else min_value


func interaction_hint() -> String:
	return "hold click, drag up or down to switch"
