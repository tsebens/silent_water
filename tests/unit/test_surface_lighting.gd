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


func test_dives_start_in_day_and_no_key_toggles_it() -> void:
	InputSetup.ensure_actions()
	expect(not InputMap.has_action(&"dev_toggle_night"), "no night toggle action")
	expect(SurfaceLighting.other(SurfaceLighting.DAY) == SurfaceLighting.NIGHT, "other of day")
	expect(SurfaceLighting.other(SurfaceLighting.NIGHT) == SurfaceLighting.DAY, "other of night")


func test_sky_fog_affect_ramp() -> void:
	expect_near(SurfaceLighting.sky_fog_affect(0.0), 0.0)
	expect_near(SurfaceLighting.sky_fog_affect(SurfaceLighting.RAMP_DEPTH), 1.0)
	expect_near(SurfaceLighting.sky_fog_affect(500.0), 1.0)
	var prev: float = -1.0
	var d: float = -2.0
	while d <= SurfaceLighting.RAMP_DEPTH + 20.0:
		var a: float = SurfaceLighting.sky_fog_affect(d)
		expect(a >= prev - 0.000001, "fog_sky_affect decreased with depth at %.1f" % d)
		prev = a
		d += 0.5


func test_presets_use_the_sky_swatch_and_only_day_has_a_sun_disc() -> void:
	expect(SurfaceLighting.DAY.sky_swatch == &"sky_day", "day sky is sky_day")
	expect(Palette.main().has(&"sky_day"), "sky_day exists")
	expect(SurfaceLighting.DAY.sun_disc_size > 0.0, "day has a disc")
	expect_near(SurfaceLighting.NIGHT.sun_disc_size, 0.0)
	expect_near(SurfaceLighting.NIGHT.sun_glow, 0.0)


func test_sky_material_follows_preset() -> void:
	var env: Environment = Environment.new()
	env.sky = Sky.new()
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = load("res://src/world/sky.gdshader") as Shader
	env.sky.sky_material = m
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	var node: SurfaceLighting = SurfaceLighting.new()
	node.environment_node = we
	node.set_preset(SurfaceLighting.DAY)
	expect(m.get_shader_parameter(&"sky_color") == SurfaceLighting.DAY.sky_color, "day sky colour")
	expect(float(m.get_shader_parameter(&"sun_disc_size")) > 0.0, "day disc")
	node.set_preset(SurfaceLighting.NIGHT)
	expect_near(float(m.get_shader_parameter(&"sun_disc_size")), 0.0)
	node.free()
	we.free()


func test_preset_sun_reaches_surface_material() -> void:
	var surface: OceanSurface = OceanSurface.new()
	runner.add_child(surface)
	var m: ShaderMaterial = surface.material_override as ShaderMaterial
	var node: SurfaceLighting = SurfaceLighting.new()
	node.surface = surface
	for p: LightPreset in [SurfaceLighting.DAY, SurfaceLighting.NIGHT]:
		node.set_preset(p)
		expect(m.get_shader_parameter(&"sun_direction").is_equal_approx(p.sun_direction.normalized()), "%s direction" % p.preset_name)
		expect(m.get_shader_parameter(&"sun_color") == p.light_color, "%s colour" % p.preset_name)
		expect_near(float(m.get_shader_parameter(&"sun_strength")), p.sun_energy)
	expect(not SurfaceLighting.DAY.sun_direction.normalized().is_equal_approx(SurfaceLighting.NIGHT.sun_direction.normalized()), "presets set different sun directions")
	expect(SurfaceLighting.DAY.sun_direction.y > 0.0 and SurfaceLighting.NIGHT.sun_direction.y > 0.0, "sun above the horizon")
	node.free()
	surface.free()
