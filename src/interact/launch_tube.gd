class_name LaunchTube
extends Node
## A decoy launch tube: a [LoaderDrawer], a [DecoyCradle] in it and a prime lever.
##
## States: EMPTY, LOADED (a decoy seated and the drawer closed) and PRIMED (the
## prime lever down, the drawer locked shut). [method fire] sends a primed tube's
## decoy out: it spends [constant AIR_COST_FRACTION] of the ballast air, plays the
## launch thump, empties the tube, releases the lever and emits [signal fired].
##
## Host-authoritative: any peer asks via [method request_fire]; the host checks
## and runs it, then tells every peer the tube's state. Decoy items are local to
## their carrier, so priming is checked on the peer that pulls the lever (it can
## see its own drawer and cradle) and the host takes the primed flag from it.

enum State { EMPTY, LOADED, PRIMED }

## Share of the air tank's capacity one launch spends.
const AIR_COST_FRACTION: float = 0.05

## A tube was fired. [param exit_point] is the world position the decoy leaves from.
signal fired(exit_point: Vector3)
## A fire was refused (not primed, or short of air).
signal fire_refused(reason: String)
signal state_changed(state: State)

## Shown on the plate: FORE TUBE or STERN TUBE.
@export var tube_name: String = "FORE TUBE"
@export var drawer: LoaderDrawer
@export var cradle: DecoyCradle
## Prime lever (an Interactable): its max end is down, primed.
@export var prime_lever: Interactable
## Where the decoy leaves the hull. Unset: this tube's own position.
@export var exit_point: Node3D
## Plays the launch thump (a one-off SoundEmitter). Optional.
@export var emitter: SoundEmitter
## Optional lamps mirroring the three lamp bools.
@export var empty_lamp: IndicatorLamp
@export var loaded_lamp: IndicatorLamp
@export var primed_lamp: IndicatorLamp
## Unset: the first node in the sub_controller group.
@export var controller: SubController
## Tests: act as the host without a multiplayer peer.
var simulate_host: bool = false

var _primed: bool = false


func _ready() -> void:
	if controller == null and is_inside_tree():
		controller = get_tree().get_first_node_in_group(&"sub_controller") as SubController
	if drawer != null:
		drawer.value_changed.connect(_on_changed)
	if cradle != null:
		cradle.decoy_seated.connect(_on_changed)
		cradle.decoy_released.connect(_on_changed)
	if prime_lever != null:
		prime_lever.value_changed.connect(_on_lever_changed)
	if _is_host() and _online():
		Net.peer_joined.connect(_on_peer_joined)
	_refresh()


func state() -> State:
	if _primed:
		return State.PRIMED
	if cradle != null and cradle.is_occupied() and drawer != null and drawer.is_closed():
		return State.LOADED
	return State.EMPTY


func is_primed() -> bool:
	return _primed


func empty_lit() -> bool:
	return state() == State.EMPTY


func loaded_lit() -> bool:
	return state() == State.LOADED


func primed_lit() -> bool:
	return state() == State.PRIMED


## Air one launch spends (t).
func air_cost_t() -> float:
	var capacity: float = controller.model.air_capacity_t if controller != null else 60.0
	return capacity * AIR_COST_FRACTION


## Any peer: pull the lever. Refused with the drawer open, the cradle empty, or
## when already primed. Returns whether this peer accepted it.
func request_prime() -> bool:
	if state() != State.LOADED:
		return false
	if _is_host():
		_set_primed(true)
	elif _online():
		_set_primed(true)
		_rpc_request_prime.rpc_id(1)
	return true


## Any peer: fire the primed tube. The host decides.
func request_fire() -> void:
	if _is_host():
		fire()
	elif _online():
		_rpc_request_fire.rpc_id(1)


## Host: fires. Refused unless PRIMED and with enough air (the tube stays
## PRIMED). Returns whether it fired.
func fire() -> bool:
	if not _is_host():
		return false
	if not _primed:
		fire_refused.emit("not primed")
		return false
	if controller == null or not controller.spend_air(air_cost_t()):
		fire_refused.emit("not enough air")
		return false
	var at: Vector3 = exit_position()
	if emitter != null:
		emitter.world_position = at
		emitter.fire()
	if _online():
		_rpc_play_launch.rpc(at)
	_empty_tube()
	_set_primed(false)
	fired.emit(at)
	return true


func exit_position() -> Vector3:
	if exit_point != null and exit_point.is_inside_tree():
		return exit_point.global_position
	if exit_point != null:
		return exit_point.position
	return Vector3.ZERO


## Frees the seated decoy: it has left through the hull.
func _empty_tube() -> void:
	if cradle == null:
		return
	var d: DecoyItem = cradle.release()
	if d != null:
		d.queue_free()


func _set_primed(on: bool) -> void:
	if _primed == on:
		return
	_primed = on
	if drawer != null:
		drawer.locked = on
	_sync_lever()
	if _is_host() and _online():
		_rpc_state.rpc(on)
	_refresh()


## The lever stays down while primed and is up otherwise.
func _sync_lever() -> void:
	if prime_lever == null:
		return
	var want: float = prime_lever.max_value if _primed else prime_lever.min_value
	if is_equal_approx(prime_lever.get_value(), want):
		return
	if prime_lever.is_held_locally():
		prime_lever.drive_to(want, true)
	elif _is_host() and _online():
		prime_lever.host_set_value(want)
	else:
		prime_lever.state.set_value_silent(want)
		prime_lever._apply_visual(want)


func _on_lever_changed(value: float) -> void:
	if prime_lever == null or not prime_lever.is_held_locally():
		return
	var down: bool = value >= (prime_lever.min_value + prime_lever.max_value) * 0.5
	if down and not _primed:
		if not request_prime():
			prime_lever.drive_to(prime_lever.min_value, true)
	elif not down and _primed:
		prime_lever.drive_to(prime_lever.max_value, true)


func _on_changed(_arg: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	var s: State = state()
	if empty_lamp != null:
		empty_lamp.set_lit(s == State.EMPTY)
	if loaded_lamp != null:
		loaded_lamp.set_lit(s == State.LOADED)
	if primed_lamp != null:
		primed_lamp.set_lit(s == State.PRIMED)
	state_changed.emit(s)


@rpc("any_peer", "reliable")
func _rpc_request_prime() -> void:
	if _is_host():
		_set_primed(true)


@rpc("any_peer", "reliable")
func _rpc_request_fire() -> void:
	if _is_host():
		fire()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(primed: bool) -> void:
	if _primed and not primed:
		_empty_tube()
	_primed = primed
	if drawer != null:
		drawer.locked = primed
	_sync_lever()
	_refresh()


## Clients: hear the launch thump. Plays only; the noise event is the host's.
@rpc("authority", "call_remote", "reliable")
func _rpc_play_launch(at: Vector3) -> void:
	play_launch_sound(at)


## Plays the launch thump at [param at] without emitting a field noise event.
func play_launch_sound(at: Vector3) -> void:
	if emitter == null:
		return
	var was: bool = emitter.field_events
	emitter.field_events = false
	emitter.world_position = at
	emitter.fire()
	emitter.field_events = was


func _on_peer_joined(peer_id: int) -> void:
	if _primed and _is_host() and _online():
		_rpc_state.rpc_id(peer_id, true)


func _is_host() -> bool:
	return simulate_host or (is_inside_tree() and multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()
