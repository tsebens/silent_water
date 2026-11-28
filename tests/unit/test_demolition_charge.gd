extends TestCase
## Demolition charge and charge point: carry weight, setting arms the objective, only at a point, state syncs.


func _objective() -> DemolitionObjective:
	var o: DemolitionObjective = DemolitionObjective.new()
	o.charge_count = 2
	runner.add_child(o)
	o.set_reactor_on(false)
	return o


func test_carrying_adds_weight() -> void:
	var carrier: Node3D = Node3D.new()
	var c: DemolitionCharge = DemolitionCharge.new()
	c.weight_kg = 5.0
	runner.add_child(carrier)
	runner.add_child(c)
	expect_eq(c.carried_weight(), 0.0, "uncarried adds nothing")
	expect(c.pick_up(carrier), "picked up")
	expect_eq(DemolitionCharge.total_weight_carried_by(carrier, runner), 5.0, "carrier bears the weight")
	expect(not c.pick_up(carrier), "cannot be picked up twice")
	carrier.queue_free()
	c.queue_free()


func test_set_at_point_arms() -> void:
	var o: DemolitionObjective = _objective()
	var p: ChargePoint = ChargePoint.new()
	p.objective = o
	p.index = 1
	runner.add_child(p)
	var carrier: Node3D = Node3D.new()
	var c: DemolitionCharge = DemolitionCharge.new()
	runner.add_child(carrier)
	runner.add_child(c)
	c.pick_up(carrier)
	expect(c.set_at(p), "set at the point")
	expect(o.is_armed(1) and p.is_armed(), "armed")
	expect(c.is_set() and not c.is_carried(), "no longer carried")
	expect_eq(DemolitionCharge.total_weight_carried_by(carrier, runner), 0.0, "weight gone")
	var c2: DemolitionCharge = DemolitionCharge.new()
	runner.add_child(c2)
	c2.pick_up(carrier)
	expect(not c2.set_at(p), "occupied point refuses")
	expect(c2.is_carried(), "refused charge still carried")
	for n: Node in [o, p, carrier, c, c2]:
		n.queue_free()


func test_cannot_set_elsewhere_or_with_reactor_on() -> void:
	var o: DemolitionObjective = DemolitionObjective.new()
	runner.add_child(o)
	var p: ChargePoint = ChargePoint.new()
	p.objective = o
	runner.add_child(p)
	var carrier: Node3D = Node3D.new()
	var c: DemolitionCharge = DemolitionCharge.new()
	runner.add_child(carrier)
	runner.add_child(c)
	expect(not c.set_at(p), "not carried yet")
	c.pick_up(carrier)
	expect(not c.set_at(null), "no point, no set")
	expect(not c.set_at(p), "reactor still on")
	expect(not o.is_armed(0) and c.is_carried(), "nothing changed")
	for n: Node in [o, p, carrier, c]:
		n.queue_free()


func test_state_syncs_from_snapshot() -> void:
	var host: DemolitionObjective = _objective()
	var client: DemolitionObjective = DemolitionObjective.new()
	client.charge_count = 2
	client.simulate_client = true
	runner.add_child(client)
	var p: ChargePoint = ChargePoint.new()
	p.objective = client
	p.index = 0
	runner.add_child(p)
	var seen: Array[bool] = []
	p.armed_changed.connect(func(a: bool) -> void: seen.append(a))
	host.arm_charge(0)
	client.apply_snapshot(host.snapshot())
	expect(p.is_armed(), "client point shows armed")
	host.disarm_charge(0)
	client.apply_snapshot(host.snapshot())
	expect(not p.is_armed(), "and disarmed")
	expect_eq(seen.size(), 2, "armed_changed fired for each")
	for n: Node in [host, client, p]:
		n.queue_free()
