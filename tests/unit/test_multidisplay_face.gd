extends TestCase
## MultiDisplay centre chevrons, edge ring and the pilot preset.

const PILOT := "res://assets/models/cockpit/pilot_multidisplay.tres"


func _display() -> MultiDisplay:
	var d: MultiDisplay = MultiDisplay.new()
	d.chevrons_enabled = true
	d.chevron_count = 3
	d.chevron_step = 1.0
	return d


func test_chevron_count() -> void:
	var d: MultiDisplay = _display()
	expect_eq(d.chevrons_lit(0.0), 0, "zero lights none")
	expect_eq(d.chevrons_lit(0.3), 1, "small positive")
	expect_eq(d.chevrons_lit(5.0), 3, "large positive clamps to count")
	expect_eq(d.chevrons_lit(-0.3), 1, "small negative")
	expect_eq(d.chevrons_lit(-5.0), 3, "large negative")
	expect_eq(d.chevrons_lit(1.5), 2, "steps per chevron")
	d.chevrons_enabled = false
	expect_eq(d.chevrons_lit(5.0), 0, "off draws none")
	d.free()


func test_ring_fraction_and_colour() -> void:
	var d: MultiDisplay = MultiDisplay.new()
	d.ring_enabled = true
	d.ring_segments = 10
	d.ring_warn_below = 0.5
	d.ring_alarm_below = 0.2
	expect_near(d.ring_lit_fraction(1.0), 1.0, 1e-6)
	expect_near(d.ring_lit_fraction(0.5), 0.5, 1e-6)
	expect_near(d.ring_lit_fraction(0.0), 0.0, 1e-6)
	expect_eq(d.ring_swatch_for(0.9), &"light_ok")
	expect_eq(d.ring_swatch_for(0.5), &"light_warn", "warn at threshold")
	expect_eq(d.ring_swatch_for(0.51), &"light_ok")
	expect_eq(d.ring_swatch_for(0.2), &"light_alarm", "alarm at threshold")
	expect_eq(d.ring_swatch_for(0.21), &"light_warn")
	d.ring_enabled = false
	expect_eq(d.ring_lit(1.0), 0, "off lights none")
	d.free()


func test_defaults_leave_face_unchanged() -> void:
	var d: MultiDisplay = MultiDisplay.new()
	expect(not d.chevrons_enabled and not d.ring_enabled, "off by default")
	d.free()


func test_pilot_preset_matches_sub_controller() -> void:
	var p: MultiDisplayPreset = load(PILOT) as MultiDisplayPreset
	expect(p != null, "preset loads")
	var kinds: Array = [
		MultiDisplaySlot.Kind.NUMBER, MultiDisplaySlot.Kind.PIE,
		MultiDisplaySlot.Kind.BAR, MultiDisplaySlot.Kind.NUMBER]
	var names: Array = [&"depth", &"tank_fraction", &"buoyancy", &"altitude"]
	expect_eq(p.slots.size(), 4)
	var sub: SubController = SubController.new()
	runner.add_child(sub)
	for i: int in range(4):
		expect_eq(p.slots[i].readout, names[i], "slot %d readout" % i)
		expect_eq(p.slots[i].kind, kinds[i], "slot %d widget" % i)
	var all: Array = names + [p.chevron_readout, p.ring_readout]
	expect_eq(p.chevron_readout, &"vertical_speed")
	expect_eq(p.ring_readout, &"air_fraction")
	for n: StringName in all:
		expect(typeof(sub.readout(n)) == TYPE_FLOAT, "%s returns a float" % n)
	expect(p.chevrons_enabled and p.ring_enabled)
	var d: MultiDisplay = MultiDisplay.new()
	d.apply_preset(p)
	expect_eq(d.slots.size(), 4)
	expect_eq(d.ring_readout, &"air_fraction")
	d.free()
	sub.queue_free()
