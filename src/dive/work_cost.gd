class_name WorkCost
extends Resource
## What one kind of dive work costs, in budget points: a fixed number, or a range when min and max differ.

## Id of the kind of work, e.g. &"scan".
@export var kind: StringName = &""
## Lowest cost in points.
@export var points_min: int = 0
## Highest cost in points; equal to the minimum for a fixed cost.
@export var points_max: int = 0


## The cost for this kind: the fixed value, or a pick inside the range that depends only on [param seed_value].
func pick(seed_value: int) -> int:
	if points_max <= points_min:
		return points_min
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, String(kind)])
	return rng.randi_range(points_min, points_max)
