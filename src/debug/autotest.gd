class_name Autotest
extends Node
## Scripted multi-instance check, enabled with `--autotest`. Each instance runs
## a role chosen by `--name` (Crew1 is the host), acts out a short scenario,
## then prints one `AUTOTEST_REPORT {json}` line and quits. tools/check.sh
## compares the reports from every instance.
##
## Scenario (seconds after the session starts):
##   Crew2 walks forward for 1.5 s, grabs the engine lever at 2.0 and drags it
##     to max, releases at 3.5.
##   Crew3 tries to grab the same lever at 2.5 while Crew2 holds it and drags
##     it toward min. The host must reject this.
##   Crew1 (host) turns the ballast valve to about half between 2.0 and 3.0.
##   Everyone reports at 6.0; clients quit, the host quits once they are gone.

const REPORT_AT: float = 6.0

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


func _physics_process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var me: Player = _game.local_player()
	var lever: Interactable = _game.get_node("Interior/Stations/EngineLever") as Interactable
	var valve: Interactable = _game.get_node("Interior/Stations/BallastValve") as Interactable
	match role:
		"Crew2":
			if me != null:
				me.bot_move = Vector2(0, -1) if _t < 1.5 else Vector2.ZERO
			_once("grab", 2.0, func() -> void: lever.begin_interaction())
			if _t > 2.1 and _t < 3.3:
				lever.drag(Vector2(0, -8))
			_once("release", 3.5, func() -> void: lever.end_interaction())
		"Crew3":
			_once("grab", 2.5, func() -> void: lever.begin_interaction())
			if _t > 2.6 and _t < 3.2:
				lever.drag(Vector2(0, 8))
			_once("release", 3.4, func() -> void: lever.end_interaction())
		"Crew1":
			_once("grab", 2.0, func() -> void: valve.begin_interaction())
			if _t > 2.0 and _t < 3.0:
				# Clockwise circle, roughly 1.5 turns over the second.
				var a: float = (_t - 2.0) * TAU * 1.5
				var r: float = 120.0
				valve.drag(Vector2(-sin(a), cos(a)) * r * TAU * 1.5 * delta)
			_once("release", 3.0, func() -> void: valve.end_interaction())
	_once("report", REPORT_AT, _report)
	if role == "Crew1" and _done.has("report") and multiplayer.get_peers().is_empty():
		_once("quit", 0.0, func() -> void: get_tree().quit(0))


func _once(key: String, at: float, action: Callable) -> void:
	if _t >= at and not _done.has(key):
		_done.append(key)
		action.call()


func _report() -> void:
	var positions: Dictionary = {}
	for p: Node in _game.players.get_children():
		var pl: Player = p as Player
		positions[str(pl.name)] = [snappedf(pl.position.x, 0.01), snappedf(pl.position.y, 0.01), snappedf(pl.position.z, 0.01)]
	var lever: Interactable = _game.get_node("Interior/Stations/EngineLever") as Interactable
	var valve: Interactable = _game.get_node("Interior/Stations/BallastValve") as Interactable
	var report: Dictionary = {
		"role": role,
		"peer": Net.local_id(),
		"is_host": Net.is_host(),
		"players": positions,
		"lever": snappedf(lever.get_value(), 0.001),
		"lever_holder": lever.state.holder,
		"valve": snappedf(valve.get_value(), 0.001),
		"sub_transform": var_to_str(_game.sub_frame.sub_transform),
	}
	print("AUTOTEST_REPORT " + JSON.stringify(report))
	if not Net.is_host():
		await get_tree().create_timer(0.5).timeout
		Net.leave()
		get_tree().quit(0)
