extends TestCase

const C := PowerSystem.Circuit
const B := PowerSystem.BreakerState


func _make(client: bool = false) -> PowerSystem:
	var p: PowerSystem = PowerSystem.new()
	p.simulate_client = client
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func _tripped_count(p: PowerSystem) -> int:
	var n: int = 0
	for c: int in PowerSystem.CIRCUIT_NAMES:
		if p.breaker_state(c as C) == B.TRIPPED:
			n += 1
	return n


func test_hit_trips_one_or_two_circuits() -> void:
	var p: PowerSystem = _make()
	p.on_hull_strike(p.config.trip_hit_threshold + 0.5)
	var n: int = _tripped_count(p)
	expect(n >= 1 and n <= 2, "one or two tripped, got %d" % n)
	p.free()


func test_soft_hit_trips_nothing() -> void:
	var p: PowerSystem = _make()
	p.on_hull_strike(p.config.trip_hit_threshold * 0.5)
	expect_eq(_tripped_count(p), 0)
	p.free()


func test_flooding_trips_motor_and_pump() -> void:
	var p: PowerSystem = _make()
	p.set_bilge_water(p.config.trip_flood_threshold * 0.5)
	expect_eq(_tripped_count(p), 0)
	p.set_bilge_water(p.config.trip_flood_threshold + 0.1)
	expect_eq(p.breaker_state(C.MOTOR), B.TRIPPED)
	expect_eq(p.breaker_state(C.BILGE_PUMP), B.TRIPPED)
	expect_eq(p.breaker_state(C.SONAR), B.ON)
	p.free()


func test_flooding_trips_once_per_crossing() -> void:
	var p: PowerSystem = _make()
	p.set_bilge_water(2.0)
	p.set_breaker(C.MOTOR, true)
	p.set_bilge_water(2.0)
	expect_eq(p.breaker_state(C.MOTOR), B.ON)
	expect_eq(p.wear(C.MOTOR), 1)
	p.free()


func test_reversal_overload_trips_motor() -> void:
	var p: PowerSystem = _make()
	p.set_engine_output(-1.0)
	p.step(0.5)
	p.set_engine_output(1.0)
	expect_eq(p.breaker_state(C.MOTOR), B.TRIPPED)
	p.free()


func test_slow_reversal_does_not_trip() -> void:
	var p: PowerSystem = _make()
	p.set_engine_output(-1.0)
	p.step(1.5)
	p.set_engine_output(1.0)
	expect_eq(p.breaker_state(C.MOTOR), B.ON)
	p.free()


func test_pump_start_under_full_motor_trips_pump() -> void:
	var p: PowerSystem = _make()
	p.start_generator()
	p.step(p.config.generator_start_delay + 0.1)
	p.set_engine_output(1.0)
	p.set_bilge_pump_running(true)
	expect_eq(p.breaker_state(C.BILGE_PUMP), B.TRIPPED)
	expect_eq(p.breaker_state(C.MOTOR), B.ON)
	p.free()


func test_pump_start_with_idle_motor_is_fine() -> void:
	var p: PowerSystem = _make()
	p.set_bilge_pump_running(true)
	expect_eq(p.breaker_state(C.BILGE_PUMP), B.ON)
	p.free()


func test_reset_by_switching_on_keeps_wear() -> void:
	var p: PowerSystem = _make()
	p.trip(C.SONAR)
	expect(not p.is_powered(C.SONAR))
	p.set_breaker(C.SONAR, true)
	expect_eq(p.breaker_state(C.SONAR), B.ON)
	expect_eq(p.wear(C.SONAR), 1)
	p.free()


func test_third_trip_blows() -> void:
	var p: PowerSystem = _make()
	for i: int in 2:
		p.trip(C.FANS)
		expect_eq(p.breaker_state(C.FANS), B.TRIPPED)
		p.set_breaker(C.FANS, true)
	p.trip(C.FANS)
	expect_eq(p.breaker_state(C.FANS), B.BLOWN)
	expect_eq(p.wear(C.FANS), 3)
	p.set_breaker(C.FANS, true)
	expect_eq(p.breaker_state(C.FANS), B.BLOWN)
	p.free()


func test_replace_consumes_spare_and_resets_wear() -> void:
	var p: PowerSystem = _make()
	p.set_breaker_state(C.HELM, B.ON)
	for i: int in 3:
		p.trip(C.HELM)
		p.set_breaker(C.HELM, true)
	expect_eq(p.breaker_state(C.HELM), B.BLOWN)
	var before: int = p.spares
	expect(p.replace_breaker(C.HELM))
	expect_eq(p.spares, before - 1)
	expect_eq(p.wear(C.HELM), 0)
	expect_eq(p.breaker_state(C.HELM), B.OFF)
	p.set_breaker(C.HELM, true)
	expect(p.is_powered(C.HELM))
	p.free()


func test_replace_refused_without_spares_or_when_not_blown() -> void:
	var p: PowerSystem = _make()
	expect(not p.replace_breaker(C.SONAR), "not blown")
	expect_eq(p.spares, p.config.spare_count)
	p.set_breaker_state(C.SONAR, B.BLOWN)
	p.spares = 0
	expect(not p.replace_breaker(C.SONAR), "no spares")
	expect_eq(p.breaker_state(C.SONAR), B.BLOWN)
	p.free()


func test_tripped_and_blown_replicate() -> void:
	var host: PowerSystem = _make()
	var client: PowerSystem = _make(true)
	host.trip(C.SONAR)
	host.set_breaker_state(C.FANS, B.BLOWN)
	host.spares = 2
	client._rpc_snapshot(host.snapshot())
	expect_eq(client.breaker_state(C.SONAR), B.TRIPPED)
	expect_eq(client.breaker_state(C.FANS), B.BLOWN)
	expect_eq(client.wear(C.SONAR), 1)
	expect_eq(client.spares, 2)
	host.free()
	client.free()


func test_client_does_not_trip_itself() -> void:
	var client: PowerSystem = _make(true)
	client.trip(C.SONAR)
	client.on_hull_strike(5.0)
	expect_eq(client.breaker_state(C.SONAR), B.ON)
	client.free()
