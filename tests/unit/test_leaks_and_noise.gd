extends TestCase
## Integration tests for leaks, the bilge pump and the noise sum, in a real
## Game scene, offline (this peer is the host).

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var leaks: LeakSystem
var controller: SubController


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	Acoustics.reset()
	leaks = game.get_node("LeakSystem") as LeakSystem
	controller = game.get_node("SubController") as SubController
	controller.model.position = Vector3(0, -40, -100)
	controller.model.tank_water_t = controller.model.tank_capacity_t * 0.5


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _open_leak() -> Leak:
	leaks.open_random_leak()
	return game.get_node("Interior/Leaks").get_child(leaks.open_index) as Leak


func test_open_leak_floods_bilge_and_hisses() -> void:
	var leak: Leak = _open_leak()
	expect(leak.is_open)
	expect(leak.spray.emitting, "spray on")
	await _frames(120)
	expect(controller.model.bilge_water_t > 0.03, "bilge %f" % controller.model.bilge_water_t)
	expect(Acoustics.sub_intensity >= LeakSystem.LEAK_INTENSITY * 0.99, "leak should be audible to the noise system")


func test_steady_patch_closes_leak_for_a_long_time() -> void:
	var leak: Leak = _open_leak()
	leak.begin_interaction()
	await _frames(int(60 * (Leak.PATCH_TIME + 0.3)))
	expect(not leak.is_open, "patched")
	expect_eq(leaks.open_index, -1)
	expect(leaks._timer > LeakSystem.PATCH_HOLD_SEC.y - 5.0, "steady patch holds long (%f)" % leaks._timer)
	expect_near(leak.get_value(), 0.0, 0.001, "progress reset")


func test_shaky_patch_holds_briefly() -> void:
	var leak: Leak = _open_leak()
	leak.begin_interaction()
	for i: int in range(int(60 * (Leak.PATCH_TIME + 0.3))):
		leak.drag(Vector2(15, -12))  # ~1150 px/s of shake
		await runner.get_tree().physics_frame
	expect(not leak.is_open)
	expect(leaks._timer < LeakSystem.PATCH_HOLD_SEC.x + 5.0, "shaky patch holds briefly (%f)" % leaks._timer)


func test_letting_go_early_does_not_patch() -> void:
	var leak: Leak = _open_leak()
	leak.begin_interaction()
	await _frames(30)
	leak.end_interaction()
	await _frames(120)
	expect(leak.is_open, "still leaking")
	expect_near(leak.get_value(), 0.0, 0.001)


func test_leak_reopens_after_patch_wears_off() -> void:
	var leak: Leak = _open_leak()
	leak.begin_interaction()
	await _frames(int(60 * (Leak.PATCH_TIME + 0.3)))
	leaks._timer = 0.05
	leaks.mean_interval_sec = 0.01
	await _frames(20)
	expect(leaks.open_index != -1, "the leak recurs")


func test_spontaneous_rate_matches_mean_interval() -> void:
	leaks._timer = 0.0
	leaks._rng.seed = 12345  # deterministic: no random CI flake
	var depth: float = LeakSystem.FLOOR_DEPTH
	var dt: float = 0.5
	var steps: int = 100000
	var hits: int = 0
	for i: int in range(steps):
		if leaks.spontaneous_roll(dt, depth):
			hits += 1
	var expected: float = steps * dt * leaks.spontaneous_rate(depth)
	expect(absf(hits - expected) < 5.0 * sqrt(expected), "hits %d vs expected %f" % [hits, expected])


func test_depth_factor_monotonic_and_deeper_is_likelier() -> void:
	var prev: float = -1.0
	for d: int in range(0, 400, 10):
		var f: float = LeakSystem.depth_factor(float(d))
		expect(f >= prev, "monotonic at %d m" % d)
		prev = f
	expect(LeakSystem.depth_factor(0.0) < LeakSystem.depth_factor(LeakSystem.FLOOR_DEPTH))


func test_dev_switch_stops_spontaneous_but_not_strikes() -> void:
	leaks._timer = 0.0
	leaks.mean_interval_sec = 0.01
	leaks.request_spontaneous_disabled(true)
	expect(leaks.spontaneous_disabled)
	for i: int in range(5000):
		expect(not leaks.spontaneous_roll(1.0, 200.0), "no spontaneous leak")
	leaks._on_hull_strike(LeakSystem.STRIKE_FOR_CERTAIN_LEAK)
	expect(leaks.open_index != -1, "hard strike still leaks")


func test_pump_empties_bilge_noisily() -> void:
	controller.model.bilge_water_t = 2.0
	var pump: Lever = game.get_node("Interior/Stations/Bilge/Pump") as Lever
	pump.host_set_value(1.0)
	await _frames(60)
	expect(controller.model.bilge_water_t < 1.97, "pump removes water (%f)" % controller.model.bilge_water_t)
	expect(Acoustics.sub_db() > 77.0, "pump is loud (%f dB)" % Acoustics.sub_db())


func test_bilge_water_makes_sub_heavier() -> void:
	var before: float = controller.model.buoyancy_accel()
	controller.model.change_bilge(4.0)
	expect(controller.model.buoyancy_accel() < before - 0.2)


func test_engine_noise_reaches_about_80_db_at_full() -> void:
	var throttle: SpringAxis = game.get_node("Interior/Stations/Pilot/Throttle") as SpringAxis
	throttle.host_set_value(1.0)
	await _frames(60 * 7)
	expect_near(Acoustics.sub_db(), 80.0, 1.0)
	expect(not Acoustics.is_masked(), "full ahead is not masked")


func test_quiet_sub_is_masked() -> void:
	await _frames(10)
	expect(Acoustics.is_masked(), "a still sub (%f dB) should hide under the ocean (%f dB)" % [Acoustics.sub_db(), Acoustics.ambient_db()])


func test_max_surfaceable_bilge_is_reserve_buoyancy() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	expect_near(m.max_surfaceable_bilge_t(), 10.0, 0.001, "default model")
	m.displacement_t = 160.0
	expect_near(m.max_surfaceable_bilge_t(), 160.0 - 139.64 - 0.36, 0.001, "displacement")
	m.dry_mass_t = 140.64
	expect_near(m.max_surfaceable_bilge_t(), 160.0 - 140.64 - 0.36, 0.001, "dry mass")
	m.payload_t = 1.36
	expect_near(m.max_surfaceable_bilge_t(), 160.0 - 140.64 - 1.36, 0.001, "payload")


func test_one_unattended_leak_floods_in_three_to_five_minutes() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	var t: float = 0.0
	while m.bilge_water_t < m.max_surfaceable_bilge_t() and t < 1000.0:
		m.change_bilge(leaks.leak_flow * 0.1)
		t += 0.1
	expect(t >= 180.0 and t <= 300.0, "time to unsurfaceable %f s" % t)


func test_pump_is_between_one_and_two_leaks() -> void:
	expect(leaks.leak_flow < leaks.pump_flow, "pump beats one leak")
	expect(leaks.pump_flow < 2.0 * leaks.leak_flow, "pump loses to two leaks")


func test_pump_beats_one_leak_but_not_two() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	m.bilge_water_t = 5.0
	m.change_bilge(leaks.leak_flow * 10.0)
	m.change_bilge(-leaks.pump_flow * 10.0)
	expect_near(m.bilge_water_t, 5.0 + (leaks.leak_flow - leaks.pump_flow) * 10.0, 0.0001)
	expect(m.bilge_water_t < 5.0, "one leak + pump: falling")
	var before: float = m.bilge_water_t
	m.change_bilge(2.0 * leaks.leak_flow * 10.0)
	m.change_bilge(-leaks.pump_flow * 10.0)
	expect(m.bilge_water_t > before, "two leaks + pump: rising")
