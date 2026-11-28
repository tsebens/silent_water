class_name FacilityGasStore
extends RefCounted
## The station's stored gas, which life support pushes into pumped-out zones. Plain data (replicates as
## one float); drawing more than is left returns only what is left.

var capacity: float = 0.0
var amount: float = 0.0


static func create(cap: float) -> FacilityGasStore:
	var s: FacilityGasStore = FacilityGasStore.new()
	s.capacity = cap
	s.amount = cap
	return s


func is_empty() -> bool:
	return amount <= 0.0


## Takes up to [param want] units; returns how many were actually taken.
func draw(want: float) -> float:
	var got: float = clampf(minf(want, amount), 0.0, amount)
	amount -= got
	return got
