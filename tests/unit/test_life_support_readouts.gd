extends TestCase
## LifeSupportReadouts: named readouts, ppm mapping and alarm levels.

const L := LifeSupportAlarmLevels.Level

var src: LifeSupportReadouts
var co2_changes: Array[int] = []
var o2_changes: Array[int] = []


func before_each() -> void:
	src = LifeSupportReadouts.new()
	runner.add_child(src)
	co2_changes.clear()
	o2_changes.clear()
	src.co2_alarm_changed.connect(func(l: int) -> void: co2_changes.append(l))
	src.o2_alarm_changed.connect(func(l: int) -> void: o2_changes.append(l))


func after_each() -> void:
	src.free()


func test_readout_names() -> void:
	expect(src.is_in_group(&"life_support_readouts"))
	src.o2_level = 0.6
	src.co2_ppm = 10000.0
	src.saturation_a = 0.3
	src.saturation_b = 0.7
	expect_near(src.readout(&"o2_level"), 0.6)
	expect_near(src.readout(&"co2_ppm"), 10000.0)
	expect_near(src.readout(&"co2_level"), 0.25)
	expect_near(src.readout(&"saturation_a"), 0.3)
	expect_near(src.readout(&"saturation_b"), 0.7)
	expect_near(src.readout(&"bogus"), 0.0)


func test_co2_level_mapping() -> void:
	for pair: Array in [[0.0, 0.0], [7000.0, 0.175], [25000.0, 0.625], [40000.0, 1.0], [80000.0, 1.0]]:
		src.co2_ppm = pair[0]
		expect_near(src.readout(&"co2_level"), pair[1], 0.0001, "ppm %s" % pair[0])


func test_co2_alarm_levels() -> void:
	var lv: LifeSupportAlarmLevels = src.alarm_levels
	expect_eq(lv.co2_level_for(6999.0), L.OFF)
	expect_eq(lv.co2_level_for(7000.0), L.STEADY)
	expect_eq(lv.co2_level_for(24999.0), L.STEADY)
	expect_eq(lv.co2_level_for(25000.0), L.FLASH)


func test_o2_alarm_levels() -> void:
	var lv: LifeSupportAlarmLevels = src.alarm_levels
	expect_eq(lv.o2_level_for(0.26), L.OFF)
	expect_eq(lv.o2_level_for(0.25), L.STEADY)
	expect_eq(lv.o2_level_for(0.11), L.STEADY)
	expect_eq(lv.o2_level_for(0.10), L.FLASH)


func test_signals_once_per_change() -> void:
	src.co2_ppm = 8000.0
	src.co2_ppm = 9000.0
	expect_eq(co2_changes, [L.STEADY] as Array[int])
	src.co2_ppm = 30000.0
	src.co2_ppm = 31000.0
	src.co2_ppm = 400.0
	expect_eq(co2_changes, [L.STEADY, L.FLASH, L.OFF] as Array[int])
	src.o2_level = 0.2
	src.o2_level = 0.15
	src.o2_level = 0.05
	expect_eq(o2_changes, [L.STEADY, L.FLASH] as Array[int])
