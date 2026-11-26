class_name LifeSupportAlarmDriver
extends Node
## Drives the life support station's O2 and CO2 alarm lamps from the alarm levels of the
## [LifeSupportReadouts] source (group `life_support_readouts`). The lamps are found by node name
## ([constant O2_LAMP], [constant CO2_LAMP]) in [member station], or, if that is unset, anywhere in the
## tree, so the generated station scene needs no script. STEADY lights the lamp; FLASH toggles it at
## [member flash_hz].

const O2_LAMP: StringName = &"O2AlarmLamp"
const CO2_LAMP: StringName = &"Co2AlarmLamp"

## The instanced station that holds the lamps. Unset: search the whole tree.
@export var station: Node
@export var flash_hz: float = 2.0

var _clock: float = 0.0


func _process(delta: float) -> void:
	advance(delta)


## Moves the flash clock on by [param delta] seconds and sets both lamps.
func advance(delta: float) -> void:
	_clock += delta
	var src: LifeSupportReadouts = _source()
	if src == null:
		return
	_drive(_lamp(O2_LAMP), src.o2_alarm())
	_drive(_lamp(CO2_LAMP), src.co2_alarm())


func _drive(lamp: IndicatorLamp, level: LifeSupportAlarmLevels.Level) -> void:
	if lamp == null:
		return
	match level:
		LifeSupportAlarmLevels.Level.STEADY:
			lamp.set_lit(true)
		LifeSupportAlarmLevels.Level.FLASH:
			lamp.set_lit(fmod(_clock * flash_hz, 1.0) < 0.5)
		_:
			lamp.set_lit(false)


func _source() -> LifeSupportReadouts:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(LifeSupportReadouts.GROUP) as LifeSupportReadouts


func _lamp(lamp_name: StringName) -> IndicatorLamp:
	var root: Node = station if station != null else (get_tree().current_scene if is_inside_tree() else null)
	if root == null:
		root = get_tree().root
	return root.find_child(String(lamp_name), true, false) as IndicatorLamp
