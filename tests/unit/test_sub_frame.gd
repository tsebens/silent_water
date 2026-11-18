extends TestCase
## Integration tests for the sub-frame: a real Game scene, offline, one player.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _physics_frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_world_root_is_inverse_of_sub_pose() -> void:
	var pose: Transform3D = Transform3D(Basis.from_euler(Vector3(0.2, 0.5, -0.1)), Vector3(10, -20, 30))
	game.sub_frame.set_pose(pose)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var world: Node3D = game.get_node("World") as Node3D
	var combined: Transform3D = world.transform * pose
	expect(combined.is_equal_approx(Transform3D.IDENTITY), "world * pose should be identity, got %s" % combined)


func test_gravity_tilts_with_pitch() -> void:
	game.sub_frame.set_pose(Transform3D(Basis.from_euler(Vector3(deg_to_rad(20), 0, 0)), Vector3.ZERO))
	await runner.get_tree().process_frame
	var g: Vector3 = game.sub_frame.gravity_in_sub()
	expect_near(g.length(), SubFrame.GRAVITY, 0.001)
	# Nose up (positive pitch about X) => gravity pulls toward the stern (+Z).
	expect(g.z > 3.0, "gravity z %f should point aft" % g.z)


func test_player_does_not_slide_on_tilted_deck() -> void:
	await _physics_frames(30)  # settle onto the deck
	var me: Player = game.local_player()
	expect(me != null, "local player spawned")
	if me == null:
		return
	game.sub_frame.set_pose(Transform3D(Basis.from_euler(Vector3(deg_to_rad(12), 0, deg_to_rad(6))), Vector3.ZERO))
	await _physics_frames(10)
	var start: Vector3 = me.position
	await _physics_frames(180)
	var moved: float = (me.position - start).length()
	expect(moved < 0.05, "standing player slid %f m" % moved)
	expect(me.is_on_floor(), "player stays on the deck")


func test_player_moves_with_input_in_sub_frame() -> void:
	await _physics_frames(30)
	var me: Player = game.local_player()
	if me == null:
		expect(false, "no player")
		return
	# Moving the sub must not move the player inside it.
	game.sub_frame.set_pose(Transform3D(Basis(), Vector3(0, 0, -500)), Vector3(0, 0, -5))
	var start: Vector3 = me.position
	await _physics_frames(30)
	expect((me.position - start).length() < 0.02, "sub motion moved the player")
	me.bot_move = Vector2(0, -1)
	await _physics_frames(60)
	me.bot_move = Vector2.ZERO
	expect(start.z - me.position.z > 1.5, "walked forward %f m" % (start.z - me.position.z))


func test_player_slides_on_steep_deck() -> void:
	await _physics_frames(30)
	var me: Player = game.local_player()
	if me == null:
		expect(false, "no player")
		return
	game.sub_frame.set_pose(Transform3D(Basis.from_euler(Vector3(deg_to_rad(40), 0, 0)), Vector3.ZERO))
	var start: Vector3 = me.position
	await _physics_frames(60)
	expect(me.position.z - start.z > 0.3, "player should slide aft on a 40° deck")
