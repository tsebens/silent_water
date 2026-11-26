class_name PowerSystem
extends Node
## The sub's power: battery, generator, motor draw and nine breakers. Not an
## autoload. Host-authoritative simulation; displays ask [method readout].
## Faults (tripped, blown) exist as breaker states but are driven by a later arc.

signal breaker_changed(circuit: Circuit, state: BreakerState)
## Emitted when a circuit gains or loses power (breaker, blackout).
signal circuit_powered(circuit: Circuit, powered: bool)
signal blackout_changed(blackout: bool)
signal generator_changed(running: bool)
signal generator_overheated

enum Circuit { MOTOR, THRUSTERS, BILGE_PUMP, CABIN_LTS, EXT_LTS, SONAR, FANS, HELM, DISPLAYS }
enum BreakerState { OFF, ON, TRIPPED, BLOWN }

const GROUP: StringName = &"power_system"
const CIRCUIT_NAMES: Dictionary = {
	Circuit.MOTOR: &"motor",
	Circuit.THRUSTERS: &"thrusters",
	Circuit.BILGE_PUMP: &"bilge_pump",
	Circuit.CABIN_LTS: &"cabin_lts",
	Circuit.EXT_LTS: &"ext_lts",
	Circuit.SONAR: &"sonar",
	Circuit.FANS: &"fans",
	Circuit.HELM: &"helm",
	Circuit.DISPLAYS: &"displays",
}

@export var config: PowerConfig = PowerConfig.new()

var charge: float = 1.0
var heat: float = 0.0
var spares: int = 4
## Overheated: the generator shut itself down and is cooling.
var heat_locked: bool = false

var _breakers: Dictionary = {}
var _wear: Dictionary = {}
var _powered: Dictionary = {}
var _gen_running: bool = false
var _gen_starting: bool = false
var _start_left: float = 0.0
var _blackout: bool = false
var _engine_output: float = 0.0
var _thruster_demand: float = 0.0
var _bilge_running: bool = false
var _draw_per_min: float = 0.0


func _init() -> void:
	for c: int in CIRCUIT_NAMES:
		_breakers[c] = BreakerState.ON
		_wear[c] = 0
		_powered[c] = true


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"noise_sources")
	spares = config.spare_count
	_refresh_power()


func _physics_process(delta: float) -> void:
	step(delta)


## Advance the simulation by [param delta] seconds.
func step(delta: float) -> void:
	if _gen_starting:
		_start_left -= delta
		if _start_left <= 0.0:
			_gen_starting = false
			_set_generator_running(true)
	_draw_per_min = _compute_draw()
	var net: float = -_draw_per_min
	if _gen_running:
		net += config.generator_charge_rate
	charge = clampf(charge + net * delta / 60.0, 0.0, 1.0)
	_update_heat(delta)
	_refresh_power()


# -- Generator ---------------------------------------------------------------

## Begin starting the generator. False if it cannot start (cooling, already on).
func start_generator() -> bool:
	if _gen_running or _gen_starting or heat_locked:
		return false
	_gen_starting = true
	_start_left = config.generator_start_delay
	return true


func stop_generator() -> void:
	_gen_starting = false
	_set_generator_running(false)


func generator_running() -> bool:
	return _gen_running


func generator_starting() -> bool:
	return _gen_starting


func _set_generator_running(on: bool) -> void:
	if _gen_running == on:
		return
	_gen_running = on
	generator_changed.emit(on)


func _update_heat(delta: float) -> void:
	var heavy: bool = (
		_gen_running
		and charge < 1.0
		and config.power_for_output(_engine_output) * _motor_factor() >= config.heat_load_power
	)
	if heavy:
		heat = minf(heat + config.heat_rise_per_s * delta, config.heat_limit)
	else:
		heat = maxf(heat - config.heat_fall_per_s * delta, 0.0)
	if _gen_running and heat >= config.heat_limit:
		heat_locked = true
		stop_generator()
		generator_overheated.emit()
	elif heat_locked and heat < config.heat_restart_threshold:
		heat_locked = false


# -- Motor and demand --------------------------------------------------------

## The pilot's requested engine output, -1..1.
func set_engine_output(output: float) -> void:
	_engine_output = clampf(output, -1.0, 1.0)


func set_thruster_demand(demand: float) -> void:
	_thruster_demand = clampf(absf(demand), 0.0, 1.0)


func set_bilge_pump_running(on: bool) -> void:
	_bilge_running = on


## Highest engine output the motor allows now (0 with the MOTOR breaker out or
## the battery empty; capped on the battery alone).
func engine_output_limit() -> float:
	if not is_powered(Circuit.MOTOR):
		return 0.0
	if _gen_running:
		return 1.0
	return config.output_for_power(config.motor_cap_battery)


## Engine output after the limit.
func effective_engine_output() -> float:
	return clampf(_engine_output, -engine_output_limit(), engine_output_limit())


func _motor_factor() -> float:
	return 1.0 if is_powered(Circuit.MOTOR) else 0.0


func motor_power() -> float:
	return config.power_for_output(effective_engine_output())


# -- Breakers ----------------------------------------------------------------

func breaker_state(circuit: Circuit) -> BreakerState:
	return _breakers.get(circuit, BreakerState.ON) as BreakerState


## Switch a breaker with the station's control. Switching on resets a trip;
## a blown breaker does nothing until replaced. Returns the resulting state.
func set_breaker(circuit: Circuit, on: bool) -> BreakerState:
	var s: BreakerState = breaker_state(circuit)
	if s == BreakerState.BLOWN:
		return s
	set_breaker_state(circuit, BreakerState.ON if on else BreakerState.OFF)
	return breaker_state(circuit)


## Force a state (used by the fault system and tests).
func set_breaker_state(circuit: Circuit, state: BreakerState) -> void:
	if _breakers.get(circuit) == state:
		return
	_breakers[circuit] = state
	breaker_changed.emit(circuit, state)
	_refresh_power()


func wear(circuit: Circuit) -> int:
	return _wear.get(circuit, 0) as int


func is_blackout() -> bool:
	return _blackout


## True when the circuit's breaker is on and the sub has power.
func is_powered(circuit: Circuit) -> bool:
	return breaker_state(circuit) == BreakerState.ON and not _blackout


# -- Draw --------------------------------------------------------------------

func _circuit_idle_draw(circuit: Circuit) -> float:
	match circuit:
		Circuit.CABIN_LTS:
			return config.cabin_lights_draw
		Circuit.EXT_LTS:
			return config.ext_lights_draw
		Circuit.FANS:
			return config.fans_draw
		Circuit.DISPLAYS:
			return config.displays_draw
		Circuit.SONAR:
			return config.sonar_draw
		Circuit.HELM:
			return config.helm_draw
	return 0.0


func _compute_draw() -> float:
	var total: float = 0.0
	for c: int in CIRCUIT_NAMES:
		if breaker_state(c as Circuit) != BreakerState.ON:
			continue
		total += _circuit_idle_draw(c as Circuit)
	if breaker_state(Circuit.MOTOR) == BreakerState.ON:
		total += config.motor_full_draw * motor_power()
	if breaker_state(Circuit.THRUSTERS) == BreakerState.ON:
		total += config.thruster_full_draw * _thruster_demand
	if breaker_state(Circuit.BILGE_PUMP) == BreakerState.ON and _bilge_running:
		total += config.bilge_pump_draw
	# A dead battery draws nothing, so the generator can bring it back.
	return 0.0 if _blackout else total


func draw_per_minute() -> float:
	return _draw_per_min


func _max_draw() -> float:
	return (
		config.cabin_lights_draw + config.ext_lights_draw + config.fans_draw
		+ config.displays_draw + config.sonar_draw + config.helm_draw
		+ config.motor_full_draw + config.thruster_full_draw + config.bilge_pump_draw
	)


func _refresh_power() -> void:
	var was: bool = _blackout
	# Blackout when empty; recovers as soon as charge is above zero.
	_blackout = charge <= 0.0
	if _blackout != was:
		blackout_changed.emit(_blackout)
	for c: int in CIRCUIT_NAMES:
		var p: bool = is_powered(c as Circuit)
		if _powered.get(c) != p:
			_powered[c] = p
			circuit_powered.emit(c, p)


# -- Noise and readouts ------------------------------------------------------

## Linear intensity: constant generator noise plus the motor's throttle noise.
func noise_intensity() -> float:
	var n: float = 0.0
	if _gen_running:
		n += config.generator_noise
	if is_powered(Circuit.MOTOR):
		n += config.motor_noise_full * motor_power()
	return n


func readout(readout_name: StringName) -> float:
	match readout_name:
		&"battery_charge":
			return charge
		&"load":
			return clampf(_draw_per_min / _max_draw(), 0.0, 1.0)
		&"generator_running":
			return 1.0 if _gen_running else 0.0
		&"generator_heat":
			return heat
		&"spares_remaining":
			return float(spares)
	var s: String = String(readout_name)
	if s.begins_with("breaker_"):
		for c: int in CIRCUIT_NAMES:
			if s == "breaker_" + String(CIRCUIT_NAMES[c]):
				return float(breaker_state(c as Circuit))
	return 0.0
