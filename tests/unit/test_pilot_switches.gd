extends TestCase
## Pilot strip drivers: the headlight and cabin switches, and the threshold lamp.


class FakeSource extends Node:
	var values: Dictionary = {}

	func readout(name: StringName) -> float:
		return float(values.get(name, 0.0))


func _switch(on: bool) -> Interactable:
	var s: Interactable = Interactable.new()
	runner.add_child(s)
	s.host_set_value(1.0 if on else 0.0)
	return s


func _headlight() -> SpotLight3D:
	var l: SpotLight3D = SpotLight3D.new()
	var pl: PaletteLight = PaletteLight.new()
	pl.swatch = &"light_work_white"
	l.add_child(pl)
	runner.add_child(l)
	return l


func test_headlight_power_and_swatch() -> void:
	var pal: Palette = Palette.main()
	var light: SpotLight3D = _headlight()
	var power: Interactable = _switch(true)
	var colour: Interactable = _switch(false)
	var drv: HeadlightSwitch = HeadlightSwitch.new()
	drv.light = light
	drv.power = power
	drv.colour = colour
	runner.add_child(drv)
	expect(light.visible, "on")
	expect(light.light_color.is_equal_approx(pal.color(&"light_work_white")), "halogen white")
	colour.host_set_value(1.0)
	drv.update()
	expect(light.light_color.is_equal_approx(pal.color(&"light_stealth_red")), "red")
	colour.host_set_value(0.0)
	drv.update()
	expect(light.light_color.is_equal_approx(pal.color(&"light_work_white")), "back to white")
	power.host_set_value(0.0)
	drv.update()
	expect(not light.visible, "off")


func test_dimmer_scales_cabin_lights_when_on() -> void:
	var root: Node3D = Node3D.new()
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_energy = 2.0
	root.add_child(lamp)
	runner.add_child(root)
	var dimmer: Interactable = _switch(true)
	var cl: CabinLights = CabinLights.new()
	cl.lights_root = root
	cl.dimmer = dimmer
	runner.add_child(cl)
	var power: Interactable = _switch(true)
	var drv: CabinSwitch = CabinSwitch.new()
	drv.lights = cl
	drv.power = power
	runner.add_child(drv)
	cl._process(0.0)
	expect_near(lamp.light_energy, 2.0, 0.001, "full dimmer")
	dimmer.host_set_value(0.5)
	cl._process(0.0)
	expect_near(lamp.light_energy, 2.0 * lerpf(CabinLights.MIN_LEVEL, 1.0, 0.5), 0.001, "dimmer still scales")
	power.host_set_value(0.0)
	drv.update()
	cl._process(0.0)
	expect_near(lamp.light_energy, 0.0, 0.0001, "off is dark")
	power.host_set_value(1.0)
	drv.update()
	cl._process(0.0)
	expect(lamp.light_energy > 0.5, "back on")


func test_cabin_stealth_switch() -> void:
	var root: Node3D = Node3D.new()
	var lamp: OmniLight3D = OmniLight3D.new()
	var pl: PaletteLight = PaletteLight.new()
	pl.swatch = &"light_cabin"
	pl.stealth_swatch = &"light_stealth_red"
	lamp.add_child(pl)
	root.add_child(lamp)
	runner.add_child(root)
	var cl: CabinLights = CabinLights.new()
	cl.lights_root = root
	runner.add_child(cl)
	var sw: Interactable = _switch(false)
	var drv: CabinSwitch = CabinSwitch.new()
	drv.lights = cl
	drv.stealth_switch = sw
	runner.add_child(drv)
	expect(not cl.stealth, "starts normal")
	sw.host_set_value(1.0)
	drv.update()
	expect(cl.stealth, "stealth on")
	expect(lamp.light_color.is_equal_approx(Palette.main().color(&"light_stealth_red")), "red cabin light")
	sw.host_set_value(0.0)
	drv.update()
	expect(not cl.stealth, "stealth off")


func test_bilge_lamp_threshold() -> void:
	var model: SubPhysicsModel = SubPhysicsModel.new()
	var limit: float = model.max_surfaceable_bilge_t()
	var src: FakeSource = FakeSource.new()
	src.add_to_group(&"sub_readouts")
	src.values = {&"bilge_water_t": limit * 0.24, &"bilge_limit": limit}
	runner.add_child(src)
	var lamp: IndicatorLamp = IndicatorLamp.new()
	runner.add_child(lamp)
	var drv: ThresholdLamp = ThresholdLamp.new()
	drv.lamp = lamp
	drv.readout = &"bilge_water_t"
	drv.threshold = 0.25
	drv.threshold_of = &"bilge_limit"
	runner.add_child(drv)
	drv.update()
	expect(not lamp.is_lit(), "just under")
	src.values[&"bilge_water_t"] = limit * 0.26
	drv.update()
	expect(lamp.is_lit(), "just over")
	src.values[&"bilge_water_t"] = limit * 0.1
	drv.update()
	expect(not lamp.is_lit(), "drops out")


func test_unwired_lamp_stays_unlit() -> void:
	var lamp: IndicatorLamp = IndicatorLamp.new()
	runner.add_child(lamp)
	var drv: ThresholdLamp = ThresholdLamp.new()
	drv.lamp = lamp
	drv.threshold = 0.0075
	runner.add_child(drv)
	drv.update()
	expect(not lamp.is_lit(), "no readout")
	drv.readout = &"co2"
	drv.update()
	expect(not lamp.is_lit(), "no source")


func test_pilot_strip_switch_flips_on_a_click() -> void:
	var sw: SwitchLever = SwitchLever.new()
	runner.add_child(sw)
	var power: Interactable = _switch(false)
	var drv: CabinSwitch = CabinSwitch.new()
	drv.power = sw
	runner.add_child(drv)
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.max_value, "clicked on")
	expect_eq(drv.power.get_value(), sw.max_value, "the listener reads the new value")
	power.queue_free()
	drv.queue_free()
	sw.queue_free()


func test_guarded_switch_needs_two_clicks_to_flip() -> void:
	var sw: GuardedSwitch = (load("res://assets/models/kit/guarded_toggle/guarded_toggle.tscn") as PackedScene).instantiate() as GuardedSwitch
	runner.add_child(sw)
	var drv: CabinSwitch = CabinSwitch.new()
	drv.power = sw
	runner.add_child(drv)
	sw.begin_interaction()
	sw.click_action()
	expect_eq(sw.get_value(), sw.min_value, "first click lifts the cap, the value is unchanged")
	expect(sw.cap_open, "cap lifted")
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.max_value, "second click sets it on")
	expect_eq(drv.power.get_value(), sw.max_value, "the listener reads the new value")
	drv.queue_free()
	sw.queue_free()
