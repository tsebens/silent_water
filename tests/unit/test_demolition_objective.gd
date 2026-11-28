extends TestCase
## DemolitionObjective: ordering, countdown, failure and host-authoritative replication.

var obj: DemolitionObjective


func _make(client: bool = false) -> DemolitionObjective:
	var o: DemolitionObjective = DemolitionObjective.new()
	o.simulate_client = client
	o.fuse_sec = 10.0
	runner.add_child(o)
	o.set_physics_process(false)
	return o


func before_each() -> void:
	obj = _make()


func after_each() -> void:
	obj.free()


func _arm_all() -> void:
	for i: int in obj.charge_count:
		obj.arm_charge(i)


func test_charges_cannot_arm_while_reactor_on() -> void:
	expect(not obj.arm_charge(0), "refused")
	expect_eq(obj.armed_count(), 0)
	obj.set_reactor_on(false)
	expect_eq(obj.state, DemolitionObjective.State.REACTOR_OFF)
	expect(obj.arm_charge(0), "accepted once the reactor is down")


func test_countdown_starts_only_when_all_armed() -> void:
	var started: Array[float] = []
	obj.countdown_started.connect(func(f: float) -> void: started.append(f))
	obj.set_reactor_on(false)
	for i: int in obj.charge_count - 1:
		obj.arm_charge(i)
	expect_eq(obj.state, DemolitionObjective.State.REACTOR_OFF)
	expect(started.is_empty(), "no fuse yet")
	obj.step(5.0)
	expect_near(obj.fuse_left, 0.0, 0.0001, "fuse idle")
	obj.arm_charge(obj.charge_count - 1)
	expect_eq(obj.state, DemolitionObjective.State.COUNTDOWN)
	expect_eq(started, [10.0])


func test_fuse_runs_to_detonation() -> void:
	var boom: Array[bool] = []
	obj.detonated.connect(func() -> void: boom.append(true))
	obj.set_reactor_on(false)
	_arm_all()
	obj.step(4.0)
	expect_near(obj.fuse_left, 6.0)
	obj.step(7.0)
	expect_eq(obj.state, DemolitionObjective.State.DETONATED)
	expect_eq(boom.size(), 1)


func test_disarm_fails() -> void:
	var reasons: Array[StringName] = []
	obj.failed.connect(func(r: StringName) -> void: reasons.append(r))
	obj.set_reactor_on(false)
	obj.arm_charge(0)
	obj.disarm_charge(0)
	expect_eq(obj.state, DemolitionObjective.State.FAILED)
	expect_eq(reasons, [&"charge_disarmed"] as Array[StringName])


func test_abort_countdown_fails_and_stops_fuse() -> void:
	obj.set_reactor_on(false)
	_arm_all()
	obj.abort_countdown()
	expect_eq(obj.state, DemolitionObjective.State.FAILED)
	expect_eq(obj.fail_reason, &"countdown_aborted")
	obj.step(100.0)
	expect_eq(obj.state, DemolitionObjective.State.FAILED, "never detonates after failing")


func test_reactor_restart_after_arming_fails() -> void:
	obj.set_reactor_on(false)
	obj.arm_charge(0)
	obj.set_reactor_on(true)
	expect_eq(obj.state, DemolitionObjective.State.FAILED)


func test_reactor_restart_before_arming_is_recoverable() -> void:
	obj.set_reactor_on(false)
	obj.set_reactor_on(true)
	expect_eq(obj.state, DemolitionObjective.State.REACTOR_ON)


func test_state_replicates_and_client_never_applies_requests() -> void:
	var client: DemolitionObjective = _make(true)
	obj.set_reactor_on(false)
	_arm_all()
	obj.step(3.0)
	client._rpc_snapshot(obj.snapshot())
	expect_eq(client.state, DemolitionObjective.State.COUNTDOWN)
	expect_eq(client.armed_count(), client.charge_count)
	expect_near(client.fuse_left, 7.0)
	expect(not client.is_reactor_on())
	client.disarm_charge(0)
	client.step(100.0)
	expect_eq(client.state, DemolitionObjective.State.COUNTDOWN, "client does not advance state itself")
	client.free()
