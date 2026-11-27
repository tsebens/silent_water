class_name ScienceModule
extends Node3D
## The contract every science instrument module honours. The module scripts (SCAN, SWEEP, PROBE, CAMERA) extend this
## and turn the numbers below into a screen readout. The base does nothing on its own.

signal armed_changed(armed: bool)

## Which [enum ModuleLoadout.Type] this is.
var module_type: int = ModuleLoadout.Type.NONE
## Whether the module is running.
var armed: bool = false:
	set(v):
		if v == armed:
			return
		armed = v
		armed_changed.emit(armed)


## How well the work is going, 0..1.
func health() -> float:
	return 0.0


## Seconds left before the work finishes (or is lost); 0 when not armed.
func time_left() -> float:
	return 0.0


## What would make it go better, for the screen ("CLOSER", "HOLD STILL"); empty when nothing would.
func hint() -> String:
	return ""


## The operator's work key: arms a stopped module, stops a running one.
func toggle_armed() -> void:
	armed = not armed


## A key or mouse event routed to this module while it is the active one. Return true if used.
func work(_event: InputEvent) -> bool:
	return false


func display_name() -> String:
	return ModuleLoadout.type_name(module_type)
