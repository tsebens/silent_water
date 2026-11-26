class_name PowerSystem
extends Node
## The sub's power: battery, generator, motor draw and nine breakers. Not an
## autoload. Host-authoritative simulation; displays ask [method readout].
## Faults: hits, flooding and overload trip breakers; each trip wears one and
## the third blows it. A blown breaker is replaced from [member spares].
##
## Replication follows [MapModel]: the host simulates and owns the state; every
## peer asks the host through [method request_breaker], [method request_generator]
## and the engine-side setters on the host. The host sends a snapshot on every
## discrete change and every [constant SNAPSHOT_INTERVAL] seconds (charge and
## heat drift), and a full snapshot to each joining peer. Clients do not simulate.

signal breaker_changed(circuit: Circuit, state: BreakerState)
## Emitted when a circuit gains or loses power (breaker, blackout).
signal circuit_powered(circuit: Circuit, powered: bool)
signal blackout_changed(blackout: bool)
signal generator_changed(running: bool)
signal generator_overheated
signal breaker_tripped(circuit: Circuit)
signal breaker_blown(circuit: Circuit)
signal breaker_replaced(circuit: Circuit)
## A junction box on a circuit's line is damaged (sparking) or repaired.
signal box_damage_changed(circuit: Circuit, box: int, damaged: bool)

enum Circuit { MOTOR, THRUSTERS, BILGE_PUMP, CABIN_LTS, EXT_LTS, SONAR, FANS, HELM, DISPLAYS }
enum BreakerState { OFF, ON, TRIPPED, BLOWN }

const SNAPSHOT_INTERVAL: float = 0.5
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
## Dev flag: start with this battery charge (0-1). Negative keeps the default (full).
@export var dev_start_charge: float = -1.0
## Dev flag: start with the generator already running.
@export var dev_generator_running: bool = false
## Optional: the sub's controller. Only its hull_strike signal is used.
@export var controller: SubController
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false

var charge: float = 1.0
var heat: float = 0.0
var spares: int = 4
## Overheated: the generator shut itself down and is cooling.
var heat_locked: bool = false

var _breakers: Dictionary = {}
## Damaged junction boxes: key [method box_key] -> true.
var _damaged: Dictionary = {}
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
var _snapshot_timer: float = 0.0
var _clock: float = 0.0
var _output_history: Array[Vector2] = []
var _flooded: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	for c: int in CIRCUIT_NAMES:
		_breakers[c] = BreakerState.ON
		_wear[c] = 0
		_powered[c] = true


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"noise_sources")
	spares = config.spare_count
	_rng.randomize()
	if controller == null and is_inside_tree():
		controller = get_tree().get_first_node_in_group(&"sub_controller") as SubController
	if controller != null:
		controller.hull_strike.connect(on_hull_strike)
	if dev_start_charge >= 0.0:
		charge = clampf(dev_start_charge, 0.0, 1.0)
	if dev_generator_running:
		_gen_running = true
	_refresh_power()
	breaker_changed.connect(func(_c: Circuit, _s: BreakerState) -> void: _broadcast())
	generator_changed.connect(func(_r: bool) -> void: _broadcast())
	generator_overheated.connect(_broadcast)
	blackout_changed.connect(func(_b: bool) -> void: _broadcast())
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


func _physics_process(delta: float) -> void:
	if not _is_host():
		return
	step(delta)
	if _online():
		_snapshot_timer += delta
		if _snapshot_timer >= SNAPSHOT_INTERVAL:
			_broadcast()


# -- Replication -------------------------------------------------------------

func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()


## Any peer: switch a breaker. The host applies it; clients ask the host.
func request_breaker(circuit: Circuit, on: bool) -> void:
	if _is_host():
		set_breaker(circuit, on)
	elif _online():
		_rpc_request_breaker.rpc_id(1, int(circuit), on)


## Any peer: start (true) or stop (false) the generator.
func request_generator(run: bool) -> void:
	if _is_host():
		if run:
			start_generator()
		else:
			stop_generator()
	elif _online():
		_rpc_request_generator.rpc_id(1, run)


@rpc("any_peer", "reliable")
func _rpc_request_breaker(circuit: int, on: bool) -> void:
	if _is_host() and CIRCUIT_NAMES.has(circuit):
		set_breaker(circuit as Circuit, on)


@rpc("any_peer", "reliable")
func _rpc_request_generator(run: bool) -> void:
	if not _is_host():
		return
	if run:
		start_generator()
	else:
		stop_generator()


## Any peer: replace a blown breaker from the spares.
func request_replace(circuit: Circuit) -> void:
	if _is_host():
		replace_breaker(circuit)
	elif _online():
		_rpc_request_replace.rpc_id(1, int(circuit))


@rpc("any_peer", "reliable")
func _rpc_request_replace(circuit: int) -> void:
	if _is_host() and CIRCUIT_NAMES.has(circuit):
		replace_breaker(circuit as Circuit)


## Any peer: repair a damaged junction box.
func request_repair(circuit: Circuit, box: int) -> void:
	if _is_host():
		repair_box(circuit, box)
	elif _online():
		_rpc_request_repair.rpc_id(1, int(circuit), box)


@rpc("any_peer", "reliable")
func _rpc_request_repair(circuit: int, box: int) -> void:
	if _is_host() and CIRCUIT_NAMES.has(circuit):
		repair_box(circuit as Circuit, box)


## The full replicated state as plain data.
func snapshot() -> Dictionary:
	var br: Dictionary = {}
	var wr: Dictionary = {}
	for c: int in CIRCUIT_NAMES:
		br[c] = int(_breakers[c])
		wr[c] = int(_wear[c])
	return {
		"breakers": br, "wear": wr, "charge": charge, "heat": heat,
		"heat_locked": heat_locked, "spares": spares, "gen_running": _gen_running,
		"gen_starting": _gen_starting, "start_left": _start_left,
		"engine_output": _engine_output, "thruster_demand": _thruster_demand,
		"bilge_running": _bilge_running, "draw": _draw_per_min,
		"damaged": _damaged.keys(),
	}


## Adopt a host snapshot, emitting the same signals a local change would.
func apply_snapshot(snap: Dictionary) -> void:
	charge = float(snap["charge"])
	heat = float(snap["heat"])
	heat_locked = bool(snap["heat_locked"])
	spares = int(snap["spares"])
	_start_left = float(snap["start_left"])
	_gen_starting = bool(snap["gen_starting"])
	_engine_output = float(snap["engine_output"])
	_thruster_demand = float(snap["thruster_demand"])
	_bilge_running = bool(snap["bilge_running"])
	_draw_per_min = float(snap["draw"])
	var dmg: Array = snap.get("damaged", [])
	var box_changes: Array[Vector3i] = []
	for k: int in _damaged.keys():
		if not dmg.has(k):
			box_changes.append(Vector3i(k / 16, k % 16, 0))
	for k: int in dmg:
		if not _damaged.has(k):
			box_changes.append(Vector3i(k / 16, k % 16, 1))
	_damaged.clear()
	for k: int in dmg:
		_damaged[k] = true
	var wr: Dictionary = snap["wear"]
	for c: int in wr:
		_wear[c] = int(wr[c])
	var changed: Array[int] = []
	var br: Dictionary = snap["breakers"]
	for c: int in br:
		if _breakers.get(c) != int(br[c]):
			_breakers[c] = int(br[c])
			changed.append(c)
	var running: bool = bool(snap["gen_running"])
	var gen_changed: bool = running != _gen_running
	_gen_running = running
	for c: int in changed:
		breaker_changed.emit(c as Circuit, _breakers[c] as BreakerState)
	if gen_changed:
		generator_changed.emit(running)
	for b: Vector3i in box_changes:
		box_damage_changed.emit(b.x as Circuit, b.y, b.z == 1)
	_refresh_power()


func _broadcast() -> void:
	_snapshot_timer = 0.0
	if _is_host() and _online():
		_rpc_snapshot.rpc(snapshot())


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_snapshot.rpc_id(peer_id, snapshot())


## Advance the simulation by [param delta] seconds.
func step(delta: float) -> void:
	_clock += delta
	if controller != null and controller.model != null:
		set_bilge_water(controller.model.bilge_water_t)
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
	var out: float = clampf(output, -1.0, 1.0)
	if _is_host():
		_check_output_overload(out)
	_engine_output = out


func set_thruster_demand(demand: float) -> void:
	_thruster_demand = clampf(absf(demand), 0.0, 1.0)


func set_bilge_pump_running(on: bool) -> void:
	var starting: bool = on and not _bilge_running
	_bilge_running = on
	if starting and _is_host() and is_powered(Circuit.BILGE_PUMP) \
			and motor_power() >= config.overload_pump_motor_power:
		trip(Circuit.BILGE_PUMP)


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
	# A damaged line trips again as soon as it is switched back on.
	if on and line_damaged(circuit):
		trip(circuit)
	return breaker_state(circuit)


## Force a state (used by the fault system and tests).
func set_breaker_state(circuit: Circuit, state: BreakerState) -> void:
	if _breakers.get(circuit) == state:
		return
	_breakers[circuit] = state
	breaker_changed.emit(circuit, state)
	_refresh_power()


## Trip a breaker that is on: it cuts out and wears; the wear limit blows it.
## Host only. Breakers already off, tripped or blown are unaffected.
func trip(circuit: Circuit) -> void:
	if not _is_host() or breaker_state(circuit) != BreakerState.ON:
		return
	_wear[circuit] = wear(circuit) + 1
	if wear(circuit) >= config.wear_limit:
		set_breaker_state(circuit, BreakerState.BLOWN)
		breaker_blown.emit(circuit)
	else:
		set_breaker_state(circuit, BreakerState.TRIPPED)
	breaker_tripped.emit(circuit)


## A hull strike of [param speed] m/s: at or above the threshold, one or two
## random circuits that are on trip. Wired to [signal SubController.hull_strike].
func on_hull_strike(speed: float) -> void:
	if not _is_host() or speed < config.trip_hit_threshold:
		return
	var live: Array[int] = []
	for c: int in CIRCUIT_NAMES:
		if breaker_state(c as Circuit) == BreakerState.ON:
			live.append(c)
	var count: int = mini(_rng.randi_range(1, 2), live.size())
	for i: int in count:
		var k: int = _rng.randi_range(0, live.size() - 1)
		trip(live[k] as Circuit)
		live.remove_at(k)
	if speed >= config.damage_hit_threshold and _rng.randf() < config.damage_chance:
		damage_box(
			_rng.randi_range(0, CIRCUIT_NAMES.size() - 1) as Circuit,
			_rng.randi_range(0, config.junction_boxes_per_line - 1))


# -- Damaged lines ----------------------------------------------------------

static func box_key(circuit: int, box: int) -> int:
	return circuit * 16 + box


func box_count(_circuit: Circuit) -> int:
	return config.junction_boxes_per_line


func box_damaged(circuit: Circuit, box: int) -> bool:
	return _damaged.has(box_key(circuit, box))


## True when any junction box on the circuit's line is damaged.
func line_damaged(circuit: Circuit) -> bool:
	for b: int in box_count(circuit):
		if box_damaged(circuit, b):
			return true
	return false


## Damage the line at a junction box; a live circuit trips at once. Host only.
func damage_box(circuit: Circuit, box: int) -> void:
	if not _is_host() or box < 0 or box >= box_count(circuit) or box_damaged(circuit, box):
		return
	_damaged[box_key(circuit, box)] = true
	box_damage_changed.emit(circuit, box, true)
	trip(circuit)
	_broadcast()


## Clear a box's damage; its sparking stops. Host only. False if not damaged.
func repair_box(circuit: Circuit, box: int) -> bool:
	if not _is_host() or not box_damaged(circuit, box):
		return false
	_damaged.erase(box_key(circuit, box))
	box_damage_changed.emit(circuit, box, false)
	_broadcast()
	return true


## Bilge water in tonnes. Crossing above the flood threshold trips the MOTOR
## and the BILGE PUMP once; it re-arms when the water falls back below it.
func set_bilge_water(tonnes: float) -> void:
	if not _is_host():
		return
	if tonnes > config.trip_flood_threshold:
		if not _flooded:
			_flooded = true
			trip(Circuit.MOTOR)
			trip(Circuit.BILGE_PUMP)
	else:
		_flooded = false


func _check_output_overload(new_output: float) -> void:
	_output_history.append(Vector2(_clock, new_output))
	while not _output_history.is_empty() and _clock - _output_history[0].x > config.overload_window:
		_output_history.remove_at(0)
	for h: Vector2 in _output_history:
		if absf(new_output - h.y) >= config.overload_output_jump:
			_output_history.clear()
			trip(Circuit.MOTOR)
			return


## Replace a blown breaker from the spares: it comes back off with no wear.
## Refused (false) with no spares or when the breaker is not blown.
func replace_breaker(circuit: Circuit) -> bool:
	if not _is_host() or breaker_state(circuit) != BreakerState.BLOWN or spares <= 0:
		return false
	spares -= 1
	_wear[circuit] = 0
	set_breaker_state(circuit, BreakerState.OFF)
	breaker_replaced.emit(circuit)
	_broadcast()
	return true


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


## Named parts of [method noise_intensity], for the session log.
func noise_breakdown() -> Dictionary:
	return {
		"generator": config.generator_noise if _gen_running else 0.0,
		"motor": config.motor_noise_full * motor_power() if is_powered(Circuit.MOTOR) else 0.0,
	}


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
