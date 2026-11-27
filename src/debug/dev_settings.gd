class_name DevSettings
extends RefCounted
## Developer-mode switches, local to this machine.

## Single-player mode: the seated pilot also runs the ballast (Numpad 8 blow,
## Numpad 2 flood). Toggle with F5, or start with `--solo`.
static var single_player: bool = OS.get_cmdline_user_args().has("--solo")

## Night light preset instead of day (F7, or start with `--night`).
static var night: bool = OS.get_cmdline_user_args().has("--night")


## Flips the day/night preset; returns the new value of `night`.
static func toggle_night() -> bool:
	night = not night
	return night


## Forces the local bad-air view to a ladder level (F8 cycles): -1 follows the
## player's real impairment, otherwise an index into [member IMPAIRMENT_LEVELS].
static var impairment_level: int = -1

## Strength at each forced level, matching the CO2 ladder rungs 1.5%, 2.5%, 3%, 4%, 7%.
const IMPAIRMENT_LEVELS: PackedFloat32Array = [0.05, 0.35, 0.55, 0.85, 1.0]


## Next forced level: off, then each rung, then back to off. Returns it.
static func cycle_impairment_level() -> int:
	impairment_level += 1
	if impairment_level >= IMPAIRMENT_LEVELS.size():
		impairment_level = -1
	return impairment_level


## Forced strength, or -1.0 when not forcing.
static func forced_impairment() -> float:
	if impairment_level < 0 or impairment_level >= IMPAIRMENT_LEVELS.size():
		return -1.0
	return IMPAIRMENT_LEVELS[impairment_level]
