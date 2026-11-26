extends TestCase

const C := PowerSystem.Circuit
const B := PowerSystem.BreakerState


func _make(client: bool = false) -> PowerSystem:
	var p: PowerSystem = PowerSystem.new()
	p.simulate_client = client
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func test_state_syncs_to_a_second_instance() -> void:
	var host: PowerSystem = _make()
	var client: PowerSystem = _make(true)
	var seen: Array[int] = []
	client.breaker_changed.connect(func(c: PowerSystem.Circuit, _s: PowerSystem.BreakerState) -> void: seen.append(c))
	host.set_breaker(C.SONAR, false)
	host.start_generator()
	host.step(host.config.generator_start_delay + 0.1)
	host.charge = 0.4
	client._rpc_snapshot(host.snapshot())
	expect_eq(client.breaker_state(C.SONAR), B.OFF)
	expect(not client.is_powered(C.SONAR))
	expect(client.generator_running())
	expect_near(client.charge, 0.4)
	expect_eq(seen, [C.SONAR as int])


func test_late_joiner_snapshot_carries_current_state() -> void:
	var host: PowerSystem = _make()
	host.set_breaker(C.FANS, false)
	host.set_breaker_state(C.HELM, B.TRIPPED)
	host.charge = 0.0
	host.step(0.1)
	var late: PowerSystem = _make(true)
	late._rpc_snapshot(host.snapshot())
	expect_eq(late.breaker_state(C.FANS), B.OFF)
	expect_eq(late.breaker_state(C.HELM), B.TRIPPED)
	expect(late.is_blackout(), "blackout follows the replicated charge")


func test_client_request_is_applied_only_by_the_host() -> void:
	var host: PowerSystem = _make()
	var client: PowerSystem = _make(true)
	client._rpc_request_breaker(C.SONAR as int, false)
	client._rpc_request_generator(true)
	expect_eq(client.breaker_state(C.SONAR), B.ON, "a client never applies a request")
	expect(not client.generator_starting())
	host._rpc_request_breaker(C.SONAR as int, false)
	host._rpc_request_generator(true)
	expect_eq(host.breaker_state(C.SONAR), B.OFF)
	expect(host.generator_starting())
	host._rpc_request_breaker(99, false)
	expect_eq(host.breaker_state(C.SONAR), B.OFF, "an unknown circuit is ignored")


func test_client_does_not_simulate() -> void:
	var client: PowerSystem = _make(true)
	client.set_physics_process(true)
	client._physics_process(1.0)
	expect_eq(client.charge, 1.0)


func test_dev_flags_set_default_state() -> void:
	var p: PowerSystem = PowerSystem.new()
	p.dev_start_charge = 0.25
	p.dev_generator_running = true
	runner.add_child(p)
	expect_near(p.charge, 0.25)
	expect(p.generator_running())
