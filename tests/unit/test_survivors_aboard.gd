extends TestCase
## SurvivorsAboard: clamped count, changed signal, snapshot round trip.

var s: SurvivorsAboard
var seen: Array[int] = []


func before_each() -> void:
	s = SurvivorsAboard.new()
	runner.add_child(s)
	seen.clear()
	s.changed.connect(func(n: int) -> void: seen.append(n))


func after_each() -> void:
	s.free()


func test_add_remove_clamp() -> void:
	expect(s.is_in_group(&"survivors_aboard"))
	s.add(3)
	expect_eq(s.count, 3)
	s.remove(1)
	expect_eq(s.count, 2)
	s.remove(10)
	expect_eq(s.count, 0)
	s.add(-4)
	expect_eq(s.count, 0)
	s.add()
	expect_eq(s.count, 1)


func test_signal_only_on_change() -> void:
	s.add(2)
	s.remove(0)
	s.remove(5)
	s.remove(1)
	expect_eq(seen, [2, 0] as Array[int])


func test_total_mass() -> void:
	s.mass_per_survivor_kg = 70.0
	s.add(3)
	expect_near(s.total_mass_kg(), 210.0)
	s.mass_per_survivor_kg = -5.0
	expect_near(s.mass_per_survivor_kg, 0.0)


func test_snapshot_round_trip() -> void:
	s.mass_per_survivor_kg = 90.0
	s.add(4)
	var c: SurvivorsAboard = SurvivorsAboard.new()
	runner.add_child(c)
	c.simulate_client = true
	var got: Array[int] = []
	c.changed.connect(func(n: int) -> void: got.append(n))
	c.apply_snapshot(s.snapshot())
	expect_eq(c.count, 4)
	expect_near(c.mass_per_survivor_kg, 90.0)
	expect(got.size() > 0)
	# Clients do not change the count themselves.
	c.add(2)
	expect_eq(c.count, 4)
	c.free()


func test_snapshot_count_only_emits_changed() -> void:
	var c: SurvivorsAboard = SurvivorsAboard.new()
	runner.add_child(c)
	c.simulate_client = true
	var got: Array[int] = []
	c.changed.connect(func(n: int) -> void: got.append(n))
	c.apply_snapshot({"count": 3, "mass": c.mass_per_survivor_kg})
	expect_eq(got, [3] as Array[int])
	c.apply_snapshot({"count": 3, "mass": c.mass_per_survivor_kg})
	expect_eq(got.size(), 1)
	c.free()
