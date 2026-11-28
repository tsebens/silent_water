class_name ImpairmentParams
extends Resource
## Every tunable of the bad-air effects: the CO2 ladder, the O2 mapping onto it,
## incapacitation and recovery, lingering blur, and movement impairment.
## CO2 is in ppm (10000 ppm = 1%), cabin O2 is a fraction 1 to 0.

## Ladder CO2 points (ppm), ascending. Strength is linear between them and
## constant outside: 0 at the first, [member ladder_strengths] elsewhere.
@export var ladder_ppm: PackedFloat32Array = PackedFloat32Array([15000.0, 25000.0, 30000.0, 40000.0, 70000.0])
## Effect strength (0 to 1) at each of [member ladder_ppm]. Saturated at the end.
@export var ladder_strengths: PackedFloat32Array = PackedFloat32Array([0.0, 0.35, 0.55, 0.85, 1.0])

## Cabin O2 lost (fraction below 1) that puts the O2 mapping at the top of the
## ladder. Smaller than the CO2 route needs, so low oxygen escalates faster.
@export_range(0.01, 1.0) var o2_deficit_for_max: float = 0.5
## Deficit at which the O2 mapping leaves 0 strength.
@export_range(0.0, 1.0) var o2_deficit_start: float = 0.02

## Equivalent CO2 at or above which a crew member drops.
@export var incapacitate_ppm: float = 70000.0
## Equivalent CO2 below which a fallen crew member recovers.
@export var recover_ppm: float = 40000.0

## Blur amount at full strength, and how much of the strength it follows.
@export_range(0.0, 1.0) var blur_at_full: float = 1.0
## Vignette narrowing (0 none, 1 nearly closed) at full strength.
@export_range(0.0, 1.0) var vignette_at_full: float = 0.9
## Strength below which the vignette does not begin (it starts at 2.5%).
@export_range(0.0, 1.0) var vignette_start_strength: float = 0.2
## Movement speed lost at full strength (fraction).
@export_range(0.0, 1.0) var slowdown_at_full: float = 0.7
## Movement wander swing (fraction of input magnitude) at full strength.
@export_range(0.0, 2.0) var wander_swing_at_full: float = 0.8
## Strength below which movement is unaffected (starts at 2.5%).
@export_range(0.0, 1.0) var movement_start_strength: float = 0.2

## Blur left on standing up, and the seconds it takes to fade.
@export_range(0.0, 1.0) var linger_blur_start: float = 1.0
@export var linger_blur_seconds: float = 12.0
