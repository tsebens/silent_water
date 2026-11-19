extends TestCase
## The terrain's shape: where the floor, walls, ledges and rim are.

var site: CanyonSite


func before_each() -> void:
	site = CanyonSite.new()


func after_each() -> void:
	site.free()


func test_floor_ledges_and_rim() -> void:
	expect_near(site.height_at(0, -250), CanyonSite.FLOOR_Y, 12.0, "canyon floor")
	expect_near(site.height_at(-42, -100), CanyonSite.SHELF1_TOP, 6.0, "shelf 1")
	expect_near(site.height_at(40, -280), CanyonSite.SHELF2_TOP, 6.0, "shelf 2")
	expect_near(site.height_at(-100, -200), CanyonSite.RIM_Y, 12.0, "west plateau")
	expect_near(site.height_at(100, -200), CanyonSite.RIM_Y, 12.0, "east plateau")


func test_array_site_is_level() -> void:
	var o: Vector3 = CanyonSite.OBJECTIVE_POSITION
	expect_near(site.height_at(o.x, o.z), CanyonSite.SHELF2_TOP, 0.5)
	expect_near(site.height_at(o.x + 6.0, o.z - 6.0), CanyonSite.SHELF2_TOP, 1.0)


func test_ends_are_closed() -> void:
	expect(site.height_at(0, CanyonSite.NORTH_Z - 20.0) > -40.0, "north end rises")
	expect(site.height_at(0, CanyonSite.SOUTH_Z + 20.0) > -40.0, "south end rises")


func test_start_is_over_open_water() -> void:
	var s: Vector3 = CanyonSite.START_POSITION
	expect(site.height_at(s.x, s.z) < -150.0, "deep water under the start")


func test_deterministic() -> void:
	var other: CanyonSite = CanyonSite.new()
	for p: Vector2 in [Vector2(3, -77), Vector2(-50, -300), Vector2(45, -10)]:
		expect_eq(site.height_at(p.x, p.y), other.height_at(p.x, p.y))
	other.free()


func test_walls_are_not_straight() -> void:
	# The wall foot meanders along the canyon.
	var a: float = site.height_at(-45, -100)
	var b: float = site.height_at(-45, -330)
	expect(absf(a - b) > 3.0, "meander changes the wall profile (%f vs %f)" % [a, b])
