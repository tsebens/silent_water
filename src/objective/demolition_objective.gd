class_name DemolitionObjective
extends Node
## Host-side decommission objective: shut down the reactor, arm every charge point, then leave before the fuse runs
## out. States run in order (see [enum State]). The reactor's own switch drives [method set_reactor_on]; charge
## points call [method arm_charge] / [method disarm_charge]. The host owns the state and replicates a snapshot.

signal reactor_shut_down
signal charge_armed(index: int)
signal charge_disarmed(index: int)
signal countdown_started(fuse_sec: float)
signal detonated
signal failed(reason: StringName)
signal state_changed(state: State)

enum State { REACTOR_ON, REACTOR_OFF, CHARGES_ARMED, COUNTDOWN, DETONATED, FAILED }

## Number of charge points that must be armed.
@export var charge_count: int = 3
## Seconds from the last charge being armed to detonation. Tuned by playtest.
@export var fuse_sec: float = 90.0
## Set on a client's copy: it never advances the state itself.
var simulate_client: bool = false

var state: State = State.REACTOR_ON
var fuse_left: float = 0.0
var fail_reason: StringName = &""

var _armed: PackedByteArray = PackedByteArray()
var _reactor_on: bool = true


func _ready() -> void:
	reset()


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()


func reset() -> void:
	_armed.resize(charge_count)
	_armed.fill(0)
	_reactor_on = true
	state = State.REACTOR_ON
	fuse_left = 0.0
	fail_reason = &""


func is_reactor_on() -> bool:
	return _reactor_on


func is_armed(index: int) -> bool:
	return index >= 0 and index < _armed.size() and _armed[index] != 0


func armed_count() -> int:
	var n: int = 0
	for c: int in _armed:
		n += c
	return n


func is_finished() -> bool:
	return state == State.DETONATED or state == State.FAILED


## True when charges may be armed: the reactor is down and the objective is still live.
func can_arm() -> bool:
	return state == State.REACTOR_OFF or state == State.CHARGES_ARMED or state == State.COUNTDOWN


## Driven by the reactor's switch. Turning it back on before the countdown just undoes the shutdown; once charges
## are armed, restarting the reactor fails the objective.
func set_reactor_on(on: bool) -> void:
	if not _is_host() or is_finished() or on == _reactor_on:
		return
	_reactor_on = on
	if not on:
		if state == State.REACTOR_ON:
			_set_state(State.REACTOR_OFF)
			reactor_shut_down.emit()
	elif armed_count() > 0 or state == State.COUNTDOWN:
		_fail(&"reactor_restarted")
	else:
		_set_state(State.REACTOR_ON)
	_broadcast()


## Arms charge [param index]. Refused (false) while the reactor is on. Arming the last one starts the fuse.
func arm_charge(index: int) -> bool:
	if not _is_host() or not can_arm() or index < 0 or index >= _armed.size() or _armed[index] != 0:
		return false
	_armed[index] = 1
	charge_armed.emit(index)
	if armed_count() == _armed.size():
		_set_state(State.CHARGES_ARMED)
		fuse_left = fuse_sec
		_set_state(State.COUNTDOWN)
		countdown_started.emit(fuse_sec)
	_broadcast()
	return true


## Disarming a charge after the reactor is down fails the objective.
func disarm_charge(index: int) -> bool:
	if not _is_host() or is_finished() or not is_armed(index):
		return false
	_armed[index] = 0
	charge_disarmed.emit(index)
	_fail(&"charge_disarmed")
	_broadcast()
	return true


## Aborts a running countdown. Fails the objective.
func abort_countdown() -> void:
	if _is_host() and state == State.COUNTDOWN:
		_fail(&"countdown_aborted")
		_broadcast()


## Advance the fuse by [param delta] seconds.
func step(delta: float) -> void:
	if not _is_host() or state != State.COUNTDOWN:
		return
	fuse_left = maxf(fuse_left - delta, 0.0)
	if fuse_left <= 0.0:
		_set_state(State.DETONATED)
		detonated.emit()
		_broadcast()


func _physics_process(delta: float) -> void:
	step(delta)


func _fail(reason: StringName) -> void:
	fail_reason = reason
	fuse_left = 0.0
	_set_state(State.FAILED)
	failed.emit(reason)


func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


# -- Replication (host authoritative) ---------------------------------------

func snapshot() -> Dictionary:
	return {"state": state as int, "armed": _armed.duplicate(), "reactor_on": _reactor_on, "fuse": fuse_left, "reason": fail_reason}


func apply_snapshot(snap: Dictionary) -> void:
	_armed = (snap["armed"] as PackedByteArray).duplicate()
	_reactor_on = bool(snap["reactor_on"])
	fuse_left = float(snap["fuse"])
	fail_reason = snap["reason"] as StringName
	_set_state(int(snap["state"]) as State)


func _broadcast() -> void:
	if _is_host() and _online():
		_rpc_snapshot.rpc(snapshot())


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)
