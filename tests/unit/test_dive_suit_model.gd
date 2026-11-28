extends TestCase
## Dive suit: air drain and refill, protection, and the worn effects.

var m: DiveSuitModel


func before_each() -> void:
	m = DiveSuitModel.new(load("res://src/life_support/dive_suit_params.tres") as DiveSuitParams)


func test_drains_while_worn() -> void:
	var start: float = m.air
	m.set_worn(true)
	m.step(10.0)
	expect(m.air < start, "air drains while worn")


func test_holds_when_not_worn() -> void:
	m.air = 100.0
	m.step(10.0)
	expect_near(m.air, 100.0)


func test_refills_when_off_and_refilling() -> void:
	m.air = 100.0
	m.step(1.0, true)
	expect(m.air > 100.0, "refills")
	m.step(100000.0, true)
	expect_near(m.air, m.params.air_capacity_seconds)


func test_no_refill_while_worn() -> void:
	m.set_worn(true)
	m.air = 100.0
	m.step(1.0, true)
	expect(m.air < 100.0, "worn suit drains, never refills")


func test_empty_is_unprotected() -> void:
	m.set_worn(true)
	expect(m.protects(), "protects with air")
	m.step(100000.0)
	expect(m.is_empty(), "empty")
	expect(not m.protects(), "no protection when empty")
	var a: Array[float] = m.filter_ambient(70000.0, 0.5)
	expect_near(a[0], 70000.0)
	expect_near(a[1], 0.5)


func test_protects_zeroes_bad_air() -> void:
	m.set_worn(true)
	var a: Array[float] = m.filter_ambient(70000.0, 0.5)
	expect_near(a[0], m.params.protected_co2_ppm)
	expect_near(a[1], m.params.protected_o2)
	m.set_worn(false)
	expect_near(m.filter_ambient(70000.0, 0.5)[0], 70000.0)


func test_effects_worn_and_not() -> void:
	expect_near(m.view_narrowing(), 0.0)
	expect_near(m.speed_multiplier(), 1.0)
	m.set_worn(true)
	expect(m.view_narrowing() > 0.0, "view narrows")
	expect(m.speed_multiplier() < 1.0, "slower")


func test_warning_levels() -> void:
	expect_eq(m.warning_level(), DiveSuitModel.WARN_NONE)
	m.set_worn(true)
	expect_eq(m.warning_level(), DiveSuitModel.WARN_NONE)
	m.air = m.params.air_capacity_seconds * m.params.low_air_fraction
	expect_eq(m.warning_level(), DiveSuitModel.WARN_LOW)
	m.air = m.params.air_capacity_seconds * m.params.critical_air_fraction
	expect_eq(m.warning_level(), DiveSuitModel.WARN_CRITICAL)
	m.set_worn(false)
	expect_eq(m.warning_level(), DiveSuitModel.WARN_NONE)
