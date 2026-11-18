extends TestCase


func test_clamps_to_range() -> void:
	var s: InteractableState = InteractableState.new(0.0, 1.0, 0.5)
	s.set_value(2.0)
	expect_eq(s.value, 1.0)
	s.set_value(-1.0)
	expect_eq(s.value, 0.0)


func test_reversed_range_is_normalized() -> void:
	var s: InteractableState = InteractableState.new(10.0, -10.0, 0.0)
	expect_eq(s.min_value, -10.0)
	expect_eq(s.max_value, 10.0)


func test_only_one_holder() -> void:
	var s: InteractableState = InteractableState.new()
	expect(s.try_grab(2))
	expect(not s.try_grab(3), "second player must not steal the control")
	expect(s.try_grab(2), "holder re-grabbing is fine")
	expect(not s.release(3))
	expect(s.release(2))
	expect(s.try_grab(3))


func test_only_holder_moves_value() -> void:
	var s: InteractableState = InteractableState.new(0.0, 1.0, 0.0)
	expect(not s.request(5, 0.7), "nobody holds it yet")
	s.try_grab(5)
	expect(not s.request(6, 0.9))
	expect(s.request(5, 0.7))
	expect_near(s.value, 0.7)


func test_rate_tracks_speed_and_decays() -> void:
	var s: InteractableState = InteractableState.new(0.0, 2.0, 0.0)
	# Sweep the full range in 0.5 s at 60 Hz => 2 full ranges per second.
	for i: int in range(30):
		s.set_value(2.0 * float(i + 1) / 30.0)
		s.tick(1.0 / 60.0)
	expect(s.normalized_rate > 1.5, "rate %f should approach 2" % s.normalized_rate)
	for i: int in range(60):
		s.tick(1.0 / 60.0)
	expect(s.normalized_rate < 0.01, "rate %f should decay when still" % s.normalized_rate)


func test_slow_movement_is_quiet_fast_is_loud() -> void:
	var p: NoiseProfile = NoiseProfile.new()
	p.idle_intensity = 0.0
	p.max_intensity = 1.0
	p.clank_rate = 2.0
	p.exponent = 2.0
	expect_near(p.intensity_for_rate(0.0), 0.0)
	expect_near(p.intensity_for_rate(0.2), 0.01)
	expect_near(p.intensity_for_rate(2.0), 1.0)
	expect_near(p.intensity_for_rate(10.0), 1.0, 0.0001, "clamped")
