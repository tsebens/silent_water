class_name FloodRecovery
extends RefCounted
## Pump and re-pressurise (host side). Each pumping zone's water level falls at the tuned rate, but only
## while the zone is isolated ([method FloodZones.can_pump]), and each bit of water removed must be replaced
## by gas drawn from the station's [FacilityGasStore]. With too little gas the pump stalls; with the store
## empty the zone can never be recovered. A zone is recovered once dry with its air restored, which emits
## [signal zone_recovered] (the cue for suits to come off, #845). Plain state replicates via [method to_dict].

signal zone_recovered(zone: StringName)
signal pump_started(zone: StringName)
signal pump_stalled(zone: StringName)

const START_SOUND: SoundType = preload("res://src/noise/sound_types/pump_hum.tres")
const STALL_SOUND: SoundType = preload("res://src/noise/sound_types/impact.tres")
const TUNING: FloodTuning = preload("res://src/facility/flood_tuning.tres")

var zones: FloodZones
var store: FacilityGasStore
var tuning: FloodTuning
## Zone id -> water level 0..1 for zones that have started pumping.
var level: Dictionary = {}
## Zone id -> true while its pump is switched on.
var pumping: Dictionary = {}
## Zone id -> true while the pump is stalled for want of gas.
var stalled: Dictionary = {}
## Zone id -> true once recovered.
var recovered: Dictionary = {}


static func create(fz: FloodZones, t: FloodTuning = TUNING) -> FloodRecovery:
	var r: FloodRecovery = FloodRecovery.new()
	r.zones = fz
	r.tuning = t
	r.store = FacilityGasStore.create(t.gas_store_capacity)
	return r


func water_level(zone: StringName) -> float:
	if not zones.is_flooded(zone):
		return 0.0
	return level.get(String(zone), 1.0)


func is_pumping(zone: StringName) -> bool:
	return pumping.get(String(zone), false)


func is_stalled(zone: StringName) -> bool:
	return stalled.get(String(zone), false)


func is_recovered(zone: StringName) -> bool:
	return recovered.get(String(zone), false)


## True when the gas left cannot refill what is still to be pumped out of the zone.
func is_unrecoverable(zone: StringName) -> bool:
	return zones.is_flooded(zone) and store.amount < water_level(zone) * tuning.gas_per_level - 0.0001


## Switch a zone's pump on. False unless the zone is flooded and isolated. Noisy.
func start_pump(zone: StringName, at: Vector3 = Vector3.ZERO, source: Object = null) -> bool:
	if not zones.is_flooded(zone) or not zones.can_pump(zone) or is_pumping(zone):
		return false
	pumping[String(zone)] = true
	stalled.erase(String(zone))
	if not level.has(String(zone)):
		level[String(zone)] = 1.0
	Acoustics.emit_event(START_SOUND, at, source, tuning.start_noise_scale)
	pump_started.emit(zone)
	return true


func stop_pump(zone: StringName) -> void:
	pumping.erase(String(zone))
	stalled.erase(String(zone))


## Advance every running pump by [param dt] seconds.
func tick(dt: float, at: Vector3 = Vector3.ZERO, source: Object = null) -> void:
	for k: Variant in pumping.keys():
		_tick_zone(StringName(k), dt, at, source)


func _tick_zone(zone: StringName, dt: float, at: Vector3, source: Object) -> void:
	var key: String = String(zone)
	if not zones.can_pump(zone):
		return  # an open breach (or path to the sea) means the pump makes no progress
	var want: float = minf(tuning.pump_rate * dt, level.get(key, 1.0))
	var cost: float = want * tuning.gas_per_level
	var got: float = store.draw(cost)
	var done: float = want if cost <= 0.0 else want * (got / cost)
	level[key] = maxf(0.0, level.get(key, 1.0) - done)
	if got < cost - 0.0001:
		if not is_stalled(zone):
			stalled[key] = true
			Acoustics.emit_event(STALL_SOUND, at, source, tuning.stall_noise_scale)
			pump_stalled.emit(zone)
		return
	stalled.erase(key)
	if level[key] <= 0.0:
		zones.drain(zone)
		pumping.erase(key)
		recovered[key] = true
		zone_recovered.emit(zone)


func to_dict() -> Dictionary:
	return {"level": level.duplicate(), "pumping": pumping.duplicate(), "stalled": stalled.duplicate(),
		"recovered": recovered.duplicate(), "gas": store.amount}


func apply_dict(d: Dictionary) -> void:
	level = (d.get("level", {}) as Dictionary).duplicate()
	pumping = (d.get("pumping", {}) as Dictionary).duplicate()
	stalled = (d.get("stalled", {}) as Dictionary).duplicate()
	recovered = (d.get("recovered", {}) as Dictionary).duplicate()
	store.amount = d.get("gas", store.amount)
