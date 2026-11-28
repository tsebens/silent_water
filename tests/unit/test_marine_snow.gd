extends TestCase
## Marine snow: depth-dependent density wiring.


func test_peak_depth_is_the_light_ramp_depth() -> void:
	expect_near(OceanSurface.SNOW_PEAK_DEPTH, SurfaceLighting.RAMP_DEPTH)


func test_ready_sets_shader_uniforms() -> void:
	var snow: MarineSnow = MarineSnow.new()
	runner.add_child(snow)
	var m: ShaderMaterial = snow.material_override as ShaderMaterial
	expect_near(float(m.get_shader_parameter(&"peak_depth")), SurfaceLighting.RAMP_DEPTH)
	expect_near(float(m.get_shader_parameter(&"surface_y")), OceanSurface.SURFACE_Y)
	expect_near(float(m.get_shader_parameter(&"curve_power")), OceanSurface.SNOW_CURVE_POWER)
	snow.free()


func test_flakes_have_stable_thresholds() -> void:
	var snow: MarineSnow = MarineSnow.new()
	snow.flake_count = 10
	var arrays: Array = snow._build_mesh().surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	expect(colors.size() == 40, "four vertices per flake")
	for i: int in range(10):
		for c: int in range(1, 4):
			expect_near(colors[i * 4 + c].r, colors[i * 4].r)
	snow.free()
