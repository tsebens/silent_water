class_name CanisterSlot
extends Node3D
## A seat for one [ScrubberCanister]: a cradle or a storage hole. It takes a
## canister when empty and refuses a second; [method release] lets it go again.
## A seated canister is placed at this node's origin, standing along its +Y.
##
## Network sync is not required: control behaviour only, local to the player.

signal seated(canister: ScrubberCanister)
signal released(canister: ScrubberCanister)

var _canister: ScrubberCanister = null


func is_occupied() -> bool:
	return _canister != null


func canister() -> ScrubberCanister:
	return _canister


## Seats [param c]. Returns false (nothing changes) when the slot is occupied.
func try_seat(c: ScrubberCanister) -> bool:
	if c == null or _canister != null:
		return false
	if c.is_seated():
		return false
	_canister = c
	c.global_transform = global_transform
	c._set_slot(self)
	seated.emit(c)
	return true


## Releases the seated canister and returns it (null when empty).
func release() -> ScrubberCanister:
	var c: ScrubberCanister = _canister
	if c == null:
		return null
	_canister = null
	c._set_slot(null)
	released.emit(c)
	return c
