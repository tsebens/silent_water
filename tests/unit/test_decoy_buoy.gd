extends TestCase
## DecoyBuoy: travels then hangs, cannot be picked up, emits the decoy sound, pins the map,
## and appears when a primed LaunchTube fires.


func _buoy(chart: MapModel = null) -> DecoyBuoy:
	var b: DecoyBuoy = DecoyBuoy.new()
	b.simulate_host = true
	b.origin = Vector3(1.0, 2.0, 3.0)
	b.direction = Vector3(0.0, 0.0, -1.0)
	runner.add_child(b)
	return b


func test_moves_then_hangs() -> void:
	var b: DecoyBuoy = _buoy()
	expect_near(b.global_position.distance_to(b.origin), 0.0, 0.001, "starts at the exit point")
	b.advance(b.travel_s * 0.5)
	var mid: float = b.global_position.distance_to(b.origin)
	expect(mid > 0.1 and mid < b.travel_m, "part way")
	b.advance(b.travel_s)
	expect(b.is_hanging(), "hanging")
	expect_near(b.global_position.distance_to(b.origin), b.travel_m, 0.001, "a few metres out")
	var at: Vector3 = b.global_position
	b.advance(5.0)
	expect(b.global_position == at, "stays put")
	b.queue_free()


func test_item_cannot_be_picked_up() -> void:
	var b: DecoyBuoy = _buoy()
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	expect(b.item != null, "has the decoy look")
	expect(not b.item.pick_up(carrier), "pickup refused")
	expect(not b.item.is_carried(), "not carried")
	expect(b.item.get_node_or_null("Grab") == null or b.item.get_node("Grab").is_queued_for_deletion(), "no grab body")
	carrier.queue_free()
	b.queue_free()


func test_emits_decoy_sound() -> void:
	var det: SoundDetector = SoundDetector.new()
	det.threshold_db = -200.0
	runner.add_child(det)
	det.world_position = Vector3(1.0, 2.0, 3.0)
	var kinds: Array[StringName] = []
	det.heard.connect(func(e: SoundEvent) -> void: kinds.append(e.kind))
	var b: DecoyBuoy = _buoy()
	expect_eq(b.emitter.sound_type.kind, &"decoy")
	b.advance(b.travel_s)
	b.emitter.advance(b.emitter.sound_type.period * 1.5)
	expect(kinds.has(&"decoy"), "decoy event heard")
	det.queue_free()
	b.queue_free()


func test_pin_added_and_removed() -> void:
	var chart: MapModel = MapModel.new()
	runner.add_child(chart)
	var b: DecoyBuoy = _buoy()
	var n: int = 0
	for p: Dictionary in chart.pins:
		if int(p["kind"]) == MapModel.Kind.DECOY:
			n += 1
			expect_near((p["pos"] as Vector3).distance_to(b.hang_position()), 0.0, 0.001, "pin at the hang point")
	expect_eq(n, 1, "one DECOY pin")
	runner.remove_child(b)
	b.free()
	expect(chart.pins.is_empty(), "pin goes with the buoy")
	chart.queue_free()


func test_firing_a_primed_tube_spawns_a_buoy() -> void:
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
	var holder: Node3D = Node3D.new()
	runner.add_child(holder)
	DecoyBuoy.attach(tube, holder)
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(carrier)
	item.drop_into(cradle)
	expect(tube.request_prime(), "primed")
	expect_eq(holder.get_child_count(), 1, "just the spawner yet")
	expect(tube.fire(), "fired")
	var found: Array[Node] = []
	for c: Node in holder.get_children():
		if c is DecoyBuoy:
			found.append(c)
	expect_eq(found.size(), 1, "a buoy appears")
	if found.size() == 1:
		expect_near((found[0] as Node3D).global_position.distance_to(Vector3(1.0, 2.0, 3.0)), 0.0, 0.001, "at the exit point")
	for n: Node in [ctrl, drawer, cradle, lever, exit, tube, holder, carrier]:
		n.queue_free()
	for n: Node in found:
		n.queue_free()
