class_name Valve
extends Interactable
## A handwheel valve. Drag the mouse in circles to turn it: clockwise opens.
## The turn is read from how the mouse's direction of travel rotates
## ([CrankTracker]), so circles of any size work.

## Full turns of the wheel from min to max.
@export var turns_full_range: float = 3.0
@export var wheel: Node3D

var _crank: CrankTracker = CrankTracker.new()


func begin_interaction() -> void:
	_crank.reset()
	super.begin_interaction()


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current + _swept_turns(relative) / turns_full_range * (max_value - min_value)


## Turns swept by a mouse drag (clockwise positive).
func _swept_turns(relative: Vector2) -> float:
	return _crank.feed(relative)


func _apply_visual(v: float) -> void:
	if wheel == null:
		return
	var t: float = inverse_lerp(min_value, max_value, v)
	wheel.rotation.z = -t * turns_full_range * TAU


func interaction_hint() -> String:
	return "hold click, circle the mouse (clockwise opens)"
