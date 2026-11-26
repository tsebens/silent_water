extends TestCase
## PilotSeat helm behaviours: ballast keys without single-player mode, wheel
## zoom, and the JoystickIndicator.


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
	seat.holo = HoloMap.new()
	runner.add_child(seat)
	runner.add_child(seat.holo)
	return seat


func test_ballast_keys_drive_valves_without_single_player() -> void:
	DevSettings.single_player = false
	var seat: PilotSeat = _seat()
	seat._local_grabbing = true
	seat.drive(0.0, 0.0, 0.0, 1.0, 0.25)
	expect(seat.blow_valve.get_normalized() > 0.0, "blow key opens the blow valve")
	expect_near(seat.flood_valve.get_normalized(), 0.0, 0.001)
	seat.drive(0.0, 0.0, 0.0, -1.0, 0.25)
	expect(seat.flood_valve.get_normalized() > 0.0, "flood key opens the flood valve")
	seat._local_grabbing = false


func test_hint_always_lists_ballast_keys() -> void:
	DevSettings.single_player = false
	expect(PilotSeat.helm_hint().contains("blow") and PilotSeat.helm_hint().contains("flood"), "hint lists ballast")
	expect(not _seat().station_name().contains("SINGLE"), "title has no single-player tag")


func test_wheel_zooms_within_limits_only_when_seated() -> void:
	var seat: PilotSeat = _seat()
	var start: float = seat.holo.meters_per_unit
	expect(not seat.zoom_wheel(true), "ignored while not seated")
	expect_near(seat.holo.meters_per_unit, start)
	seat._local_grabbing = true
	seat.zoom_wheel(true)
	expect(seat.holo.meters_per_unit < start, "wheel up zooms in")
	seat.zoom_wheel(false)
	expect_near(seat.holo.meters_per_unit, start, 0.001)
	for i: int in range(100):
		seat.zoom_wheel(true)
	expect_near(seat.holo.meters_per_unit, seat.holo.min_meters_per_unit)
	for i: int in range(100):
		seat.zoom_wheel(false)
	expect_near(seat.holo.meters_per_unit, seat.holo.max_meters_per_unit)
	seat._local_grabbing = false


func test_joystick_tilts_in_proportion_to_each_axis() -> void:
	var j: JoystickIndicator = JoystickIndicator.new()
	j.stick = Node3D.new()
	j.add_child(j.stick)
	j.fore_aft = _axis()
	j.side = _axis()
	runner.add_child(j)
	j.fore_aft._set_local(0.5, true)
	j.refresh()
	var half: Vector3 = j.stick.transform.basis.get_euler()
	expect_near(absf(half.x), deg_to_rad(j.max_deg) * 0.5, 0.001)
	expect_near(half.z, 0.0, 0.001)
	j.fore_aft._set_local(1.0, true)
	j.refresh()
	expect_near(absf(j.stick.transform.basis.get_euler().x), deg_to_rad(j.max_deg), 0.001)
	j.fore_aft._set_local(0.0, true)
	j.side._set_local(-0.5, true)
	j.refresh()
	expect_near(absf(j.stick.transform.basis.get_euler().z), deg_to_rad(j.max_deg) * 0.5, 0.001)


func test_one_axis_stick_ignores_the_other() -> void:
	var j: JoystickIndicator = JoystickIndicator.new()
	j.stick = Node3D.new()
	j.add_child(j.stick)
	j.side = _axis()
	runner.add_child(j)
	j.side._set_local(1.0, true)
	j.refresh()
	expect_near(j.stick.transform.basis.get_euler().x, 0.0, 0.001, "no fore-aft tilt")
	expect(absf(j.stick.transform.basis.get_euler().z) > 0.1, "side tilts")
