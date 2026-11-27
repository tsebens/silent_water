extends TestCase
## LifeSupportReadouts replication: a client shows the host's readouts, and never simulates.


func _make(client: bool) -> LifeSupportReadouts:
	var r: LifeSupportReadouts = LifeSupportReadouts.new()
	r.simulate_client = client
	runner.add_child(r)
	r.set_physics_process(false)
	return r


func test_client_reads_the_hosts_values() -> void:
	var host: LifeSupportReadouts = _make(false)
	var client: LifeSupportReadouts = _make(true)
	host.crew_override = 4
	host.fans_on = false
	host.step(120.0)
	host.saturation_a = 0.4
	host.saturation_b = 0.9
	client.apply_snapshot(host.snapshot())
	expect_near(client.co2_ppm, host.co2_ppm, 0.001)
	expect_near(client.o2_level, host.o2_level, 0.0001)
	expect_near(client.saturation_a, 0.4)
	expect_near(client.saturation_b, 0.9)
	expect_near(client.readout(&"co2_production_rate"), host.readout(&"co2_production_rate"), 0.0001)
	expect(client.readout(&"co2_ppm") > 400.0)
	host.free()
	client.free()


func test_client_alarms_follow_replicated_values() -> void:
	var host: LifeSupportReadouts = _make(false)
	var client: LifeSupportReadouts = _make(true)
	host.co2_ppm = 20000.0
	client.apply_snapshot(host.snapshot())
	expect_eq(client.co2_alarm(), host.co2_alarm())
	host.free()
	client.free()


func test_client_does_not_simulate() -> void:
	var client: LifeSupportReadouts = _make(true)
	client.set_physics_process(true)
	client.crew_override = 4
	client._physics_process(10.0)
	expect_near(client.co2_ppm, 400.0)
	client.free()


func test_client_reads_the_hosts_cabin_o2() -> void:
	var host: LifeSupportReadouts = _make(false)
	var client: LifeSupportReadouts = _make(true)
	host.cabin_o2 = 0.62
	client.apply_snapshot(host.snapshot())
	expect_near(client.cabin_o2, 0.62)
	expect_near(client.readout(&"cabin_o2"), 0.62)
	host.free()
	client.free()
