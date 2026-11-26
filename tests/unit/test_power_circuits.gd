extends TestCase
## Consumers on their circuits: SONAR, DISPLAYS, HELM and FANS react to their
## circuit's power by signal.

const C := PowerSystem.Circuit
const B := PowerSystem.BreakerState


func _power() -> PowerSystem:
	# Other tests leave power systems in the tree; sinks bind to the first in the group.
	for stale: Node in runner.get_tree().get_nodes_in_group(PowerSystem.GROUP):
		stale.remove_from_group(PowerSystem.GROUP)
	var p: PowerSystem = PowerSystem.new()
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func _axis() -> SpringAxis:
	var a: SpringAxis = SpringAxis.new()
	runner.add_child(a)
	return a


func _seat() -> PilotSeat:
	var seat: PilotSeat = PilotSeat.new()
	seat.throttle = _axis()
	seat.rudder = _axis()
	seat.planes = _axis()
	seat.blow_valve = Interactable.new()
	runner.add_child(seat.blow_valve)
	seat.flood_valve = Interactable.new()
	runner.add_child(seat.flood_valve)
	runner.add_child(seat)
	return seat


func test_sonar_dead_when_circuit_out() -> void:
	var p: PowerSystem = _power()
	var s: SonarStation = SonarStation.new()
	runner.add_child(s)
	s.signal_db = 80.0
	expect(s.powered)
	expect_near(s.readout(&"signal"), 80.0)
	p.set_breaker(C.SONAR, false)
	expect(not s.powered, "unpowered by signal")
	expect_near(s.readout(&"signal"), 0.0)
	expect(not s.is_local_operator())
	p.set_breaker(C.SONAR, true)
	expect(s.powered, "powers back up")
	s.free()
	p.free()


func test_sonar_screen_goes_dark() -> void:
	var p: PowerSystem = _power()
	var chart: FlatChart = FlatChart.new()
	runner.add_child(chart)
	p.set_breaker(C.SONAR, false)
	expect(not chart.visible)
	p.set_breaker(C.SONAR, true)
	expect(chart.visible)
	chart.free()
	p.free()


func test_displays_go_dark() -> void:
	var p: PowerSystem = _power()
	var holo: HoloMap = HoloMap.new()
	var multi: MultiDisplay = MultiDisplay.new()
	var depth: DepthFinder = DepthFinder.new()
	var ball: Navball = Navball.new()
	var label: Label3D = Label3D.new()
	label.name = "HDG"
	ball.add_child(label)
	for n: Node in [holo, multi, depth, ball]:
		runner.add_child(n)
	p.set_breaker(C.DISPLAYS, false)
	expect(not holo.visible and not holo.powered, "holo dark")
	expect(not multi.visible and not multi.powered, "multidisplay dark")
	expect(not depth.visible and not depth.powered, "depth finder dark")
	expect(not ball.powered and not label.visible, "navball digits dark")
	p.set_breaker(C.DISPLAYS, true)
	expect(holo.visible and multi.visible and depth.visible and label.visible, "back on")
	for n: Node in [holo, multi, depth, ball]:
		n.free()
	p.free()


func test_sonar_circuit_leaves_displays_alone() -> void:
	var p: PowerSystem = _power()
	var depth: DepthFinder = DepthFinder.new()
	runner.add_child(depth)
	p.set_breaker(C.SONAR, false)
	expect(depth.visible)
	depth.free()
	p.free()


func test_helm_out_blocks_ballast_keeps_steering() -> void:
	var p: PowerSystem = _power()
	var seat: PilotSeat = _seat()
	seat._local_grabbing = true
	for a: SpringAxis in [seat.throttle, seat.rudder, seat.planes]:
		a._local_grabbing = true
	p.set_breaker(C.HELM, false)
	expect(not seat.helm_powered)
	seat.drive(0.0, 1.0, 1.0, 1.0, 0.25)
	expect_near(seat.blow_valve.get_normalized(), 0.0, 0.001, "blow key blocked")
	expect(seat.rudder.get_value() > 0.0, "rudder still steers")
	expect(seat.planes.get_value() > 0.0, "planes still work")
	seat.drive(0.0, 0.0, 0.0, -1.0, 0.25)
	expect_near(seat.flood_valve.get_normalized(), 0.0, 0.001, "flood key blocked")
	p.set_breaker(C.HELM, true)
	seat.drive(0.0, 0.0, 0.0, 1.0, 0.25)
	expect(seat.blow_valve.get_normalized() > 0.0, "ballast back with power")
	seat._local_grabbing = false
	seat.free()
	p.free()


func test_helm_loss_releases_held_ballast() -> void:
	var p: PowerSystem = _power()
	var seat: PilotSeat = _seat()
	seat._local_grabbing = true
	seat.drive(0.0, 0.0, 0.0, 1.0, 0.25)
	expect(seat.blow_valve.get_normalized() > 0.0)
	p.set_breaker(C.HELM, false)
	expect_near(seat.blow_valve.get_normalized(), 0.0, 0.001, "valve closed on loss")
	seat._local_grabbing = false
	seat.free()
	p.free()


func test_fans_state_readable_and_signalled() -> void:
	var p: PowerSystem = _power()
	var ls: LifeSupportReadouts = LifeSupportReadouts.new()
	runner.add_child(ls)
	var events: Array[bool] = []
	ls.fans_powered_changed.connect(func(on: bool) -> void: events.append(on))
	expect(ls.fans_powered)
	expect_near(ls.readout(&"fans_powered"), 1.0)
	p.set_breaker(C.FANS, false)
	expect(not ls.fans_powered)
	expect_near(ls.readout(&"fans_powered"), 0.0)
	p.set_breaker(C.FANS, true)
	expect_eq(events.size(), 2)
	expect(events[0] == false and events[1] == true)
	ls.free()
	p.free()


func test_blackout_unpowers_every_consumer() -> void:
	var p: PowerSystem = _power()
	var s: SonarStation = SonarStation.new()
	var ls: LifeSupportReadouts = LifeSupportReadouts.new()
	runner.add_child(s)
	runner.add_child(ls)
	p.charge = 0.0
	p.step(0.1)
	expect(not s.powered and not ls.fans_powered)
	s.free()
	ls.free()
	p.free()
