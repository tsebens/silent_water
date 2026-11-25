extends TestCase
## The bar instrument: fill follows the readout, the colour band steps at the
## thresholds, and out-of-range readouts clamp.


func _gauge() -> LinearGauge:
	var g: LinearGauge = LinearGauge.new()
	runner.add_child(g)
	return g


func _bar_colour(g: LinearGauge) -> Color:
	return ((g.get_node("Bar/Fill") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color


func test_fill_fraction_follows_the_readout() -> void:
	var g: LinearGauge = _gauge()
	g.min_value = 0.0
	g.max_value = 200.0
	expect_near(g.fraction_for(0.0), 0.0, 1e-6)
	expect_near(g.fraction_for(50.0), 0.25, 1e-6)
	expect_near(g.fraction_for(200.0), 1.0, 1e-6)
	g.show_fraction(0.25)
	var bar: Node3D = g.get_node("Bar") as Node3D
	expect_near(bar.scale.y, 0.25, 1e-5, "bar height is the fraction")
	g.queue_free()


func test_bar_rises_from_the_bottom_of_the_track() -> void:
	var g: LinearGauge = _gauge()
	g.show_fraction(0.5)
	var bar: Node3D = g.get_node("Bar") as Node3D
	var fill: MeshInstance3D = bar.get_node("Fill") as MeshInstance3D
	expect_near(bar.position.y, 0.0, 1e-5, "pivot on the track bottom")
	expect_near(fill.position.y - g.track_height * 0.5, 0.0, 1e-5, "fill stands on the pivot")
	expect_near((fill.position.y + g.track_height * 0.5) * bar.scale.y, g.track_height * 0.5, 1e-5, "top at half the track")
	g.queue_free()


func test_band_colour_changes_at_50_and_85_percent() -> void:
	var g: LinearGauge = _gauge()
	expect_eq(g.swatch_for(0.49), g.ok_swatch)
	expect_eq(g.swatch_for(0.5), g.ok_swatch, "50% is still ok")
	expect_eq(g.swatch_for(0.51), g.warn_swatch)
	expect_eq(g.swatch_for(0.85), g.warn_swatch, "85% is still warn")
	expect_eq(g.swatch_for(0.86), g.alarm_swatch)
	g.show_fraction(0.3)
	var ok: Color = _bar_colour(g)
	g.show_fraction(0.7)
	var warn: Color = _bar_colour(g)
	g.show_fraction(0.95)
	var alarm: Color = _bar_colour(g)
	expect(ok != warn and warn != alarm and ok != alarm, "three distinct colours")
	expect(ok.is_equal_approx(Palette.main().color(g.ok_swatch)), "ok colour from the palette")
	g.queue_free()


func test_thresholds_are_exports() -> void:
	var g: LinearGauge = _gauge()
	g.warn_at = 0.2
	g.alarm_at = 0.4
	expect_eq(g.swatch_for(0.3), g.warn_swatch)
	expect_eq(g.swatch_for(0.5), g.alarm_swatch)
	g.queue_free()


func test_out_of_range_values_clamp() -> void:
	var g: LinearGauge = _gauge()
	g.min_value = 10.0
	g.max_value = 20.0
	expect_near(g.fraction_for(-5.0), 0.0, 1e-6)
	expect_near(g.fraction_for(99.0), 1.0, 1e-6)
	g.show_fraction(7.0)
	expect_near(g.shown_fraction(), 1.0, 1e-6, "over-range display clamps")
	g.show_fraction(-3.0)
	expect_near(g.shown_fraction(), 0.0, 1e-6)
	g.queue_free()
