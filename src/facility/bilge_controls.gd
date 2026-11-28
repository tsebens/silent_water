class_name BilgeControls
extends Node3D
## The workshop's bilge controls. Interacting starts the pump on [member zone] (and clears a stall by
## restarting it); life support supplies the gas from the [FacilityGasStore] inside [member recovery].
## Host-authoritative: a client asks the host, the host applies it (the noise comes from [FloodRecovery]),
## ticks the model, and replicates its state.

signal changed(zone: StringName)

@export var zone: StringName = &""
var recovery: FloodRecovery = null


func _ready() -> void:
	add_to_group(&"bilge_controls")


func _process(delta: float) -> void:
	if recovery == null or (Net.is_online() and not multiplayer.is_server()):
		return
	if recovery.pumping.is_empty():
		return
	var before: Dictionary = recovery.to_dict()
	recovery.tick(delta, global_position, self)
	if recovery.to_dict() != before:
		changed.emit(zone)
		if Net.is_online() and (recovery.is_stalled(zone) != (before.stalled as Dictionary).has(String(zone)) or recovery.is_recovered(zone) != (before.recovered as Dictionary).has(String(zone))):
			_rpc_state.rpc(recovery.to_dict(), recovery.zones.state.to_dict())


func interact() -> void:
	if recovery == null:
		return
	if not Net.is_online() or multiplayer.is_server():
		_apply_start()
	else:
		_rpc_request_start.rpc_id(1)


func _apply_start() -> void:
	recovery.stalled.erase(String(zone))
	if recovery.start_pump(zone, global_position, self):
		changed.emit(zone)
		if Net.is_online():
			_rpc_state.rpc(recovery.to_dict(), recovery.zones.state.to_dict())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_start() -> void:
	if multiplayer.is_server():
		_apply_start()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(d: Dictionary, zone_state: Dictionary) -> void:
	if recovery != null:
		recovery.apply_dict(d)
		recovery.zones.state = FloodZoneState.from_dict(zone_state)
		changed.emit(zone)


func interaction_hint() -> String:
	if recovery == null or recovery.is_recovered(zone):
		return "bilge pumps idle"
	if recovery.is_pumping(zone):
		return "pumping: stalled, no gas" if recovery.is_stalled(zone) else "pumping"
	return "start the bilge pump" if recovery.zones.can_pump(zone) else "zone not isolated"
