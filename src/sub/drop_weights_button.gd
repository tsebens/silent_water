class_name DropWeightsButton
extends Node
## The drop-weights release. With the `guard` open (upper half of its range) a
## press of `button`, once per dive, sheds the weights' mass from the sub model
## so it turns buoyant and rises. Emits [signal released] and records the drop
## in the [SessionLog].
##
## Host-authoritative: any peer asks via [method request_release]; the host
## applies it once and tells every peer ([method _rpc_state]). Joining peers get
## the current state. [method reset] re-arms it for the next dive.

signal released

## Two-position hinge that must be open for a press to count.
@export var guard: Interactable
## The press itself (a PushButton).
@export var button: Interactable
## Unset: the first node in the sub_controller group.
@export var controller: SubController
## Unset: the first node in the session_log group.
@export var session_log: SessionLog
## Optional: re-arms on the director's dive_reset.
@export var director: DiveDirector
## Tests: act as the host without a multiplayer peer.
var simulate_host: bool = false

var _released: bool = false


func _ready() -> void:
	if controller == null:
		controller = get_tree().get_first_node_in_group(&"sub_controller") as SubController
	if session_log == null:
		session_log = get_tree().get_first_node_in_group(&"session_log") as SessionLog
	if button != null:
		button.value_changed.connect(_on_button_changed)
	if director != null:
		director.dive_reset.connect(reset)
	if _is_host() and _online():
		Net.peer_joined.connect(_on_peer_joined)


func is_released() -> bool:
	return _released


func guard_open() -> bool:
	return guard != null and guard.get_normalized() >= 0.5


## Host: re-arms for the next dive.
func reset() -> void:
	_released = false
	if _is_host() and _online():
		_rpc_state.rpc(false)


## Any peer: ask for the release. Ignored while the guard is closed or once released.
func request_release() -> void:
	if _released or not guard_open():
		return
	if _is_host():
		_apply()
	elif _online():
		_rpc_request.rpc_id(1)


func _on_button_changed(value: float) -> void:
	# Only a press by the player holding the button is a request.
	if button == null or not button.is_held_locally():
		return
	if value >= (button.min_value + button.max_value) * 0.5:
		request_release()


func _apply() -> void:
	if _released or not _is_host():
		return
	_released = true
	var mass: float = 0.0
	var depth: float = 0.0
	if controller != null:
		mass = controller.model.shed_drop_weights()
		depth = controller.model.depth()
	if session_log != null:
		session_log.record_drop_weights(mass, depth)
	released.emit()
	if _online():
		_rpc_state.rpc(true)


@rpc("any_peer", "reliable")
func _rpc_request() -> void:
	# The guard is read here too: the request only counts if it is open on the host.
	if _is_host() and guard_open():
		_apply()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(released_now: bool) -> void:
	var was: bool = _released
	_released = released_now
	if released_now and not was:
		released.emit()


func _on_peer_joined(peer_id: int) -> void:
	if _released and _is_host() and _online():
		_rpc_state.rpc_id(peer_id, true)


func _is_host() -> bool:
	return simulate_host or (is_inside_tree() and multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()
