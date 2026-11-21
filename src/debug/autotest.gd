class_name Autotest
extends Node
## Scripted multi-instance check, enabled with `--autotest`. Each instance runs
## a role chosen by `--name` (Crew1 is the host), acts out a short scenario,
## then prints one `AUTOTEST_REPORT {json}` line and quits. tools/check.sh
## compares the reports from every instance (tools/compare_autotest.py).
##
## Scenario (seconds after the session starts):
##   Crew2 walks forward for 1.5 s, grabs the cabin lights lever at 2.0, drags
##     it all the way down and releases at 3.5.
##   Crew3 tries to grab the same lever from 2.5, once it sees Crew2 holding
##     it, and drags it up. The host must reject this. At 3.6 Crew3 takes the helm and holds
##     W (throttle ahead) and A (rudder to port) from 4.0.
##   Crew1 (host) opens the flood valve about 1.5 turns between 2.0 and 3.0.
##   Crew2 "talks" at 75 dB from 4.0 on (simulated mic level) and puts on
##   the sonar headset at 4.5 (it's on the starboard side; the cord check
##   uses distance, so Crew2 is moved next to it first).
##   At 10.0 (engine fully spooled, so noise is steady) the host tells every
##   instance to report at once; clients then quit, and the host quits once
##   they are gone. The host holds the report for up to REPORT_GRACE while any
##   peer's last voice report is older than VOICE_FRESH, so a lost unreliable
##   packet or a scheduler stall near the snapshot can't read a timed-out voice
##   as silence (#86). After the grace it reports regardless.

const REPORT_AT: float = 10.0
## Longest the host waits past REPORT_AT for fresh voice reports (s).
const REPORT_GRACE: float = 3.0
## A peer's voice counts as fresh when its last report is younger than this (s).
## Must stay well under Acoustics.VOICE_TIMEOUT or the wait is pointless.
const VOICE_FRESH: float = 0.25
const STATIONS: String = "Interior/Stations/"

var role: String = ""
var _game: Game
var _t: float = -1.0
var _done: PackedStringArray = PackedStringArray()


func setup(game: Game, player_name: String) -> void:
	_game = game
	role = player_name
	Net.hosting_started.connect(_begin)
	Net.connected_to_host.connect(_begin)


func _begin() -> void:
	_t = 0.0


func _node(path: String) -> Node:
	return _game.get_node(STATIONS + path)


func _physics_process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var me: Player = _game.local_player()
	var lever: Interactable = _node("Pilot/Dimmer") as Interactable
	var flood: Interactable = _node("Ballast/FloodValve") as Interactable
	var seat: PilotSeat = _node("Pilot/Seat") as PilotSeat
	match role:
		"Crew2":
			if me != null:
				me.bot_move = Vector2(0, -1) if _t < 1.5 else Vector2.ZERO
			_once("grab", 2.0, func() -> void: lever.begin_interaction())
			if _t > 2.1 and _t < 3.3:
				lever.drag(Vector2(0, 8))
			_once("release", 3.5, func() -> void: lever.end_interaction())
			# Through the mic meter, so it's the only thing reporting this voice.
			MicMeter.forced_db = 75.0 if _t > 4.0 else -1.0
			_once("pin", 5.0, func() -> void:
				(_game.get_node("MapModel") as MapModel).add_pin(Vector3(5, -30, -80), MapModel.Kind.DANGER))
			if me != null:
				_once("headset", 4.5, func() -> void:
					var headset: Wearable = _node("Sonar/Headset") as Wearable
					me.teleport(headset.global_position + Vector3(-0.8, -1.4, 0))
					me.put_on(headset))
		"Crew3":
			# Only contest the lever once Crew2's hold has reached this instance:
			# instances start their clocks when they connect, so on a loaded
			# runner a fixed time can land before Crew2's grab and Crew3 would
			# win the lever (#210). Never grab late either.
			if _t >= 2.5 and _t < 3.2 and not _done.has("grab") \
					and lever.state.holder != InteractableState.NO_HOLDER \
					and lever.state.holder != Net.local_id():
				_once("grab", 2.5, func() -> void: lever.begin_interaction())
			if _done.has("grab") and _t < 3.2:
				lever.drag(Vector2(0, -8))
			_once("release", 3.4, func() -> void: lever.end_interaction())
			if me != null:
				_once("sit", 3.6, func() -> void: me.sit_in(seat))
				me.bot_move = Vector2(-1, -1) if _t > 4.0 else Vector2.ZERO
		"Crew1":
			_once("grab", 2.0, func() -> void: flood.begin_interaction())
			if _t > 2.0 and _t < 3.0:
				# Clockwise circle, 1.5 turns over the second.
				var a: float = (_t - 2.0) * TAU * 1.5
				var r: float = 120.0
				flood.drag(Vector2(-sin(a), cos(a)) * r * TAU * 1.5 * delta)
			_once("release", 3.0, func() -> void: flood.end_interaction())
	# The host tells everyone when to report so all snapshots are simultaneous.
	if Net.is_host() and not _done.has("report"):
		var ages: Array[float] = []
		for peer: int in multiplayer.get_peers():
			ages.append(Acoustics.voice_age(peer))
		if report_due(_t, ages):
			_rpc_report.rpc()
	if role == "Crew1" and _done.has("report") and multiplayer.get_peers().is_empty():
		_once("quit", 0.0, func() -> void: get_tree().quit(0))


## Whether the host should snapshot now, given the session time and how long
## ago each connected peer last reported its voice. True once REPORT_AT has
## passed and every report is fresher than VOICE_FRESH, or once REPORT_GRACE
## more has run out either way.
static func report_due(t: float, voice_ages: Array[float]) -> bool:
	if t < REPORT_AT:
		return false
	if t >= REPORT_AT + REPORT_GRACE:
		return true
	for age: float in voice_ages:
		if age >= VOICE_FRESH:
			return false
	return true


func _once(key: String, at: float, action: Callable) -> void:
	if _t >= at and not _done.has(key):
		_done.append(key)
		action.call()


static func _count_host_events() -> int:
	var n: int = 0
	for entry: Array in DevLog.lines:
		if String(entry[1]).begins_with("[host]"):
			n += 1
	return n


static func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


@rpc("authority", "call_local", "reliable")
func _rpc_report() -> void:
	_done.append("report")
	_report()


func _report() -> void:
	var positions: Dictionary = {}
	for p: Node in _game.players.get_children():
		var pl: Player = p as Player
		positions[str(pl.name)] = [snappedf(pl.position.x, 0.01), snappedf(pl.position.y, 0.01), snappedf(pl.position.z, 0.01)]
	var seat: PilotSeat = _node("Pilot/Seat") as PilotSeat
	var controller: SubController = _game.get_node("SubController") as SubController
	var report: Dictionary = {
		"role": role,
		"peer": Net.local_id(),
		"is_host": Net.is_host(),
		"players": positions,
		"lever": snappedf((_node("Pilot/Dimmer") as Interactable).get_value(), 0.001),
		"lever_holder": (_node("Pilot/Dimmer") as Interactable).state.holder,
		"throttle": snappedf((_node("Pilot/Throttle") as Interactable).get_value(), 0.001),
		"flood": snappedf((_node("Ballast/FloodValve") as Interactable).get_value(), 0.001),
		"rudder": snappedf((_node("Pilot/Rudder") as Interactable).get_value(), 0.001),
		"seat_holder": seat.state.holder,
		"seat_point": [snappedf(seat.seat_transform().origin.x, 0.01), snappedf(seat.seat_transform().origin.y, 0.01), snappedf(seat.seat_transform().origin.z, 0.01)],
		"engine": snappedf(controller.engine_output, 0.01),
		"tank": snappedf(controller.tank_fraction, 0.001),
		"depth": snappedf(controller.depth, 0.01),
		"sub_db": snappedf(Acoustics.sub_db(), 0.01),
		"host_events": _count_host_events(),
		"pins": (_game.get_node("MapModel") as MapModel).pins.size(),
		"headset_holder": (_node("Sonar/Headset") as Interactable).state.holder,
		"apex_state": (_game.get_node("World/Apex") as ApexMonster).state(),
		"apex_pos": _vec((_game.get_node("World/Apex") as ApexMonster).position),
		"ambient_db": snappedf(Acoustics.ambient_db(), 0.01),
	}
	if Net.is_host():
		var voices: Dictionary = {}
		for peer: int in multiplayer.get_peers():
			voices[str(peer)] = snappedf(NoiseLevel.to_db(Acoustics.voice_intensity(peer)), 0.1)
		report["voices_db"] = voices
	print("AUTOTEST_REPORT " + JSON.stringify(report))
	if not Net.is_host():
		await get_tree().create_timer(0.5).timeout
		Net.leave()
		get_tree().quit(0)
