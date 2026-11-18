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
	expect(m.engine < 0.3, "engine should not jump to full (%f)" % m.engine)
	_run(5.0, 1.0)
	expect_near(m.engine, 1.0, 0.001)


func test_astern_is_slower() -> void:
	_run(120.0, -1.0)
	expect(m.forward_speed() < -1.5 and m.forward_speed() > -2.6, "astern speed %f" % m.forward_speed())


func test_rudder_needs_flow() -> void:
	_run(10.0, 0.0, 1.0)
	expect(absf(m.angles.y) < 0.01, "no turning while stopped")
	before_each()
	_run(60.0, 1.0)
	var yaw0: float = m.angles.y
	_run(10.0, 1.0, 1.0)
	expect(m.angles.y < yaw0 - 0.3, "positive rudder turns to starboard (yaw decreases), got %f" % (m.angles.y - yaw0))


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


func test_flood_and_blow() -> void:
	m.tank_water_t = 0.0
	_run(10.0, 0.0, 0.0, 0.0, 1.0)
	expect_near(m.tank_water_t, 3.5, 0.1, "flooded")
	var air_before: float = m.air_t
	_run(2.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	expect_near(m.tank_water_t, 2.1, 0.1, "blown")
	expect_near(air_before - m.air_t, 1.4, 0.1, "air used")


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
	expect(m.position.y <= 0.0 and m.position.y > -1.5, "surfaced, y=%f" % m.position.y)


func test_collide_removes_inward_velocity() -> void:
	m.velocity = Vector3(0, -2, 1)
	var impact: float = m.collide(Vector3.UP)
	expect_near(impact, 2.0)
	expect(m.velocity.y >= 0.0)
