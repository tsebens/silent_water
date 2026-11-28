class_name DorsalHatch
extends Node
## The dorsal hatch in the conning tower: the surface hatch, and the hatch that mates to a station's docking
## collar. Host-authoritative and replicated like [LockoutTrunk] (a snapshot on every change, a full one to each
## joining peer; clients ask through [method request_open] and [method request_close] and only read).
##
## It opens only when the sub is at the surface (depth under [member surface_depth_m]) or [member mated] (the
## docking arc sets it). It refuses to open underwater, and if the sub dives while it is open it closes itself and
## sounds the alarm chime. Dry-only: it is not an airlock, so nobody goes out through it while submerged.
## Operated by hand: the wheel ([member wheel]) turned past [constant END_FRACTION] opens it, back closes it.
## The tower's [member transit] is climbable only while the hatch is open.
##
## Noise: one clank per move ([member clank_emitter]); the forced close adds the chime ([member chime_emitter]).

## A wheel counts as turned to an end past this fraction of its range.
const END_FRACTION: float = 0.9

## The hatch opened (by a person, or replicated to this peer).
signal hatch_opened
## The hatch closed (by a person, by a dive, or replicated to this peer).
signal hatch_closed

## The sub counts as surfaced above this depth (m below the waterline).
@export var surface_depth_m: float = 1.0
@export var wheel: Valve
@export var transit: ClimbTransit
@export var clank_emitter: SoundEmitter
@export var chime_emitter: SoundEmitter

## True while the hatch is open.
var is_open: bool = false
## True while the sub is mated to a docking collar; set by the docking arc, on the host.
var mated: bool = false
## Test seam: a depth (m) to use in place of the sub's physics state. Negative means unset.
var depth_override: float = -1.0
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false

var _controller: SubController


func _ready() -> void:
	if wheel != null:
		wheel.value_changed.connect(_on_wheel)
	if transit != null:
		transit.gate = Callable(self, "_climbable")
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _climbable() -> bool:
	return is_open


## The sub's depth (m below the waterline): the override if set, else the sub controller's physics state.
## Unknown (no controller) counts as deep, so the hatch stays shut.
func depth() -> float:
	if depth_override >= 0.0:
		return depth_override
	if _controller == null and is_inside_tree():
		_controller = get_tree().get_first_node_in_group(&"sub_controller") as SubController
	return _controller.model.depth() if _controller != null else INF


## True when the sub is surfaced or mated, so the hatch may open.
func can_open() -> bool:
	return mated or depth() < surface_depth_m


## Ask to open. The host opens it if allowed; a client forwards the request. Returns true if it opened.
func request_open() -> bool:
	if not _is_host():
		if is_inside_tree() and Net.is_online():
			_rpc_request.rpc_id(1, true)
		return false
	if is_open or not can_open():
		return false
	_set_open(true)
	return true


## Ask to close. The host closes it; a client forwards the request. Returns true if it closed.
func request_close() -> bool:
	if not _is_host():
		if is_inside_tree() and Net.is_online():
			_rpc_request.rpc_id(1, false)
		return false
	if not is_open:
		return false
	_set_open(false)
	return true


## Host: the docking arc sets whether the sub is mated.
func set_mated(value: bool) -> void:
	if not _is_host() or mated == value:
		return
	mated = value
	_changed()


func _physics_process(_delta: float) -> void:
	check_dive()


## Host: an open hatch closes itself, with the chime, once the sub is neither surfaced nor mated.
## Returns true if it closed.
func check_dive() -> bool:
	if not _is_host() or not is_open or can_open():
		return false
	_set_open(false)
	if chime_emitter != null:
		chime_emitter.world_position = _position()
		chime_emitter.fire()
	if wheel != null and wheel.state != null:
		wheel.state.set_value_silent(wheel.min_value)  # the wheel goes back with the hatch
	return true


func _set_open(open: bool) -> void:
	is_open = open
	if open:
		hatch_opened.emit()
	else:
		hatch_closed.emit()
	if clank_emitter != null:
		clank_emitter.world_position = _position()
		clank_emitter.fire()
	_changed()


func _position() -> Vector3:
	var n: Node3D = get_parent() as Node3D
	return n.global_position if n != null and n.is_inside_tree() else Vector3.ZERO


func _on_wheel(v: float) -> void:
	var f: float = inverse_lerp(wheel.min_value, wheel.max_value, v)
	if f >= END_FRACTION:
		request_open()
	elif f <= 1.0 - END_FRACTION:
		request_close()


func _changed() -> void:
	if _is_host() and is_inside_tree() and Net.is_online():
		_rpc_snapshot.rpc(snapshot())


# -- Replication -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {"open": is_open, "mated": mated}


func apply_snapshot(snap: Dictionary) -> void:
	mated = bool(snap["mated"])
	var open: bool = bool(snap["open"])
	if open != is_open:
		is_open = open
		if open:
			hatch_opened.emit()
		else:
			hatch_closed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(open: bool) -> void:
	if not _is_host():
		return
	if open:
		request_open()
	else:
		request_close()


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_snapshot.rpc_id(peer_id, snapshot())
