extends TestCase
## Lights, headlight, electric bilge pump and emergency lights follow their breakers.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const C := PowerSystem.Circuit

var game: Game
var power: PowerSystem
var leaks: LeakSystem
var lights: CabinLights
var controller: SubController


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	power = game.get_node("Interior/PowerSystem") as PowerSystem
	leaks = game.get_node("LeakSystem") as LeakSystem
	lights = game.get_node("CabinLights") as CabinLights
	controller = game.get_node("SubController") as SubController
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _pump_lever() -> Lever:
	return game.get_node("Interior/Stations/Bilge/Pump") as Lever


func test_cabin_breaker_darkens_cabin_lights() -> void:
	lights.enabled = true
	lights.dimmer = null
	await _frames(2)
	var l: Light3D = lights.cabin_lights()[0]
	expect(l.light_energy > 0.0, "lit when powered")
	power.set_breaker(C.CABIN_LTS, false)
	await _frames(2)
	expect_near(l.light_energy, 0.0, 0.0001)


func test_ext_breaker_turns_headlight_off() -> void:
	var sw: HeadlightSwitch = game.get_node("Interior/Stations/Pilot/HeadlightSwitch") as HeadlightSwitch
	var hl: Light3D = sw.light
	hl.visible = true
	sw.power = null
	sw.update()
	expect(hl.visible, "on when powered")
	power.set_breaker(C.EXT_LTS, false)
	sw.power = game.get_node("Interior/Stations/Pilot/Anchors/HeadlightSwitch") as Interactable if game.has_node("Interior/Stations/Pilot/Anchors/HeadlightSwitch") else null
	expect(not sw._powered(), "unpowered with EXT LTS out")


func test_pump_breaker_stops_flow_and_noise() -> void:
	_pump_lever().host_set_value(1.0)
	expect(leaks.pump_on(), "pump runs")
	expect_near(leaks.current_pump_flow(), leaks.pump_flow, 0.0001)
	power.set_breaker(C.BILGE_PUMP, false)
	expect(not leaks.pump_on(), "pump off")
	expect_near(leaks.current_pump_flow(), 0.0, 0.0001)
	expect_near(leaks.noise_breakdown()["bilge pump"] as float, 0.0, 0.0000001)


func test_manual_pump_still_bails_when_unpowered() -> void:
	power.set_breaker(C.BILGE_PUMP, false)
	controller.model.bilge_water_t = 2.0
	leaks.manual_bail(0.5)
	expect(controller.model.bilge_water_t < 2.0, "manual bail works (%f)" % controller.model.bilge_water_t)


func test_emergency_lights_at_blackout_and_cabin_out() -> void:
	var em: Node3D = game.get_node("Interior/EmergencyLights") as Node3D
	await _frames(2)
	expect(not em.visible, "off normally")
	power.set_breaker(C.CABIN_LTS, false)
	await _frames(2)
	expect(em.visible, "on with CABIN LTS out")
	power.set_breaker(C.CABIN_LTS, true)
	power.charge = 0.0
	power._refresh_power()
	await _frames(2)
	expect(power.is_blackout(), "blackout")
	expect(em.visible, "on at blackout")
