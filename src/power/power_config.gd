class_name PowerConfig
extends Resource
## Every tunable of the [PowerSystem]. Starting values, tuned in play.
## Rates are battery charge (0-1) per minute unless noted; times are seconds.

## Draw of each circuit while powered and idle (charge per minute). All six
## together hold the sub for about 30 minutes (1/30 = 0.0333).
@export var cabin_lights_draw: float = 0.008
@export var ext_lights_draw: float = 0.004
@export var fans_draw: float = 0.010
@export var displays_draw: float = 0.004
@export var sonar_draw: float = 0.004
@export var helm_draw: float = 0.003333
## Extra draw at full demand (charge per minute).
@export var thruster_full_draw: float = 0.03
@export var bilge_pump_draw: float = 0.02
## Motor draw at power 1.0 (charge per minute). With the 40% cap and the idle
## loads above, full throttle on the battery empties it in about 8 minutes.
@export var motor_full_draw: float = 0.2292

## Motor power fraction available on the battery alone.
@export_range(0.0, 1.0) var motor_cap_battery: float = 0.4
## Motor power is output ^ this (thrust ∝ output, speed ∝ √thrust).
@export var motor_exponent: float = 1.5

## Charge per minute while the generator runs (about 4 minutes empty to full).
@export var generator_charge_rate: float = 0.28
@export var generator_start_delay: float = 4.0
## Constant generator noise, linear intensity (about 85 dB).
@export var generator_noise: float = 0.03
## Motor noise at full output, linear intensity (about 73 dB).
@export var motor_noise_full: float = 0.002

## Heat is 0-1. It rises under heavy load (charging, motor power at or above
## [member heat_load_power]) and falls otherwise.
@export var heat_rise_per_s: float = 1.0 / 660.0
@export var heat_fall_per_s: float = 1.0 / 300.0
@export var heat_limit: float = 1.0
## After a self-shutdown the generator won't restart until heat is below this.
@export var heat_restart_threshold: float = 0.5
@export var heat_load_power: float = 0.6

## Fault tuning, driven by a later arc but held here with the rest.
@export var trip_hit_threshold: float = 1.0
@export var trip_flood_threshold: float = 1.0
@export var wear_limit: int = 3
@export var spare_count: int = 4


## Engine output limit for a motor power fraction.
func output_for_power(power: float) -> float:
	return pow(clampf(power, 0.0, 1.0), 1.0 / motor_exponent)


## Motor power fraction for an engine output.
func power_for_output(output: float) -> float:
	return pow(clampf(absf(output), 0.0, 1.0), motor_exponent)
