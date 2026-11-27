extends TestCase
## End-to-end: a crude autopilot flies a whole dive with the real controls and
## physics (apex switched off). It proves the loop can be completed: flood
## down, reach the array, hold still and scan, blow back to the surface.
## It also gives a rough idea of how long a dive takes.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const TIME_LIMIT_SEC: float = 20.0 * 60.0
## Hover point near the array, off the wall, a little above the shelf.
const HOVER: Vector3 = Vector3(24, CanyonSite.SHELF2_TOP + 10.0, -250)
## Close enough to the hover point to start scanning (the scanner reaches 30 m).
const ARRIVE_M: float = 20.0

var game: Game
var c: SubController
var scan: ScanObjective
var director: DiveDirector
var completed: bool = false
var _stuck_time: float = 0.0
var _backing: float = 0.0


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	Acoustics.reset()
	c = game.get_node("SubController") as SubController
	scan = game.get_node("ScanObjective") as ScanObjective
	director = game.get_node("DiveDirector") as DiveDirector
	var apex: ApexMonster = game.get_node("World/Apex") as ApexMonster
	apex.brain_enabled = false
	apex.speed_unaware = 0.0
	(game.get_node("LeakSystem") as LeakSystem).set_physics_process(false)
	completed = false
	director.dive_complete.connect(func() -> void: completed = true)


func after_each() -> void:
	game.end_session()
	game.free()


func _put(path: String, v: float) -> void:
	var it: Interactable = game.get_node("Interior/Stations/" + path) as Interactable
	if not is_equal_approx(it.get_value(), v):
		it.host_set_value(v)


## Ballast and planes toward a target depth (world y).
func _hold_depth(target_y: float) -> void:
	var err: float = c.model.position.y - target_y  # + means too high
	var vy: float = c.model.velocity.y
	var want_vy: float = clampf(-err * 0.08, -0.8, 0.8)
	var dv: float = vy - want_vy
	_put("Ballast/Panel/FloodWheel", clampf(dv * 2.0, 0.0, 1.0))
	_put("Ballast/Panel/BlowWheel", clampf(-dv * 1.0, 0.0, 1.0))
	_put("Pilot/Planes", clampf(err * 0.05, -1.0, 1.0))


func _steer_to(target: Vector3) -> float:
	var to: Vector3 = target - c.model.position
	var flat: float = Vector2(to.x, to.z).length()
	var desired_yaw: float = atan2(-to.x, -to.z)
	var err: float = wrapf(desired_yaw - c.model.angles.y, -PI, PI)
	_put("Pilot/Rudder", clampf(-err * 3.0, -1.0, 1.0))
	# Full ahead in transit, slow on approach, then coast in and brake.
	var order: float = 3.0 if flat > 90.0 else (1.0 if flat > 45.0 else 0.0)
	if flat < 45.0 and c.speed > 0.7:
		order = -1.0
	if flat < 45.0 and c.speed < 0.25 and flat > ARRIVE_M:
		order = 1.0  # Nudge closer.
	if absf(err) > 1.2 and flat > 45.0:
		order = 1.0  # Slow down to turn.
	# Pinned against rock with way on ordered: back off like a pilot would.
	if order > 0.0 and absf(c.speed) < 0.15:
		_stuck_time += 1.0 / 60.0
	else:
		_stuck_time = 0.0
	if _stuck_time > 8.0:
		_backing = 10.0
		_stuck_time = 0.0
	if _backing > 0.0:
		_backing -= 1.0 / 60.0
		order = -2.0
		_put("Pilot/Rudder", 0.0)
	_put("Pilot/Throttle", order / 3.0)
	return flat


func test_autopilot_completes_a_dive() -> void:
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	var scan_started_at: float = -1.0
	var phase: String = "descend"
	while t < TIME_LIMIT_SEC and not completed:
		match phase:
			"descend":
				# Sink in place to working depth first, then cross at depth.
				_put("Pilot/Throttle", 0.0)
				_put("Pilot/Rudder", 0.0)
				_hold_depth(HOVER.y)
				if absf(c.model.position.y - HOVER.y) < 8.0:
					phase = "transit"
			"transit":
				var flat: float = _steer_to(HOVER)
				_hold_depth(HOVER.y)
				if flat < ARRIVE_M and absf(c.model.position.y - HOVER.y) < 6.0:
					phase = "scan"
			"scan":
				_steer_to(HOVER)
				_hold_depth(HOVER.y)
				if scan.in_position():
					_put("Science/Station/Panel/Bay0/Module/ArmSwitch", 1.0)
					if scan_started_at < 0.0:
						scan_started_at = t
				if scan.complete:
					phase = "ascend"
			"ascend":
				_put("Pilot/Throttle", 0.0)
				_put("Pilot/Rudder", 0.0)
				_put("Pilot/Planes", 0.0)
				_put("Ballast/Panel/FloodWheel", 0.0)
				_put("Ballast/Panel/BlowWheel", 1.0 if not c.surfaced else 0.0)
		await runner.get_tree().physics_frame
		t += dt
		if fmod(t, 60.0) < dt:
			print("[full dive] t=%.0f %s pos=%s speed=%.2f" % [t, phase, c.model.position.snapped(Vector3.ONE), c.speed])
	print("[full dive] %s after %.0f s (scan began %.0f s), air left %.0f%%, max depth %.0f m" % [
		"complete" if completed else "stuck in phase " + phase, t, scan_started_at, c.air_fraction * 100.0, director.max_depth])
	expect(completed, "autopilot should finish the dive (stuck in %s at %s)" % [phase, c.model.position])
	expect(director.max_depth > 120.0, "it actually went deep")
