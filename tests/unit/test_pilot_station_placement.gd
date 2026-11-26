extends TestCase
## The generated pilot station placed in the sub (#483): one of each part, the old gauge pods gone, the speed gauge
## scaled to the model, the bilge lamp and the switches live, and the seated eye 1.15 m above the floor.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var ctl: SubController


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	ctl = game.get_node("SubController") as SubController
	ctl.enabled = false
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _count(root: Node, type_name: StringName) -> int:
	var n: int = 1 if root.is_class(type_name) or (root.get_script() != null and (root.get_script() as Script).get_global_name() == type_name) else 0
	for c: Node in root.get_children():
		n += _count(c, type_name)
	return n


func _pilot() -> Node3D:
	return game.get_node("Interior/Stations/Pilot") as Node3D


func test_one_of_each_and_no_old_pods() -> void:
	var interior: Node = game.get_node("Interior")
	expect_eq(_count(interior, &"PilotSeat"), 1, "one pilot seat")
	expect_eq(_count(interior, &"DepthFinder"), 1, "one depth finder")
	expect_eq(_count(interior, &"MultiDisplay"), 1, "one multidisplay")
	expect_eq(_count(interior, &"Navball"), 1, "one navball")
	expect_eq(_count(_pilot().get_node("Anchors"), &"IndicatorLamp"), 3, "three warning lamps")
	expect_eq(_count(interior.get_node("Stations/Maps/PilotHolo").get_parent(), &"HoloMap"), 2, "pilot and table holograms")
	for gone: String in ["LeftPod", "RightPod", "CenterPod"]:
		expect(_pilot().get_node_or_null(gone) == null, "%s is gone" % gone)
	for path: String in ["Seat", "Throttle", "Rudder", "Planes", "Dimmer", "Strip"]:
		expect(_pilot().get_node_or_null(path) != null, "%s resolves" % path)
	expect_eq(_count(_pilot(), &"Gauge"), 2, "two dials: the speed gauge and the noise repeater")


func test_speed_gauge_scale_is_the_models_top_speed() -> void:
	var g: Gauge = _pilot().get_node("Anchors/SpeedGauge") as Gauge
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var top: float = ctl.model.top_forward_speed()
	expect_near(g.max_value, top, 0.001, "max is top speed")
	expect_near(g.min_value, -top, 0.001, "min is minus top speed")


func test_bilge_lamp_lights_over_threshold() -> void:
	var lamp: IndicatorLamp = _pilot().get_node("Anchors/BilgeLamp") as IndicatorLamp
	var drv: ThresholdLamp = _pilot().get_node("Drivers/BilgeLampDriver") as ThresholdLamp
	ctl.model.bilge_water_t = 0.0
	ctl.bilge_water_t = 0.0
	drv.update()
	expect(not lamp.lit, "dry: unlit")
	var wet: float = 0.25 * ctl.model.max_surfaceable_bilge_t() + 0.5
	ctl.bilge_water_t = wet
	drv.update()
	expect(lamp.lit, "over a quarter of the limit: lit")


func test_switches_change_the_lights() -> void:
	var head: Light3D = game.get_node("Interior/Lights/Headlight") as Light3D
	var ext: Interactable = _pilot().get_node("Anchors/ExternalLightSwitch") as Interactable
	var ext_col: Interactable = _pilot().get_node("Anchors/ExternalColourSwitch") as Interactable
	var cab: Interactable = _pilot().get_node("Anchors/CabinLightSwitch") as Interactable
	var cab_col: Interactable = _pilot().get_node("Anchors/CabinColourSwitch") as Interactable
	var hs: HeadlightSwitch = _pilot().get_node("HeadlightSwitch") as HeadlightSwitch
	var cs: CabinSwitch = game.get_node("CabinSwitch") as CabinSwitch
	var lights: CabinLights = game.get_node("CabinLights") as CabinLights
	hs.update()
	cs.update()
	expect(head.visible, "headlight starts on")
	expect(lights.enabled, "cabin lights start on")
	ext.host_set_value(0.0)
	hs.update()
	expect(not head.visible, "external switch off: headlight off")
	ext.host_set_value(1.0)
	ext_col.host_set_value(1.0)
	hs.update()
	expect(head.visible, "back on")
	var pl: PaletteLight = head.get_node("PaletteLight") as PaletteLight
	expect(pl.stealth, "colour switch up: the headlight goes red")
	cab.host_set_value(0.0)
	cs.update()
	expect(not lights.enabled, "cabin switch off: cabin lights off")
	cab.host_set_value(1.0)
	cab_col.host_set_value(1.0)
	cs.update()
	expect(lights.enabled and lights.stealth, "cabin on and red")


func test_seated_eye_is_1_15_m_above_the_floor_on_the_centreline() -> void:
	var seat: PilotSeat = _pilot().get_node("Seat") as PilotSeat
	var sit: Vector3 = seat.sit_point.global_position
	var origin: Vector3 = SubLayout.position(&"pilot")
	expect_near(sit.x, 0.0, 0.001, "sit point on the centreline")
	expect(sit.is_equal_approx(origin), "sit point at the program's pilot position, got %s" % sit)
	expect_near(seat.eye_height, 1.15, 0.0001, "eye height 1.15 m")
	expect_near(sit.y + seat.eye_height - origin.y, 1.15, 0.0001, "eye is 1.15 m above the floor")


func test_hologram_sits_at_the_anchor() -> void:
	var holo: Node3D = game.get_node("Interior/Stations/Maps/PilotHolo") as Node3D
	var anchor: Node3D = _pilot().get_node("Anchors/HologramAnchor") as Node3D
	expect(holo.global_position.is_equal_approx(anchor.global_position), "holo at %s, anchor at %s" % [holo.global_position, anchor.global_position])
