extends TestCase
## Jumping in the sub frame: raises the player, lands them, and thuds.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	(game.get_node("SubController") as SubController).enabled = false
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _physics_frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_jump_rises_and_lands_in_sub_local_space() -> void:
	await _physics_frames(30)
	var me: Player = game.local_player()
	game.sub_frame.set_pose(Transform3D(Basis(), Vector3(0, 0, -500)), Vector3(0, 0, -5))
	await _physics_frames(5)
	var floor_y: float = me.position.y
	me.bot_jump = true
	var peak: float = floor_y
	for i: int in range(90):
		await runner.get_tree().physics_frame
		peak = maxf(peak, me.position.y)
	expect(peak - floor_y > 0.1, "jump rose %f m" % (peak - floor_y))
	expect(peak - floor_y <= me.jump_height + 0.05, "hop stays low (%f m)" % (peak - floor_y))
	expect(me.is_on_floor(), "back on the floor")
	expect_near(me.position.y, floor_y, 0.03, "returned to floor height")


func test_landing_is_louder_than_a_step() -> void:
	await _physics_frames(30)
	var me: Player = game.local_player()
	expect(me.is_in_group(&"noise_sources"), "player is a noise source")
	expect_eq(me.noise_intensity(), 0.0, "standing still is silent")
	me.bot_jump = true
	var loudest: float = 0.0
	for i: int in range(90):
		await runner.get_tree().physics_frame
		loudest = maxf(loudest, me.noise_intensity())
	expect(loudest > Player.FOOTSTEP_INTENSITY, "landing %f above a walking step" % loudest)
	expect_eq(me.sync_landings, 1, "landing replicated")
