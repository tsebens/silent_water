class_name LifeSupportReadouts
extends Node
## Source of the life support readouts, in group [code]life_support_readouts[/code].
## Holds plain settable values (no simulation; the CO2 model is separate work).
## Displays ask [method readout] by name.

signal co2_alarm_changed(level: LifeSupportAlarmLevels.Level)
signal o2_alarm_changed(level: LifeSupportAlarmLevels.Level)

const GROUP: StringName = &"life_support_readouts"

@export var alarm_levels: LifeSupportAlarmLevels = LifeSupportAlarmLevels.new()
## CO2 ppm that reads as co2_level 1.0 (the IDLH line).
@export var co2_full_scale_ppm: float = 40000.0

var o2_level: float = 1.0:
	set(v):
		o2_level = clampf(v, 0.0, 1.0)
		_update_alarms()
var co2_ppm: float = 400.0:
	set(v):
		co2_ppm = maxf(v, 0.0)
		_update_alarms()
var saturation_a: float = 0.0
var saturation_b: float = 0.0

var _co2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF
var _o2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF


func _ready() -> void:
	add_to_group(GROUP)
	_update_alarms()


func readout(readout_name: StringName) -> float:
	match readout_name:
		&"o2_level":
			return o2_level
		&"co2_level":
			return clampf(co2_ppm / co2_full_scale_ppm, 0.0, 1.0) if co2_full_scale_ppm > 0.0 else 0.0
		&"co2_ppm":
			return co2_ppm
		&"saturation_a":
			return saturation_a
		&"saturation_b":
			return saturation_b
		&"capacity_a":
			return 1.0 - saturation_a
		&"capacity_b":
			return 1.0 - saturation_b
	return 0.0


func co2_alarm() -> LifeSupportAlarmLevels.Level:
	return _co2_alarm


func o2_alarm() -> LifeSupportAlarmLevels.Level:
	return _o2_alarm


func _update_alarms() -> void:
	var c: LifeSupportAlarmLevels.Level = alarm_levels.co2_level_for(co2_ppm)
	if c != _co2_alarm:
		_co2_alarm = c
		co2_alarm_changed.emit(c)
	var o: LifeSupportAlarmLevels.Level = alarm_levels.o2_level_for(o2_level)
	if o != _o2_alarm:
		_o2_alarm = o
		o2_alarm_changed.emit(o)
