extends TestCase


func _make() -> PowerSystem:
	var p: PowerSystem = PowerSystem.new()
	runner.add_child(p)
	p.set_physics_process(false)
	return p


func test_running_instrument_raises_draw() -> void:
	var p: PowerSystem = _make()
	p.step(0.5)
	var base: float = p.draw_per_minute()
	p.set_instrument_load(&"scan", 2.0)
	p.step(0.5)
	expect_near(p.draw_per_minute(), base + 2.0, 0.001, "instrument adds its draw")
	expect(p.instrument_running(&"scan"), "reported running")
	p.free()


func test_stopped_instrument_returns_to_prior_draw() -> void:
	var p: PowerSystem = _make()
	p.step(0.5)
	var base: float = p.draw_per_minute()
	p.set_instrument_load(&"scan", 2.0)
	p.set_instrument_load(&"sweep", 1.0)
	p.step(0.5)
	expect_near(p.draw_per_minute(), base + 3.0, 0.001, "two instruments sum")
	p.clear_instrument_load(&"scan")
	p.clear_instrument_load(&"sweep")
	p.step(0.5)
	expect_near(p.draw_per_minute(), base, 0.001, "back to the prior draw")
	expect(not p.instrument_running(&"scan"), "not running")
	p.free()


func test_instrument_drains_battery() -> void:
	var p: PowerSystem = _make()
	p.step(1.0)
	var c0: float = p.charge
	p.step(60.0)
	var plain: float = c0 - p.charge
	p.charge = c0
	p.set_instrument_load(&"scan", 6.0)
	p.step(60.0)
	expect(c0 - p.charge > plain, "battery drains faster with an instrument")
	p.free()


func test_blackout_stops_instrument() -> void:
	var p: PowerSystem = _make()
	p.set_instrument_load(&"scan", 2.0)
	p.charge = 0.0
	p.step(0.5)
	p.step(0.5)
	expect(p.is_blackout(), "blackout")
	expect(not p.instrument_running(&"scan"), "instrument stopped")
	expect_near(p.instrument_draw(), 0.0, 0.0001, "no instrument draw")
	expect_near(p.draw_per_minute(), 0.0, 0.0001, "no draw")
	p.free()
