class_name WatertightDoor
extends Node3D
## A door wheel. Interacting toggles the door between two zones in [member zones]. Host-authoritative: a client
## asks the host, the host applies it ([IsolationRules.toggle_door], which makes the noise) and replicates the
## whole [FloodZoneState] to everyone.

signal toggled(open: bool)

## Door key in the model: "<zone a>|<zone b>" (see [method FloodZones.door_keys]).
@export var door_key: String = ""
var zones: FloodZones = null


func _ready() -> void:
	add_to_group(&"watertight_doors")


func is_open() -> bool:
	return zones != null and zones.is_door_open(door_key)


## The interact: host applies directly, a client asks the host.
func interact() -> void:
	if zones == null:
		return
	if not Net.is_online() or multiplayer.is_server():
		_apply_toggle()
	else:
		_rpc_request_toggle.rpc_id(1)


func _apply_toggle() -> void:
	if IsolationRules.toggle_door(zones, door_key, global_position, self):
		toggled.emit(is_open())
		if Net.is_online():
			_rpc_state.rpc(zones.state.to_dict())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_toggle() -> void:
	if multiplayer.is_server():
		_apply_toggle()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(d: Dictionary) -> void:
	if zones != null:
		zones.state = FloodZoneState.from_dict(d)
		toggled.emit(is_open())


func interaction_hint() -> String:
	return "turn the wheel to open" if not is_open() else "turn the wheel to close"
