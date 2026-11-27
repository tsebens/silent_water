class_name GuardedSwitch
extends SwitchLever
## A [SwitchLever] under a hinged cap. From off with the cap closed, one click
## lifts the cap (the value is unchanged); a second click sets the switch on and
## the cap stays open while it is on. One click from on sets it off and closes
## the cap. A cap lifted over an off switch drops after [member drop_timeout]
## seconds untouched.
##
## The cap state is host-authoritative and replicated like the value: the
## holder asks the host, the host applies it and tells every peer.

signal cap_changed(open: bool)

## Seconds an untouched lifted cap over an off switch stays up before dropping.
@export var drop_timeout: float = 5.0
## Cap hinge angle when open (degrees, about X). Closed is 0.
@export var cap_open_deg: float = -100.0
## Hinge pivot of the cap. Unset: the child node named `Cap`.
@export var cap: Node3D

var cap_open: bool = false
var _open_for: float = 0.0


func _ready() -> void:
	super._ready()
	if cap == null:
		cap = get_node_or_null("Cap") as Node3D
	_apply_cap()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if multiplayer.is_server():
		step_cap(delta)


## Host: advances the auto-drop timer by [param delta] s.
func step_cap(delta: float) -> void:
	if not cap_open or _is_on():
		_open_for = 0.0
		return
	if state.holder != InteractableState.NO_HOLDER:
		_open_for = 0.0
		return
	_open_for += delta
	if _open_for >= drop_timeout:
		_host_set_cap(false)


func click_action() -> void:
	if not cap_open:
		_request_cap(true)
	elif _is_on():
		_request_cap(false)
		drive_to(min_value)
	else:
		drive_to(max_value)


func interaction_hint() -> String:
	return "click to switch" if cap_open else "click to lift the cap"


func _is_on() -> bool:
	return get_value() >= (min_value + max_value) * 0.5


func _request_cap(open: bool) -> void:
	if multiplayer.is_server():
		_host_set_cap(open)
	else:
		_set_cap_local(open)
		_rpc_cap_request.rpc_id(1, open)


func _host_set_cap(open: bool) -> void:
	_set_cap_local(open)
	_rpc_cap.rpc(open)


func _set_cap_local(open: bool) -> void:
	_open_for = 0.0
	if open == cap_open:
		return
	cap_open = open
	_apply_cap()
	cap_changed.emit(cap_open)


func _apply_cap() -> void:
	if cap != null:
		cap.rotation.x = deg_to_rad(cap_open_deg) if cap_open else 0.0


@rpc("any_peer", "reliable")
func _rpc_cap_request(open: bool) -> void:
	if multiplayer.is_server() and state.holder == _sender():
		_host_set_cap(open)


@rpc("authority", "call_remote", "reliable")
func _rpc_cap(open: bool) -> void:
	_set_cap_local(open)


func _on_peer_joined(peer_id: int) -> void:
	super._on_peer_joined(peer_id)
	if multiplayer.is_server():
		_rpc_cap.rpc_id(peer_id, cap_open)
