class_name LifeSupportAlarmDriver
extends Node
## Drives the life support station's O2 and CO2 alarm lamps from the alarm levels of the
## [LifeSupportReadouts] source (group `life_support_readouts`). The lamps are found by node name
## ([constant O2_LAMP], [constant CO2_LAMP]) in [member station], or, if that is unset, anywhere in the
## tree, so the generated station scene needs no script. STEADY lights the lamp; FLASH toggles it at
## [member flash_hz].
##
## The driver also plays the alarm chime ([constant CHIME_PATH]) from the lamps: every
## [member steady_chime_period] seconds while the worst alarm is STEADY, every [member flash_chime_period]
## while it FLASHes, and never while both are off. Each chime is a small noise event.

const O2_LAMP: StringName = &"O2AlarmLamp"
const CO2_LAMP: StringName = &"Co2AlarmLamp"

## The instanced station that holds the lamps. Unset: search the whole tree.
@export var station: Node
@export var flash_hz: float = 2.0

const CHIME_PATH: String = "res://src/noise/sound_types/alarm_chime.tres"

## Seconds between chimes while the worst alarm is steady, and while it flashes.
@export var steady_chime_period: float = 2.5
@export var flash_chime_period: float = 0.6

## Chimes played so far.
var chime_count: int = 0

var _clock: float = 0.0
var _chime_wait: float = 0.0
var _chime: SoundEmitter


func _process(delta: float) -> void:
	advance(delta)


## Moves the flash clock on by [param delta] seconds and sets both lamps.
func advance(delta: float) -> void:
	_clock += delta
	var src: LifeSupportReadouts = _source()
	if src == null:
		return
	var o2: LifeSupportAlarmLevels.Level = src.o2_alarm()
	var co2: LifeSupportAlarmLevels.Level = src.co2_alarm()
	_drive(_lamp(O2_LAMP), o2)
	_drive(_lamp(CO2_LAMP), co2)
	_chime_step(delta, maxi(int(o2), int(co2)) as LifeSupportAlarmLevels.Level)


## The chime emitter (one-shot sound type), created on first use.
func chime_emitter() -> SoundEmitter:
	if _chime == null:
		_chime = SoundEmitter.new()
		_chime.name = "ChimeEmitter"
		_chime.sound_type = load(CHIME_PATH) as SoundType  # load, not preload (script dependency cycle)
		add_child(_chime)
	return _chime


func _chime_step(delta: float, worst: LifeSupportAlarmLevels.Level) -> void:
	if worst == LifeSupportAlarmLevels.Level.OFF:
		_chime_wait = 0.0
		return
	var period: float = flash_chime_period if worst == LifeSupportAlarmLevels.Level.FLASH else steady_chime_period
	_chime_wait = minf(_chime_wait, period) - delta
	if _chime_wait > 0.0:
		return
	_chime_wait = period
	var em: SoundEmitter = chime_emitter()
	var lamp: IndicatorLamp = _lamp(O2_LAMP)
	if lamp != null and lamp.is_inside_tree():
		em.world_position = lamp.global_position
	em.fire()
	chime_count += 1


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
