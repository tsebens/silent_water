class_name DecoyCradle
extends Node3D
## A seat for one [DecoyItem]: the half-pipe cradle of a launch tube's drawer.
## It takes a decoy when empty and refuses a second; [method release] lets it
## go again. A seated decoy is placed at this node's origin.
##
## Control behaviour only, local to the player.

signal decoy_seated(decoy: DecoyItem)
signal decoy_released(decoy: DecoyItem)

var _decoy: DecoyItem = null


func is_occupied() -> bool:
	return _decoy != null


func decoy() -> DecoyItem:
	return _decoy


## Seats [param d]. Returns false (nothing changes) when the cradle is occupied.
func try_seat(d: DecoyItem) -> bool:
	if d == null or _decoy != null:
		return false
	if d.is_seated():
		return false
	_decoy = d
	d.global_transform = global_transform
	d._set_cradle(self)
	decoy_seated.emit(d)
	return true


## Releases the seated decoy and returns it (null when empty).
func release() -> DecoyItem:
	var d: DecoyItem = _decoy
	if d == null:
		return null
	_decoy = null
	d._set_cradle(null)
	decoy_released.emit(d)
	return d
