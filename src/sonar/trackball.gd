class_name Trackball
extends HydrophoneWheel
## Trains the hydrophone with a desk trackball. Rolling the ball sideways
## swings the listening bearing: drag right is clockwise. Bearings work as on
## the handwheel ([method HydrophoneWheel.bearing_deg]).
##
## The ball turns about the trackball's local Y axis (up the desk) as the
## bearing changes, so the rotation reads like the roll that caused it.

## Bearing change per pixel of horizontal mouse drag (degrees).
@export var degrees_per_px: float = 0.25
## Ball rotation per degree of bearing (degrees).
@export var ball_deg_per_bearing_deg: float = 3.0
@export var ball: Node3D

var _ball_basis: Basis = Basis.IDENTITY
var _have_ball: bool = false


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current + relative.x * degrees_per_px


func _apply_visual(v: float) -> void:
	if ball == null:
		return
	if not _have_ball:
		_ball_basis = ball.transform.basis
		_have_ball = true
	ball.transform.basis = _ball_basis * Basis(Vector3.UP, deg_to_rad(v * ball_deg_per_bearing_deg))


func interaction_hint() -> String:
	return "hold click, drag sideways to train the hydrophone"
