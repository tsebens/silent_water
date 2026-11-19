class_name StationSeat
extends Interactable
## A seat that locks a player to a station (E to sit, E to stand). The player
## is held at [member sit_point] with their eyes at [member eye_height] above
## it. Only one occupant at a time (the Interactable grab lock).

## Where the seated player's feet go (sub-local, relative to this node).
@export var sit_point: Node3D
## Eye height above [member sit_point] while seated (m).
@export var eye_height: float = 1.15
## Whether a seated player may grab controls within reach (sonar: yes).
@export var allows_grabbing: bool = false


func seat_transform() -> Transform3D:
	return sit_point.global_transform if sit_point != null else global_transform


## Station name shown at the aiming point while seated.
func station_name() -> String:
	return display_name()


## Controls hint shown while seated.
func seated_hint() -> String:
	return "E to stand"


func interaction_hint() -> String:
	return "press E to sit"
