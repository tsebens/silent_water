class_name JoystickIndicator
extends Node3D
## A display-only stick that tilts to show one or two [SpringAxis] values.
## [member fore_aft] tilts the stick fore and aft (throttle; planes: positive
## dives, tipping the stick forward). [member side] is optional and tilts it
## side to side (rudder: positive is starboard). A one-axis stick leaves the
## other tilt at zero. It has no input.

## The node that tilts.
@export var stick: Node3D
@export var fore_aft: SpringAxis
@export var side: SpringAxis
## Tilt at full deflection of an axis, degrees.
@export var max_deg: float = 20.0


func _process(_delta: float) -> void:
	refresh()


## Sets the stick's tilt from the axes' current values.
func refresh() -> void:
	if stick == null:
		return
	var fore: float = fore_aft.get_value() if fore_aft != null else 0.0
	var lateral: float = side.get_value() if side != null else 0.0
	var pitch: Basis = Basis(Vector3.RIGHT, -deg_to_rad(max_deg) * fore)
	var roll: Basis = Basis(Vector3.FORWARD, deg_to_rad(max_deg) * lateral)
	stick.transform.basis = roll * pitch
