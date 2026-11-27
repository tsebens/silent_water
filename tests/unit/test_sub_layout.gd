extends TestCase
## SubLayout: the program's layout in the interior frame, and the one frame conversion.

const STATIONS: Array[StringName] = [
	&"pilot", &"sonar", &"sonar_seat", &"countermeasures", &"map_table", &"science",
	&"engineering", &"life_support", &"ballast", &"bilge", &"scanner",
]
const FEATURES: Array[StringName] = [&"lock_out_trunk", &"tower_ladder", &"lockers", &"status_board"]


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
	expect_near(p.z, -3.9)
	expect_near(p.y, -0.20, 0.0001, "the cockpit floor is one step down")


func test_sonar_and_seat_positions() -> void:
	var s: Vector3 = SubLayout.position(&"sonar")
	expect(s.x > 0.8 and s.x < 1.3, "sonar is starboard, got %s" % s.x)
	expect_near(s.z, -2.95)
	expect_near(s.y, 0.0)
	expect_eq(String(SubLayout.record(&"sonar")["faces"]), "starboard", "sonar faces the starboard hull")
	var seat: Vector3 = SubLayout.position(&"sonar_seat")
	expect_near(seat.z, s.z, 0.001, "the seat is level with the desk along the hull")
	expect(seat.x > 0.0 and seat.x < s.x, "the seat is on the aisle side of the desk")


func test_starboard_wall_runs_sonar_science_countermeasures() -> void:
	var sonar: Rect2 = SubLayout.footprint(&"sonar")
	var sci: Rect2 = SubLayout.footprint(&"science")
	var cm: Rect2 = SubLayout.footprint(&"countermeasures")
	expect(SubLayout.position(&"science").x > 0.0, "science is starboard")
	expect(sci.position.y >= sonar.end.y - 0.001, "science is aft of sonar")
	expect(sci.end.y <= cm.position.y + 0.001, "science is forward of countermeasures")
	expect_near(cm.end.y, 1.5, 0.001, "countermeasures end at the bulkhead")
	expect(sci.size.y >= 1.8, "science takes the bulk of the wall (%f m)" % sci.size.y)


func test_lockers_are_port_aft_of_the_map_table_and_clear_of_the_way_out() -> void:
	expect(SubLayout.position(&"lockers").x < 0.0, "lockers are port")
	expect(SubLayout.position(&"lockers").z > SubLayout.position(&"map_table").z, "lockers are aft of the map table")
	var lk: Rect2 = SubLayout.footprint(&"lockers")
	expect(not lk.grow(-0.001).intersects(SubLayout.footprint(&"tower_ladder")), "lockers clear of the tower ladder")
	expect(not lk.grow(-0.001).intersects(SubLayout.footprint(&"lock_out_trunk")), "lockers clear of the lock-out trunk")
	expect_near(SubLayout.position(&"lock_out_trunk").x, 0.0, 0.001, "the hatch is on the centreline")
	expect_near(SubLayout.position(&"lock_out_trunk").z, 0.5, 0.001, "the hatch is at z 0.5")
	expect(not SubLayout.has(&"science") or SubLayout.position(&"science").x > 0.0, "no port science reservation")


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


func test_hull_inside_checks() -> void:
	expect(SubLayout.inside_hull(0.0, SubLayout.hull_centre_y(), 0.0), "centre is inside")
	var half: Vector2 = SubLayout.hull_inner_half(0.0)
	expect(SubLayout.inside_hull(half.x - 0.01, SubLayout.hull_centre_y(), 0.0), "just inside the wall")
	expect(not SubLayout.inside_hull(half.x + 0.01, SubLayout.hull_centre_y(), 0.0), "just outside the wall")
	expect(not SubLayout.inside_hull(0.0, SubLayout.hull_top_y(), 0.0), "the envelope top is wall, not cabin")
	expect_eq(SubLayout.hull_inner_half(SubLayout.hull_size().z / 2.0), Vector2.ZERO, "closed at the ends")
