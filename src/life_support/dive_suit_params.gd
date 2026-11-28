class_name DiveSuitParams
extends Resource
## Every tunable of the dive suit: its air supply, how fast it drains and refills,
## and how awkward it is to wear. Air is in seconds of breathing.

## Air a full supply holds, in seconds.
@export var air_capacity_seconds: float = 600.0
## Air used per second while worn (1 is real time).
@export var drain_rate: float = 1.0
## Air gained per second while refilling (not worn, on a refill source).
@export var refill_rate: float = 20.0

## View narrowing (0 none, 1 nearly closed) while worn: the helmet frames the screen.
@export_range(0.0, 1.0) var view_narrowing_worn: float = 0.35
## Walk-speed multiplier while worn.
@export_range(0.05, 1.0) var speed_multiplier_worn: float = 0.8

## Air fraction at or below which the low-air warning shows (level 1).
@export_range(0.0, 1.0) var low_air_fraction: float = 0.25
## Air fraction at or below which the warning is critical (level 2).
@export_range(0.0, 1.0) var critical_air_fraction: float = 0.1

## Ambient values a protected wearer breathes: clean CO2 (ppm) and O2 fraction.
@export var protected_co2_ppm: float = 400.0
@export_range(0.0, 1.0) var protected_o2: float = 1.0
