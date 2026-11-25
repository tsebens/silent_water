extends TestCase
## MultiDisplay: four slots read their readouts and follow changes; the slot logic
## formats numbers, fills pies and signed bars, and switches to indicator swatches.

const K := MultiDisplaySlot.Kind


class FakeSource:
	extends Node
	var vals: Dictionary = {}

	func readout(n: StringName) -> float:
		return float(vals.get(n, 0.0))


func _slot(kind: MultiDisplaySlot.Kind, readout: StringName) -> MultiDisplaySlot:
	var s: MultiDisplaySlot = MultiDisplaySlot.new()
	s.kind = kind
	s.readout = readout
	return s


func test_four_slots_read_and_update() -> void:
	var src: FakeSource = FakeSource.new()
	src.add_to_group(&"md_test_source")
	src.vals = {&"a": 12.5, &"b": 1.0, &"c": 50.0, &"d": -2.0}
	runner.add_child(src)
	var d: MultiDisplay = MultiDisplay.new()
	d.source_group = &"md_test_source"
	var s_text: MultiDisplaySlot = _slot(K.TEXT, &"b")
	s_text.texts = PackedStringArray(["OFF", "ON"])
	var s_bar: MultiDisplaySlot = _slot(K.BAR, &"d")
	s_bar.min_value = -5.0
	s_bar.max_value = 5.0
	var s_pie: MultiDisplaySlot = _slot(K.PIE, &"c")
	d.slots = [_slot(K.NUMBER, &"a"), s_text, s_pie, s_bar]
	runner.add_child(d)
	d.refresh()
	expect_near(d.values[0], 12.5, 1e-6)
	expect_near(d.values[1], 1.0, 1e-6)
	expect_near(d.values[2], 50.0, 1e-6)
	expect_near(d.values[3], -2.0, 1e-6)
	expect_eq(s_text.text_for(d.values[1]), "ON")
	src.vals[&"a"] = 3.0
	src.vals[&"b"] = 0.0
	d.refresh()
	expect_near(d.values[0], 3.0, 1e-6, "number follows the readout")
	expect_eq(s_text.text_for(d.values[1]), "OFF", "text follows the readout")
	for i: int in range(4):
		expect(d.draws_slot(i), "slot %d draws" % i)
	var dial: MultiDisplaySlot = _slot(K.DIAL, &"a")
	dial.min_value = 0.0
	dial.max_value = 10.0
	expect_near(dial.fraction_for(2.5), 0.25, 1e-6, "dial fraction")
	d.queue_free()
	src.queue_free()


func test_number_format_units_and_pie() -> void:
	var s: MultiDisplaySlot = _slot(K.NUMBER, &"x")
	s.format = "%.1f"
	s.units = "m"
	expect_eq(s.number_for(12.345), "12.3 m")
	s.format = "%d"
	s.units = ""
	expect_eq(s.number_for(7.0), "7")
	var p: MultiDisplaySlot = _slot(K.PIE, &"x")
	p.min_value = 0.0
	p.max_value = 200.0
	expect_near(p.pie_for(50.0), 0.25, 1e-6)
	expect_near(p.pie_for(500.0), 1.0, 1e-6, "pie clamps")


func test_signed_bar() -> void:
	var b: MultiDisplaySlot = _slot(K.BAR, &"x")
	b.min_value = -10.0
	b.max_value = 10.0
	var pos: Vector2 = b.bar_span(5.0)
	expect_near(pos.x, 0.5, 1e-6, "positive starts at zero line")
	expect_near(pos.y, 0.75, 1e-6)
	var neg: Vector2 = b.bar_span(-5.0)
	expect_near(neg.x, 0.25, 1e-6)
	expect_near(neg.y, 0.5, 1e-6, "negative ends at zero line")
	b.min_value = 0.0
	expect_near(b.bar_span(5.0).x, 0.0, 1e-6, "unsigned bar rises from the bottom")


func test_warning_thresholds_use_indicator_swatches() -> void:
	var s: MultiDisplaySlot = _slot(K.NUMBER, &"x")
	s.warn_at = 60.0
	s.alarm_at = 90.0
	expect_eq(s.swatch_for(10.0), &"light_readout")
	expect_eq(s.swatch_for(60.0), &"light_warn")
	expect_eq(s.swatch_for(95.0), &"light_alarm")
	expect_eq(s.marker_for(10.0), "")
	expect_eq(s.marker_for(70.0), "!", "warning has a non-colour cue")
	expect_eq(s.marker_for(95.0), "!!")
	var pal: Palette = Palette.main()
	expect(pal.color(s.swatch_for(70.0)) != pal.color(s.swatch_for(10.0)), "warning colour differs")
	s.low_is_bad = true
	s.warn_at = 30.0
	s.alarm_at = 10.0
	expect_eq(s.swatch_for(50.0), &"light_readout")
	expect_eq(s.swatch_for(25.0), &"light_warn")
	expect_eq(s.swatch_for(5.0), &"light_alarm")


func test_empty_slot_draws_nothing() -> void:
	var d: MultiDisplay = MultiDisplay.new()
	d.slots = [_slot(K.NUMBER, &"a")]
	runner.add_child(d)
	expect(d.draws_slot(0))
	expect(not d.draws_slot(1), "missing slot is empty")
	expect(not d.draws_slot(3))
	d.slots = [_slot(K.EMPTY, &"a")]
	expect(not d.draws_slot(0), "EMPTY kind draws nothing")
	d.queue_free()
