extends TestCase
## PlayerImpairment: state follows the cabin air per player; incapacitated replicates host to client.


func _make(client: bool) -> PlayerImpairment:
	var p: PlayerImpairment = PlayerImpairment.new()
	p.simulate_client = client
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func test_clean_air_does_nothing() -> void:
	var p: PlayerImpairment = _make(false)
	p.step(1.0, 400.0, 1.0)
	expect_near(p.impairment, 0.0)
	expect(not p.incapacitated)


func test_follows_co2() -> void:
	var p: PlayerImpairment = _make(false)
	p.step(1.0, 30000.0, 1.0)
	expect(p.impairment > 0.4)
	expect(not p.incapacitated)
	p.step(1.0, 90000.0, 1.0)
	expect(p.incapacitated)
	p.step(1.0, 400.0, 1.0)
	expect(not p.incapacitated)


func test_follows_cabin_o2() -> void:
	var p: PlayerImpairment = _make(false)
	p.step(1.0, 400.0, 0.0)
	expect(p.incapacitated)


func test_players_are_independent() -> void:
	var a: PlayerImpairment = _make(false)
	var b: PlayerImpairment = _make(false)
	a.step(1.0, 90000.0, 1.0)
	b.step(1.0, 400.0, 1.0)
	expect(a.incapacitated)
	expect(not b.incapacitated)


func test_client_gets_hosts_state() -> void:
	var host: PlayerImpairment = _make(false)
	var client: PlayerImpairment = _make(true)
	host.step(1.0, 90000.0, 1.0)
	client.apply_snapshot(host.snapshot())
	expect(client.incapacitated)
	expect_near(client.impairment, host.impairment)


func test_client_does_not_simulate() -> void:
	var client: PlayerImpairment = _make(true)
	client.set_physics_process(true)
	client.readouts_override = LifeSupportReadouts.new()
	client.readouts_override.co2_ppm = 90000.0
	client._physics_process(1.0)
	expect(not client.incapacitated)
	client.readouts_override.free()


func test_crew_reads_the_nodes() -> void:
	var holder: Node = Node.new()
	holder.name = "4242"
	runner.add_child(holder)
	var a: PlayerImpairment = PlayerImpairment.new()
	holder.add_child(a)
	a.set_physics_process(false)
	var crew: PlayerImpairment.Crew = PlayerImpairment.Crew.new(runner.get_tree())
	expect(not crew.is_incapacitated(4242))
	a.step(1.0, 90000.0, 1.0)
	expect(crew.is_incapacitated(4242))
	expect(crew.crew_ids().has(4242))
