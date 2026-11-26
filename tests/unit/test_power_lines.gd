extends TestCase

const C := PowerSystem.Circuit
const B := PowerSystem.BreakerState


func _make(client: bool = false) -> PowerSystem:
	var p: PowerSystem = PowerSystem.new()
	p.simulate_client = client
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func _damaged_count(p: PowerSystem) -> int:
	var n: int = 0
	for c: int in PowerSystem.CIRCUIT_NAMES:
		for b: int in p.box_count(c as C):
			if p.box_damaged(c as C, b):
				n += 1
	return n


func test_strong_hit_can_damage_a_line() -> void:
	var p: PowerSystem = _make()
	p.config.damage_chance = 1.0
	p.on_hull_strike(p.config.damage_hit_threshold + 1.0)
	expect_eq(_damaged_count(p), 1)
	p.free()


func test_moderate_hit_does_not_damage() -> void:
	var p: PowerSystem = _make()
	p.config.damage_chance = 1.0
	p.on_hull_strike(p.config.trip_hit_threshold + 0.1)
	expect(p.config.trip_hit_threshold + 0.1 < p.config.damage_hit_threshold)
	expect_eq(_damaged_count(p), 0)
	p.free()


func test_damaging_a_line_trips_it() -> void:
	var p: PowerSystem = _make()
	p.damage_box(C.SONAR, 0)
	expect(p.line_damaged(C.SONAR))
	expect_eq(p.breaker_state(C.SONAR), B.TRIPPED)
	p.free()


func test_damaged_circuit_retrips_on_reset() -> void:
	var p: PowerSystem = _make()
	p.damage_box(C.SONAR, 1)
	p.set_breaker(C.SONAR, true)
	expect_eq(p.breaker_state(C.SONAR), B.TRIPPED)
	expect(not p.is_powered(C.SONAR))
	p.free()


func test_repair_clears_damage_and_reset_holds() -> void:
	var p: PowerSystem = _make()
	var changes: Array[bool] = []
	p.box_damage_changed.connect(func(_c: C, _b: int, d: bool) -> void: changes.append(d))
	p.damage_box(C.FANS, 0)
	expect(p.repair_box(C.FANS, 0))
	expect(not p.box_damaged(C.FANS, 0))
	expect(not p.line_damaged(C.FANS))
	expect_eq(changes, [true, false])
	p.set_breaker(C.FANS, true)
	expect_eq(p.breaker_state(C.FANS), B.ON)
	expect(not p.repair_box(C.FANS, 0), "nothing left to repair")
	p.free()


func test_line_stays_damaged_until_every_box_is_repaired() -> void:
	var p: PowerSystem = _make()
	p.damage_box(C.HELM, 0)
	p.damage_box(C.HELM, 1)
	p.repair_box(C.HELM, 0)
	expect(p.line_damaged(C.HELM))
	p.repair_box(C.HELM, 1)
	expect(not p.line_damaged(C.HELM))
	p.free()


func test_damage_replicates() -> void:
	var host: PowerSystem = _make()
	var client: PowerSystem = _make(true)
	var seen: Array[bool] = []
	client.box_damage_changed.connect(func(_c: C, _b: int, d: bool) -> void: seen.append(d))
	host.damage_box(C.THRUSTERS, 1)
	client._rpc_snapshot(host.snapshot())
	expect(client.box_damaged(C.THRUSTERS, 1))
	host.repair_box(C.THRUSTERS, 1)
	client._rpc_snapshot(host.snapshot())
	expect(not client.box_damaged(C.THRUSTERS, 1))
	expect_eq(seen, [true, false])
	var late: PowerSystem = _make(true)
	host.damage_box(C.MOTOR, 0)
	late._rpc_snapshot(host.snapshot())
	expect(late.box_damaged(C.MOTOR, 0))
	host.free()
	client.free()
	late.free()


func test_client_cannot_damage_locally() -> void:
	var client: PowerSystem = _make(true)
	client.damage_box(C.SONAR, 0)
	expect(not client.box_damaged(C.SONAR, 0))
	client.free()


func test_junction_box_sparks_while_damaged_and_repair_clears() -> void:
	var p: PowerSystem = _make()
	var box: JunctionBox = JunctionBox.new()
	box.power = p
	box.circuit = C.CABIN_LTS
	box.box_index = 0
	runner.add_child(box)
	expect(not box.is_damaged)
	p.damage_box(C.CABIN_LTS, 0)
	expect(box.is_damaged)
	box.complete_repair()
	expect(not box.is_damaged)
	expect(not p.line_damaged(C.CABIN_LTS))
	box.free()
	p.free()
