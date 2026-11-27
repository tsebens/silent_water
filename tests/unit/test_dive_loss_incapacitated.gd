extends TestCase
## The dive is lost only when every crew member is incapacitated.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


class StubCrew:
	extends CrewIncapacitation
	var ids: Array[int] = [1, 2, 3]
	var down: Dictionary = {}

	func crew_ids() -> Array[int]:
		return ids

	func is_incapacitated(id: int) -> bool:
		return down.has(id)


var game: Game
var director: DiveDirector
var crew: StubCrew


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	director = game.get_node("DiveDirector") as DiveDirector
	var apex: ApexMonster = game.get_node("World/Apex") as ApexMonster
	apex.brain_enabled = false
	apex.speed_unaware = 0.0
	crew = StubCrew.new()
	director.incapacitation = crew


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_no_loss_when_some_are_down() -> void:
	crew.down = {1: true, 2: true}
	await _frames(10)
	expect_eq(director.phase, DiveDirector.Phase.DIVING)


func test_loss_when_all_are_down() -> void:
	crew.down = {1: true, 2: true, 3: true}
	await _frames(10)
	expect_eq(director.phase, DiveDirector.Phase.LOST)


func test_recovery_before_the_last_falls_prevents_loss() -> void:
	crew.down = {1: true, 2: true}
	await _frames(10)
	crew.down.erase(2)
	await _frames(5)
	crew.down[3] = true
	await _frames(10)
	expect_eq(director.phase, DiveDirector.Phase.DIVING)


func test_default_interface_never_loses() -> void:
	director.incapacitation = CrewIncapacitation.new()
	await _frames(10)
	expect_eq(director.phase, DiveDirector.Phase.DIVING)
