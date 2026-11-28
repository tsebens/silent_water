class_name ChargePoint
extends Node3D
## A place a [DemolitionCharge] can be set. It holds one charge and reports arming to a [DemolitionObjective] by
## index. The objective is host-authoritative and replicates its snapshot, so this node mirrors [method armed]
## from the objective's signals and snapshot rather than holding its own network state.

signal armed_changed(armed: bool)
signal charge_set(charge: DemolitionCharge)

## Index of this point in the objective's charge list.
@export var index: int = 0
@export var objective: DemolitionObjective:
	set(value):
		if objective != null:
			_disconnect_objective()
		objective = value
		if is_inside_tree() and objective != null:
			_connect_objective()

var _charge: DemolitionCharge = null
var _armed: bool = false


func _ready() -> void:
	add_to_group(&"charge_points")
	if objective != null:
		_connect_objective()
		_sync()


func _connect_objective() -> void:
	if not objective.charge_armed.is_connected(_on_objective_changed):
		objective.charge_armed.connect(_on_objective_changed)
		objective.charge_disarmed.connect(_on_objective_changed)
		objective.state_changed.connect(_on_state_changed)


func _disconnect_objective() -> void:
	if objective.charge_armed.is_connected(_on_objective_changed):
		objective.charge_armed.disconnect(_on_objective_changed)
		objective.charge_disarmed.disconnect(_on_objective_changed)
		objective.state_changed.disconnect(_on_state_changed)


func _on_objective_changed(_i: int) -> void:
	_sync()


func _on_state_changed(_s: DemolitionObjective.State) -> void:
	_sync()


## Mirrors the objective's armed flag for this index (also how a client sees the host's arming).
func _sync() -> void:
	if objective == null:
		return
	var now: bool = objective.is_armed(index)
	if now == _armed:
		return
	_armed = now
	if not now and _charge != null:
		var c: DemolitionCharge = _charge
		_charge = null
		c._unset()
	armed_changed.emit(now)


func is_armed() -> bool:
	return _armed


func is_occupied() -> bool:
	return _charge != null


func charge() -> DemolitionCharge:
	return _charge


## True when a charge may be set here now: empty, not armed, and the objective accepts charges.
func can_accept() -> bool:
	return objective != null and _charge == null and not _armed and objective.can_arm()


## Seats [param c] and arms this point on the objective. Returns false, nothing changed, when it cannot.
## Called by [method DemolitionCharge.set_at].
func try_set(c: DemolitionCharge) -> bool:
	if c == null or not can_accept():
		return false
	if not objective.arm_charge(index):
		return false
	_charge = c
	_armed = true
	c.global_transform = global_transform
	charge_set.emit(c)
	armed_changed.emit(true)
	return true


func interaction_hint() -> String:
	if _armed:
		return "charge armed"
	return "press E to set the charge" if can_accept() else "shut the reactor down first"
