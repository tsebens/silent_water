extends TestCase
## A seated pilot can flip the four light switches and grab nothing else new (#608).

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


func _seat() -> PilotSeat:
	return game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat


func _switch(name: String) -> Interactable:
	return game.get_node("Interior/Stations/Pilot/Anchors/" + name) as Interactable


func test_seated_pilot_flips_a_light_switch() -> void:
	var me: Player = game.local_player()
	var sw: Interactable = _switch("CabinLightSwitch")
	var before: float = sw.get_value()
	me.sit_in(_seat())
	me.press_interact(sw)
	me.release_interact()
	expect(not is_equal_approx(sw.get_value(), before), "seated click flipped the switch")
	me.stand_up()


func test_seat_lists_exactly_four_switches() -> void:
	expect_eq(_seat().switches.size(), 4, "four switches")
	for n: String in ["ExternalLightSwitch", "ExternalColourSwitch", "CabinLightSwitch", "CabinColourSwitch"]:
		expect(_seat().allow_grab(_switch(n)), n + " allowed")


func test_seated_pilot_cannot_grab_other_controls() -> void:
	var me: Player = game.local_player()
	var seat: PilotSeat = _seat()
	me.sit_in(seat)
	var other: Interactable = game.get_node("Interior/Stations/Pilot/Dimmer") as Interactable
	expect(not seat.allow_grab(other), "dimmer not allowed")
	var before: float = other.get_value()
	me.press_interact(other)
	me.release_interact()
	expect_eq(other.get_value(), before, "dimmer untouched")
	expect(me.held_control() == null, "nothing held")
	me.stand_up()


func test_standing_player_still_flips_switches() -> void:
	var me: Player = game.local_player()
	var sw: Interactable = _switch("ExternalLightSwitch")
	var before: float = sw.get_value()
	me.press_interact(sw)
	me.release_interact()
	expect(not is_equal_approx(sw.get_value(), before), "standing click flipped it")


func test_hint_mentions_switches() -> void:
	expect(PilotSeat.helm_hint().contains("switch"), "seated hint lists switches")
