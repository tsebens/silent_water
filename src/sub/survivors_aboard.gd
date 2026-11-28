class_name SurvivorsAboard
extends Node
## How many rescued survivors are aboard the sub, in group [code]survivors_aboard[/code].
## The host owns the count ([method add], [method remove]) and replicates it with the
## per-survivor mass; clients only read. The weight and breathing systems read
## [method total_mass_kg] and [member count].
##
## Replication follows [LifeSupportReadouts]: a snapshot on every change and a full
## one to each joining peer.

## The count or the per-survivor mass changed.
signal changed(count: int)

const GROUP: StringName = &"survivors_aboard"

## Mass of one survivor, in kilograms.
@export var mass_per_survivor_kg: float = 80.0:
	set(v):
		v = maxf(v, 0.0)
		if is_equal_approx(v, mass_per_survivor_kg):
			return
		mass_per_survivor_kg = v
		_changed()
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false

var count: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


## Host: [param n] more survivors come aboard. Ignored on clients.
func add(n: int = 1) -> void:
	_set_count(count + maxi(n, 0))


## Host: [param n] survivors leave, never below zero. Ignored on clients.
func remove(n: int = 1) -> void:
	_set_count(count - maxi(n, 0))


func total_mass_kg() -> float:
	return float(count) * mass_per_survivor_kg


func _set_count(v: int) -> void:
	if not _is_host():
		return
	v = maxi(v, 0)
	if v == count:
		return
	count = v
	_changed()


func _changed() -> void:
	changed.emit(count)
	if _is_host() and is_inside_tree() and Net.is_online():
		_rpc_snapshot.rpc(snapshot())


# -- Replication -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {"count": count, "mass": mass_per_survivor_kg}


func apply_snapshot(snap: Dictionary) -> void:
	var c: int = maxi(int(snap["count"]), 0)
	var m: float = maxf(float(snap["mass"]), 0.0)
	if c == count and is_equal_approx(m, mass_per_survivor_kg):
		return
	count = c
	mass_per_survivor_kg = m  # its setter emits changed


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_snapshot.rpc_id(peer_id, snapshot())
