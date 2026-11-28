class_name WorkCostTable
extends Resource
## The costs of kinds of dive work and the budgets of dive sizes, authored in a .tres. Unknown names are reported
## (a warning and [constant UNKNOWN]), never answered with zero.

## Returned for an unknown kind or size.
const UNKNOWN: int = -1

@export var costs: Array[WorkCost] = []
@export var sizes: Array[DiveSize] = []


func has_kind(kind: StringName) -> bool:
	return _find_cost(kind) != null


func has_size(size_name: StringName) -> bool:
	return _find_size(size_name) != null


## Points for [param kind], a seeded pick inside its range. [constant UNKNOWN] if the kind is not in the table.
func cost_for(kind: StringName, seed_value: int = 0) -> int:
	var c: WorkCost = _find_cost(kind)
	if c == null:
		push_warning("WorkCostTable: unknown work kind '%s'" % kind)
		return UNKNOWN
	return c.pick(seed_value)


## The cost entry for [param kind], or null.
func cost_entry(kind: StringName) -> WorkCost:
	return _find_cost(kind)


## Budget for [param size_name]. [constant UNKNOWN] if the size is not in the table.
func budget_for(size_name: StringName) -> int:
	var s: DiveSize = _find_size(size_name)
	if s == null:
		push_warning("WorkCostTable: unknown dive size '%s'" % size_name)
		return UNKNOWN
	return s.budget_points


func _find_cost(kind: StringName) -> WorkCost:
	for c: WorkCost in costs:
		if c != null and c.kind == kind:
			return c
	return null


func _find_size(size_name: StringName) -> DiveSize:
	for s: DiveSize in sizes:
		if s != null and s.size_name == size_name:
			return s
	return null
