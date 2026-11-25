class_name ZoomLever
extends Lever
## A spring-centred lever that emits a zoom rate in -1..1: push up to zoom in,
## pull down to zoom out. Releasing it returns it to 0.

## Emitted whenever the rate changes (the holder's pose, replicated to all).
signal zoom_rate_changed(rate: float)


func _init() -> void:
	super._init()
	min_value = -1.0
	max_value = 1.0
	initial_value = 0.0


func _release_value(_current: float) -> float:
	return 0.0


func _after_change() -> void:
	super._after_change()
	zoom_rate_changed.emit(state.value)


## The current zoom rate, -1..1.
func zoom_rate() -> float:
	return get_value()


func interaction_hint() -> String:
	return "hold click, drag up to zoom in, down to zoom out"
