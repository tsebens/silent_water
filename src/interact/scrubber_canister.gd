class_name ScrubberCanister
extends Node3D
## A carried CO2 scrubber canister. A player lifts it straight out of a
## [CanisterSlot] and carries it (it follows a carrier node), then drops it back
## into a slot or sets it down. [member capacity] is a plain exported fraction
## (1 fresh, 0 spent); what uses it (the CO2 balance) is not part of this script.
##
## [member capacity] is host-authoritative and replicated to every client in
## every state (seated, carried, stored): the host sends it when it changes, at
## most every [constant SNAPSHOT_INTERVAL] seconds, and to each joining peer.
## Canisters are matched across peers by node path. Carrying itself stays local.
##
## Local axes: the canister stands along +Y from its base.

const SNAPSHOT_INTERVAL: float = 0.5

signal capacity_changed(capacity: float)
signal carried_changed(carrier: Node3D)
signal seated_changed(slot: CanisterSlot)

## Remaining absorbing capacity, 0 (spent) to 1 (fresh).
@export_range(0.0, 1.0) var capacity: float = 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if is_equal_approx(capacity, v):
			return
		capacity = v
		capacity_changed.emit(capacity)
## How far the canister is lifted straight up when it is picked up (m); the
## motion that shows it leaving the cradle.
@export var lift_height: float = 0.12
## Where a carried canister hangs relative to its carrier.
@export var carry_offset: Vector3 = Vector3(0.0, -0.1, -0.45)

## Test seam: behave as a client even where the peer is offline.
var simulate_client: bool = false

var _carrier: Node3D = null
var _slot: CanisterSlot = null
var _sent_capacity: float = -1.0
var _send_timer: float = 0.0


func _ready() -> void:
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


func _physics_process(delta: float) -> void:
	if not _is_host() or not _online():
		return
	_send_timer += delta
	if _send_timer >= SNAPSHOT_INTERVAL and not is_equal_approx(_sent_capacity, capacity):
		_send_timer = 0.0
		_sent_capacity = capacity
		_rpc_capacity.rpc(capacity)


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()


## Capacity as replicated to clients.
func snapshot() -> Dictionary:
	return {"capacity": capacity}


func apply_snapshot(snap: Dictionary) -> void:
	capacity = float(snap["capacity"])


@rpc("authority", "call_remote", "reliable")
func _rpc_capacity(v: float) -> void:
	apply_snapshot({"capacity": v})


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_capacity.rpc_id(peer_id, capacity)


func _process(_delta: float) -> void:
	if _carrier != null and is_instance_valid(_carrier):
		global_transform = _carrier.global_transform * Transform3D(Basis.IDENTITY, carry_offset)


func is_carried() -> bool:
	return _carrier != null


func is_seated() -> bool:
	return _slot != null


func slot() -> CanisterSlot:
	return _slot


func carrier() -> Node3D:
	return _carrier


## Lifts the canister out of its slot (if seated) and hands it to [param by].
## Returns false when it is already carried.
func pick_up(by: Node3D) -> bool:
	if by == null or _carrier != null:
		return false
	if _slot != null:
		var from: CanisterSlot = _slot
		global_position += from.global_transform.basis.y * lift_height
		from.release()
	_carrier = by
	carried_changed.emit(_carrier)
	return true


## Lets go of the canister, leaving it where it hangs. Returns false when it is
## not carried.
func drop() -> bool:
	if _carrier == null:
		return false
	_carrier = null
	carried_changed.emit(null)
	return true


## Drops the canister into [param target]. Returns false, still carried, when the
## slot refuses it (occupied).
func drop_into(target: CanisterSlot) -> bool:
	if _carrier == null or target == null:
		return false
	if not target.try_seat(self):
		return false
	_carrier = null
	carried_changed.emit(null)
	return true


## Called by [CanisterSlot] only.
func _set_slot(s: CanisterSlot) -> void:
	_slot = s
	seated_changed.emit(s)


func interaction_hint() -> String:
	return "press E to pick up" if _carrier == null else "press E to drop"
