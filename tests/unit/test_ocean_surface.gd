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
