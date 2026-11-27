class_name TubeLamps
extends Node
## Drives a panel's three [IndicatorLamp]s from a [LaunchTube]'s state, so they
## match the loader's own lamps: exactly one of EMPTY / LOADED / PRIMED is lit,
## and it follows every transition.

@export var tube: LaunchTube
@export var empty_lamp: IndicatorLamp
@export var loaded_lamp: IndicatorLamp
@export var primed_lamp: IndicatorLamp


func _ready() -> void:
	if tube != null:
		tube.state_changed.connect(_on_state_changed)
	refresh()


func refresh() -> void:
	if tube == null:
		return
	_on_state_changed(tube.state())


func _on_state_changed(s: LaunchTube.State) -> void:
	if empty_lamp != null:
		empty_lamp.set_lit(s == LaunchTube.State.EMPTY)
	if loaded_lamp != null:
		loaded_lamp.set_lit(s == LaunchTube.State.LOADED)
	if primed_lamp != null:
		primed_lamp.set_lit(s == LaunchTube.State.PRIMED)
