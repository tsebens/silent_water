class_name PilotSeat
extends Interactable
## The pilot's chair. Holding it means sitting in it: the player is locked to
## [member sit_point], and their WASD drives the rudder and dive planes.
## Only one pilot at a time (the Interactable grab lock).

@export var rudder: SpringAxis
@export var planes: SpringAxis
## Where the seated player's feet go (sub-local, relative to this node).
@export var sit_point: Node3D


func begin_interaction() -> void:
	super.begin_interaction()
	rudder.begin_interaction()
	planes.begin_interaction()


func end_interaction() -> void:
	rudder.end_interaction()
	planes.end_interaction()
	super.end_interaction()


## Local pilot input: x = rudder (A/D), y = planes (W dives, S rises).
func drive(input: Vector2, delta: float) -> void:
	if not is_held_locally():
		return
	rudder.drive_input(input.x, delta)
	planes.drive_input(-input.y, delta)


func seat_transform() -> Transform3D:
	return sit_point.global_transform if sit_point != null else global_transform


func interaction_hint() -> String:
	return "click to sit · WASD flies · click again to stand"
