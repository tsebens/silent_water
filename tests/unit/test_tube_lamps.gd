extends TestCase
## TubeLamps: exactly the lamp for the tube's state is lit and it follows transitions.


func _make() -> Array:
	var ctrl: SubController = SubController.new()
	runner.add_child(ctrl)
	var drawer: LoaderDrawer = LoaderDrawer.new()
	var body: Node3D = Node3D.new()
	drawer.add_child(body)
	drawer.body = body
	runner.add_child(drawer)
	var cradle: DecoyCradle = DecoyCradle.new()
	runner.add_child(cradle)
	var lever: Lever = Lever.new()
	runner.add_child(lever)
	var tube: LaunchTube = LaunchTube.new()
	tube.simulate_host = true
	tube.drawer = drawer
	tube.cradle = cradle
	tube.prime_lever = lever
	tube.controller = ctrl
	runner.add_child(tube)
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var lamps: Array[IndicatorLamp] = []
	for i: int in 3:
		var l: IndicatorLamp = IndicatorLamp.new()
		runner.add_child(l)
		lamps.append(l)
	var t: TubeLamps = TubeLamps.new()
	t.tube = tube
	t.empty_lamp = lamps[0]
	t.loaded_lamp = lamps[1]
	t.primed_lamp = lamps[2]
	runner.add_child(t)
	return [t, tube, drawer, cradle, carrier, lamps[0], lamps[1], lamps[2], ctrl, lever]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func _lit(a: Array, e: bool, l: bool, p: bool, msg: String) -> void:
	expect_eq((a[5] as IndicatorLamp).is_lit(), e, msg + ": empty")
	expect_eq((a[6] as IndicatorLamp).is_lit(), l, msg + ": loaded")
	expect_eq((a[7] as IndicatorLamp).is_lit(), p, msg + ": primed")


func test_lamps_follow_each_transition() -> void:
	var a: Array = _make()
	var drawer: LoaderDrawer = a[2]
	_lit(a, true, false, false, "empty at start")
	drawer.begin_interaction()
	drawer.drive_to(1.0)
	drawer.end_interaction()
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(a[4])
	item.drop_into(a[3])
	_lit(a, true, false, false, "seated, drawer open")
	drawer.begin_interaction()
	drawer.drive_to(0.0)
	drawer.end_interaction()
	_lit(a, false, true, false, "loaded")
	expect((a[1] as LaunchTube).request_prime(), "primes")
	_lit(a, false, false, true, "primed")
	expect((a[1] as LaunchTube).fire(), "fires")
	_lit(a, true, false, false, "emptied after fire")
	_free(a)
