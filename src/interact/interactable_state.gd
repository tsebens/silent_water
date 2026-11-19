class_name InteractableState
extends RefCounted
## Network-agnostic state for a physical control: value, range, who holds it,
## and how fast it is moving. Kept separate from the node so it can be unit
## tested without a scene tree or network.

const NO_HOLDER: int = 0
## Time constant for smoothing the rate of change (s).
const RATE_SMOOTHING_SEC: float = 0.15

var min_value: float = 0.0
var max_value: float = 1.0
var value: float = 0.0
var holder: int = NO_HOLDER
## Smoothed |dv/dt| divided by the range: 1.0 means a full sweep per second.
var normalized_rate: float = 0.0

var _pending_delta: float = 0.0


func _init(p_min: float = 0.0, p_max: float = 1.0, p_value: float = 0.0) -> void:
	min_value = minf(p_min, p_max)
	max_value = maxf(p_min, p_max)
	value = clampf(p_value, min_value, max_value)


func clamp_value(v: float) -> float:
	return clampf(v, min_value, max_value)


## Grants the control to [param peer] if nobody holds it. Returns true if
## [param peer] holds it afterwards.
func try_grab(peer: int) -> bool:
	if holder == NO_HOLDER:
		holder = peer
	return holder == peer


func release(peer: int) -> bool:
	if holder != peer:
		return false
	holder = NO_HOLDER
	return true


## Applies a requested value from [param peer]. Only the holder may move it.
## Returns true if the value was accepted.
func request(peer: int, v: float) -> bool:
	if holder != peer:
		return false
	set_value(v)
	return true


## Sets the value directly (clamped) and records the movement for rate tracking.
func set_value(v: float) -> void:
	var clamped: float = clamp_value(v)
	_pending_delta += absf(clamped - value)
	value = clamped


## Sets the value without recording movement (game logic, not a hand on
## the control), so it makes no noise.
func set_value_silent(v: float) -> void:
	value = clamp_value(v)
	_pending_delta = 0.0
	normalized_rate = 0.0


## Advances rate tracking by [param delta] seconds. Call once per tick.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var span: float = maxf(max_value - min_value, 0.0001)
	var instant_rate: float = _pending_delta / span / delta
	_pending_delta = 0.0
	var w: float = 1.0 - exp(-delta / RATE_SMOOTHING_SEC)
	normalized_rate = lerpf(normalized_rate, instant_rate, w)


func normalized() -> float:
	return inverse_lerp(min_value, max_value, value)
