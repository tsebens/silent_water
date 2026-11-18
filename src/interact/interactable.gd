class_name Interactable
extends Node3D
## Base for every physical control (lever, valve, switch...).
##
## Networking: a client asks the host to grab the control, then streams
## requested values while dragging. The local holder sees its own movement
## immediately (prediction); the host clamps, accepts only the holder's
## requests, and broadcasts the result. Only one player can hold a control at a
## time, which resolves conflicting input. Releasing sends a reliable final value.
##
## Subclasses override [method _drag_to_value] (mouse drag -> new value) and
## [method _apply_visual] (value -> pose of the mesh).

signal value_changed(value: float)
signal holder_changed(peer_id: int)

@export var min_value: float = 0.0
@export var max_value: float = 1.0
@export var initial_value: float = 0.0
@export var noise_profile: NoiseProfile
## Shown in debug output and later on labels.
@export var label: String = ""

var state: InteractableState

var _local_grabbing: bool = false


func _init() -> void:
	state = InteractableState.new()


func _ready() -> void:
	state = InteractableState.new(min_value, max_value, initial_value)
	add_to_group(&"interactables")
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	_apply_visual(state.value)


func _physics_process(delta: float) -> void:
	state.tick(delta)


## Current value (predicted for the local holder, authoritative otherwise).
func get_value() -> float:
	return state.value


func get_normalized() -> float:
	return state.normalized()


## Noise this control is making right now, in linear intensity units.
func get_noise_intensity() -> float:
	if noise_profile == null:
		return 0.0
	return noise_profile.intensity_for_rate(state.normalized_rate)


func is_held_locally() -> bool:
	return _local_grabbing


# --- Local player API -------------------------------------------------------

func begin_interaction() -> void:
	_local_grabbing = true
	_rpc_grab.rpc_id(1)


func drag(relative: Vector2) -> void:
	if not _local_grabbing:
		return
	var target: float = state.clamp_value(_drag_to_value(state.value, relative))
	if is_equal_approx(target, state.value):
		return
	_set_local(target)
	if not multiplayer.is_server():
		_rpc_request.rpc_id(1, target)
	else:
		_host_apply(Net.local_id(), target)


func end_interaction() -> void:
	if not _local_grabbing:
		return
	_local_grabbing = false
	_rpc_release.rpc_id(1, state.value)


## Host only: sets the value from game logic (not a player), e.g. a reset.
func host_set_value(v: float) -> void:
	assert(multiplayer.is_server())
	state.set_value(v)
	_after_change()
	_rpc_value.rpc(state.value, true)


# --- Subclass hooks ---------------------------------------------------------

## Maps a mouse drag to a new value. Override.
func _drag_to_value(current: float, _relative: Vector2) -> float:
	return current


## Updates meshes for a value. Override.
func _apply_visual(_v: float) -> void:
	pass


# --- Networking --------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _rpc_grab() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _sender()
	var granted: bool = state.try_grab(sender)
	_rpc_holder.rpc(state.holder)
	if not granted:
		# Tell the loser the true value so its prediction snaps back.
		_rpc_value.rpc_id(sender, state.value, true)


@rpc("any_peer", "call_local", "reliable")
func _rpc_release(final_value: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _sender()
	if state.holder != sender:
		return
	_host_apply(sender, final_value)
	state.release(sender)
	_rpc_holder.rpc(state.holder)
	_rpc_value.rpc(state.value, true)


@rpc("any_peer", "unreliable_ordered")
func _rpc_request(v: float) -> void:
	if multiplayer.is_server():
		_host_apply(_sender(), v)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_value_stream(v: float) -> void:
	_receive_value(v, false)


@rpc("authority", "call_remote", "reliable")
func _rpc_value(v: float, authoritative: bool) -> void:
	_receive_value(v, authoritative)


@rpc("authority", "call_local", "reliable")
func _rpc_holder(peer_id: int) -> void:
	if state.holder == peer_id:
		return
	state.holder = peer_id
	if peer_id != Net.local_id():
		_local_grabbing = false
	holder_changed.emit(peer_id)


func _host_apply(sender: int, v: float) -> void:
	if not state.request(sender, v):
		return
	_after_change()
	_rpc_value_stream.rpc(state.value)


func _receive_value(v: float, authoritative: bool) -> void:
	# The local holder trusts its own prediction while dragging; streamed echoes
	# are ignored. Reliable (authoritative) values always win.
	if _local_grabbing and not authoritative:
		return
	if _local_grabbing and authoritative and state.holder == Net.local_id():
		return
	_set_local(v)


func _set_local(v: float) -> void:
	state.set_value(v)
	_after_change()


func _after_change() -> void:
	_apply_visual(state.value)
	value_changed.emit(state.value)


func _sender() -> int:
	var id: int = multiplayer.get_remote_sender_id()
	return id if id != 0 else Net.local_id()


func _on_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_holder.rpc_id(peer_id, state.holder)
		_rpc_value.rpc_id(peer_id, state.value, true)


func _on_peer_left(peer_id: int) -> void:
	if multiplayer.is_server() and state.release(peer_id):
		_rpc_holder.rpc(state.holder)
