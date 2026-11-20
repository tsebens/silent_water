extends TestCase
## Surfacing light ramp and day/night presets.


func test_intensity_monotonic_over_ramp_and_constant_below() -> void:
	var prev: float = -1.0
	var d: float = SurfaceLighting.RAMP_DEPTH + 20.0
	while d >= -1.0:
		var i: float = SurfaceLighting.light_intensity(SurfaceLighting.DAY, d)
		expect(i >= prev - 0.000001, "intensity decreased as depth decreased at %.1f" % d)
		prev = i
		d -= 0.5
	expect_near(SurfaceLighting.light_intensity(SurfaceLighting.DAY, SurfaceLighting.RAMP_DEPTH), 0.0)
	expect_near(SurfaceLighting.light_intensity(SurfaceLighting.DAY, 200.0), 0.0)
	expect_near(SurfaceLighting.light_intensity(SurfaceLighting.DAY, SurfaceLighting.RAMP_DEPTH + 1.0),
		SurfaceLighting.light_intensity(SurfaceLighting.DAY, 300.0))
	expect(SurfaceLighting.light_intensity(SurfaceLighting.DAY, 5.0) > 0.0, "light visible near surface")
	expect_near(SurfaceLighting.light_intensity(SurfaceLighting.DAY, 0.0), SurfaceLighting.DAY.sun_energy)


func test_day_and_night_differ_and_day_is_default() -> void:
	var day: float = SurfaceLighting.light_intensity(SurfaceLighting.DAY, 10.0)
	var night: float = SurfaceLighting.light_intensity(SurfaceLighting.NIGHT, 10.0)
	expect(day > night, "day brighter than night")
	expect(night > 0.0, "night still has a faint cue")
	expect(not SurfaceLighting.light_color_at(SurfaceLighting.DAY, 10.0).is_equal_approx(
		SurfaceLighting.light_color_at(SurfaceLighting.NIGHT, 10.0)), "colours differ")
	var node: SurfaceLighting = SurfaceLighting.new()
	expect(node.preset == SurfaceLighting.DAY, "day by default")
	node.free()


func test_dev_setting_toggles_preset() -> void:
	var before: bool = DevSettings.night
	DevSettings.night = false
	expect(DevSettings.toggle_night(), "day -> night")
	expect(not DevSettings.toggle_night(), "night -> day")
	expect(SurfaceLighting.other(SurfaceLighting.DAY) == SurfaceLighting.NIGHT, "other of day")
	expect(SurfaceLighting.other(SurfaceLighting.NIGHT) == SurfaceLighting.DAY, "other of night")
	DevSettings.night = before
