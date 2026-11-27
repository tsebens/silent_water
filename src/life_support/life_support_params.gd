class_name LifeSupportParams
extends Resource
## Every pace of the life support simulation, tuned without code. Gas amounts
## are litres of CO2 at cabin conditions; [member free_air_volume_m3] turns them
## into ppm. Times are seconds.

## Free air volume of the sub's interior.
@export var free_air_volume_m3: float = 40.0
## The CO2 floor scrubbing and venting never cross.
@export var baseline_ppm: float = 400.0

## CO2 each crew member inside the sub breathes out (litres per second). Four
## crew take 0.7% to 1.5% in about 4 minutes with the fans off.
@export var co2_per_crew_per_s: float = 0.33333
## One fresh canister's maximum removal (litres per second): above four crew.
@export var canister_max_rate: float = 1.5
## Litres of CO2 a canister absorbs from fresh to spent.
@export var canister_capacity_l: float = 1030.0
## Saturation below which a canister removes at full rate.
@export_range(0.0, 1.0) var effective_until: float = 0.85

## O2 tank fraction one crew member breathes per second (four crew: 45 minutes).
@export var o2_tank_per_crew_per_s: float = 1.0 / (45.0 * 60.0 * 4.0)
## Cabin O2 fraction lost per crew member per second once the tank is empty
## (four crew: 5 minutes from normal to nothing).
@export var cabin_o2_fall_per_crew_per_s: float = 1.0 / (5.0 * 60.0 * 4.0)

## While surfaced, CO2 vents at excess / this (seconds)...
@export var vent_time_constant: float = 8.0
## ...but never slower than this (ppm per second), so it finishes in about 30 s.
@export var vent_min_ppm_per_s: float = 100.0


## Litres of CO2 in the cabin air at [param ppm].
func ppm_to_litres(ppm: float) -> float:
	return ppm * free_air_volume_m3 * 1000.0 / 1000000.0


func litres_to_ppm(litres: float) -> float:
	return litres * 1000000.0 / (free_air_volume_m3 * 1000.0)
