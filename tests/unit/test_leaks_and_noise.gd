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
	controller.model.position = Vector3(0, -15, 0)


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
	await _frames(10)
	expect(leaks.open_index != -1, "the leak recurs")


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
	var telegraph: Telegraph = game.get_node("Interior/Stations/Engineering/Telegraph") as Telegraph
	telegraph.host_set_value(3.0)
	await _frames(60 * 7)
	expect_near(Acoustics.sub_db(), 80.0, 1.0)
	expect(not Acoustics.is_masked(), "full ahead is not masked")


func test_quiet_sub_is_masked() -> void:
	await _frames(10)
	expect(Acoustics.is_masked(), "a still sub (%f dB) should hide under the ocean (%f dB)" % [Acoustics.sub_db(), Acoustics.ambient_db()])
