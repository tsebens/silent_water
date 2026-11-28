class_name DivePlan
extends Resource
## The result of [DiveGenerator]: the chosen work in order (a prerequisite always before what needs it), what it
## costs in total and what is left of the budget.

@export var size_name: StringName = &""
@export var seed_value: int = 0
@export var budget: int = 0
## Chosen work, in order. Parallel to [member costs].
@export var items: Array[WorkOption] = []
@export var costs: PackedInt32Array = PackedInt32Array()
## Steps in the main objective (its prerequisites and itself); they are the first items. 0 if none fit.
@export var main_steps: int = 0


func total_cost() -> int:
	var sum: int = 0
	for c: int in costs:
		sum += c
	return sum


func leftover() -> int:
	return budget - total_cost()


func has_item(option_name: StringName) -> bool:
	return index_of(option_name) >= 0


func index_of(option_name: StringName) -> int:
	for i: int in items.size():
		if items[i].option_name == option_name:
			return i
	return -1


## Names of the items in order, for comparing plans.
func names() -> Array[StringName]:
	var out: Array[StringName] = []
	for o: WorkOption in items:
		out.append(o.option_name)
	return out
