class_name Lever
extends Interactable
## A lever that pivots about its local X axis. Drag the mouse up/down to move it.

## Total swing of the handle between min and max (degrees).
@export var swing_deg: float = 90.0
## Value change per pixel of vertical mouse drag, as a fraction of the range.
@export var sensitivity: float = 0.004
@export var pivot: Node3D


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current - relative.y * sensitivity * (max_value - min_value)


func _apply_visual(v: float) -> void:
	if pivot == null:
		return
	var t: float = inverse_lerp(min_value, max_value, v)
	pivot.rotation.x = deg_to_rad(lerpf(swing_deg * 0.5, -swing_deg * 0.5, t))


func interaction_hint() -> String:
	return "hold click, drag up or down"
