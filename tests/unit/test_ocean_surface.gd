extends TestCase
## Ocean surface: wave function, snow clipping, and the node in the world scene.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func test_snow_density_zero_at_and_above_surface() -> void:
	expect_near(OceanSurface.snow_density(0.0), 0.0)
	expect_near(OceanSurface.snow_density(-5.0), 0.0)
	expect_near(OceanSurface.snow_density(10.0), 1.0)
	expect_near(OceanSurface.snow_density(10.0, 0.4), 0.4)


func test_wave_height_deterministic_bounded_and_varying() -> void:
	var amp: float = 0.6
	var first: float = OceanSurface.wave_height(Vector2(3, 4), 2.0, amp, 14.0, 0.5)
	expect_near(first, OceanSurface.wave_height(Vector2(3, 4), 2.0, amp, 14.0, 0.5))
	var distinct: Dictionary = {}
	for i: int in range(200):
		var h: float = OceanSurface.wave_height(Vector2(i * 1.7, i * 0.9), i * 0.3, amp, 14.0, 0.5)
		expect(absf(h) <= amp + 0.0001, "wave exceeds amplitude")
		distinct[snappedf(h, 0.001)] = true
	expect(distinct.size() > 20, "wave should vary")
	expect(not is_equal_approx(first, OceanSurface.wave_height(Vector2(9, 4), 2.0, amp, 14.0, 0.5)), "varies with position")
	expect(not is_equal_approx(first, OceanSurface.wave_height(Vector2(3, 4), 3.0, amp, 14.0, 0.5)), "varies with time")


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
