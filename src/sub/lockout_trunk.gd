class_name LockoutTrunk
extends Node
## The lock-out trunk: a host-authoritative, replicated state machine for the diver's
## airlock. Top hatch above, bottom hatch to the sea. No scene wiring: the wiring arc
## listens to the signals and drives noise from [method pump_running] and [signal hatch_moved].
##
## Transitions not allowed by the table in #918 are refused and change nothing. The top
## hatch can always be opened from inside once [code]DRY_SEALED[/code], and a flooded
## trunk can always be drained, so nobody is sealed in without a way out.
##
## Replication follows [SurvivorsAboard]: a snapshot on every change and a full one to
## each joining peer. Clients ask the host through [method request]; they only read.

enum State {
	DRY_OPEN,
	DRY_SEALED,
	FLOODING,
	FLOODED,
	BOTTOM_OPEN,
	BOTTOM_CLOSED_FLOODED,
	DRAINING,
}

enum Action { SEAL_TOP, OPEN_TOP, START_FLOOD, START_DRAIN, OPEN_BOTTOM, CLOSE_BOTTOM }

const NO_OCCUPANT: int = 0

signal state_changed(new_state: State)
## The bottom hatch opened with an occupant: they go out.
signal diver_exited(occupant: int)
## The bottom hatch closed with an occupant: they came back in.
signal diver_entered(occupant: int)
## A hatch moved: [param hatch] is [code]&"top"[/code] or [code]&"bottom"[/code].
signal hatch_moved(hatch: StringName, open: bool)

## Seconds the pumps take to flood the trunk.
@export var flood_time: float = 15.0
## Seconds the pumps take to drain the trunk.
@export var drain_time: float = 15.0
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false

var state: State = State.DRY_OPEN
## Seconds spent in FLOODING or DRAINING so far.
var progress: float = 0.0
## Who is inside (a player id), or [constant NO_OCCUPANT].
var occupant: int = NO_OCCUPANT

## Allowed transitions: state -> action -> next state.
const _TABLE: Dictionary = {
	State.DRY_OPEN: {Action.SEAL_TOP: State.DRY_SEALED},
	State.DRY_SEALED: {Action.OPEN_TOP: State.DRY_OPEN, Action.START_FLOOD: State.FLOODING},
	State.FLOODED: {Action.OPEN_BOTTOM: State.BOTTOM_OPEN, Action.START_DRAIN: State.DRAINING},
	State.BOTTOM_OPEN: {Action.CLOSE_BOTTOM: State.FLOODED},
}


func _ready() -> void:
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func seal_top() -> bool:
	return request(Action.SEAL_TOP)


func open_top() -> bool:
	return request(Action.OPEN_TOP)


func start_flood() -> bool:
	return request(Action.START_FLOOD)


func start_drain() -> bool:
	return request(Action.START_DRAIN)


func open_bottom() -> bool:
	return request(Action.OPEN_BOTTOM)


func close_bottom() -> bool:
	return request(Action.CLOSE_BOTTOM)


func can(action: Action) -> bool:
	return _TABLE.get(state, {}).has(action)


## True while the pumps run.
func pump_running() -> bool:
	return state == State.FLOODING or state == State.DRAINING


## Fraction through the current pump run, 0 when the pumps are idle.
func pump_fraction() -> float:
	if state == State.FLOODING:
		return clampf(progress / maxf(flood_time, 0.001), 0.0, 1.0)
	if state == State.DRAINING:
		return clampf(progress / maxf(drain_time, 0.001), 0.0, 1.0)
	return 0.0


## Ask for [param action]. The host applies it; a client forwards it. Returns true if
## the host applied it (always false on a client).
func request(action: Action) -> bool:
	if not _is_host():
		if is_inside_tree() and Net.is_online():
			_rpc_request.rpc_id(1, action as int)
		return false
	if not can(action):
		return false
	var next: State = _TABLE[state][action]
	_enter(next)
	if action == Action.SEAL_TOP or action == Action.OPEN_TOP:
		hatch_moved.emit(&"top", action == Action.OPEN_TOP)
	if action == Action.OPEN_BOTTOM:
		hatch_moved.emit(&"bottom", true)
		if occupant != NO_OCCUPANT:
			diver_exited.emit(occupant)
	elif action == Action.CLOSE_BOTTOM:
		hatch_moved.emit(&"bottom", false)
		if occupant != NO_OCCUPANT:
			diver_entered.emit(occupant)
	_changed()
	return true


## Host: someone steps in. Only while the top is open and the trunk is empty.
func enter(who: int) -> bool:
	if not _is_host() or state != State.DRY_OPEN or occupant != NO_OCCUPANT or who == NO_OCCUPANT:
		return false
	occupant = who
	_changed()
	return true


## Host: the occupant steps out through the top. Only while the top is open.
func leave() -> bool:
	if not _is_host() or state != State.DRY_OPEN or occupant == NO_OCCUPANT:
		return false
	occupant = NO_OCCUPANT
	_changed()
	return true


## Host: advance the pump timers by [param dt] seconds.
func step(dt: float) -> void:
	if not pump_running():
		return
	progress += dt
	if not _is_host():
		return
	if state == State.FLOODING and progress >= flood_time:
		_enter(State.FLOODED)
		_changed()
	elif state == State.DRAINING and progress >= drain_time:
		_enter(State.DRY_SEALED)
		_changed()


func _physics_process(delta: float) -> void:
	step(delta)


func _enter(next: State) -> void:
	state = next
	progress = 0.0
	state_changed.emit(next)


func _changed() -> void:
	if _is_host() and is_inside_tree() and Net.is_online():
		_rpc_snapshot.rpc(snapshot())


# -- Replication -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {"state": state as int, "progress": progress, "occupant": occupant,
		"flood": flood_time, "drain": drain_time}


func apply_snapshot(snap: Dictionary) -> void:
	var s: int = int(snap["state"])
	if s < 0 or s > State.DRAINING:
		return
	flood_time = float(snap["flood"])
	drain_time = float(snap["drain"])
	progress = float(snap["progress"])
	occupant = int(snap["occupant"])
	if s != state:
		state = s as State
		state_changed.emit(state)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(action: int) -> void:
	if not _is_host() or action < 0 or action > Action.CLOSE_BOTTOM:
		return
	request(action as Action)


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_snapshot.rpc_id(peer_id, snapshot())
