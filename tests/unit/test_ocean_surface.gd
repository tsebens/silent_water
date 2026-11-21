extends TestCase
## Ocean surface: wave function, snow clipping, and the node in the world scene.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func test_snow_density_zero_at_and_above_surface() -> void:
	expect_near(OceanSurface.snow_density(0.0), 0.0)
	expect_near(OceanSurface.snow_density(-5.0), 0.0)
	expect_near(OceanSurface.snow_density(10.0), 1.0)
	expect_near(OceanSurface.snow_density(10.0, 0.4), 0.4)


func _default_waves(steep: float = 0.7) -> Array[OceanSurface.Wave]:
	return OceanSurface.generate_waves(30.0, 5, steep, 6.0, 40.0, 1.2)


## Independent reference: the Gerstner sum written out per point, from the
## documented formulas (GPU Gems ch. 1), using the wave table's raw numbers.
func _ref(waves: Array[OceanSurface.Wave], x: float, z: float, t: float) -> Vector3:
	var hy: float = 0.0
	var dx: float = 0.0
	var dz: float = 0.0
	for w: OceanSurface.Wave in waves:
		var th: float = w.k * (w.dir.x * x + w.dir.y * z) - w.omega * t
		hy += w.amp * sin(th)
		dx += w.dir.x * w.horiz * cos(th)
		dz += w.dir.y * w.horiz * cos(th)
	return Vector3(dx, hy, dz)


func test_wave_height_matches_reference_table() -> void:
	var waves: Array[OceanSurface.Wave] = _default_waves()
	var pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(3, 4, 2), Vector3(-17.5, 8.25, 11), Vector3(120, -60, 5.5),
		Vector3(1000, 333, 40), Vector3(-250, 90, 0.1)]
	for p: Vector3 in pts:
		var r: Vector3 = _ref(waves, p.x, p.y, p.z)
		expect_near(OceanSurface.wave_height(Vector2(p.x, p.y), p.z, waves), r.y)
		var d: Vector2 = OceanSurface.horizontal_displacement(Vector2(p.x, p.y), p.z, waves)
		expect_near(d.x, r.x)
		expect_near(d.y, r.z)


func test_height_bounded_and_varying() -> void:
	var waves: Array[OceanSurface.Wave] = _default_waves()
	var distinct: Dictionary = {}
	for i: int in range(200):
		var h: float = OceanSurface.wave_height(Vector2(i * 1.7, i * 0.9), i * 0.3, waves)
		expect(absf(h) <= 1.2 + 0.0001, "wave exceeds amplitude")
		distinct[snappedf(h, 0.001)] = true
	expect(distinct.size() > 20, "wave should vary")
	expect(not is_equal_approx(OceanSurface.wave_height(Vector2(3, 4), 2.0, waves),
		OceanSurface.wave_height(Vector2(3, 4), 3.0, waves)), "varies with time")


func test_wave_table_is_deterministic_and_pinned() -> void:
	var a: Array[OceanSurface.Wave] = _default_waves()
	var b: Array[OceanSurface.Wave] = _default_waves()
	expect_eq(a.size(), 5)
	var amp_sum: float = 0.0
	for i: int in range(a.size()):
		expect_near(a[i].k, b[i].k)
		expect(a[i].dir.is_equal_approx(b[i].dir), "same direction")
		expect_near(a[i].dir.length(), 1.0)
		expect_near(a[i].omega, sqrt(OceanSurface.GRAVITY * a[i].k) * 0.4)
		amp_sum += a[i].amp
	expect_near(amp_sum, 1.2)
	# Wavelengths span the range, longest first; amplitude grows with wavelength.
	expect_near(TAU / a[0].k, 40.0)
	expect_near(TAU / a[4].k, 6.0)
	expect_near(a[0].amp / a[4].amp, 40.0 / 6.0)
	# Pinned first and last entries (wind 30 deg, spread 40 deg).
	expect_near(a[0].dir.angle(), deg_to_rad(30.0 + 0.0))
	expect_near(a[1].dir.angle(), deg_to_rad(30.0 + (fposmod(0.6180339887 + 0.5, 1.0) - 0.5) * 80.0))
	expect_near(a[0].horiz, 0.7 / (5.0 * a[0].k))
	# The shader receives exactly these numbers.
	var packed: Array[PackedVector4Array] = OceanSurface.pack_waves(a)
	expect_eq(packed[0].size(), OceanSurface.MAX_WAVES)
	for i: int in range(a.size()):
		expect(packed[0][i].is_equal_approx(Vector4(a[i].dir.x, a[i].dir.y, a[i].k, a[i].omega)), "wave_a %d" % i)
		expect(packed[1][i].is_equal_approx(Vector4(a[i].amp, a[i].horiz, 0.0, 0.0)), "wave_b %d" % i)
	# Count is clamped to the shader's array size.
	expect_eq(OceanSurface.generate_waves(0.0, 99, 0.5, 6.0, 40.0, 1.0).size(), OceanSurface.MAX_WAVES)
	expect_eq(OceanSurface.generate_waves(0.0, 0, 0.5, 6.0, 40.0, 1.0).size(), 1)


func test_steepness_sharpens_crests() -> void:
	var flat: Array[OceanSurface.Wave] = _default_waves(0.0)
	var prev: float = -1.0
	for st: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var waves: Array[OceanSurface.Wave] = _default_waves(st)
		var max_d: float = 0.0
		var max_tilt: float = 0.0
		for i: int in range(400):
			var p: Vector2 = Vector2(i * 2.3, i * 1.1)
			max_d = maxf(max_d, OceanSurface.horizontal_displacement(p, 1.5, waves).length())
			var n: Vector3 = OceanSurface.wave_normal(p, 1.5, waves)
			max_tilt = maxf(max_tilt, acos(n.y))
			# Height never depends on steepness.
			expect_near(OceanSurface.wave_height(p, 1.5, waves), OceanSurface.wave_height(p, 1.5, flat))
		if st == 0.0:
			expect_near(max_d, 0.0)
		expect(max_d > prev, "displacement should grow with steepness (%.2f)" % st)
		prev = max_d
	# Steepness 0: pure vertical sines, one per wave.
	var w0: OceanSurface.Wave = flat[0]
	for i: int in range(50):
		var p: Vector2 = Vector2(i * 4.1, -i * 2.7)
		expect(OceanSurface.horizontal_displacement(p, 0.7, flat).is_zero_approx(), "no horizontal motion at steepness 0")
	var single: Array[OceanSurface.Wave] = [w0]
	expect_near(OceanSurface.wave_height(Vector2(5, 3), 0.7, single),
		w0.amp * sin(w0.k * w0.dir.dot(Vector2(5, 3)) - w0.omega * 0.7))


func test_crest_narrower_than_trough_with_steepness() -> void:
	# Along the wave's direction, the actual surface x of the crest-phase points
	# bunch together (crest narrow) and trough-phase points spread (flat trough).
	var waves: Array[OceanSurface.Wave] = OceanSurface.generate_waves(0.0, 1, 1.0, 20.0, 20.0, 1.0, 0.0)
	var w: OceanSurface.Wave = waves[0]
	var crest_span: float = _span(waves, w, 0.0, 1.0)
	var trough_span: float = _span(waves, w, PI, 1.0)
	expect(crest_span < trough_span, "crest %.2f should be narrower than trough %.2f" % [crest_span, trough_span])


## Actual horizontal spacing of two rest points either side of phase `centre`.
func _span(waves: Array[OceanSurface.Wave], w: OceanSurface.Wave, centre: float, half_phase: float) -> float:
	# th = k x (t = 0), crest at th = PI/2 so shift the phase centre accordingly.
	var c: float = centre + PI * 0.5
	var x0: float = (c - half_phase) / w.k
	var x1: float = (c + half_phase) / w.k
	var a: float = x0 + OceanSurface.horizontal_displacement(Vector2(x0, 0.0), 0.0, waves).x
	var b: float = x1 + OceanSurface.horizontal_displacement(Vector2(x1, 0.0), 0.0, waves).x
	return b - a


func test_normal_matches_numeric_gradient_without_displacement() -> void:
	# At steepness 0 the analytic normal is the plain height-field normal.
	var waves: Array[OceanSurface.Wave] = _default_waves(0.0)
	var e: float = 0.01
	for i: int in range(20):
		var p: Vector2 = Vector2(i * 3.7, i * 1.3)
		var hx: float = (OceanSurface.wave_height(p + Vector2(e, 0), 1.0, waves) - OceanSurface.wave_height(p - Vector2(e, 0), 1.0, waves)) / (2.0 * e)
		var hz: float = (OceanSurface.wave_height(p + Vector2(0, e), 1.0, waves) - OceanSurface.wave_height(p - Vector2(0, e), 1.0, waves)) / (2.0 * e)
		var expected: Vector3 = Vector3(-hx, 1.0, -hz).normalized()
		expect((OceanSurface.wave_normal(p, 1.0, waves) - expected).length() < 0.001, "normal at %s" % p)


func test_default_subdivision_resolves_smallest_wavelength() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var cells: float = OceanSurface.cells_per_wavelength(surface.size, surface.subdivisions, surface.min_wavelength)
	expect(cells >= OceanSurface.MIN_CELLS_PER_WAVELENGTH, "only %.2f cells per smallest wavelength" % cells)
	surface.free()


func test_material_receives_wave_table() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var m: ShaderMaterial = _material_of(surface)
	expect_eq(int(m.get_shader_parameter(&"wave_count")), surface.wave_count)
	var a: PackedVector4Array = m.get_shader_parameter(&"wave_a")
	expect_eq(a.size(), OceanSurface.MAX_WAVES)
	expect_near(a[0].z, TAU / surface.max_wavelength)
	# make_material works with no arguments.
	var d: ShaderMaterial = OceanSurface.make_material()
	expect(d.shader != null, "default material has the shader")
	expect_eq(int(d.get_shader_parameter(&"wave_count")), 5)
	surface.free()


func test_wave_parameters_exported() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var props: Array[String] = []
	for p: Dictionary in surface.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_EDITOR != 0:
			props.append(String(p["name"]))
	for name: String in ["wind_direction_deg", "wave_count", "steepness", "min_wavelength", "max_wavelength"]:
		expect(props.has(name), "%s exported" % name)
	surface.free()


func test_surface_node_tracks_sub() -> void:
	var game: Game = GAME_SCENE.instantiate() as Game
	(game.get_node("SubController") as SubController).enabled = false
	runner.add_child(game)
	game.start_session()
	var surface: OceanSurface = game.get_node("World/OceanSurface") as OceanSurface
	expect(surface != null, "surface node exists")
	game.sub_frame.set_pose(Transform3D(Basis(), Vector3(300, -40, -500)), Vector3.ZERO)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	expect(absf(surface.position.x - 300.0) <= surface.size / 40.0, "follows x")
	expect(absf(surface.position.z + 500.0) <= surface.size / 40.0, "follows z")
	expect_near(surface.position.y, 0.0)
	game.end_session()
	game.free()


func _material_of(surface: OceanSurface) -> ShaderMaterial:
	runner.add_child(surface)
	var m: ShaderMaterial = surface.material_override as ShaderMaterial
	return m


func test_surface_is_translucent_and_transmits() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var m: ShaderMaterial = _material_of(surface)
	expect(m != null, "material exists")
	expect(float(m.get_shader_parameter(&"alpha")) < 1.0, "alpha < 1")
	expect(float(m.get_shader_parameter(&"alpha")) > 0.0, "alpha > 0")
	expect(float(m.get_shader_parameter(&"transmission")) > 0.0, "transmission > 0")
	var props: Array[String] = []
	for p: Dictionary in surface.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_EDITOR != 0:
			props.append(String(p["name"]))
	for name: String in ["alpha", "tint", "transmission"]:
		expect(props.has(name), "%s exported" % name)
	surface.alpha = 0.5
	surface.tint = Color.RED
	surface.apply_settings(m)
	expect_near(float(m.get_shader_parameter(&"alpha")), 0.5)
	expect(m.get_shader_parameter(&"tint") == Color.RED, "tint reaches the material")
	surface.free()


func test_ripple_parameters_exported_and_nonzero() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var m: ShaderMaterial = _material_of(surface)
	expect(float(m.get_shader_parameter(&"ripple_strength")) > 0.0, "ripple strength non-zero")
	expect(float(m.get_shader_parameter(&"ripple_scale")) > 0.0, "ripple scale positive")
	var props: Array[String] = []
	for p: Dictionary in surface.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_EDITOR != 0:
			props.append(String(p["name"]))
	expect(props.has("ripple_scale"), "ripple_scale exported")
	expect(props.has("ripple_strength"), "ripple_strength exported")
	surface.free()


func test_no_surface_inside_hull_at_waterline() -> void:
	var surface: OceanSurface = OceanSurface.new()
	var m: ShaderMaterial = _material_of(surface)
	# The camera sits in the cabin at the waterline; the surface point there is clipped.
	var cam: Vector3 = Vector3(0.0, 0.0, 1.0)
	var centre: Vector3 = m.get_shader_parameter(&"hull_center")
	var half: Vector3 = m.get_shader_parameter(&"hull_half_extents")
	var basis: Basis = m.get_shader_parameter(&"hull_basis")
	expect(OceanSurface.inside_hull(cam, centre, half, basis), "waterline point inside the hull is not drawn")
	expect(OceanSurface.inside_hull(Vector3(1.9, 0.5, -4.9), centre, half, basis), "near corner still inside")
	expect(not OceanSurface.inside_hull(Vector3(8.0, 0.0, 0.0), centre, half, basis), "outside the hull is drawn")
	expect(not OceanSurface.inside_hull(Vector3(0.0, 0.0, 6.0), centre, half, basis), "beyond the bow is drawn")
	# A rotated hull moves the clip with it.
	var rot: Basis = Basis(Vector3.UP, PI * 0.5)
	expect(OceanSurface.inside_hull(Vector3(4.0, 0.0, 0.0), centre, half, rot), "rotated hull covers +x")
	expect(not OceanSurface.inside_hull(Vector3(0.0, 0.0, 4.0), centre, half, rot), "rotated hull frees +z")
	surface.free()
