extends TestCase
## SubController taking its engine limit and noise from the PowerSystem.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const C := PowerSystem.Circuit

var game: Game
var controller: SubController
var power: PowerSystem


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	controller = game.get_node("SubController") as SubController
	power = game.get_node("Interior/PowerSystem") as PowerSystem
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _full_ahead() -> void:
	(game.get_node("Interior/Stations/Pilot/Throttle") as SpringAxis).host_set_value(1.0)


func test_battery_caps_engine() -> void:
	power.stop_generator()
	_full_ahead()
	await _frames(60 * 6)
	expect(controller.engine_output <= 0.55, "capped on battery (%f)" % controller.engine_output)
	expect(controller.engine_output > 0.5, "reaches the cap (%f)" % controller.engine_output)


func test_generator_gives_full_engine() -> void:
	power.dev_generator_running = true
	power._gen_running = true
	_full_ahead()
	await _frames(60 * 4)
	expect(controller.engine_output > 0.9, "full on generator (%f)" % controller.engine_output)


func test_motor_out_gives_zero() -> void:
	power.set_breaker(C.MOTOR, false)
	_full_ahead()
	await _frames(60 * 3)
	expect_eq(controller.engine_output, 0.0, "MOTOR out")


func test_empty_battery_gives_zero() -> void:
	power.charge = 0.0
	power.step(0.1)
	_full_ahead()
	await _frames(60 * 3)
	expect_eq(controller.engine_output, 0.0, "battery empty")


func test_noise_breakdown_has_motor_and_generator() -> void:
	power._gen_running = true
	_full_ahead()
	await _frames(60 * 4)
	var parts: Dictionary = controller.noise_breakdown()
	expect(float(parts.get("motor", 0.0)) > 0.0, "motor term")
	expect_near(float(parts.get("generator", 0.0)), 0.03, 0.0001, "generator term")
	expect(not parts.has("engine"), "no separate engine term")


func test_motor_noise_is_quieter_than_old_engine() -> void:
	expect_near(SubController.ENGINE_FULL_INTENSITY, 0.002, 0.0001)
	expect_near(power.config.motor_noise_full, 0.002, 0.0001)


func test_thrusters_out_stop_noise_and_turning() -> void:
	var rudder: SpringAxis = game.get_node("Interior/Stations/Pilot/Rudder") as SpringAxis
	rudder.host_set_value(1.0)
	await _frames(5)
	expect(controller.thruster_intensity() > 0.0, "thrusters loud when powered")
	var yaw_on: float = absf(controller.model.angular_velocity.y)
	expect(yaw_on > 0.0, "turns in place when powered")
	power.set_breaker(C.THRUSTERS, false)
	controller.model.angular_velocity = Vector3.ZERO
	await _frames(30)
	expect_eq(controller.thruster_intensity(), 0.0, "thruster noise stops")
	expect_near(controller.model.angular_velocity.y, 0.0, 0.0001, "no turning in place")
