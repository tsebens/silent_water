class_name LifeSupportReadouts
extends Node
## Source of the life support readouts, in group [code]life_support_readouts[/code].
## Holds plain settable values (no simulation; the CO2 model is separate work).
## Displays ask [method readout] by name.

signal co2_alarm_changed(level: LifeSupportAlarmLevels.Level)
signal o2_alarm_changed(level: LifeSupportAlarmLevels.Level)
## The FANS circuit gained or lost power. Life support reacts to this; there is
## no CO2 simulation yet.
signal fans_powered_changed(powered: bool)

const GROUP: StringName = &"life_support_readouts"
## Name of the station's fan switch (a SwitchLever), found anywhere under [member station] or the tree.
const FAN_SWITCH: StringName = &"FanToggle"

@export var alarm_levels: LifeSupportAlarmLevels = LifeSupportAlarmLevels.new()
## CO2 ppm that reads as co2_level 1.0 (the IDLH line).
@export var co2_full_scale_ppm: float = 40000.0
## The instanced life support station whose fan switch sets [member fans_on]. Unset: search the whole tree.
@export var station: Node

var o2_level: float = 1.0:
	set(v):
		o2_level = clampf(v, 0.0, 1.0)
		_update_alarms()
var co2_ppm: float = 400.0:
	set(v):
		co2_ppm = maxf(v, 0.0)
		_update_alarms()
## False while the FANS circuit is unpowered: scrubbing has stopped.
var fans_powered: bool = true
## The crew's fan switch: on by default. The fans run when it is on and the FANS circuit is powered.
var fans_on: bool = true
var saturation_a: float = 0.0
var saturation_b: float = 0.0

var _co2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF
var _o2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF


func _ready() -> void:
	add_to_group(GROUP)
	PowerSink.bind(self, PowerSystem.Circuit.FANS, set_fans_powered)
	_update_alarms()
	_bind_fan_switch()


## Follows the station's fan switch, if one is in the tree.
func _bind_fan_switch() -> void:
	var root: Node = station if station != null else get_tree().root
	var sw: SwitchLever = root.find_child(FAN_SWITCH, true, false) as SwitchLever
	if sw == null:
		return
	sw.value_changed.connect(func(v: float) -> void: set_fans_on(inverse_lerp(sw.min_value, sw.max_value, v) > 0.5))
	set_fans_on(sw.get_normalized() > 0.5)


func set_fans_on(on: bool) -> void:
	fans_on = on


## True when the scrubber fans are turning: switched on and powered.
func fans_running() -> bool:
	return fans_on and fans_powered


func set_fans_powered(on: bool) -> void:
	if fans_powered == on:
		return
	fans_powered = on
	fans_powered_changed.emit(on)


func readout(readout_name: StringName) -> float:
	match readout_name:
		&"fans_powered":
			return 1.0 if fans_powered else 0.0
		&"fans_running":
			return 1.0 if fans_running() else 0.0
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
