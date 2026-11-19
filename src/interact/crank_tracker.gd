class_name CrankTracker
extends RefCounted
## Reads "cranking" from mouse motion: the turn is how far the direction of
## travel rotates, so a circle of any size or speed counts as exactly one turn
## and straight drags count as none. Clockwise on screen (y down) is positive.
##
## Replaces the old virtual-cursor orbit, which doubled back when a wide, fast
## circle produced mouse steps bigger than its fixed 120 px orbit.

## Motion is gathered into steps at least this long before reading direction,
## so mouse jitter doesn't spin the wheel.
const MIN_STEP_PX: float = 6.0
## A direction change bigger than this between steps is a reversal or a
## glitch, not cranking; it's ignored rather than counted.
const MAX_STEP_TURN: float = deg_to_rad(110.0)

var _pending: Vector2 = Vector2.ZERO
var _prev_dir: Vector2 = Vector2.ZERO


func reset() -> void:
	_pending = Vector2.ZERO
	_prev_dir = Vector2.ZERO


## Feeds a mouse motion; returns turns swept (fraction of a full turn).
func feed(relative: Vector2) -> float:
	_pending += relative
	if _pending.length() < MIN_STEP_PX:
		return 0.0
	var dir: Vector2 = _pending.normalized()
	_pending = Vector2.ZERO
	if _prev_dir == Vector2.ZERO:
		_prev_dir = dir
		return 0.0
	var swept: float = atan2(_prev_dir.cross(dir), _prev_dir.dot(dir))
	_prev_dir = dir
	if absf(swept) > MAX_STEP_TURN:
		return 0.0
	return swept / TAU
