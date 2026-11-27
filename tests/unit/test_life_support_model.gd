extends TestCase
## The pure life support model: breathing, scrubbing, the O2 tank and venting.

const DT: float = 0.5


func _model() -> LifeSupportModel:
	return LifeSupportModel.new(load("res://src/life_support/life_support_params.tres") as LifeSupportParams)


func _caps(n: int) -> Array[float]:
	var a: Array[float] = []
	for i: int in n:
		a.append(1.0)
	return a


## Steps until [param done] returns true or [param limit] seconds pass; returns the time.
func _run(m: LifeSupportModel, crew: int, fans: bool, surfaced: bool, caps: Array[float], limit: float, done: Callable) -> float:
	var t: float = 0.0
	while t < limit and not done.call():
		m.step(DT, crew, fans, surfaced, caps)
		t += DT
	return t


func test_params_resource_loads() -> void:
	expect(load("res://src/life_support/life_support_params.tres") is LifeSupportParams)


func test_production_scales_with_crew() -> void:
	var one: LifeSupportModel = _model()
	var four: LifeSupportModel = _model()
	var none: Array[float] = []
	one.step(10.0, 1, false, false, none)
	four.step(10.0, 4, false, false, none)
	var rise1: float = one.co2_ppm() - 400.0
	var rise4: float = four.co2_ppm() - 400.0
	expect(rise1 > 0.0, "one crew raises CO2")
	expect_near(rise4, rise1 * 4.0, 0.01, "four crew breathe four times as much")
	var empty: LifeSupportModel = _model()
	empty.step(10.0, 0, false, false, none)
	expect_near(empty.co2_ppm(), 400.0, 0.001, "empty sub adds nothing")


func test_effectiveness_curve() -> void:
	var m: LifeSupportModel = _model()
	expect_near(m.effectiveness(0.0), 1.0)
	expect_near(m.effectiveness(0.85), 1.0)
	expect_near(m.effectiveness(1.0), 0.0)
	var mid: float = m.effectiveness(0.925)
	expect(mid > 0.0 and mid < 1.0, "smooth in between")
	expect(m.effectiveness(0.9) > m.effectiveness(0.95), "falls monotonically")


func test_no_removal_with_fans_off() -> void:
	var m: LifeSupportModel = _model()
	m.set_co2_ppm(5000.0)
	var caps: Array[float] = _caps(2)
	m.step(10.0, 0, false, false, caps)
	expect_near(m.co2_ppm(), 5000.0, 0.001, "fans off: nothing removed")
	expect_near(caps[0], 1.0, 0.0001, "and no capacity used")
	m.step(10.0, 0, true, false, caps)
	expect(m.co2_ppm() < 5000.0, "fans on: removed")


func test_saturation_drains_capacity() -> void:
	var m: LifeSupportModel = _model()
	m.set_co2_ppm(5000.0)
	var caps: Array[float] = _caps(2)
	m.step(10.0, 0, true, false, caps)
	expect(caps[0] < 1.0 and caps[1] < 1.0, "both canisters drain")
	expect_near(caps[0], caps[1], 0.0001, "equally")
	var spent: Array[float] = [0.0]
	var before: float = m.co2_ppm()
	m.step(10.0, 0, true, false, spent)
	expect_near(m.co2_ppm(), before, 0.001, "a spent canister removes nothing")


func test_fresh_pair_holds_for_four_crew() -> void:
	var m: LifeSupportModel = _model()
	var caps: Array[float] = _caps(2)
	for i: int in 1200:
		m.step(DT, 4, true, false, caps)
		expect(m.co2_ppm() <= 400.0 + 0.01, "holds at the floor")
		expect(m.co2_ppm() >= 400.0 - 0.001, "never below the floor")
	var m2: LifeSupportModel = _model()
	m2.set_co2_ppm(6000.0)
	var caps2: Array[float] = _caps(2)
	m2.step(5.0, 4, true, false, caps2)
	expect(m2.co2_ppm() < 6000.0, "a fresh pair draws it down")
	expect(m2.removal_capacity(_caps(1)) >= 4.0 * m2.params.co2_per_crew_per_s, "one canister outpaces four crew")


func test_fans_off_climb_takes_four_minutes() -> void:
	var m: LifeSupportModel = _model()
	m.set_co2_ppm(7000.0)
	var none: Array[float] = []
	var t: float = _run(m, 4, false, false, none, 1000.0, func() -> bool: return m.co2_ppm() >= 15000.0)
	expect_near(t, 240.0, 60.0, "0.7%% to 1.5%% in about 4 minutes (got %f)" % t)


func test_one_canister_carries_four_crew_fifteen_minutes() -> void:
	var m: LifeSupportModel = _model()
	var caps: Array[float] = _caps(1)
	var t: float = _run(m, 4, true, false, caps, 3000.0, func() -> bool: return m.co2_ppm() >= 7000.0)
	expect_near(t, 900.0, 225.0, "one canister lasts about 15 minutes (got %f)" % t)


func test_o2_tank_lasts_forty_five_minutes_then_cabin_falls() -> void:
	var m: LifeSupportModel = _model()
	var caps: Array[float] = _caps(2)
	var t: float = _run(m, 4, true, false, caps, 6000.0, func() -> bool: return m.o2_tank <= 0.0)
	expect_near(t, 2700.0, 675.0, "tank lasts about 45 minutes (got %f)" % t)
	expect_near(m.cabin_o2, 1.0, 0.0001, "cabin O2 holds while the tank has any")
	m.step(30.0, 4, true, false, caps)
	expect(m.cabin_o2 < 1.0, "then cabin O2 falls")


func test_surface_venting_reaches_baseline_in_thirty_seconds() -> void:
	for fans: bool in [false, true]:
		var m: LifeSupportModel = _model()
		m.set_co2_ppm(15000.0)
		var none: Array[float] = []
		var t: float = _run(m, 4, fans, true, none, 120.0, func() -> bool: return m.co2_ppm() <= 400.5)
		expect_near(t, 30.0, 7.5, "vents in about 30 s, fans %s (got %f)" % [fans, t])
