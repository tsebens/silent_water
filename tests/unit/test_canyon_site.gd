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


func test_deterministic_across_instances_and_calls() -> void:
	var other: CanyonSite = CanyonSite.new()
	for p: Vector2 in [Vector2(-47, -250), Vector2(12, -120), Vector2(55, -300), Vector2(-90, 10)]:
		expect_eq(site.height_at(p.x, p.y), site.height_at(p.x, p.y))
		expect_eq(site.height_at(p.x, p.y), other.height_at(p.x, p.y))
	other.free()


func test_scan_target_and_shelves_hold_position() -> void:
	var o: Vector3 = CanyonSite.OBJECTIVE_POSITION
	expect_near(site.height_at(o.x, o.z), CanyonSite.SHELF2_TOP, 0.5, "scan target")
	for s: Array in [[CanyonSite.SHELF1, CanyonSite.SHELF1_TOP], [CanyonSite.SHELF2, CanyonSite.SHELF2_TOP]]:
		var area: AABB = s[0]
		var c: Vector3 = area.get_center()
		expect_near(site.height_at(c.x, c.z), s[1], 6.0, "shelf centre")
	expect(site.height_at(-42, -100) > CanyonSite.SHELF1_TOP - 6.0, "shelf 1 present")
	expect(site.height_at(-42, -230) < CanyonSite.SHELF1_TOP - 20.0, "shelf 1 ends near z=-160")


## Total variation of the wall profile along x at fixed z, per metre step.
func _slope_spread(s: CanyonSite) -> float:
	var vals: Array[float] = []
	var total: float = 0.0
	var n: int = 0
	for z: float in [-220.0, -240.0, -260.0, -380.0]:
		var prev: float = s.height_at(-30.0, z)
		for k: int in range(1, 31):
			var cur: float = s.height_at(-30.0 - k, z)
			vals.append(cur - prev)
			prev = cur
	for v: float in vals:
		total += v
		n += 1
	var mean: float = total / n
	var var_sum: float = 0.0
	for v: float in vals:
		var_sum += (v - mean) * (v - mean)
	return var_sum / n


func test_strata_make_a_step_pattern_on_walls() -> void:
	var flat_site: CanyonSite = CanyonSite.new()
	flat_site.strata_strength = 0.0
	expect(_slope_spread(site) > _slope_spread(flat_site) * 1.15, "strata add slope variation on the wall")
	flat_site.free()


## Mean squared second difference (1 m) along z of the detail layer alone:
## the height with detail minus the height without it.
func _roughness(s: CanyonSite, bare: CanyonSite, x: float) -> float:
	var sum: float = 0.0
	var n: int = 0
	var z: float = -300.0
	while z < -200.0:
		var vals: Array[float] = []
		for dz: float in [-1.0, 0.0, 1.0]:
			vals.append(s.height_at(x, z + dz) - bare.height_at(x, z + dz))
		var d2: float = vals[0] - 2.0 * vals[1] + vals[2]
		sum += d2 * d2
		n += 1
		z += 1.0
	return sum / n


func test_detail_is_damped_on_steep_ground() -> void:
	var s: CanyonSite = CanyonSite.new()
	s.strata_strength = 0.0
	s.rock_amp = 0.0
	var bare: CanyonSite = CanyonSite.new()
	bare.strata_strength = 0.0
	bare.rock_amp = 0.0
	bare.detail_amp = 0.0
	var flat: float = _roughness(s, bare, -5.0)
	var steep: float = _roughness(s, bare, -46.0)
	expect(flat > 0.0, "flat ground has detail")
	expect(steep < flat, "steep roughness %f below flat %f" % [steep, flat])
	s.free()
	bare.free()
