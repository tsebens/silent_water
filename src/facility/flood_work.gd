class_name FloodWork
extends Resource
## The dive-generator work item for recovering a flooded facility. Its cost is a placeholder tuned here.
## It is complete when every flooded zone on the objective path is recovered ([FloodObjective]).

## Kind of work, a key of the [WorkCostTable].
@export var kind: StringName = &"recover_flooding"
## Budget points the item costs (placeholder, about 20 to 25).
@export var points: int = 22
## Facility state flag that makes this item part of a dive.
@export var state_flag: StringName = &"flooded"
## Whether it may be the dive's main objective.
@export var can_be_main: bool = false


## A [WorkOption] for the generator's site list, named [param option_name].
func to_option(option_name: StringName) -> WorkOption:
	var o: WorkOption = WorkOption.new()
	o.option_name = option_name
	o.kind = kind
	o.state_flag = state_flag
	o.can_be_main = can_be_main
	return o
