class_name LoaderDrawer
extends Interactable
## A slide drawer worked with the mouse: value 0 is closed, 1 is open. Dragging
## slides [member body] along [member slide_axis], clamped to the travel, so the
## slide is clearly animated. While [member locked] (the launch tube is primed)
## it does not move. Replicated like every [Interactable].

## Direction the drawer opens, in this node's local space.
@export var slide_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## How far it opens (m).
@export var travel_m: float = 0.65
## The moving part (drawer box with its cradle). Unset: nothing is posed.
@export var body: Node3D
## Value change per pixel of vertical drag, as a fraction of the range.
@export var sensitivity: float = 0.004
## At or below this value the drawer counts as closed.
@export var closed_threshold: float = 0.02
## At or above this value the drawer counts as open.
@export var open_threshold: float = 0.98

## While true the drawer cannot be moved.
var locked: bool = false

var _rest: Vector3 = Vector3.ZERO
var _rest_known: bool = false


func is_closed() -> bool:
	return get_normalized() <= closed_threshold


func is_open() -> bool:
	return get_normalized() >= open_threshold


## A locked drawer ignores every move, however it is driven.
func drive_to(target: float, silent: bool = false) -> void:
	if locked:
		return
	super.drive_to(target, silent)


func _drag_to_value(current: float, relative: Vector2) -> float:
	if locked:
		return current
	return current + relative.y * sensitivity * (max_value - min_value)


func _release_value(current: float) -> float:
	return current


func _apply_visual(v: float) -> void:
	if body == null:
		return
	if not _rest_known:
		_rest = body.position
		_rest_known = true
	body.position = _rest + slide_axis.normalized() * travel_m * inverse_lerp(min_value, max_value, v)


func interaction_hint() -> String:
	return "drawer is locked" if locked else "hold click, drag to slide"
