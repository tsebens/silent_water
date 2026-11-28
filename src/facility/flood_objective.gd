class_name FloodObjective
extends RefCounted
## Objective: recover every flooded zone on the objective path. It watches [signal FloodRecovery.zone_recovered]
## and completes once each listed zone is recovered. Which zones are on the path is chosen when it is created
## (by default every zone flooded at that moment).

signal zone_done(zone: StringName)
signal completed

const WORK: FloodWork = preload("res://src/facility/flood_work.tres")

var recovery: FloodRecovery
## Zone id -> true for each zone that must be recovered.
var required: Dictionary = {}
var done: bool = false


## [param path_zones] empty means every zone flooded now.
static func create(r: FloodRecovery, path_zones: Array = []) -> FloodObjective:
	var o: FloodObjective = FloodObjective.new()
	o.recovery = r
	var list: Array = path_zones
	if list.is_empty():
		for z: Variant in r.zones.zone_ids():
			if r.zones.is_flooded(StringName(z)):
				list.append(z)
	for z: Variant in list:
		o.required[String(z)] = true
	r.zone_recovered.connect(o._on_recovered)
	o._check()
	return o


## Budget points this work item costs the dive.
func points() -> int:
	return WORK.points


func recovered_count() -> int:
	var n: int = 0
	for z: String in required:
		if recovery.is_recovered(StringName(z)):
			n += 1
	return n


func is_complete() -> bool:
	return done


func _on_recovered(zone: StringName) -> void:
	if required.has(String(zone)):
		zone_done.emit(zone)
	_check()


func _check() -> void:
	if done or recovered_count() < required.size():
		return
	done = true
	completed.emit()
