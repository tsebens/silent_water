class_name PushButton
extends Interactable
## A momentary push button: pressed ([member max_value]) while held, springs
## back to [member min_value] on release. The plunger slides along the
## button's local -Z (into the panel) by [member travel] when pressed.

## How far the cap sinks when pressed (m).
@export var travel: float = 0.004
@export var plunger: Node3D

var _rest: Vector3 = Vector3.ZERO
var _have_rest: bool = false


func begin_interaction() -> void:
	super.begin_interaction()
	drive_to(max_value)


func _drag_to_value(_current: float, _relative: Vector2) -> float:
	return max_value


func _release_value(_current: float) -> float:
	return min_value


func _apply_visual(v: float) -> void:
	if plunger == null:
		return
	if not _have_rest:
		_rest = plunger.position
		_have_rest = true
	plunger.position = _rest + Vector3(0.0, 0.0, -travel * inverse_lerp(min_value, max_value, v))


func interaction_hint() -> String:
	return "click to press"
