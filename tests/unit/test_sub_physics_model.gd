extends TestCase

const DT: float = 1.0 / 60.0

var m: SubPhysicsModel


func before_each() -> void:
	m = SubPhysicsModel.new()
	m.position = Vector3(0, -50, 0)


func _run(seconds: float, order: float = 0.0, rudder: float = 0.0, planes: float = 0.0, flood: float = 0.0, blow: float = 0.0) -> void:
	for i: int in range(int(seconds / DT)):
		m.step(DT, order, rudder, planes, flood, blow)


func test_neutral_near_half_tank() -> void:
	m.tank_water_t = m.tank_capacity_t * 0.5
	expect(absf(m.buoyancy_accel()) < 0.01, "buoyancy at half tank %f" % m.buoyancy_accel())


func test_full_tank_sinks_empty_tank_rises() -> void:
	m.tank_water_t = m.tank_capacity_t
	_run(30.0)
	expect(m.velocity.y < -0.5, "full tank sink rate %f" % m.velocity.y)
	expect(m.velocity.y > -1.5, "sink rate should be capped by drag, got %f" % m.velocity.y)
	before_each()
	m.tank_water_t = 0.0
	_run(30.0)
	expect(m.velocity.y > 0.5, "empty tank rise rate %f" % m.velocity.y)


func test_heavier_payload_slows_climb() -> void:
	m.tank_water_t = 0.0
	_run(30.0)
	var light: float = m.velocity.y
	before_each()
	m.tank_water_t = 0.0
	m.payload_t += 5.0
	_run(30.0)
	expect(m.velocity.y < light - 0.1, "salvage weight should slow the climb (%f vs %f)" % [m.velocity.y, light])


func test_full_ahead_top_speed_about_3() -> void:
	_run(120.0, 1.0)
	expect_near(m.forward_speed(), 3.0, 0.2, "top speed")


func test_engine_spools_slowly() -> void:
	_run(1.0, 1.0)
	expect(m.engine < 0.5, "engine should not jump to full (%f)" % m.engine)
	_run(5.0, 1.0)
	expect_near(m.engine, 1.0, 0.001)


func test_astern_is_slower() -> void:
	_run(120.0, -1.0)
	expect(m.forward_speed() < -1.5 and m.forward_speed() > -2.6, "astern speed %f" % m.forward_speed())


func test_thrusters_turn_in_place() -> void:
	_run(10.0, 0.0, 1.0)
	expect(m.angles.y < -deg_to_rad(45.0), "full rudder while stopped turns over 45° in 10 s (%f°)" % rad_to_deg(m.angles.y))
	expect(m.velocity.length() < 0.05, "turning in place doesn't move the sub")


func test_rudder_adds_turn_at_speed() -> void:
	var still: SubPhysicsModel = SubPhysicsModel.new()
	for i: int in range(int(5.0 / DT)):
		still.step(DT, 0.0, 1.0, 0, 0, 0)
	_run(60.0, 1.0)
	var yaw0: float = m.angles.y
	_run(5.0, 1.0, 1.0)
	expect(m.angles.y - yaw0 < still.angles.y - 0.1, "turning is quicker with way on (%f vs %f)" % [m.angles.y - yaw0, still.angles.y])
	expect(m.angles.y - yaw0 < -0.3, "positive rudder turns to starboard (yaw decreases)")


func test_planes_dive_and_pitch_is_limited() -> void:
	_run(60.0, 1.0)
	var y0: float = m.position.y
	_run(30.0, 1.0, 0.0, 1.0)
	expect(m.angles.x < -0.1, "dive planes pitch nose down (%f)" % m.angles.x)
	expect(m.angles.x >= -m.max_pitch - 0.001)
	expect(m.position.y < y0 - 5.0, "diving at speed loses depth (%f)" % (m.position.y - y0))


func test_righting_levels_the_hull() -> void:
	m.angles = Vector3(0.4, 0.0, 0.3)
	_run(40.0)
	expect(absf(m.angles.x) < 0.05 and absf(m.angles.z) < 0.05, "hull should level, got %s" % m.angles)


func test_vent_does_not_flood_while_riding_high() -> void:
	m.position = Vector3(0, 0, 0)
	m.tank_water_t = 0.0
	m.step(DT, 0, 0, 0, 1.0, 0)
	expect_eq(m.tank_water_t, 0.0)


func test_flood_and_blow() -> void:
	m.tank_water_t = 0.0
	_run(10.0, 0.0, 0.0, 0.0, 1.0)
	expect_near(m.tank_water_t, 10.0 * m.flood_rate_t, 0.1, "flooded")
	var air_before: float = m.air_t
	_run(2.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	var blown: float = 2.0 * m.blow_rate_t
	expect_near(m.tank_water_t, 10.0 * m.flood_rate_t - blown, 0.1, "blown")
	expect_near(air_before - m.air_t, blown, 0.1, "air used")


func test_blow_stops_when_air_runs_out() -> void:
	m.air_t = 0.5
	m.tank_water_t = 10.0
	_run(5.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	expect_near(m.tank_water_t, 9.5, 0.01)
	expect_near(m.air_t, 0.0)


func test_floats_at_surface() -> void:
	m.position = Vector3(0, -5, 0)
	m.tank_water_t = 0.0
	_run(60.0)
	expect(m.is_surfaced(), "surfaced, y=%f" % m.position.y)
	expect(m.position.y < 0.0, "a sub rides low in the water")


func test_collide_removes_inward_velocity() -> void:
	m.velocity = Vector3(0, -2, 1)
	var impact: float = m.collide(Vector3.UP)
	expect_near(impact, 2.0)
	expect(m.velocity.y >= 0.0)


func test_blowing_an_empty_tank_uses_no_air() -> void:
	m.tank_water_t = 1.0
	_run(10.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	expect_eq(m.tank_water_t, 0.0)
	expect_near(m.air_capacity_t - m.air_t, 1.0, 0.01, "only the water's worth of air is used")


func test_responsive_speed_up_and_slow_down() -> void:
	# M7: twice as quick to reach speed and to coast down, same top speed.
	var t: float = 0.0
	while m.forward_speed() < 2.5 and t < 120.0:
		m.step(DT, 1.0, 0, 0, 0, 0)
		t += DT
	expect(t < 20.0, "reaches 2.5 m/s in %f s" % t)
	_run(40.0, 1.0)
	_run(10.0, 0.0)
	# Quadratic drag: v = v0 / (1 + k v0 t). With k doubled, ~1.5 m/s after 10 s
	# (it was ~2.0). Throttling astern brakes harder still.
	expect(m.forward_speed() < 1.8, "coasts down quickly (%f m/s after 10 s)" % m.forward_speed())


func test_throttle_dead_zone_mapping() -> void:
	var cases: Array[Vector2] = [
		Vector2(0.10, 0.0), Vector2(-0.14, 0.0), Vector2(0.15, 0.0), Vector2(0.575, 0.5),
		Vector2(1.0, 1.0), Vector2(-0.15, 0.0), Vector2(-0.575, -0.5), Vector2(-1.0, -1.0),
	]
	for c: Vector2 in cases:
		expect_near(SubPhysicsModel.throttle_order(c.x, 0.15), c.y, 0.0001)


func test_throttle_dead_zone_configurable() -> void:
	expect_near(SubPhysicsModel.throttle_order(0.3, 0.0), 0.3, 0.0001)
	expect_near(SubPhysicsModel.throttle_order(-0.8, 0.0), -0.8, 0.0001)
	expect_near(SubPhysicsModel.throttle_order(0.3, 0.3), 0.0, 0.0001)
	expect_near(SubPhysicsModel.throttle_order(0.65, 0.3), 0.5, 0.0001)


func test_engine_converges_to_zero_in_dead_band() -> void:
	m.engine = 0.6
	_run(20.0, SubPhysicsModel.throttle_order(0.14, 0.15))
	expect_near(m.engine, 0.0, 0.0001)


func test_bilge_is_uncapped_and_floors_at_zero() -> void:
	expect_near(m.change_bilge(12.0), 12.0, 0.0001)
	expect_near(m.bilge_water_t, 12.0, 0.0001, "above the old 8 t")
	expect_near(m.change_bilge(-100.0), -12.0, 0.0001, "actual change")
	expect_near(m.bilge_water_t, 0.0, 0.0001)


func test_bilge_height_from_tonnage() -> void:
	expect_eq(SubPhysicsModel.bilge_height_m(0.0), 0.0)
	expect(SubPhysicsModel.bilge_height_m(1.0) < SubPhysicsModel.bilge_height_m(2.0), "monotonic")
	var h3: float = SubPhysicsModel.bilge_height_m(3.0)
	var h4: float = SubPhysicsModel.bilge_height_m(4.0)
	expect(h3 >= 0.15 and h3 <= 0.20, "3 t height %f" % h3)
	expect(h4 >= 0.15 and h4 <= 0.20, "4 t height %f" % h4)


func test_enough_bilge_defeats_blown_tanks() -> void:
	m.tank_water_t = 0.0
	expect(m.buoyancy_accel() > 0.0, "blown tanks rise")
	var reserve_t: float = m.displacement_t - (m.dry_mass_t + m.payload_t)
	m.change_bilge(reserve_t + 2.0)
	expect(m.buoyancy_accel() < 0.0, "flooded sub sinks with tanks blown")
	m.change_bilge(-100.0)
	expect(m.buoyancy_accel() > 0.0, "pumped down it rises again")


func test_hull_bounds_come_from_layout() -> void:
	expect_near(SubPhysicsModel.hull_bottom(), SubLayout.hull_bottom_y(), 0.0001)
	expect_near(SubPhysicsModel.hull_top(), SubLayout.hull_top_y(), 0.0001)
	expect_near(SubPhysicsModel.hull_top() - SubPhysicsModel.hull_bottom(), SubLayout.hull_size().y, 0.0001, "hull height")
	var m: SubPhysicsModel = SubPhysicsModel.new()
	m.position.y = -SubPhysicsModel.hull_top() - 0.01
	expect_eq(m.submerged_fraction(), 1.0)
	expect(not m.is_surfaced(), "just below the surface")
	m.position.y = -SubPhysicsModel.hull_bottom() + 0.01
	expect_eq(m.submerged_fraction(), 0.0)


func test_flood_fills_empty_tank_in_capacity_over_rate() -> void:
	m.tank_water_t = 0.0
	var t: float = m.tank_capacity_t / m.flood_rate_t
	_run(t - 0.5, 0.0, 0.0, 0.0, 1.0, 0.0)
	expect(m.tank_water_t < m.tank_capacity_t - 0.1, "tank should not be full early (%f)" % m.tank_water_t)
	_run(1.0, 0.0, 0.0, 0.0, 1.0, 0.0)
	expect_near(m.tank_water_t, m.tank_capacity_t, 0.001, "tank full after capacity / flood rate")
	expect_near(t, 14.3, 0.5, "full flood time about 14 s")


func test_blow_empties_full_tank_in_capacity_over_rate() -> void:
	m.tank_water_t = m.tank_capacity_t
	var air_before: float = m.air_t
	var t: float = m.tank_capacity_t / m.blow_rate_t
	_run(t - 0.5, 0.0, 0.0, 0.0, 0.0, 1.0)
	expect(m.tank_water_t > 0.1, "tank should not be empty early (%f)" % m.tank_water_t)
	_run(1.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	expect_near(m.tank_water_t, 0.0, 0.001, "tank empty after capacity / blow rate")
	expect_near(air_before - m.air_t, m.tank_capacity_t, 0.001, "air spent equals tank capacity")
	expect_near(t, 7.1, 0.5, "full blow time about 7 s")
