class_name DemolitionCharge
extends Node3D
## A demolition charge a player carries to a [ChargePoint] and sets with an interact. Built like [DecoyItem]:
## carrying is plain local state that follows a carrier node. A charge can only be set at a charge point; it
## is never dropped anywhere else. Weight and space cost are placeholders for the future carry-load system.

signal carried_changed(carrier: Node3D)
signal set_at_point(point: ChargePoint)

## Mass added to whoever carries it (kg). Placeholder.
@export var weight_kg: float = 8.0
## Inventory space it takes (slots). Placeholder.
@export var space_cost: float = 2.0
## Where a carried charge hangs relative to its carrier.
@export var carry_offset: Vector3 = Vector3(0.0, -0.2, -0.45)

var _carrier: Node3D = null
var _point: ChargePoint = null


func _ready() -> void:
	add_to_group(&"demolition_charges")


func _process(_delta: float) -> void:
	if _carrier != null and is_instance_valid(_carrier):
		global_transform = _carrier.global_transform * Transform3D(Basis.IDENTITY, carry_offset)


func is_carried() -> bool:
	return _carrier != null


func carrier() -> Node3D:
	return _carrier


func is_set() -> bool:
	return _point != null


func point() -> ChargePoint:
	return _point


## Weight this charge adds to its carrier (kg); zero once set or when nobody holds it.
func carried_weight() -> float:
	return weight_kg if _carrier != null else 0.0


## Space this charge takes from its carrier; zero once set or when nobody holds it.
func carried_space() -> float:
	return space_cost if _carrier != null else 0.0


## Total weight of every charge [param by] is carrying under [param tree_root] (any node in the tree).
static func total_weight_carried_by(by: Node3D, tree_root: Node) -> float:
	var total: float = 0.0
	for n: Node in tree_root.get_tree().get_nodes_in_group(&"demolition_charges"):
		var c: DemolitionCharge = n as DemolitionCharge
		if c != null and c.carrier() == by:
			total += c.carried_weight()
	return total


## Returns false when already carried or already set.
func pick_up(by: Node3D) -> bool:
	if by == null or _carrier != null or _point != null:
		return false
	_carrier = by
	carried_changed.emit(_carrier)
	return true


## Sets the charge at [param target]. Refused (false, still carried) when not carried, when [param target] is
## null, or when the point refuses it (occupied, or the objective is not ready for charges).
func set_at(target: ChargePoint) -> bool:
	if _carrier == null or target == null:
		return false
	if not target.try_set(self):
		return false
	_carrier = null
	_point = target
	carried_changed.emit(null)
	set_at_point.emit(target)
	return true


## Called by [ChargePoint] when its charge is removed again.
func _unset() -> void:
	_point = null


func interaction_hint() -> String:
	return "press E to pick up" if _carrier == null and _point == null else ("find a charge point to set it" if _carrier != null else "")
