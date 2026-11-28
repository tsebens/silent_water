extends TestCase

const S := LockoutTrunk.State


func _make(client: bool = false) -> LockoutTrunk:
	var t: LockoutTrunk = LockoutTrunk.new()
	t.simulate_client = client
	runner.add_child(t)
	t.set_physics_process(false)
	return t


func _same(host: LockoutTrunk, client: LockoutTrunk, label: String) -> void:
	client._rpc_snapshot(host.snapshot())
	expect_eq(client.state, host.state, label + ": state")
	expect_near(client.progress, host.progress, 0.0001, label + ": progress")
	expect_eq(client.occupant, host.occupant, label + ": occupant")


func test_client_mirrors_every_step() -> void:
	var host: LockoutTrunk = _make()
	var client: LockoutTrunk = _make(true)
	var seen: Array[int] = []
	client.state_changed.connect(func(s: LockoutTrunk.State) -> void: seen.append(s))
	_same(host, client, "start")
	host.enter(5)
	_same(host, client, "enter")
	host.seal_top()
	_same(host, client, "sealed")
	host.start_flood()
	host.step(6.0)
	_same(host, client, "flooding")
	expect_near(client.pump_fraction(), 6.0 / host.flood_time)
	host.step(host.flood_time)
	_same(host, client, "flooded")
	host.open_bottom()
	_same(host, client, "bottom open")
	host.close_bottom()
	host.start_drain()
	host.step(3.0)
	_same(host, client, "draining")
	host.step(host.drain_time)
	_same(host, client, "drained")
	expect_eq(client.state, S.DRY_SEALED)
	expect_eq(seen.back(), S.DRY_SEALED as int)


func test_late_joiner_gets_full_state() -> void:
	var host: LockoutTrunk = _make()
	host.seal_top()
	host.start_flood()
	host.step(4.0)
	var late: LockoutTrunk = _make(true)
	_same(host, late, "late")
	expect_eq(late.state, S.FLOODING)


func test_client_request_applied_only_by_host() -> void:
	var host: LockoutTrunk = _make()
	var client: LockoutTrunk = _make(true)
	client._rpc_request(LockoutTrunk.Action.SEAL_TOP)
	expect_eq(client.state, S.DRY_OPEN)
	host._rpc_request(LockoutTrunk.Action.SEAL_TOP)
	expect_eq(host.state, S.DRY_SEALED)
	host._rpc_request(99)
	expect_eq(host.state, S.DRY_SEALED, "bad action ignored")


func test_client_steps_progress_but_never_transitions() -> void:
	var host: LockoutTrunk = _make()
	var client: LockoutTrunk = _make(true)
	host.seal_top()
	host.start_flood()
	client._rpc_snapshot(host.snapshot())
	client.step(host.flood_time + 1.0)
	expect_eq(client.state, S.FLOODING)
