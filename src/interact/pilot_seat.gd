class_name PilotSeat
extends Interactable
## The pilot's chair. Sitting in it (E) locks the player to [member sit_point]
## and gives them the helm: W/S throttle, A/D rudder, R/F dive planes. In
## single-player developer mode ([DevSettings]) the pilot also runs the
## ballast: Numpad 8 blows and Numpad 2 floods while held.
## Only one pilot at a time (the Interactable grab lock).

## How fast held ballast keys open the valves (fraction per second).
const BALLAST_KEY_RATE: float = 2.0

@export var throttle: SpringAxis
@export var rudder: SpringAxis
@export var planes: SpringAxis
@export var flood_valve: Interactable
@export var blow_valve: Interactable
## Where the seated player's feet go (sub-local, relative to this node).
@export var sit_point: Node3D

var _has_ballast: bool = false


func begin_interaction() -> void:
	super.begin_interaction()
	for c: Interactable in _helm():
		c.begin_interaction()
	_sync_ballast_hold()


func end_interaction() -> void:
	_release_ballast()
	for c: Interactable in _helm():
		c.end_interaction()
	super.end_interaction()


## Local pilot input, each -1..1: throttle (+ ahead), rudder (+ starboard),
## planes (+ dives); ballast: +1 blow, -1 flood, 0 neither.
func drive(throttle_dir: float, rudder_dir: float, planes_dir: float, ballast_dir: float, delta: float) -> void:
	if not is_held_locally():
		return
	throttle.drive_input(throttle_dir, delta)
	rudder.drive_input(rudder_dir, delta)
	planes.drive_input(planes_dir, delta)
	_sync_ballast_hold()
	if _has_ballast:
		var step: float = BALLAST_KEY_RATE * delta
		blow_valve.drive_to(move_toward(blow_valve.get_normalized(), 1.0 if ballast_dir > 0.0 else 0.0, step), true)
		flood_valve.drive_to(move_toward(flood_valve.get_normalized(), 1.0 if ballast_dir < 0.0 else 0.0, step), true)


func seat_transform() -> Transform3D:
	return sit_point.global_transform if sit_point != null else global_transform


func interaction_hint() -> String:
	return "press E to take the helm"


## Controls hint shown while seated.
static func helm_hint() -> String:
	var hint: String = "W/S throttle · A/D rudder · R/F planes · E to stand"
	if DevSettings.single_player:
		hint += " · Num8 blow · Num2 flood"
	return hint


func _helm() -> Array[Interactable]:
	var out: Array[Interactable] = []
	for c: Interactable in [throttle, rudder, planes]:
		if c != null:
			out.append(c)
	return out


## Takes or lets go of the ballast valves as single-player mode changes.
func _sync_ballast_hold() -> void:
	var want: bool = DevSettings.single_player and is_held_locally() and flood_valve != null and blow_valve != null
	if want and not _has_ballast:
		_has_ballast = true
		flood_valve.begin_interaction()
		blow_valve.begin_interaction()
	elif not want and _has_ballast:
		_release_ballast()


func _release_ballast() -> void:
	if not _has_ballast:
		return
	_has_ballast = false
	# Close both on the way out so nothing keeps flooding unattended.
	flood_valve.drive_to(0.0, true)
	blow_valve.drive_to(0.0, true)
	flood_valve.end_interaction()
	blow_valve.end_interaction()
