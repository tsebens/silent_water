class_name LifeSupportModel
extends RefCounted
## Pure host-side model of cabin air: CO2 mass, the O2 tank and the cabin's own
## O2. No nodes; [method step] advances it and drains the canisters it is given.

var params: LifeSupportParams
## CO2 in the cabin, litres. Read as ppm through [method co2_ppm].
var co2_litres: float = 0.0
## The O2 tank, 1 full to 0 empty.
var o2_tank: float = 1.0
## Cabin oxygen, 1 normal to 0; falls only once the tank is empty.
var cabin_o2: float = 1.0
## What the crew breathed out in the last step (litres per second).
var production_rate: float = 0.0
## What the scrubbers could remove now (litres per second), whatever the fans do.
var capacity_rate: float = 0.0


func _init(p: LifeSupportParams = null) -> void:
	params = p if p != null else LifeSupportParams.new()
	co2_litres = params.ppm_to_litres(params.baseline_ppm)


func co2_ppm() -> float:
	return params.litres_to_ppm(co2_litres)


func set_co2_ppm(ppm: float) -> void:
	co2_litres = params.ppm_to_litres(maxf(ppm, params.baseline_ppm))


## Fraction of its maximum rate a canister removes at [param saturation]: 1 until
## [member LifeSupportParams.effective_until], a smooth S-curve to 0 at 1.
func effectiveness(saturation: float) -> float:
	return 1.0 - smoothstep(params.effective_until, 1.0, saturation)


## Maximum removal of the given canister capacities (1 fresh to 0 spent) now.
func removal_capacity(capacities: Array[float]) -> float:
	var total: float = 0.0
	for c: float in capacities:
		total += params.canister_max_rate * effectiveness(1.0 - clampf(c, 0.0, 1.0))
	return total


## Advances by [param dt]. [param capacities] holds each seated canister's
## capacity and is drained in place. Crew count is those inside the sub.
func step(dt: float, crew_inside: int, fans_running: bool, surfaced: bool, capacities: Array[float]) -> void:
	var floor_l: float = params.ppm_to_litres(params.baseline_ppm)
	production_rate = params.co2_per_crew_per_s * crew_inside
	capacity_rate = removal_capacity(capacities)
	co2_litres += production_rate * dt

	if fans_running:
		var wanted: float = capacity_rate * dt
		var available: float = maxf(co2_litres - floor_l, 0.0)
		var removed: float = minf(wanted, available)
		if wanted > 0.0 and removed > 0.0:
			var share: float = removed / wanted
			for i: int in capacities.size():
				var c: float = clampf(capacities[i], 0.0, 1.0)
				var taken: float = params.canister_max_rate * effectiveness(1.0 - c) * dt * share
				capacities[i] = maxf(c - taken / params.canister_capacity_l, 0.0)
		co2_litres -= removed

	if surfaced:
		var excess_ppm: float = params.litres_to_ppm(maxf(co2_litres - floor_l, 0.0))
		var vent_ppm: float = maxf(excess_ppm / params.vent_time_constant, params.vent_min_ppm_per_s) * dt
		co2_litres -= params.ppm_to_litres(minf(vent_ppm, excess_ppm))
	co2_litres = maxf(co2_litres, floor_l)

	if o2_tank > 0.0:
		o2_tank = maxf(o2_tank - params.o2_tank_per_crew_per_s * crew_inside * dt, 0.0)
	else:
		cabin_o2 = maxf(cabin_o2 - params.cabin_o2_fall_per_crew_per_s * crew_inside * dt, 0.0)
