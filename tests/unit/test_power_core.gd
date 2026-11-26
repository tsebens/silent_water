extends TestCase

const C := PowerSystem.Circuit


func _make() -> PowerSystem:
	var p: PowerSystem = PowerSystem.new()
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func _run(p: PowerSystem, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		p.step(0.5)
		t += 0.5


## Minutes until charge hits zero (battery only), capped at limit.
func _minutes_to_empty(p: PowerSystem, limit_min: float) -> float:
	var t: float = 0.0
	while p.charge > 0.0 and t < limit_min * 60.0:
		p.step(1.0)
		t += 1.0
	return t / 60.0


func test_hold_drain_about_30_minutes() -> void:
	var p: PowerSystem = _make()
	expect_near(_minutes_to_empty(p, 60.0), 30.0, 2.0, "holding with lights and fans")
	p.free()


func test_full_throttle_drain_about_8_minutes() -> void:
	var p: PowerSystem = _make()
	p.set_engine_output(1.0)
	expect_near(_minutes_to_empty(p, 60.0), 8.0, 0.8, "full throttle on battery")
	p.free()


func test_generator_charges_in_about_4_minutes() -> void:
	var p: PowerSystem = _make()
	p.charge = 0.01
	p.start_generator()
	var t: float = 0.0
	while p.charge < 1.0 and t < 900.0:
		p.step(1.0)
		t += 1.0
	expect_near(t / 60.0, 4.0, 0.6, "empty to full")
	p.free()


func test_generator_start_delay() -> void:
	var p: PowerSystem = _make()
	expect(p.start_generator(), "starts")
	_run(p, 1.0)
	expect(not p.generator_running(), "still starting")
	_run(p, p.config.generator_start_delay)
	expect(p.generator_running(), "running after the delay")
	p.stop_generator()
	expect(not p.generator_running(), "stops at once")
	p.free()


func test_motor_cap_battery_vs_generator() -> void:
	var p: PowerSystem = _make()
	p.set_engine_output(1.0)
	expect_near(p.engine_output_limit(), pow(0.4, 1.0 / 1.5), 0.001, "battery cap")
	expect_near(p.effective_engine_output(), 0.543, 0.01)
	p.start_generator()
	_run(p, 6.0)
	expect_eq(p.engine_output_limit(), 1.0, "generator: full")
	p.free()


func test_motor_breaker_off_or_empty_gives_zero() -> void:
	var p: PowerSystem = _make()
	p.set_breaker(C.MOTOR, false)
	expect_eq(p.engine_output_limit(), 0.0, "MOTOR off")
	p.set_breaker(C.MOTOR, true)
	expect(p.engine_output_limit() > 0.0, "MOTOR back on")
	p.charge = 0.0
	p.step(0.1)
	expect_eq(p.engine_output_limit(), 0.0, "empty battery")
	p.free()


func test_generator_heat_rise_and_shutdown() -> void:
	var p: PowerSystem = _make()
	p.charge = 0.5
	p.set_engine_output(1.0)
	p.start_generator()
	_run(p, 10.0)
	expect(p.heat > 0.0, "heat rises under load")
	var t: float = 0.0
	while p.generator_running() and t < 1800.0:
		p.step(1.0)
		t += 1.0
	expect(not p.generator_running(), "shut itself down")
	expect(t > 540.0, "only after a long run (%f s)" % t)
	expect(not p.start_generator(), "no restart while hot")
	# Cool below the threshold.
	while p.heat >= p.config.heat_restart_threshold:
		p.step(1.0)
	p.step(1.0)
	expect(p.start_generator(), "restart once cool")
	p.free()


func test_heat_falls_when_idle() -> void:
	var p: PowerSystem = _make()
	p.heat = 0.5
	_run(p, 30.0)
	expect(p.heat < 0.5, "heat falls with the generator off")
	p.free()


func test_blackout_and_recovery() -> void:
	var p: PowerSystem = _make()
	var events: Array[bool] = []
	p.blackout_changed.connect(func(b: bool) -> void: events.append(b))
	p.charge = 0.0
	p.step(0.1)
	expect(p.is_blackout(), "blackout at zero")
	expect(not p.is_powered(C.FANS), "fans dead")
	p.start_generator()
	_run(p, 6.0)
	expect(not p.is_blackout(), "recovers with charge above zero")
	expect_eq(events, [true, false] as Array[bool])
	p.free()


func test_breaker_off_unpowers_and_signals() -> void:
	var p: PowerSystem = _make()
	var seen: Array = []
	p.circuit_powered.connect(func(c: int, on: bool) -> void: seen.append([c, on]))
	p.set_breaker(C.SONAR, false)
	expect(not p.is_powered(C.SONAR), "unpowered")
	expect_eq(seen, [[C.SONAR, false]])
	p.set_breaker(C.SONAR, true)
	expect(p.is_powered(C.SONAR), "powered again")
	p.set_breaker_state(C.SONAR, PowerSystem.BreakerState.BLOWN)
	p.set_breaker(C.SONAR, true)
	expect(not p.is_powered(C.SONAR), "blown stays dead")
	p.set_breaker_state(C.FANS, PowerSystem.BreakerState.TRIPPED)
	p.set_breaker(C.FANS, true)
	expect(p.is_powered(C.FANS), "trip resets by switching on")
	p.free()


func test_breaker_off_saves_power() -> void:
	var p: PowerSystem = _make()
	p.step(1.0)
	var all_on: float = p.draw_per_minute()
	p.set_breaker(C.FANS, false)
	p.step(1.0)
	expect(p.draw_per_minute() < all_on, "fans off draws less")
	p.free()


func test_noise() -> void:
	var p: PowerSystem = _make()
	expect_eq(p.noise_intensity(), 0.0, "silent at rest on battery")
	p.start_generator()
	_run(p, 6.0)
	expect_near(p.noise_intensity(), 0.03, 0.0001, "generator noise")
	p.free()


func test_readouts() -> void:
	var p: PowerSystem = _make()
	p.step(0.1)
	expect_near(p.readout(&"battery_charge"), 1.0, 0.01)
	expect(p.readout(&"load") > 0.0, "load")
	expect_eq(p.readout(&"generator_running"), 0.0)
	expect_eq(p.readout(&"generator_heat"), 0.0)
	expect_eq(p.readout(&"spares_remaining"), 4.0)
	expect_eq(p.readout(&"breaker_motor"), float(PowerSystem.BreakerState.ON))
	p.set_breaker(C.HELM, false)
	expect_eq(p.readout(&"breaker_helm"), float(PowerSystem.BreakerState.OFF))
	for n: StringName in PowerSystem.CIRCUIT_NAMES.values():
		expect(p.readout(StringName("breaker_" + String(n))) >= 0.0, "breaker_%s" % n)
	p.free()
