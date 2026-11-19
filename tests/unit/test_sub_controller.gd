extends TestCase
## Integration tests for the host SubController in a real Game scene, offline.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var controller: SubController
var strikes: Array[float] = []


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	controller = game.get_node("SubController") as SubController
	runner.add_child(game)
	game.start_session()
	strikes.clear()
	controller.hull_strike.connect(func(speed: float) -> void: strikes.append(speed))


func after_each() -> void:
	game.end_session()
	game.free()


func _physics_frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_sinking_sub_strikes_and_rests_on_shelf() -> void:
	# Over the middle of shelf 1, clear of its boulders' worst.
	controller.model.position = Vector3(-42, CanyonSite.SHELF1_TOP + 10.0, -100)
	controller.model.tank_water_t = controller.model.tank_capacity_t
	await _physics_frames(60 * 20)
	expect(strikes.size() > 0, "expected a hull strike on the shelf")
	# The hull bottom is 0.4 m below the origin.
	var site: CanyonSite = game.get_node("World/Site") as CanyonSite
	var ground: float = site.height_at(-42, -100)
	# The hull's lowest point is 1 m below the sub's origin.
	expect(controller.model.position.y > ground - 0.5, "sub sank through the shelf to %f (ground %f)" % [controller.model.position.y, ground])
	expect(absf(controller.model.velocity.y) < 0.1, "sub should come to rest, vy=%f" % controller.model.velocity.y)


func test_throttle_drives_engine() -> void:
	var throttle: SpringAxis = game.get_node("Interior/Stations/Pilot/Throttle") as SpringAxis
	throttle.host_set_value(1.0)
	await _physics_frames(60 * 3)
	expect(controller.engine_output > 0.4, "engine output %f" % controller.engine_output)
	expect(controller.speed > 0.0, "sub should be moving ahead")


func test_readouts_track_model() -> void:
	controller.model.position = Vector3(0, -22.5, 0)
	controller.model.tank_water_t = controller.model.tank_capacity_t * 0.5
	await _physics_frames(2)
	expect_near(controller.depth, 22.5, 0.5)
