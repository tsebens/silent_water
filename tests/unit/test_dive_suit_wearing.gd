extends TestCase
## Wearing a dive suit: walking speed, bad-air protection and replication.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")

var _made: Array[Node] = []


func after_each() -> void:
	for n: Node in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


func _suit(client: bool = false) -> DiveSuit:
	var s: DiveSuit = DiveSuit.new()
	s.simulate_client = client
	runner.add_child(s)
	s.set_physics_process(false)
	_made.append(s)
	return s


func _player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = "1"
	runner.add_child(p)
	_made.append(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.get_node("Impairment").set_physics_process(false)
	return p


func _speed_after(p: Player) -> float:
	p.velocity = Vector3.ZERO
	p.position = Vector3(0, 0.5, 0)
	p.bot_move = Vector2(0, -1)
	for i: int in 20:
		p._simulate(1.0 / 60.0)
	return Vector2(p.velocity.x, p.velocity.z).length()


func test_walk_speed_combines_with_impairment() -> void:
	var imp: ImpairmentModel = ImpairmentModel.new(ImpairmentParams.new())
	imp.strength = 0.8
	var suit: DiveSuitModel = DiveSuitModel.new()
	suit.set_worn(true)
	var both: float = Player.walk_speed(2.6, imp, suit)
	expect_near(both, Player.impaired_speed(2.6, imp) * suit.params.speed_multiplier_worn)
	expect_near(Player.walk_speed(2.6, null, suit), 2.6 * suit.params.speed_multiplier_worn)
	expect_near(Player.walk_speed(2.6, imp, null), Player.impaired_speed(2.6, imp))
	suit.set_worn(false)
	expect_near(Player.walk_speed(2.6, imp, suit), Player.impaired_speed(2.6, imp), 0.0001, "off: no effect")


func test_player_slower_while_suited_and_restored() -> void:
	var p: Player = _player()
	var suit: DiveSuit = _suit()
	var free: float = _speed_after(p)
	p.put_on(suit)
	suit.model.set_worn(true)
	var slow: float = _speed_after(p)
	expect_near(slow / free, suit.model.params.speed_multiplier_worn, 0.03, "slowed by the multiplier")
	p.take_off()
	suit.model.set_worn(false)
	expect_near(_speed_after(p), free, 0.03, "restored on take-off")


func test_suit_stays_on_when_walking_away() -> void:
	var p: Player = _player()
	var suit: DiveSuit = _suit()
	suit.position = Vector3(0, 0, 50)
	p.put_on(suit)
	_speed_after(p)
	expect(p.worn_suit() == suit, "no cord")


func test_empty_suit_stops_protecting() -> void:
	var suit: DiveSuit = _suit()
	suit.model.set_worn(true)
	expect_near(suit.model.filter_ambient(30000.0, 0.5)[0], suit.model.params.protected_co2_ppm)
	suit.model.air = 0.0
	expect_near(suit.model.filter_ambient(30000.0, 0.5)[0], 30000.0)


func test_air_drains_on_host_while_worn() -> void:
	var suit: DiveSuit = _suit()
	suit.state.holder = 1
	suit.set_physics_process(true)
	var before: float = suit.model.air
	suit._physics_process(10.0)
	expect_near(suit.model.air, before - 10.0 * suit.model.params.drain_rate)
	suit.state.holder = InteractableState.NO_HOLDER
	var mid: float = suit.model.air
	suit._physics_process(10.0)
	expect_near(suit.model.air, mid, 0.0001, "holds when off")


func test_worn_state_and_air_replicate_to_second_peer() -> void:
	var host: DiveSuit = _suit()
	var client: DiveSuit = _suit(true)
	host.state.holder = 7
	host.model.set_worn(true)
	host.model.air = 123.0
	client.apply_snapshot(host.snapshot())
	expect(client.is_worn(), "worn on the client")
	expect_near(client.model.air, 123.0)
	# Holder replication drives the worn flag between snapshots.
	client._on_holder(InteractableState.NO_HOLDER)
	expect(not client.is_worn(), "taken off")
	# A client never simulates.
	client.set_physics_process(true)
	client.model.set_worn(true)
	client._physics_process(10.0)
	expect_near(client.model.air, 123.0)


func test_impaired_wearer_breathes_suit_air() -> void:
	var p: Player = _player()
	var suit: DiveSuit = _suit()
	var imp: PlayerImpairment = p.get_node("Impairment") as PlayerImpairment
	suit.state.holder = 1
	suit.model.set_worn(true)
	expect_near(imp.ambient_for_wearer(30000.0, 0.5)[0], suit.model.params.protected_co2_ppm)
	suit.state.holder = 2
	expect_near(imp.ambient_for_wearer(30000.0, 0.5)[0], 30000.0, 0.0001, "someone else's suit")
