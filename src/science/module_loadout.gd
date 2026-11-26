class_name ModuleLoadout
extends Resource
## Which instrument module is fitted in each science bay. Any module type may go in any bay; an empty bay is valid.

## Module types. [constant NONE] is an empty bay.
enum Type { NONE, SCAN, SWEEP, PROBE, CAMERA }

## Bays on the station.
const BAY_COUNT: int = 3

## One [enum Type] per bay (as ints). Shorter than [constant BAY_COUNT] means the rest are empty.
@export var slots: Array[int] = [Type.SCAN, Type.SWEEP, Type.CAMERA]


static func type_name(t: int) -> String:
	match t:
		Type.SCAN: return "SCAN"
		Type.SWEEP: return "SWEEP"
		Type.PROBE: return "PROBE"
		Type.CAMERA: return "CAMERA"
	return "EMPTY"


## The type fitted in bay [param bay] ([constant Type.NONE] if empty or out of range).
func type_at(bay: int) -> int:
	if bay < 0 or bay >= slots.size():
		return Type.NONE
	return slots[bay]


## Fits [param t] in bay [param bay] (Type.NONE empties it).
func fit(bay: int, t: int) -> void:
	if bay < 0 or bay >= BAY_COUNT:
		return
	while slots.size() <= bay:
		slots.append(Type.NONE)
	slots[bay] = t
	emit_changed()
