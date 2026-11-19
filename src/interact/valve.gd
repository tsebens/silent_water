class_name Valve
extends Interactable
## A handwheel valve. Drag the mouse in circles to turn it: clockwise opens.
## The drag is tracked as a virtual cursor orbiting the wheel's centre, so the
## turn follows the angle swept, not raw distance.

## Full turns of the wheel from min to max.
@export var turns_full_range: float = 3.0
## Radius of the virtual cursor orbit in pixels.
@export var orbit_radius_px: float = 120.0
@export var wheel: Node3D

var _cursor: Vector2 = Vector2.ZERO


func begin_interaction() -> void:
	_cursor = Vector2(orbit_radius_px, 0.0)
	super.begin_interaction()


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current + _swept_turns(relative) / turns_full_range * (max_value - min_value)


## Turns swept by a mouse drag around the virtual orbit (clockwise positive).
func _swept_turns(relative: Vector2) -> float:
	var before: float = _cursor.angle()
	_cursor += relative
	# Keep the virtual cursor on the orbit so tiny jitters near the centre
	# can't spin the wheel wildly.
	if _cursor.length() < 1.0:
		_cursor = Vector2(orbit_radius_px, 0.0)
	_cursor = _cursor.normalized() * orbit_radius_px
	# Screen y points down, so a positive swept angle is clockwise on screen.
	return wrapf(_cursor.angle() - before, -PI, PI) / TAU


func _apply_visual(v: float) -> void:
	if wheel == null:
		return
	var t: float = inverse_lerp(min_value, max_value, v)
	wheel.rotation.z = -t * turns_full_range * TAU


func interaction_hint() -> String:
	return "hold click, circle the mouse (clockwise opens)"
