extends TestCase
## Pump and re-pressurise: pumping needs an isolated zone, falls at the tuned rate, drains the gas store,
## stalls without gas, and a recovered zone says so.

var det: SoundDetector
var heard_n: int = 0
var recovered_zones: Array = []


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	heard_n = 0
	recovered_zones.clear()
	det = SoundDetector.new()
	det.threshold_db = -100.0
	runner.add_child(det)
	det.heard.connect(func(_e: SoundEvent) -> void: heard_n += 1)


func after_each() -> void:
	det.free()


func _tuning() -> FloodTuning:
	var t: FloodTuning = FloodTuning.new()
	t.pump_rate = 0.1
	t.gas_per_level = 10.0
	t.gas_store_capacity = 100.0
	return t


## A flooded, isolated maintenance zone (every door shut, then the zone's own breach is patched).
func _flooded_isolated(t: FloodTuning) -> FloodRecovery:
	var fz: FloodZones = FloodZones.load_program()
	expect(fz != null, "program loads")
	for k: Variant in fz.door_keys():
		if (k as String).split("|").has("maintenance"):
			fz.set_door_open(k, false)
	fz.set_breach(&"maintenance")
	fz.set_breach(&"maintenance", false)
	var r: FloodRecovery = FloodRecovery.create(fz, t)
	r.zone_recovered.connect(func(z: StringName) -> void: recovered_zones.append(z))
	return r


func test_pump_starts_only_on_isolated_flooded_zone() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	expect(not r.start_pump(&"main"), "dry zone does not pump")
	expect(r.start_pump(&"maintenance"), "isolated flooded zone pumps")
	expect(heard_n == 1, "start makes noise")


func test_water_falls_at_tuned_rate() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	r.start_pump(&"maintenance")
	r.tick(2.0)
	expect_near(r.water_level(&"maintenance"), 0.8, 0.001, "0.1/s for 2 s")


func test_gas_store_drains_as_air_is_pushed_in() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	r.start_pump(&"maintenance")
	r.tick(2.0)
	expect_near(r.store.amount, 98.0, 0.001, "0.2 level at 10 gas per level")


func test_pump_stalls_when_gas_is_lacking() -> void:
	var t: FloodTuning = _tuning()
	t.gas_store_capacity = 5.0
	var r: FloodRecovery = _flooded_isolated(t)
	r.start_pump(&"maintenance")
	var before: int = heard_n
	r.tick(20.0)
	expect(r.is_stalled(&"maintenance"), "stalled")
	expect(heard_n == before + 1, "stall makes noise once")
	expect_near(r.water_level(&"maintenance"), 0.5, 0.001, "only what the gas allowed")
	expect(r.store.is_empty(), "store dry")
	expect(r.is_unrecoverable(&"maintenance"), "cannot be recovered")
	r.tick(5.0)
	expect(heard_n == before + 1, "no repeated stall noise")
	expect(not r.is_recovered(&"maintenance"), "not recovered")


func test_open_breach_never_pumps() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	r.start_pump(&"maintenance")
	r.zones.set_breach(&"maintenance")
	r.tick(5.0)
	expect_near(r.water_level(&"maintenance"), 1.0, 0.001, "no progress")
	expect_near(r.store.amount, 100.0, 0.001, "no gas spent")
	var r2: FloodRecovery = _flooded_isolated(_tuning())
	r2.zones.set_breach(&"maintenance")
	expect(not r2.start_pump(&"maintenance"), "cannot start with an open breach")


func test_recovered_zone_emits_signal_and_is_dry() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	r.start_pump(&"maintenance")
	r.tick(10.5)
	expect(r.is_recovered(&"maintenance"), "recovered")
	expect(recovered_zones == [&"maintenance"], "zone_recovered emitted once")
	expect(not r.zones.is_flooded(&"maintenance"), "dry")
	expect(not r.is_pumping(&"maintenance"), "pump off")
	expect_near(r.store.amount, 90.0, 0.001, "full volume of gas used")
	r.tick(1.0)
	expect(recovered_zones.size() == 1, "not emitted again")


func test_state_round_trips() -> void:
	var r: FloodRecovery = _flooded_isolated(_tuning())
	r.start_pump(&"maintenance")
	r.tick(3.0)
	var r2: FloodRecovery = FloodRecovery.create(r.zones, _tuning())
	r2.apply_dict(r.to_dict())
	expect_near(r2.water_level(&"maintenance"), 0.7, 0.001, "level")
	expect_near(r2.store.amount, r.store.amount, 0.001, "gas")
	expect(r2.is_pumping(&"maintenance"), "pumping")
