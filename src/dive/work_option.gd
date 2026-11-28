class_name WorkOption
extends Resource
## One piece of work a site offers. Its cost is not stored here: it comes from the [WorkCostTable] by [member kind].

## Unique name of this option within a site's list, e.g. &"array_s7_scan".
@export var option_name: StringName = &""
## Kind of work, a key of the cost table.
@export var kind: StringName = &""
## Kind of work that must be done before this one; empty for none. The generator picks an option of that kind.
@export var prerequisite_kind: StringName = &""
## Facility state flag (e.g. &"power_off") that makes this option part of a dive. Empty means ordinary work that is
## always eligible; a flagged option is a facility problem and is a line item only when the dive sets that flag.
@export var state_flag: StringName = &""
## Whether this option may be picked as the dive's main objective.
@export var can_be_main: bool = false
