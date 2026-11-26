class_name ProbeObjective
extends Node
## Host-side probe job. A list of points (Node3Ds in [member points], or group [code]probe_points[/code]); each is
## a place in the water at a depth. The winch lowers the probe below the hull ([member lowered], metres); the probe
## tip is at the sub's depth plus [member lowered]. When the sub is within [constant RADIUS_M] of a point (across the
## surface) and the tip is within [constant DEPTH_BAND_M] of the point's depth, the sub is still, and the probe is
## down, the hold builds; after [constant HOLD_SEC] the reading is logged and the point is done. Moving, leaving the
## band or raising the probe resets the hold. Quiet: only the winch whirs while the reel turns. Complete when every
## point is logged.

signal reading_logged(point: Node3D)
signal probe_completed

## How far the winch pays out, metres.
const MAX_LOWER_M: float = 60.0
## Winch speed, metres per second.
const LOWER_SPEED: float = 6.0
const RADIUS_M: float = 12.0
const DEPTH_BAND_M: float = 5.0
## At or under this speed the sub counts as still.
const MAX_SPEED: float = 0.3
const HOLD_SEC: float = 6.0
## Reel angle per metre of line, radians.
const REEL_RAD_PER_M: float = 0.5
## Winch whir while the reel turns (~55 dB): quiet.
const WINCH_INTENSITY: float = 0.0000003

@export var controller: SubController
@export var points: Array[Node3D] = []
## A PROBE science module that arms the winch (set by the module).
var module: ScienceModule

## Line paid out, metres.
var lowered: float = 0.0
## Winch command: -1 raise, 0 stop, 1 lower.
var winch_dir: int = 0
var done: Array[Node3D] = []
var hold: float = 0.0
var complete: bool = false

var _moving: bool = false


func _ready() -> void:
	add_to_group(&"noise_sources")
	add_to_group(&"probe_objectives")


func probe_on() -> bool:
	return not complete and module != null and module.armed


func all_points() -> Array[Node3D]:
	var out: Array[Node3D] = points.duplicate()
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(&"probe_points"):
			if n is Node3D and not out.has(n):
				out.append(n as Node3D)
	return out


func sub_position() -> Vector3:
	return controller.model.position if controller != null else Vector3.ZERO


func point_position(p: Node3D) -> Vector3:
	return p.global_position if p.is_inside_tree() else p.position


## Depth of the probe tip, metres below the surface.
func tip_depth() -> float:
	var d: float = controller.model.depth() if controller != null else 0.0
	return d + lowered


## Distance across the surface from the sub to [param p].
func range_to(p: Node3D) -> float:
	var a: Vector3 = sub_position()
	var b: Vector3 = point_position(p)
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## The point depth, metres below the surface.
func point_depth(p: Node3D) -> float:
	return maxf(-point_position(p).y, 0.0)


## True when the probe is down at [param p]: in radius and the tip in the depth band.
func in_band(p: Node3D) -> bool:
	return range_to(p) <= RADIUS_M and absf(tip_depth() - point_depth(p)) <= DEPTH_BAND_M


func is_still() -> bool:
	return controller == null or absf(controller.speed) <= MAX_SPEED


## The first unfinished point whose band the probe is in, or null.
func target() -> Node3D:
	for p: Node3D in all_points():
		if not done.has(p) and in_band(p):
			return p
	return null


func hold_progress() -> float:
	return clampf(hold / HOLD_SEC, 0.0, 1.0)


## Reel rotation, radians, following the line out.
func reel_angle() -> float:
	return lowered * REEL_RAD_PER_M


## Depth counter value, metres of line out.
func counter() -> float:
	return lowered


func noise_intensity() -> float:
	return WINCH_INTENSITY if _moving else 0.0


func noise_breakdown() -> Dictionary:
	return {"probe winch": noise_intensity()}


func readout(property: StringName) -> float:
	return float(done.size()) / float(maxi(all_points().size(), 1)) if property == &"progress" else 0.0


func reset() -> void:
	done.clear()
	complete = false
	hold = 0.0
	lowered = 0.0
	winch_dir = 0
	_moving = false
	if module != null:
		module.armed = false


## Moves the line by the winch for [param delta] seconds in [member winch_dir].
func step_winch(delta: float) -> void:
	var before: float = lowered
	if probe_on() or winch_dir < 0:
		lowered = clampf(lowered + float(winch_dir) * LOWER_SPEED * delta, 0.0, MAX_LOWER_M)
	_moving = not is_equal_approx(before, lowered)


## Advances the hold for [param delta] seconds; logs the reading when it completes.
func step_hold(delta: float) -> void:
	var t: Node3D = target() if probe_on() and lowered > 0.0 else null
	if t == null or not is_still():
		hold = 0.0
		return
	hold += delta
	if hold < HOLD_SEC:
		return
	hold = 0.0
	done.append(t)
	reading_logged.emit(t)
	var log: Node = get_tree().get_first_node_in_group(&"session_log") if is_inside_tree() else null
	if log != null:
		log.call(&"write", "PROBE %s  depth %.0f m" % [t.name, point_depth(t)])
	if done.size() >= all_points().size():
		complete = true
		module.armed = false
		probe_completed.emit()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	step_winch(delta)
	step_hold(delta)
