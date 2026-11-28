extends TestCase

const S := LockoutTrunk.State
const A := LockoutTrunk.Action


func _make(client: bool = false) -> LockoutTrunk:
	var t: LockoutTrunk = LockoutTrunk.new()
	t.simulate_client = client
	runner.add_child(t)
	t.set_physics_process(false)
	return t


## Drive a fresh trunk to [param target] through legal actions.
func _at(target: S) -> LockoutTrunk:
	var t: LockoutTrunk = _make()
	if target == S.DRY_OPEN:
		return t
	t.seal_top()
	if target == S.DRY_SEALED:
		return t
	t.start_flood()
	if target == S.FLOODING:
		return t
	t.step(t.flood_time)
	if target == S.FLOODED:
		return t
	if target == S.DRAINING:
		t.start_drain()
		return t
	t.open_bottom()
	return t


func test_outbound_and_return_sequence() -> void:
	var t: LockoutTrunk = _make()
	var exited: Array[int] = []
	var entered: Array[int] = []
	t.diver_exited.connect(func(w: int) -> void: exited.append(w))
	t.diver_entered.connect(func(w: int) -> void: entered.append(w))
	expect(t.enter(7))
	expect(t.seal_top())
	expect_eq(t.state, S.DRY_SEALED)
	expect(t.start_flood())
	expect_eq(t.state, S.FLOODING)
	t.step(t.flood_time)
	expect_eq(t.state, S.FLOODED)
	expect(t.open_bottom())
	expect_eq(t.state, S.BOTTOM_OPEN)
	expect_eq(exited, [7])
	expect(t.close_bottom())
	expect_eq(t.state, S.FLOODED)
	expect_eq(entered, [7])
	expect(t.start_drain())
	expect_eq(t.state, S.DRAINING)
	t.step(t.drain_time)
	expect_eq(t.state, S.DRY_SEALED)
	expect(t.open_top())
	expect_eq(t.state, S.DRY_OPEN)
	expect(t.leave())
	expect_eq(exited, [7], "exited once")
	expect_eq(entered, [7], "entered once")


func test_no_signals_without_occupant() -> void:
	var t: LockoutTrunk = _at(S.FLOODED)
	var n: Array[int] = [0]
	t.diver_exited.connect(func(_w: int) -> void: n[0] += 1)
	t.diver_entered.connect(func(_w: int) -> void: n[0] += 1)
	t.open_bottom()
	t.close_bottom()
	expect_eq(n[0], 0)


func test_every_unlisted_cell_is_refused() -> void:
	var allowed: Dictionary = {
		S.DRY_OPEN: [A.SEAL_TOP],
		S.DRY_SEALED: [A.OPEN_TOP, A.START_FLOOD],
		S.FLOODING: [],
		S.FLOODED: [A.OPEN_BOTTOM, A.START_DRAIN],
		S.BOTTOM_OPEN: [A.CLOSE_BOTTOM],
		S.DRAINING: [],
	}
	for st: S in allowed:
		for a: A in [A.SEAL_TOP, A.OPEN_TOP, A.START_FLOOD, A.START_DRAIN, A.OPEN_BOTTOM, A.CLOSE_BOTTOM]:
			var t: LockoutTrunk = _at(st)
			expect_eq(t.state, st, "setup reached %d" % st)
			var ok: bool = t.request(a)
			if a in allowed[st]:
				expect(ok, "state %d action %d allowed" % [st, a])
			else:
				expect(not ok, "state %d action %d refused" % [st, a])
				expect_eq(t.state, st, "refusal changes nothing")


func test_timers() -> void:
	var t: LockoutTrunk = _at(S.FLOODING)
	expect(t.pump_running())
	t.step(t.flood_time - 0.5)
	expect_eq(t.state, S.FLOODING)
	expect(not t.open_bottom())
	expect(not t.start_drain())
	t.step(0.5)
	expect_eq(t.state, S.FLOODED)
	expect(not t.pump_running())
	t.start_drain()
	t.step(t.drain_time - 0.5)
	expect_eq(t.state, S.DRAINING)
	expect(not t.open_top())
	t.step(0.5)
	expect_eq(t.state, S.DRY_SEALED)


func test_escape_from_sealed() -> void:
	var t: LockoutTrunk = _at(S.DRY_SEALED)
	expect(t.open_top(), "always openable from inside when dry and sealed")


func test_occupant_slot() -> void:
	var t: LockoutTrunk = _make()
	expect(t.enter(3))
	expect(not t.enter(4), "slot is taken")
	t.seal_top()
	expect(not t.leave(), "cannot leave through a sealed top")
	t.open_top()
	expect(t.leave())
	expect_eq(t.occupant, LockoutTrunk.NO_OCCUPANT)


func test_hatch_moved() -> void:
	var t: LockoutTrunk = _make()
	var seen: Array = []
	t.hatch_moved.connect(func(h: StringName, o: bool) -> void: seen.append([h, o]))
	t.seal_top()
	t.start_flood()
	t.step(t.flood_time)
	t.open_bottom()
	t.close_bottom()
	expect_eq(seen, [[&"top", false], [&"bottom", true], [&"bottom", false]])


func test_client_does_not_act() -> void:
	var c: LockoutTrunk = _make(true)
	expect(not c.seal_top())
	expect_eq(c.state, S.DRY_OPEN)
