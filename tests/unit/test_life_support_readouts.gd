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


func test_capacity_is_one_minus_saturation() -> void:
	src.saturation_a = 0.3
	src.saturation_b = 0.7
	expect_near(src.readout(&"capacity_a"), 0.7)
	expect_near(src.readout(&"capacity_b"), 0.3)


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


# -- Driven by the simulation ------------------------------------------------

func _cradles() -> Array[CanisterSlot]:
	var out: Array[CanisterSlot] = []
	for n: StringName in [LifeSupportReadouts.CRADLE_A, LifeSupportReadouts.CRADLE_B]:
		var slot: CanisterSlot = CanisterSlot.new()
		slot.name = n
		src.add_child(slot)
		var c: ScrubberCanister = ScrubberCanister.new()
		slot.add_child(c)
		slot.try_seat(c)
		out.append(slot)
	return out


func test_crew_raises_co2_and_drains_o2() -> void:
	src.crew_override = 4
	src.fans_on = false
	var before: float = src.co2_ppm
	src.step(60.0)
	expect(src.co2_ppm > before, "four crew breathe CO2 into the pool")
	expect(src.o2_level < 1.0, "and drain the O2 tank")
	src.crew_override = 0
	var held: float = src.co2_ppm
	src.step(60.0)
	expect_near(src.co2_ppm, held, 0.001, "no crew inside adds nothing")


func test_needles_read_capacity_and_production() -> void:
	var slots: Array[CanisterSlot] = _cradles()
	src.crew_override = 4
	src.step(1.0)
	expect_near(src.readout(&"co2_production_rate"), 4.0 * src.params.co2_per_crew_per_s / src.rate_full_scale_lps, 0.001)
	expect_near(src.readout(&"co2_capacity_rate"), 2.0 * src.params.canister_max_rate / src.rate_full_scale_lps, 0.001)
	src.set_fans_powered(false)
	src.step(1.0)
	expect_near(src.readout(&"co2_capacity_rate"), 0.0, 0.0001, "fans stopped: nothing is removed")
	expect(src.readout(&"co2_production_rate") > 0.0, "the crew still breathes")
	for s: CanisterSlot in slots:
		s.free()


func test_scrubbing_drains_canister_and_drives_saturation() -> void:
	var slots: Array[CanisterSlot] = _cradles()
	src.crew_override = 4
	src.co2_ppm = 8000.0
	src.step(30.0)
	var c: ScrubberCanister = slots[0].canister()
	expect(c.capacity < 1.0, "the canister absorbed CO2")
	expect_near(src.saturation_a, 1.0 - c.capacity, 0.0001)
	expect_near(src.readout(&"capacity_a"), c.capacity, 0.0001)
	expect(src.co2_ppm < 8000.0 + 4.0 * src.params.litres_to_ppm(src.params.co2_per_crew_per_s) * 30.0, "scrubbing held CO2 down")
	for s: CanisterSlot in slots:
		s.free()


func test_empty_cradle_reads_no_capacity() -> void:
	var a: CanisterSlot = CanisterSlot.new()
	a.name = LifeSupportReadouts.CRADLE_A
	src.add_child(a)
	var c: ScrubberCanister = ScrubberCanister.new()
	a.add_child(c)
	a.try_seat(c)
	src.step(0.1)
	expect(src.readout(&"capacity_a") > 0.9)
	a.release()
	src.step(0.1)
	expect_near(src.readout(&"capacity_a"), 0.0, 0.0001, "an emptied cradle reads no capacity")
	a.free()


func test_surfacing_vents_the_readout() -> void:
	var sc: SubController = SubController.new()
	runner.add_child(sc)
	src.crew_override = 0
	src.co2_ppm = 10000.0
	sc.surfaced = true
	for i: int in 40:
		src.step(1.0)
	expect_near(src.co2_ppm, 400.0, 1.0, "vented to baseline within about 30 s")
	sc.free()
