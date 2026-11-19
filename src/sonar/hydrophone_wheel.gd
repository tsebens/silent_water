class_name HydrophoneWheel
extends Valve
## Handwheel that trains the hydrophone. Turns freely; one full turn of the
## wheel swings the listening bearing [member degrees_per_turn] degrees.
## Bearings are relative to the bow, clockwise (90 = starboard beam).

@export var degrees_per_turn: float = 120.0


func _init() -> void:
	super._init()
	min_value = -1.0e6
	max_value = 1.0e6
	initial_value = 0.0


func bearing_deg() -> float:
	return fposmod(get_value(), 360.0)


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current + _swept_turns(relative) * degrees_per_turn


func _apply_visual(v: float) -> void:
	if wheel != null:
		wheel.rotation.z = -deg_to_rad(v / degrees_per_turn * 360.0)


func interaction_hint() -> String:
	return "hold click, circle the mouse to train the hydrophone"
