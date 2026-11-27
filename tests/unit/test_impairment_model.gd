extends TestCase
## Bad-air impairment: the CO2 ladder, the O2 mapping, incapacitation and lingering blur.

var m: ImpairmentModel


func before_each() -> void:
	m = ImpairmentModel.new(load("res://src/life_support/impairment_params.tres") as ImpairmentParams)


func test_strength_at_each_threshold() -> void:
	expect_near(m.strength_for_ppm(14000.0), 0.0)
	expect_near(m.strength_for_ppm(15000.0), 0.0)
	expect_near(m.strength_for_ppm(25000.0), 0.35)
	expect_near(m.strength_for_ppm(30000.0), 0.55)
	expect_near(m.strength_for_ppm(40000.0), 0.85)
	expect_near(m.strength_for_ppm(70000.0), 1.0)
	expect_near(m.strength_for_ppm(120000.0), 1.0)


func test_monotonic_and_continuous() -> void:
	var prev: float = 0.0
	var ppm: float = 0.0
	while ppm <= 90000.0:
		var s: float = m.strength_for_ppm(ppm)
		expect(s >= prev - 0.000001, "monotonic at %f" % ppm)
		expect(s - prev < 0.003, "continuous at %f" % ppm)
		prev = s
		ppm += 50.0


func test_o2_reaches_each_step_faster_than_co2() -> void:
	var lp: LifeSupportParams = LifeSupportParams.new()
	var crew: float = 4.0
	for target: float in [0.35, 0.55, 0.85, 1.0]:
		var co2_t: float = -1.0
		var ppm: float = lp.baseline_ppm
		while m.strength_for_ppm(ppm) < target - 0.0001 and ppm < 200000.0:
			ppm += 50.0
		co2_t = lp.ppm_to_litres(ppm - lp.baseline_ppm) / (lp.co2_per_crew_per_s * crew)
		var o2: float = 1.0
		while m.strength_for_o2(o2) < target - 0.0001 and o2 > 0.0:
			o2 -= 0.0005
		var o2_t: float = (1.0 - o2) / (lp.cabin_o2_fall_per_crew_per_s * crew)
		expect(o2_t < co2_t, "o2 faster at %f (%f vs %f)" % [target, o2_t, co2_t])


func test_combined_is_the_larger() -> void:
	m.step(0.1, 30000.0, 1.0)
	expect_near(m.strength, 0.55)
	m.step(0.1, 400.0, 0.7)
	expect_near(m.strength, m.strength_for_o2(0.7))
	m.step(0.1, 30000.0, 0.99)
	expect_near(m.strength, 0.55)


func test_incapacitation_threshold_and_hysteresis() -> void:
	m.step(0.1, 69900.0, 1.0)
	expect(not m.incapacitated)
	m.step(0.1, 70000.0, 1.0)
	expect(m.incapacitated)
	for ppm: float in [60000.0, 45000.0, 69000.0, 41000.0, 50000.0]:
		m.step(0.1, ppm, 1.0)
		expect(m.incapacitated, "stays down at %f" % ppm)
	m.step(0.1, 39900.0, 1.0)
	expect(not m.incapacitated)


func test_o2_can_incapacitate() -> void:
	m.step(0.1, 400.0, 0.4)
	expect(m.incapacitated)


func test_lingering_blur_decays() -> void:
	m.step(0.1, 80000.0, 1.0)
	m.step(0.1, 1000.0, 1.0)
	expect(not m.incapacitated)
	expect(m.blur() > 0.9)
	var last: float = m.blur()
	for i: int in range(60):
		m.step(0.5, 1000.0, 1.0)
		expect(m.blur() <= last + 0.000001)
		last = m.blur()
	expect_near(m.blur(), 0.0)
	expect_near(m.linger_blur, 0.0)


func test_outputs_scale_with_strength() -> void:
	m.step(0.1, 15000.0, 1.0)
	expect_near(m.vignette(), 0.0)
	expect_near(m.movement_slowdown(), 0.0)
	m.step(0.1, 40000.0, 1.0)
	expect(m.vignette() > 0.4)
	expect(m.movement_slowdown() > 0.3)
	expect(m.wander_swing() > 0.3)


func test_crew_incapacitation_tracks_models() -> void:
	var crew: CrewIncapacitation = CrewIncapacitation.new()
	crew.add_crew(1, ImpairmentModel.new())
	crew.add_crew(2, ImpairmentModel.new())
	crew.step(0.1, 80000.0, 1.0)
	expect(crew.all_incapacitated())
	crew.model_for(2).step(0.1, 1000.0, 1.0)
	expect(not crew.all_incapacitated())
	expect(crew.is_incapacitated(1))
