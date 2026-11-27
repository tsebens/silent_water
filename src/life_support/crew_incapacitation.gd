class_name CrewIncapacitation
extends RefCounted
## Which crew members are incapacitated. The interface the dive loss rule reads;
## the effects system implements it by overriding [method crew_ids] and
## [method is_incapacitated]. The base class has no crew, so nobody is ever down.


## Ids of every crew member in the dive.
func crew_ids() -> Array[int]:
	return []


## True while this crew member cannot act.
func is_incapacitated(_id: int) -> bool:
	return false


## True when there is crew and every one of them is down.
func all_incapacitated() -> bool:
	var ids: Array[int] = crew_ids()
	if ids.is_empty():
		return false
	for id: int in ids:
		if not is_incapacitated(id):
			return false
	return true
