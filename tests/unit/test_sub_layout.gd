extends TestCase
## SubLayout: the program's layout in the interior frame, and the one frame conversion.

const STATIONS: Array[StringName] = [
	&"pilot", &"sonar", &"sonar_seat", &"countermeasures", &"map_table",
	&"engineering", &"life_support", &"ballast", &"bilge",
]
const FEATURES: Array[StringName] = [&"lock_out_trunk", &"tower_ladder", &"lockers", &"drop_weights"]


func test_deck_converts_to_zero() -> void:
	expect_near(SubLayout.main_deck_y(), -0.95)
	expect_near(SubLayout.to_interior(Vector3(0.3, -0.95, 2.0)).y, 0.0)
	expect_near(SubLayout.to_interior(Vector3(0.3, 0.7, 2.0)).y, 1.65, 0.0001, "standing eye")


func test_conversion_round_trips() -> void:
	var p: Vector3 = Vector3(-1.2, 0.4, 3.3)
	var q: Vector3 = SubLayout.to_program(SubLayout.to_interior(p))
	expect(p.is_equal_approx(q), "round trip gave %s" % q)
	expect_near(SubLayout.to_interior(p).x, p.x)
	expect_near(SubLayout.to_interior(p).z, p.z)


func test_every_station_and_feature_present() -> void:
	for id: StringName in STATIONS + FEATURES:
		expect(SubLayout.has(id), "missing %s" % id)
	expect_eq(SubLayout.ids().size(), STATIONS.size() + FEATURES.size(), "no unlisted items")


func test_pilot_position() -> void:
	var p: Vector3 = SubLayout.position(&"pilot")
	expect_near(p.x, 0.0)
	expect_near(p.z, -3.8)
	expect_near(p.y, -0.20, 0.0001, "the cockpit floor is one step down")


func test_sonar_and_seat_positions() -> void:
	var s: Vector3 = SubLayout.position(&"sonar")
	expect(s.x > 0.8 and s.x < 1.3, "sonar is starboard, got %s" % s.x)
	expect_near(s.z, -2.95)
	expect_near(s.y, 0.0)
	var seat: Vector3 = SubLayout.position(&"sonar_seat")
	expect_near(seat.z, -2.3)
	expect(seat.z > s.z, "the seat is aft of the desk")
	expect(seat.x > 0.0, "the seat is starboard")


func test_map_table_position() -> void:
	var t: Vector3 = SubLayout.position(&"map_table")
	expect(t.x < -0.9 and t.x > -1.2, "map table is port, got %s" % t.x)
	expect_near(t.z, -1.25)
	expect_near(t.y, 0.0)
	expect_near(SubLayout.mount_height(&"map_table"), 0.75)
	var top: Rect2 = SubLayout.top_footprint(&"map_table")
	expect(top.position.x < SubLayout.footprint(&"map_table").position.x, "the top reaches into the hull wall")


func test_cockpit_floor_offset_and_floors() -> void:
	expect_near(SubLayout.cockpit_floor_offset(), -0.20)
	expect_near(SubLayout.floor_y(&"midships"), 0.0)
	expect_near(SubLayout.floor_y(&"engineering"), 0.0)


func test_footprint_and_clearances() -> void:
	var f: Rect2 = SubLayout.footprint(&"pilot")
	expect_near(f.size.x, 0.7)
	expect_near(f.size.y, 0.8)
	expect_near(SubLayout.clearance("aisle_min_m"), 0.8)
	expect_near(SubLayout.clearance("head_clear_m"), 2.0)
	expect_near(SubLayout.compartment_span(&"cockpit").x, -4.9)
