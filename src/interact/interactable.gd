class_name Interactable
extends Node3D
## Base for every physical control (lever, valve, switch...).
##
## Networking: a client asks the host to grab the control, then streams
## requested values while dragging. The local holder sees its own movement
## immediately (prediction); the host clamps, accepts only the holder's
## requests, and broadcasts the result. Only one player can hold a control at a
## time, which resolves conflicting input. Releasing sends a reliable final value,
## and so does a held control that stops moving (see [constant SETTLE_TIME]).
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

## A held control that has been still this long (s) sends its value reliably.
## Streamed requests are unreliable, so the last few can be lost or arrive
## before the grab; a key-driven control that then stays put (a throttle at
## full) would leave the host behind for good without this.
const SETTLE_TIME: float = 0.1

var _local_grabbing: bool = false
## Client: a streamed request hasn't been confirmed by a reliable settle yet.
var _unsettled: bool = false
var _still_time: float = 0.0


func _init() -> void:
	state = InteractableState.new()


func _ready() -> void:
	state = InteractableState.new(min_value, max_value, initial_value)
	add_to_group(&"interactables")
	add_to_group(&"noise_sources")
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	_apply_visual(state.value)


func _physics_process(delta: float) -> void:
	state.tick(delta)
	if _unsettled and _local_grabbing:
		_still_time += delta
		if _still_time >= SETTLE_TIME:
			_unsettled = false
			_rpc_settle.rpc_id(1, state.value)


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


## Name shown at the aiming point.
func display_name() -> String:
	return label.to_upper() if label != "" else String(name).to_upper()


## How to use it, shown under the name. Override per control.
func interaction_hint() -> String:
	return "hold click and move the mouse"


## Noise system hook (polled on the host).
func noise_intensity() -> float:
	return get_noise_intensity()


func is_held_locally() -> bool:
	return _local_grabbing


# --- Local player API -------------------------------------------------------

func begin_interaction() -> void:
	_local_grabbing = true
	_rpc_grab.rpc_id(1)


func drag(relative: Vector2) -> void:
	if not _local_grabbing:
		return
	drive_to(_drag_to_value(state.value, relative))


## Moves a control the local player holds straight to [param target]. Used by
## controls driven by keys rather than mouse drags. [param silent]: actuated
## electrically, so moving it makes no handling noise.
func drive_to(target: float, silent: bool = false) -> void:
	if not _local_grabbing:
		return
	var clamped: float = state.clamp_value(target)
	if is_equal_approx(clamped, state.value):
		return
	_set_local(clamped, silent)
	if not multiplayer.is_server():
		_rpc_request.rpc_id(1, clamped, silent)
		_unsettled = true
		_still_time = 0.0
	else:
		_host_apply(Net.local_id(), clamped, silent)


## Runs when the holder releases the button, while still holding. A control
## that acts on a plain click (a switch) overrides this and calls [method drive_to].
func click_action() -> void:
	pass


func end_interaction() -> void:
	if not _local_grabbing:
		return
	var final_value: float = state.clamp_value(_release_value(state.value))
	if not is_equal_approx(final_value, state.value):
		_set_local(final_value)
	_local_grabbing = false
	_unsettled = false
	_rpc_release.rpc_id(1, final_value)


## Host only: sets the value from game logic (not a player), e.g. a reset.
## Makes no noise.
func host_set_value(v: float) -> void:
	assert(multiplayer.is_server())
	state.set_value_silent(v)
	_after_change()
	_rpc_value.rpc(state.value, true)


# --- Subclass hooks ---------------------------------------------------------

## Maps a mouse drag to a new value. Override.
func _drag_to_value(current: float, _relative: Vector2) -> float:
	return current


## Called when the host gave this control to someone else while the local
## player thought they held it. Override to undo local effects.
func _on_lost_hold() -> void:
	pass


## Value to settle on when released (e.g. snap to a detent). Override.
func _release_value(current: float) -> float:
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
func _rpc_request(v: float, silent: bool) -> void:
	if multiplayer.is_server():
		_host_apply(_sender(), v, silent)


## Reliable: the holder's value once its control has stopped moving. Silent:
## the movement already made its noise through the stream, and a catch-up
## after lost packets mustn't sound like a slam.
@rpc("any_peer", "reliable")
func _rpc_settle(v: float) -> void:
	if multiplayer.is_server():
		_host_apply(_sender(), v, true)


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
	if peer_id != Net.local_id() and _local_grabbing:
		_local_grabbing = false
		_on_lost_hold()
	holder_changed.emit(peer_id)


func _host_apply(sender: int, v: float, silent: bool = false) -> void:
	if state.holder != sender:
		return
	if silent:
		state.set_value_silent(v)
	elif not state.request(sender, v):
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


func _set_local(v: float, silent: bool = false) -> void:
	if silent:
		state.set_value_silent(v)
	else:
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
