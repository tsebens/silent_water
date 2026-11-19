extends TestCase


func test_db_round_trip() -> void:
	expect_near(NoiseLevel.to_db(1.0), 100.0)
	expect_near(NoiseLevel.to_db(0.01), 80.0)
	expect_near(NoiseLevel.from_db(70.0), 0.001, 1e-9)


func test_two_equal_sources_add_3_db() -> void:
	var one: float = NoiseLevel.from_db(70.0)
	expect_near(NoiseLevel.to_db(one + one), 73.01, 0.01)


func test_quiet_source_barely_changes_loud_one() -> void:
	var loud: float = NoiseLevel.from_db(80.0)
	var quiet: float = NoiseLevel.from_db(60.0)
	expect(NoiseLevel.to_db(loud + quiet) < 80.05)


func test_attenuation_by_distance() -> void:
	var i: float = NoiseLevel.from_db(90.0)
	expect_near(NoiseLevel.to_db(NoiseLevel.attenuate(i, 1.0)), 90.0)
	# 15 log10(100) = 30 dB of spreading loss at 100 m.
	expect_near(NoiseLevel.to_db(NoiseLevel.attenuate(i, 100.0)), 60.0, 0.01)


func test_zero_intensity_is_finite() -> void:
	expect(is_finite(NoiseLevel.to_db(0.0)))


func test_ambient_zone_falls_off() -> void:
	var z: AmbientZone = AmbientZone.new()
	z.source_db = 110.0
	z.max_range = 50.0
	expect_near(NoiseLevel.to_db(z.intensity_at(Vector3(10, 0, 0))), 95.0, 0.01)
	expect_eq(z.intensity_at(Vector3(60, 0, 0)), 0.0)
	z.active = false
	expect_eq(z.intensity_at(Vector3(1, 0, 0)), 0.0)
	z.free()
