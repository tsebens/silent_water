extends TestCase
## Integration tests for the apex monster in a real Game scene, offline.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var apex: ApexMonster
var controller: SubController
var contacts: int = 0
var near_misses: int = 0


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	Acoustics.reset()
	apex = game.get_node("World/Apex") as ApexMonster
	controller = game.get_node("SubController") as SubController
	controller.model.position = Vector3(0, -80, -200)
	controller.model.tank_water_t = controller.model.tank_capacity_t * 0.5
	contacts = 0
	near_misses = 0
	apex.contact.connect(func() -> void: contacts += 1)
	apex.near_miss.connect(func(_d: float) -> void: near_misses += 1)


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _commit_toward(point: Vector3) -> void:
	apex.brain_enabled = false
	apex.brain.suspicion = 100.0
	apex.brain.has_heard = true
	apex.brain.last_heard = point
	apex.brain.state = SuspicionModel.State.COMMITTED


func test_quiet_sub_is_not_noticed() -> void:
	apex.position = Vector3(0, -80, -350)
	await _frames(60 * 10)
	expect_eq(apex.state(), SuspicionModel.State.UNAWARE as int, "state %s" % SuspicionModel.state_name(apex.state()))


func test_loud_sub_draws_the_monster() -> void:
	# Mid-canyon, open water between them.
	controller.model.position = Vector3(0, -80, -200)
	apex.position = Vector3(0, -80, -350)
	for i: int in range(60 * 8):
		Acoustics.report_voice(NoiseLevel.from_db(85.0))  # Shouting.
		await runner.get_tree().physics_frame
	expect(apex.state() >= SuspicionModel.State.HUNTING, "shouting at 150 m should provoke a hunt, got %s" % SuspicionModel.state_name(apex.state()))
	expect(apex.brain.last_heard.distance_to(controller.model.position) < 60.0, "it knows roughly where we are")


func test_charge_at_sub_makes_contact() -> void:
	apex.position = controller.model.position + Vector3(0, 0, 120)
	apex.basis = Basis.looking_at(Vector3(0, 0, -1))
	_commit_toward(controller.model.position)
	var state_at_contact: Array[int] = [-1]
	apex.contact.connect(func() -> void: state_at_contact[0] = apex.state())
	await _frames(60 * 12)
	expect_eq(contacts, 1, "the charge should reach the sub")
	expect_eq(state_at_contact[0], SuspicionModel.State.CONTACT as int)


func test_charge_at_stale_position_misses() -> void:
	apex.position = controller.model.position + Vector3(0, 0, 120)
	apex.basis = Basis.looking_at(Vector3(0, 0, -1))
	# It heard us 25 m to the side of where we really are.
	_commit_toward(controller.model.position + Vector3(25, 0, 0))
	await _frames(60 * 15)
	expect_eq(contacts, 0, "a sub that moved and went quiet can be missed")
	expect(near_misses >= 1, "but it should be a near miss")


func test_monster_stays_in_territory() -> void:
	apex.speed_unaware = 50.0
	await _frames(60 * 10)
	expect(apex.territory.grow(0.01).has_point(apex.position), "monster at %s left its territory" % apex.position)


func test_contact_loses_the_sub_then_resets_the_dive() -> void:
	var director: DiveDirector = game.get_node("DiveDirector") as DiveDirector
	var lights: Node3D = game.get_node("Interior/Lights") as Node3D
	controller.model.change_bilge(3.0)
	apex.position = controller.model.position + Vector3(0, 0, 12)
	apex.basis = Basis.looking_at(Vector3(0, 0, -1))
	_commit_toward(controller.model.position)
	await _frames(60)
	expect_eq(director.phase, DiveDirector.Phase.LOST)
	expect(not lights.visible, "lights die on contact")
	await _frames(int(60 * (DiveDirector.LOST_HOLD_SEC + 0.5)))
	expect_eq(director.phase, DiveDirector.Phase.DIVING)
	expect(lights.visible, "lights back after reset")
	expect_eq(controller.model.bilge_water_t, 0.0, "sub reset")
	expect(controller.enabled)
	expect_eq(apex.state(), SuspicionModel.State.UNAWARE as int)
	expect(apex.position.distance_to(apex.spawn_position) < 20.0, "monster back at its spawn")


func test_disabled_apex_is_gone() -> void:
	apex.set_active(false)
	expect(not apex.active)
	expect(apex.outside_db() < -1000.0, "silent")
	# Put it right on top of the sub and shout: nothing may happen.
	apex.position = controller.model.position + Vector3(0, 0, 5)
	for i: int in range(60 * 5):
		Acoustics.report_voice(NoiseLevel.from_db(90.0))
		await runner.get_tree().physics_frame
	expect_eq(contacts, 0, "no contact while disabled")
	expect_eq(apex.state(), SuspicionModel.State.UNAWARE as int, "no hearing while disabled")
	var cues: ThreatCues = game.get_node("ThreatCues") as ThreatCues
	await runner.get_tree().process_frame
	expect_eq(cues.proximity(), 0.0, "no felt cues while disabled")
	expect(not apex.visible, "hidden")


func test_reenabled_apex_starts_fresh() -> void:
	apex.set_active(false)
	apex.set_active(true)
	await _frames(2)
	expect(apex.active and apex.visible)
	expect(apex.position.distance_to(apex.spawn_position) < 5.0, "back home")
	expect_eq(apex.state(), SuspicionModel.State.UNAWARE as int)
