extends TestCase
## LoaderDrawer and LaunchTube: slide, lock, empty -> loaded -> primed -> fired, air cost.
## Also SubPhysicsModel.spend_air.


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
	var exit: Node3D = Node3D.new()
	runner.add_child(exit)
	exit.global_position = Vector3(1.0, 2.0, 3.0)
	var tube: LaunchTube = LaunchTube.new()
	tube.simulate_host = true
	tube.drawer = drawer
	tube.cradle = cradle
	tube.prime_lever = lever
	tube.controller = ctrl
	tube.exit_point = exit
	runner.add_child(tube)
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	return [tube, ctrl, drawer, cradle, lever, carrier, exit]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func _drag(d: LoaderDrawer, to: float) -> void:
	d.begin_interaction()
	d.drive_to(to)
	d.end_interaction()


func _load(a: Array) -> DecoyItem:
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(a[5])
	item.drop_into(a[3])
	return item


func test_spend_air() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	expect(m.spend_air(3.0), "spent")
	expect_near(m.air_t, 57.0, 0.001)
	expect(not m.spend_air(100.0), "refused when short")
	expect_near(m.air_t, 57.0, 0.001, "nothing spent on refusal")
	expect(not m.spend_air(-1.0), "negative refused")


func test_drawer_slides_clamped_and_locks() -> void:
	var a: Array = _make()
	var d: LoaderDrawer = a[2]
	expect(d.is_closed(), "starts closed")
	d.begin_interaction()
	d.drag(Vector2(0.0, 1000.0))
	expect(d.is_open(), "drag past the end clamps to open")
	expect_near((d.body.position).z, d.travel_m, 0.001, "body slid the full travel")
	d.end_interaction()
	_drag(d, 0.0)
	expect(d.is_closed(), "closed again")
	d.locked = true
	d.begin_interaction()
	d.drag(Vector2(0.0, 200.0))
	d.end_interaction()
	expect(d.is_closed(), "locked drawer does not move")
	_free(a)


func test_empty_to_loaded_to_primed() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	expect_eq(tube.state(), LaunchTube.State.EMPTY)
	expect(tube.empty_lit() and not tube.loaded_lit() and not tube.primed_lit(), "empty lamps")
	_drag(a[2], 1.0)
	var item: DecoyItem = _load(a)
	expect_eq(tube.state(), LaunchTube.State.EMPTY, "seated but drawer open is not loaded")
	_drag(a[2], 0.0)
	expect_eq(tube.state(), LaunchTube.State.LOADED)
	expect(tube.loaded_lit(), "loaded lamp")
	expect(tube.request_prime(), "primes")
	expect_eq(tube.state(), LaunchTube.State.PRIMED)
	expect(tube.primed_lit(), "primed lamp")
	expect((a[4] as Lever).get_value() >= (a[4] as Lever).max_value - 0.001, "lever down while primed")
	_drag(a[2], 1.0)
	expect((a[2] as LoaderDrawer).is_closed(), "drawer cannot open while primed")
	item.queue_free()
	_free(a)


func test_prime_refused_open_or_empty() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	expect(not tube.request_prime(), "empty cradle refused")
	_drag(a[2], 1.0)
	var item: DecoyItem = _load(a)
	expect(not tube.request_prime(), "open drawer refused")
	expect_eq(tube.state(), LaunchTube.State.EMPTY)
	item.queue_free()
	_free(a)


func test_fire_spends_air_and_empties() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	var model: SubPhysicsModel = (a[1] as SubController).model
	var exits: Array[Vector3] = []
	tube.fired.connect(func(p: Vector3) -> void: exits.append(p))
	expect(not tube.fire(), "fire refused when not primed")
	var item: DecoyItem = _load(a)
	tube.request_prime()
	expect(tube.fire(), "fires")
	expect_near(model.air_t, 57.0, 0.01, "5% of 60 t spent")
	expect_eq(tube.state(), LaunchTube.State.EMPTY)
	expect(not (a[3] as DecoyCradle).is_occupied(), "cradle emptied")
	expect(not (a[2] as LoaderDrawer).locked, "drawer unlocked")
	expect_near((a[4] as Lever).get_value(), (a[4] as Lever).min_value, 0.001, "lever released")
	expect_eq(exits.size(), 1)
	expect(exits[0].is_equal_approx(Vector3(1.0, 2.0, 3.0)), "exit point")
	expect(is_instance_valid(item), "item still valid until freed")
	_free(a)


func test_fire_refused_short_of_air() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	var model: SubPhysicsModel = (a[1] as SubController).model
	var item: DecoyItem = _load(a)
	tube.request_prime()
	model.air_t = 2.0
	var reasons: Array[String] = []
	tube.fire_refused.connect(func(r: String) -> void: reasons.append(r))
	expect(not tube.fire(), "refused")
	expect_eq(tube.state(), LaunchTube.State.PRIMED, "stays primed")
	expect_near(model.air_t, 2.0, 0.001, "no air spent")
	expect_eq(reasons.size(), 1)
	item.queue_free()
	_free(a)


func test_client_fire_is_a_request() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	tube.simulate_host = false
	var item: DecoyItem = _load(a)
	# Offline and not the server in the test tree: a request does not run the fire here.
	tube.request_fire()
	expect_near((a[1] as SubController).model.air_t, 60.0, 0.001, "client does not spend air itself")
	item.queue_free()
	_free(a)


func test_play_launch_sound_is_play_only() -> void:
	var a: Array = _make()
	var tube: LaunchTube = a[0]
	var em: SoundEmitter = SoundEmitter.new()
	runner.add_child(em)
	tube.emitter = em
	expect(em.field_events, "field events on by default")
	tube.play_launch_sound(Vector3(4.0, 5.0, 6.0))
	expect(em.field_events, "field_events restored")
	expect(em.world_position.is_equal_approx(Vector3(4.0, 5.0, 6.0)), "emitter placed at the exit")
	tube.emitter = null
	tube.play_launch_sound(Vector3.ZERO)
	em.queue_free()
	_free(a)
