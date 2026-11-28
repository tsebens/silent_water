extends TestCase
## FloodObjective: complete once every flooded zone on the path is recovered; FloodZones.water_level for
## presentation; the flood-recovery work Resource.

var completions: int = 0


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	completions = 0


func _tuning() -> FloodTuning:
	var t: FloodTuning = FloodTuning.new()
	t.pump_rate = 0.5
	t.gas_per_level = 1.0
	t.gas_store_capacity = 100.0
	return t


## Two isolated flooded zones: maintenance and main.
func _two_flooded() -> FloodRecovery:
	var fz: FloodZones = FloodZones.load_program()
	expect(fz != null, "program loads")
	for k: Variant in fz.door_keys():
		fz.set_door_open(k, false)
	fz.set_breach(&"maintenance")
	fz.set_breach(&"main")
	fz.set_breach(&"maintenance", false)
	fz.set_breach(&"main", false)
	return FloodRecovery.create(fz, _tuning())


func test_work_resource_costs_22_points() -> void:
	var w: FloodWork = load("res://src/facility/flood_work.tres")
	expect(w.points == 22, "placeholder 22 points")
	expect(w.kind == &"recover_flooding", "kind")
	var table: WorkCostTable = load("res://src/dive/presets/work_costs.tres")
	expect(table.has_kind(w.kind), "kind is in the cost table")
	expect(w.to_option(&"x").state_flag == &"flooded", "option carries the flag")


func test_completes_when_all_flooded_zones_recovered() -> void:
	var r: FloodRecovery = _two_flooded()
	var o: FloodObjective = FloodObjective.create(r)
	o.completed.connect(func() -> void: completions += 1)
	expect(o.required.size() == 2, "two zones on the path")
	expect(not o.is_complete(), "not yet")
	r.start_pump(&"maintenance")
	r.tick(3.0)
	expect(r.is_recovered(&"maintenance"), "first recovered")
	expect(not o.is_complete(), "one of two is not enough")
	expect(o.recovered_count() == 1, "count")
	r.start_pump(&"main")
	r.tick(3.0)
	expect(o.is_complete(), "complete")
	expect(completions == 1, "completed once")
	expect(o.points() == 22, "points from the resource")


func test_other_zone_recovery_does_not_count() -> void:
	var r: FloodRecovery = _two_flooded()
	var o: FloodObjective = FloodObjective.create(r, [&"main"])
	r.start_pump(&"maintenance")
	r.tick(3.0)
	expect(not o.is_complete(), "maintenance is off the path")
	r.start_pump(&"main")
	r.tick(3.0)
	expect(o.is_complete(), "path zone recovered")


func test_nothing_flooded_is_complete_at_once() -> void:
	var fz: FloodZones = FloodZones.load_program()
	var o: FloodObjective = FloodObjective.create(FloodRecovery.create(fz, _tuning()))
	expect(o.is_complete(), "nothing to recover")


func test_water_level_for_presentation() -> void:
	var r: FloodRecovery = _two_flooded()
	var fz: FloodZones = r.zones
	expect_near(fz.water_level(&"maintenance"), 1.0, 0.001, "full when flooded")
	r.start_pump(&"maintenance")
	r.tick(0.5)
	expect_near(fz.water_level(&"maintenance"), 0.75, 0.001, "falls with the pump")
	r.tick(3.0)
	expect_near(fz.water_level(&"maintenance"), 0.0, 0.001, "dry once recovered")
	expect(fz.water_level(&"nowhere") == 0.0, "unknown zone is 0")
