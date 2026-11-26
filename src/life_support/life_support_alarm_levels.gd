class_name LifeSupportAlarmLevels
extends Resource
## Thresholds for the life support alarm lamps. CO2 alarms rise with ppm; O2 alarms
## fall with the tank fraction. [method level_high] and [method level_low] are pure.

enum Level { OFF, STEADY, FLASH }

## CO2 concentration (ppm) at which the lamp lights steady (submarine 90-day limit).
@export var co2_steady_ppm: float = 7000.0
## CO2 concentration (ppm) at which the lamp flashes (1-hour emergency limit).
@export var co2_flash_ppm: float = 25000.0
## O2 tank fraction at or below which the lamp lights steady (placeholder).
@export_range(0.0, 1.0) var o2_steady: float = 0.25
## O2 tank fraction at or below which the lamp flashes (placeholder).
@export_range(0.0, 1.0) var o2_flash: float = 0.10


## Alarm level for a value that is dangerous when high (CO2).
static func level_high(value: float, steady: float, flash: float) -> Level:
	if value >= flash:
		return Level.FLASH
	if value >= steady:
		return Level.STEADY
	return Level.OFF


## Alarm level for a value that is dangerous when low (O2).
static func level_low(value: float, steady: float, flash: float) -> Level:
	if value <= flash:
		return Level.FLASH
	if value <= steady:
		return Level.STEADY
	return Level.OFF


func co2_level_for(ppm: float) -> Level:
	return level_high(ppm, co2_steady_ppm, co2_flash_ppm)


func o2_level_for(fraction: float) -> Level:
	return level_low(fraction, o2_steady, o2_flash)
