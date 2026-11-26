extends TestCase
## SwitchLever: a click throws it, a drag does nothing, and the host owns the value.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func _switch() -> SwitchLever:
	var s: SwitchLever = SwitchLever.new()
	runner.add_child(s)
	return s


func test_hint() -> void:
	var s: SwitchLever = _switch()
	expect_eq(s.interaction_hint(), "click to switch")
	s.queue_free()


func test_drag_without_release_does_not_move_it() -> void:
	var s: SwitchLever = _switch()
	s.begin_interaction()
	s.drag(Vector2(0, -200))
	expect_eq(s.get_value(), s.min_value, "drag up: still off")
	s.drag(Vector2(0, 200))
	expect_eq(s.get_value(), s.min_value, "drag down: still off")
	s.end_interaction()
	expect_eq(s.get_value(), s.min_value, "released: still off")
	s.queue_free()


func test_client_click_reaches_host_and_replicates() -> void:
	# Two instances stand for the host's and a client's copy; the wire is done by hand.
	var host: SwitchLever = _switch()
	var other: SwitchLever = _switch()
	const CLIENT: int = 7
	expect(host.state.try_grab(CLIENT), "host grants the grab")
	# The client's click drives to the opposite end; that request is what the host receives.
	var target: float = host.max_value if host.get_value() < 0.5 else host.min_value
	host._host_apply(CLIENT, target)
	expect_eq(host.get_value(), host.max_value, "host owns the flipped value")
	host.state.release(CLIENT)
	other._receive_value(host.get_value(), true)
	expect_eq(other.get_value(), other.max_value, "the other peer shows it")
	host.queue_free()
	other.queue_free()


func test_seated_player_cannot_click_when_grabbing_is_disallowed() -> void:
	var g: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(g)
	g.start_session()
	var me: Player = g.local_player()
	var seat: StationSeat = StationSeat.new()
	seat.allows_grabbing = false
	runner.add_child(seat)
	me.sit_in(seat)
	var s: SwitchLever = _switch()
	me.press_interact(s)
	me.release_interact()
	expect_eq(s.get_value(), s.min_value, "nothing happened")
	me.stand_up()
	me.press_interact(s)
	me.release_interact()
	expect_eq(s.get_value(), s.max_value, "standing, the same click flips it")
	s.queue_free()
	seat.queue_free()
	g.end_session()
	g.free()
