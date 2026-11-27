class_name CrewIncapacitation
extends RefCounted
## Which crew members are incapacitated. The interface the dive loss rule reads;
## it tracks one [ImpairmentModel] per crew member (final API, Decision #800).
## Subclasses may still override [method crew_ids] and [method is_incapacitated].
## With no crew added, nobody is ever down.


var _models: Dictionary = {}


## Track [param id] with [param model], their [ImpairmentModel].
func add_crew(id: int, model: ImpairmentModel) -> void:
	_models[id] = model


func remove_crew(id: int) -> void:
	_models.erase(id)


## The model of [param id], or null.
func model_for(id: int) -> ImpairmentModel:
	return _models.get(id) as ImpairmentModel


## Step every tracked crew member's model with the cabin air.
func step(dt: float, co2_ppm: float, cabin_o2: float) -> void:
	for id: int in _models:
		(_models[id] as ImpairmentModel).step(dt, co2_ppm, cabin_o2)


## Ids of every crew member in the dive.
func crew_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in _models:
		ids.append(id)
	return ids


## True while this crew member cannot act.
func is_incapacitated(id: int) -> bool:
	var m: ImpairmentModel = model_for(id)
	return m != null and m.incapacitated


## True when there is crew and every one of them is down.
func all_incapacitated() -> bool:
	var ids: Array[int] = crew_ids()
	if ids.is_empty():
		return false
	for id: int in ids:
		if not is_incapacitated(id):
			return false
	return true
