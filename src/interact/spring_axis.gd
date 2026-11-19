class_name SpringAxis
extends Interactable
## A -1..1 control surface driven by a pair of keys (rudder, dive planes).
## Moves at an actuator rate toward the held direction and springs back to
## centre when no key is held. Only the seated pilot drives it.

## Units per second the actuator moves.
@export var actuator_rate: float = 0.8
## Units per second it returns to centre when released. 0 = stays put
## (a throttle).
@export var return_rate: float = 1.2
## Snaps to exactly 0 inside this band when released (so "stop" is findable).
@export var center_detent: float = 0.0
## Mesh rotated to show the deflection, and the axis and angle it uses.
@export var indicator: Node3D
@export var indicator_axis: Vector3 = Vector3.RIGHT
@export var indicator_max_deg: float = 25.0


func _init() -> void:
	super._init()
	min_value = -1.0
	max_value = 1.0
	initial_value = 0.0


## Called by the seat each physics tick with the input direction (-1, 0, 1).
func drive_input(direction: float, delta: float) -> void:
	var v: float = get_value()
	var target: float
	if absf(direction) > 0.01:
		target = move_toward(v, signf(direction), actuator_rate * delta)
	elif absf(v) < center_detent:
		target = 0.0
	else:
		target = move_toward(v, 0.0, return_rate * delta)
	# Hydraulic and electric actuators: no handling noise.
	drive_to(target, true)


func _apply_visual(v: float) -> void:
	if indicator != null:
		indicator.transform.basis = Basis(indicator_axis.normalized(), deg_to_rad(indicator_max_deg) * v)


func interaction_hint() -> String:
	return "flown from the pilot seat"


## Gauge hook: the current setting.
func readout(_property: StringName) -> float:
	return get_value()
