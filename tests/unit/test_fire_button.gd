extends TestCase
## FireButton: gated on the guard, fires a primed tube once, leaves others alone.


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
	var guard: Lever = Lever.new()
	runner.add_child(guard)
	var btn: PushButton = PushButton.new()
	runner.add_child(btn)
	var f: FireButton = FireButton.new()
	f.guard = guard
	f.button = btn
	f.tube = tube
	runner.add_child(f)
	return [f, tube, guard, btn, cradle, carrier, ctrl, drawer, lever]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func _open(guard: Lever) -> void:
	guard.begin_interaction()
	guard.drive_to(guard.max_value)
	guard.end_interaction()


func _prime(a: Array) -> void:
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(a[5])
	item.drop_into(a[4])
	expect((a[1] as LaunchTube).request_prime(), "primes")


func _press(btn: PushButton) -> void:
	btn.begin_interaction()
	btn.end_interaction()


func test_closed_guard_does_nothing() -> void:
	var a: Array = _make()
	_prime(a)
	var tube: LaunchTube = a[1]
	(a[0] as FireButton).request_fire()
	_press(a[3])
	expect_eq(tube.state(), LaunchTube.State.PRIMED, "still primed")
	_free(a)


func test_unprimed_tube_unchanged() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[1]
	var air: float = (a[6] as SubController).model.air_t
	_open(a[2])
	_press(a[3])
	expect_eq(tube.state(), LaunchTube.State.EMPTY)
	expect_eq((a[6] as SubController).model.air_t, air, "no air spent")
	_free(a)


func test_open_guard_fires_primed_tube_once() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[1]
	_prime(a)
	_open(a[2])
	var count: Array = [0]
	tube.fired.connect(func(_p: Vector3) -> void: count[0] += 1)
	_press(a[3])
	expect_eq(count[0], 1, "fired once")
	expect_eq(tube.state(), LaunchTube.State.EMPTY, "tube emptied")
	(a[0] as FireButton).request_fire()
	expect_eq(count[0], 1, "empty tube does not fire again")
	_free(a)
