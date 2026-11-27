class_name DecoyItem
extends Node3D
## A carried decoy (a little fat torpedo). A player lifts it out of a
## [DecoyCradle] or off the floor and carries it (it follows a carrier node),
## then drops it into a cradle or sets it down. Built like [ScrubberCanister].
##
## The carried state ([method is_carried], [method carrier], [method is_seated])
## is plain state with [signal carried_changed] and [signal seated_changed] for
## whatever mirrors it; like the canister, it is control behaviour local to the
## carrying player and not yet net-synced.
##
## Local axes: the decoy lies along -Z (nose), seated at the cradle's origin.

signal carried_changed(carrier: Node3D)
signal seated_changed(cradle: DecoyCradle)

## How far the decoy is lifted straight up when it is picked up (m).
@export var lift_height: float = 0.1
## Where a carried decoy hangs relative to its carrier.
@export var carry_offset: Vector3 = Vector3(0.0, -0.15, -0.5)

var _carrier: Node3D = null
var _cradle: DecoyCradle = null


func _process(_delta: float) -> void:
	if _carrier != null and is_instance_valid(_carrier):
		global_transform = _carrier.global_transform * Transform3D(Basis.IDENTITY, carry_offset)


func is_carried() -> bool:
	return _carrier != null


func is_seated() -> bool:
	return _cradle != null


func cradle() -> DecoyCradle:
	return _cradle


func carrier() -> Node3D:
	return _carrier


## Lifts the decoy out of its cradle (if seated) and hands it to [param by].
## Returns false when it is already carried.
func pick_up(by: Node3D) -> bool:
	if by == null or _carrier != null:
		return false
	if _cradle != null:
		var from: DecoyCradle = _cradle
		global_position += from.global_transform.basis.y * lift_height
		from.release()
	_carrier = by
	carried_changed.emit(_carrier)
	return true


## Lets go of the decoy, leaving it where it hangs. Returns false when not carried.
func drop() -> bool:
	if _carrier == null:
		return false
	_carrier = null
	carried_changed.emit(null)
	return true


## Drops the decoy into [param target]. Returns false, still carried, when the
## cradle refuses it (occupied).
func drop_into(target: DecoyCradle) -> bool:
	if _carrier == null or target == null:
		return false
	if not target.try_seat(self):
		return false
	_carrier = null
	carried_changed.emit(null)
	return true


## Called by [DecoyCradle] only.
func _set_cradle(c: DecoyCradle) -> void:
	_cradle = c
	seated_changed.emit(c)


func interaction_hint() -> String:
	return "press E to pick up" if _carrier == null else "press E to drop"
