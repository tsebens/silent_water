extends TestCase
## Cabin lights have no dimmer: they hold level 1.0, and only the strip switch turns them off and on.


func _switch(on: bool) -> Interactable:
	var s: Interactable = Interactable.new()
	runner.add_child(s)
	s.host_set_value(1.0 if on else 0.0)
	return s


func test_level_is_fixed_and_switch_turns_lights_off_and_on() -> void:
	var root: Node3D = Node3D.new()
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_energy = 2.0
	root.add_child(lamp)
	runner.add_child(root)
	var cl: CabinLights = CabinLights.new()
	cl.lights_root = root
	runner.add_child(cl)
	var power: Interactable = _switch(true)
	var drv: CabinSwitch = CabinSwitch.new()
	drv.lights = cl
	drv.power = power
	runner.add_child(drv)
	expect_eq(cl.level(), 1.0, "level is 1.0")
	cl._process(0.0)
	expect_near(lamp.light_energy, 2.0, 0.001, "full level")
	power.host_set_value(0.0)
	drv.update()
	cl._process(0.0)
	expect_near(lamp.light_energy, 0.0, 0.0001, "off is dark")
	power.host_set_value(1.0)
	drv.update()
	cl._process(0.0)
	expect_near(lamp.light_energy, 2.0, 0.001, "back on at full level")
