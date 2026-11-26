class_name PilotSeat
extends StationSeat
## The pilot's chair. Sitting in it (E) locks the player to [member sit_point]
## and gives them the helm: W/S throttle, A/D rudder, R/F dive planes. The
## pilot also has the ballast keys: Numpad 8 blows and Numpad 2 floods while
## held (Decision #445). The mouse wheel zooms the pilot hologram.
## Only one pilot at a time (the Interactable grab lock).

## How fast held ballast keys open the valves (fraction per second).
const BALLAST_KEY_RATE: float = 2.0
## Hologram scale change per wheel step.
const ZOOM_STEP: float = 1.15

@export var throttle: SpringAxis
@export var rudder: SpringAxis
@export var planes: SpringAxis
@export var flood_valve: Interactable
@export var blow_valve: Interactable
## The pilot hologram the mouse wheel zooms.
@export var holo: HoloMap

var _has_ballast: bool = false


func begin_interaction() -> void:
	super.begin_interaction()
	for c: Interactable in _helm():
		c.begin_interaction()


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
	_sync_ballast_hold(ballast_dir)
	if _has_ballast:
		var step: float = BALLAST_KEY_RATE * delta
		blow_valve.drive_to(move_toward(blow_valve.get_normalized(), 1.0 if ballast_dir > 0.0 else 0.0, step), true)
		flood_valve.drive_to(move_toward(flood_valve.get_normalized(), 1.0 if ballast_dir < 0.0 else 0.0, step), true)


## One wheel step: up zooms in (smaller scale), down zooms out. Only the
## local pilot, and only with a hologram. Returns whether it zoomed.
func zoom_wheel(up: bool) -> bool:
	if not is_held_locally() or holo == null:
		return false
	holo.set_zoom(holo.meters_per_unit / ZOOM_STEP if up else holo.meters_per_unit * ZOOM_STEP)
	return true


func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if zoom_wheel(mb.button_index == MOUSE_BUTTON_WHEEL_UP):
		get_viewport().set_input_as_handled()


func interaction_hint() -> String:
	return "press E to take the helm"


func station_name() -> String:
	return "HELM"


func seated_hint() -> String:
	return helm_hint()


## Controls hint shown while seated.
static func helm_hint() -> String:
	return "W/S throttle · A/D rudder · R/F planes · Num8/PgUp blow · Num2/PgDn flood · wheel zoom · E to stand"


func _helm() -> Array[Interactable]:
	var out: Array[Interactable] = []
	for c: Interactable in [throttle, rudder, planes]:
		if c != null:
			out.append(c)
	return out


## Takes the ballast valves while a ballast key is down, and lets them go once
## the keys are up and both have closed, so a crewmate can turn them otherwise.
func _sync_ballast_hold(ballast_dir: float) -> void:
	if not is_held_locally() or flood_valve == null or blow_valve == null:
		_release_ballast()
	elif not _has_ballast and absf(ballast_dir) > 0.01:
		_has_ballast = true
		flood_valve.begin_interaction()
		blow_valve.begin_interaction()
	elif _has_ballast and absf(ballast_dir) <= 0.01 \
			and flood_valve.get_normalized() <= 0.01 and blow_valve.get_normalized() <= 0.01:
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
