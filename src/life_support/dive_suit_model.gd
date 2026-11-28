class_name DiveSuitModel
extends RefCounted
## Pure model of one dive suit: air that drains while worn and refills when it
## is off, plus the effects at the current state. Tunables are in DiveSuitParams.

const WARN_NONE: int = 0
const WARN_LOW: int = 1
const WARN_CRITICAL: int = 2

var params: DiveSuitParams
## Seconds of air left.
var air: float
var worn: bool = false


func _init(p: DiveSuitParams = null) -> void:
	params = p if p != null else DiveSuitParams.new()
	air = params.air_capacity_seconds


func air_fraction() -> float:
	return clampf(air / maxf(params.air_capacity_seconds, 0.0001), 0.0, 1.0)


func is_empty() -> bool:
	return air <= 0.0


func set_worn(value: bool) -> void:
	worn = value


## Advance by [param dt] seconds. Worn drains; not worn holds, or refills when
## [param refilling] is true.
func step(dt: float, refilling: bool = false) -> void:
	if worn:
		air = maxf(air - params.drain_rate * dt, 0.0)
	elif refilling:
		air = minf(air + params.refill_rate * dt, params.air_capacity_seconds)


## True while the suit is worn and has air: the wearer breathes the suit's air.
func protects() -> bool:
	return worn and not is_empty()


## Ambient air as the wearer experiences it: clean while protected, else as given.
## Returns [co2_ppm, o2].
func filter_ambient(co2_ppm: float, cabin_o2: float) -> Array[float]:
	if protects():
		return [params.protected_co2_ppm, params.protected_o2]
	return [co2_ppm, cabin_o2]


## View narrowing, 0 to 1. 0 when not worn.
func view_narrowing() -> float:
	return params.view_narrowing_worn if worn else 0.0


## Walk-speed multiplier. 1 when not worn.
func speed_multiplier() -> float:
	return params.speed_multiplier_worn if worn else 1.0


## Low-air warning level: WARN_NONE, WARN_LOW or WARN_CRITICAL. Only while worn.
func warning_level() -> int:
	if not worn:
		return WARN_NONE
	var f: float = air_fraction()
	if f <= params.critical_air_fraction:
		return WARN_CRITICAL
	if f <= params.low_air_fraction:
		return WARN_LOW
	return WARN_NONE
