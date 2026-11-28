class_name BreachPatch
extends Node3D
## A patch kit at a breached zone. Interacting clears the zone's breach flag in [member zones]. Host-
## authoritative: a client asks the host, the host applies it ([IsolationRules.patch_breach], which makes the
## noise) and replicates the whole [FloodZoneState] to everyone. Water already in the zone stays until pumped.

signal patched(zone: StringName)

@export var zone: StringName = &""
var zones: FloodZones = null


func _ready() -> void:
	add_to_group(&"breach_patches")


func is_breached() -> bool:
	return zones != null and zones.is_breached(zone)


func interact() -> void:
	if zones == null or not is_breached():
		return
	if not Net.is_online() or multiplayer.is_server():
		_apply_patch()
	else:
		_rpc_request_patch.rpc_id(1)


func _apply_patch() -> void:
	if IsolationRules.patch_breach(zones, zone, global_position, self):
		patched.emit(zone)
		if Net.is_online():
			_rpc_state.rpc(zones.state.to_dict())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_patch() -> void:
	if multiplayer.is_server():
		_apply_patch()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(d: Dictionary) -> void:
	if zones != null:
		zones.state = FloodZoneState.from_dict(d)
		patched.emit(zone)


func interaction_hint() -> String:
	return "patch the breach" if is_breached() else "no breach"
