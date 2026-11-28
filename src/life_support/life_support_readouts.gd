class_name LifeSupportReadouts
extends Node
## Source of the life support readouts, in group [code]life_support_readouts[/code].
## The host runs [LifeSupportModel] (crew inside the sub, fans, seated canisters,
## surfacing) and replicates the result; clients only display it. Displays ask
## [method readout] by name. The values stay plain settable fields, which the
## model reads back at the start of each step.
##
## Replication follows [PowerSystem]: a snapshot every [constant SNAPSHOT_INTERVAL]
## seconds and a full one to each joining peer.

signal co2_alarm_changed(level: LifeSupportAlarmLevels.Level)
signal o2_alarm_changed(level: LifeSupportAlarmLevels.Level)
## The FANS circuit gained or lost power.
signal fans_powered_changed(powered: bool)

const GROUP: StringName = &"life_support_readouts"
## Name of the station's fan switch (a SwitchLever), found anywhere under [member station] or the tree.
const FAN_SWITCH: StringName = &"FanToggle"
## Names of the station's two cradles (CanisterSlot); their canisters scrub and drive the saturations.
const CRADLE_A: StringName = &"CradleA"
const CRADLE_B: StringName = &"CradleB"
const SNAPSHOT_INTERVAL: float = 0.5

@export var alarm_levels: LifeSupportAlarmLevels = LifeSupportAlarmLevels.new()
## CO2 ppm that reads as co2_level 1.0 (the IDLH line).
@export var co2_full_scale_ppm: float = 40000.0
## The instanced life support station whose fan switch sets [member fans_on]. Unset: search the whole tree.
@export var station: Node
@export var params: LifeSupportParams = LifeSupportParams.new()
## CO2 removal or production (litres per second) that fills the rate gauge's scale:
## two fresh canisters.
@export var rate_full_scale_lps: float = 3.0
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false
## Test seam: crew count to use instead of counting players (negative: count them).
var crew_override: int = -1

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
## Cabin oxygen, 1 normal to 0. Falls only once the O2 tank is empty; the crew effects read it.
var cabin_o2: float = 1.0
## What the crew is breathing out, and what the scrubbers could remove now (litres per second).
var co2_production_lps: float = 0.0
var co2_capacity_lps: float = 0.0

var model: LifeSupportModel
var _snapshot_timer: float = 0.0
var _cradle_seen: Array[bool] = [false, false]

var _co2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF
var _o2_alarm: LifeSupportAlarmLevels.Level = LifeSupportAlarmLevels.Level.OFF


func _ready() -> void:
	add_to_group(GROUP)
	PowerSink.bind(self, PowerSystem.Circuit.FANS, set_fans_powered)
	model = LifeSupportModel.new(params)
	_update_alarms()
	_bind_fan_switch()
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


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()


## Host: advances the model by [param delta] with the crew, fans, cradle canisters
## and surfacing as they are now, and publishes the result to the readout fields.
func step(delta: float) -> void:
	model.set_co2_ppm(co2_ppm)
	model.o2_tank = o2_level
	model.cabin_o2 = cabin_o2
	var slots: Array[CanisterSlot] = [_cradle(CRADLE_A), _cradle(CRADLE_B)]
	var caps: Array[float] = []
	var seated: Array[ScrubberCanister] = []
	for slot: CanisterSlot in slots:
		if slot != null and slot.canister() != null:
			seated.append(slot.canister())
			caps.append(slot.canister().capacity)
	model.step(delta, breathers(), fans_running(), _surfaced(), caps)
	for i: int in seated.size():
		seated[i].capacity = caps[i]
	co2_ppm = model.co2_ppm()
	o2_level = model.o2_tank
	cabin_o2 = model.cabin_o2
	co2_production_lps = model.production_rate
	# The needle shows what the scrubbers remove now: nothing while the fans are stopped.
	co2_capacity_lps = model.capacity_rate if fans_running() else 0.0
	for i: int in slots.size():
		if slots[i] != null:
			var c: ScrubberCanister = slots[i].canister()
			# A cradle that never held a canister leaves the field as set; one emptied reads spent.
			if c == null and not _cradle_seen[i]:
				continue
			_cradle_seen[i] = true
			var sat: float = 1.0 - c.capacity if c != null else 1.0
			if i == 0:
				saturation_a = sat
			else:
				saturation_b = sat


## Everyone breathing the cabin air: [method crew_inside] plus the survivors aboard.
## Only this feeds the CO2 and O2 draw; incapacitation and the loss rule count players.
func breathers() -> int:
	var n: int = crew_inside()
	if is_inside_tree():
		var sv: SurvivorsAboard = get_tree().get_first_node_in_group(SurvivorsAboard.GROUP) as SurvivorsAboard
		if sv != null:
			n += sv.count
	return n


## Players in the sub ([member crew_override] replaces the count in tests). All of them count today (no diving gear, no outside).
func crew_inside() -> int:
	if crew_override >= 0:
		return crew_override
	if not is_inside_tree():
		return 0
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"noise_sources"):
		if node is Player:
			n += 1
	return n


func _surfaced() -> bool:
	if not is_inside_tree():
		return false
	var sc: SubController = get_tree().get_first_node_in_group(&"sub_controller") as SubController
	return sc != null and sc.surfaced


func _cradle(cradle_name: StringName) -> CanisterSlot:
	var root: Node = station if station != null else (get_tree().root if is_inside_tree() else null)
	return root.find_child(cradle_name, true, false) as CanisterSlot if root != null else null


# -- Replication -------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"co2_ppm": co2_ppm, "o2_level": o2_level, "cabin_o2": cabin_o2,
		"sat_a": saturation_a, "sat_b": saturation_b,
		"production": co2_production_lps, "capacity": co2_capacity_lps,
	}


func apply_snapshot(snap: Dictionary) -> void:
	co2_ppm = float(snap["co2_ppm"])
	o2_level = float(snap["o2_level"])
	cabin_o2 = float(snap["cabin_o2"])
	saturation_a = float(snap["sat_a"])
	saturation_b = float(snap["sat_b"])
	co2_production_lps = float(snap["production"])
	co2_capacity_lps = float(snap["capacity"])


func _broadcast() -> void:
	_snapshot_timer = 0.0
	if _is_host() and _online():
		_rpc_snapshot.rpc(snapshot())


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


func _on_peer_joined(peer_id: int) -> void:
	if _is_host():
		_rpc_snapshot.rpc_id(peer_id, snapshot())


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
		&"cabin_o2":
			return cabin_o2
		&"co2_production_rate":
			return clampf(co2_production_lps / rate_full_scale_lps, 0.0, 1.0) if rate_full_scale_lps > 0.0 else 0.0
		&"co2_capacity_rate":
			return clampf(co2_capacity_lps / rate_full_scale_lps, 0.0, 1.0) if rate_full_scale_lps > 0.0 else 0.0
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
