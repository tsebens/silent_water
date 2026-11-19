class_name SwitchLever
extends Lever
## An on/off lever (bilge pump). Snaps to the nearer end when released.


func _release_value(current: float) -> float:
	return max_value if current >= (min_value + max_value) * 0.5 else min_value
