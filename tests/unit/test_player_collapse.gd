extends TestCase
## Collapse: input is ignored while incapacitated, held items and seats are let go, and
## standing up restores control.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


var _made: Array[Node] = []


func after_each() -> void:
	for n: Node in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


func _player(id: String = "1") -> Player:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = id
	runner.add_child(p)
	_made.append(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.get_node("Impairment").set_physics_process(false)
	return p


func _down(p: Player, down: bool) -> void:
	(p.get_node("Impairment") as PlayerImpairment).apply_snapshot({"impairment": 1.0 if down else 0.0, "incapacitated": down})


func test_not_down_by_default() -> void:
	var p: Player = _player()
	expect(not p.is_down())
	expect_near(p.down_blend, 0.0)


func test_input_ignored_while_down() -> void:
	var p: Player = _player()
	_down(p, true)
	p._update_collapse(0.1)
	p.bot_move = Vector2(0, -1)
	var start: Vector3 = p.position
	for i: int in 10:
		p._simulate(1.0 / 60.0)
	expect_near(Vector2(p.velocity.x, p.velocity.z).length(), 0.0, 0.001)
	expect_near(Vector2(p.position.x - start.x, p.position.z - start.z).length(), 0.0, 0.001)
	_down(p, false)
	p._update_collapse(0.1)
	for i: int in 30:
		p._simulate(1.0 / 60.0)
	expect(Vector2(p.velocity.x, p.velocity.z).length() > 0.5, "walking works again after recovery")


func test_held_item_released_on_collapse() -> void:
	var p: Player = _player()
	var item: Interactable = Interactable.new()
	runner.add_child(item)
	_made.append(item)
	p.press_interact(item)
	expect(p.held_control() == item)
	_down(p, true)
	p._update_collapse(0.1)
	expect(p.held_control() == null, "held control released")


func test_headset_taken_off_on_collapse() -> void:
	var p: Player = _player()
	var w: Wearable = Wearable.new()
	runner.add_child(w)
	_made.append(w)
	p.put_on(w)
	expect(p.worn() == w)
	_down(p, true)
	p._update_collapse(0.1)
	expect(p.worn() == null, "worn item removed")


func test_seat_vacated_on_collapse() -> void:
	var p: Player = _player()
	var seat: StationSeat = StationSeat.new()
	runner.add_child(seat)
	_made.append(seat)
	p.sit_in(seat)
	expect(p.is_seated())
	_down(p, true)
	p._update_collapse(0.1)
	expect(not p.is_seated(), "seat released")


func test_down_pose_and_stand_up_take_time() -> void:
	var p: Player = _player()
	_down(p, true)
	p._update_collapse(Player.FALL_S * 0.5)
	expect(p.down_blend > 0.3 and p.down_blend < 0.7, "falling")
	p._update_collapse(Player.FALL_S)
	expect_near(p.down_blend, 1.0)
	_down(p, false)
	p._update_collapse(Player.STAND_UP_S * 0.5)
	expect(p.down_blend > 0.3 and p.down_blend < 0.7, "standing up, not instant")
	p._update_collapse(Player.STAND_UP_S)
	expect_near(p.down_blend, 0.0)


func test_look_is_limited_while_down() -> void:
	var p: Player = _player()
	_down(p, true)
	p._update_collapse(0.1)
	var yaw: float = p.rotation.y
	p._look(Vector2(-100000.0, 100000.0))
	expect(absf(angle_difference(yaw, p.rotation.y)) <= Player.DOWN_LOOK_YAW + 0.001, "yaw limited")
	expect(absf(p._head.rotation.x) <= Player.DOWN_LOOK_PITCH + 0.001, "pitch limited")


func test_linger_blur_after_recovery() -> void:
	var p: Player = _player()
	var imp: PlayerImpairment = p.get_node("Impairment") as PlayerImpairment
	_down(p, true)
	expect_near(imp.linger_blur, 0.0)
	_down(p, false)
	expect(imp.linger_blur > 0.9, "blur starts high")
	imp.tick_linger(imp.params.linger_blur_seconds * 0.5)
	expect(imp.linger_blur > 0.3 and imp.linger_blur < 0.7, "fading")
	imp.tick_linger(imp.params.linger_blur_seconds)
	expect_near(imp.linger_blur, 0.0)
