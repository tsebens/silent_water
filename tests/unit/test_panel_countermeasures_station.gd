extends TestCase
## The generated countermeasures station (docs/asset_process.md, brief #758): the FORE and AFT sections (three lamps
## over a guarded FIRE button each), the decoy status screen, the AIR and NOISE gauges, and the six-cradle decoy rack;
## every control within reach of the shoulder, every display in view of the eye, the lamps and screen readable under
## the stealth red cabin light.

const SCENE: String = "res://assets/models/panels/countermeasures_station/countermeasures_station.tscn"
const REACH_M: float = 1.1
const SHOULDER_DROP_M: float = 0.25
const MAX_ALONG_M: float = 1.0
const MAX_DEPTH_M: float = 0.451
const CONTRAST_MIN: float = 3.0
const TUBES: Array[String] = ["Fore", "Aft"]


func _make(setup: Callable = Callable()) -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	if setup.is_valid():
		setup.call(st)
	runner.add_child(st)
	return st


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
		stack.append_array(c.get_children())
	return out


## The AABB of every mesh under `n`, in the station's frame.
func _bounds(st: Node3D, n: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for m: MeshInstance3D in _meshes(n):
		var b: AABB = st.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _farthest(from: Vector3, b: AABB) -> float:
	var far: float = 0.0
	for i: int in range(8):
		far = maxf(far, from.distance_to(b.get_endpoint(i)))
	return far


func _shoulder(st: Node3D) -> Vector3:
	return (st.get_node("OperatorEye") as Node3D).position - Vector3(0.0, SHOULDER_DROP_M, 0.0)


## A launch tube with its parts, as the loader would have it; returns [tube, cradle, carrier, controller].
func _tube() -> Array:
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
	return [tube, cradle, carrier, ctrl, drawer, lever]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func _lum(c: Color) -> float:
	var lin: Callable = func(v: float) -> float:
		return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * float(lin.call(c.r)) + 0.7152 * float(lin.call(c.g)) + 0.0722 * float(lin.call(c.b))


func test_scene_loads_with_no_script_of_its_own() -> void:
	var st: Node3D = _make()
	expect(st.get_script() == null, "the panel adds no script")
	expect(st.get_node_or_null("Body") != null, "body present")
	expect(st.get_node_or_null("OperatorEye") != null, "operator eye present")
	st.queue_free()


func test_wiring_of_every_function() -> void:
	var st: Node3D = _make()
	for t: String in TUBES:
		var f: FireButton = st.get_node_or_null("%sFire" % t) as FireButton
		expect(f != null, "%sFire is a FireButton" % t)
		if f != null:
			expect(f.guard != null and f.button != null, "%sFire guard and button wired" % t)
			expect(f.tube == null, "%sFire's tube is set by the placing arc" % t)
		var lamps: TubeLamps = st.get_node_or_null("%sLamps" % t) as TubeLamps
		expect(lamps != null, "%sLamps is a TubeLamps" % t)
		if lamps != null:
			expect(lamps.empty_lamp == st.get_node("%sEmpty" % t), "%s EMPTY lamp wired" % t)
			expect(lamps.loaded_lamp == st.get_node("%sLoaded" % t), "%s LOADED lamp wired" % t)
			expect(lamps.primed_lamp == st.get_node("%sPrimed" % t), "%s PRIMED lamp wired" % t)
		for n: String in ["Empty", "Loaded", "Primed"]:
			expect(st.get_node_or_null("%s%s" % [t, n]) is IndicatorLamp, "%s%s is an IndicatorLamp" % [t, n])
	expect(st.get_node_or_null("StatusScreen") is DecoyStatusScreen, "StatusScreen is a DecoyStatusScreen")
	var air: Gauge = st.get_node_or_null("AirGauge") as Gauge
	expect(air != null, "AirGauge is a Gauge")
	if air != null:
		expect_eq(air.readout, &"air_fraction", "AIR reads air_fraction")
		expect_eq(air.title, "AIR", "AIR title")
		expect_eq(air.source_group, &"sub_readouts", "AIR reads the sub's readouts")
	var noise: Gauge = st.get_node_or_null("NoiseGauge") as Gauge
	expect(noise != null, "NoiseGauge is a Gauge")
	if noise != null:
		expect_eq(noise.source_group, &"acoustics_readouts", "NOISE reads the acoustics readouts")
		expect_eq(noise.readout, &"sub_db", "NOISE reads sub_db")
	expect(st.get_node_or_null("DecoyRack") != null, "the decoy rack is instanced")
	st.queue_free()


func test_fore_left_of_aft_and_lamps_over_the_button() -> void:
	var st: Node3D = _make()
	var fore: Node3D = st.get_node("ForeFire") as Node3D
	var aft: Node3D = st.get_node("AftFire") as Node3D
	expect(fore.position.x < aft.position.x, "FORE to the left of AFT")
	expect_near(fore.position.y, aft.position.y, 0.0001, "the two FIRE buttons on one row")
	for t: String in TUBES:
		var fire: Node3D = st.get_node("%sFire" % t) as Node3D
		var e: Node3D = st.get_node("%sEmpty" % t) as Node3D
		var l: Node3D = st.get_node("%sLoaded" % t) as Node3D
		var p: Node3D = st.get_node("%sPrimed" % t) as Node3D
		expect(e.position.x < l.position.x and l.position.x < p.position.x, "%s lamps in order EMPTY, LOADED, PRIMED" % t)
		expect(e.position.y > fire.position.y + 0.12, "%s lamps above the guard's open swing" % t)
		expect_near(l.position.x, fire.position.x, 0.0001, "%s lamps centred over their button" % t)
	var screen: Node3D = st.get_node("StatusScreen") as Node3D
	var air: Node3D = st.get_node("AirGauge") as Node3D
	expect(screen.position.y < fore.position.y and air.position.y < screen.position.y, "screen beneath FIRE, gauges beneath the screen")
	st.queue_free()


func test_six_cradles_seat_decoys() -> void:
	var st: Node3D = _make()
	var rack: Node3D = st.get_node("DecoyRack") as Node3D
	for i: int in range(1, 7):
		var c: DecoyCradle = rack.get_node("Cradle%d" % i) as DecoyCradle
		var d: DecoyItem = rack.get_node("Decoy%d" % i) as DecoyItem
		expect(c != null and d != null, "cradle and decoy %d present" % i)
		expect(c.try_seat(d), "decoy %d seats in its cradle" % i)
		expect(c.is_occupied(), "cradle %d occupied" % i)
	expect(rack.get_node_or_null("Cradle7") == null, "exactly six cradles")
	st.queue_free()


func test_fire_fires_a_primed_tube_stub() -> void:
	var a: Array = _tube()
	var tube: LaunchTube = a[0]
	var st: Node3D = _make(func(s: Node3D) -> void: (s.get_node("ForeFire") as FireButton).tube = tube)
	var f: FireButton = st.get_node("ForeFire") as FireButton
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(a[2])
	item.drop_into(a[1])
	expect(tube.request_prime(), "the stub tube primes")
	expect_eq(tube.state(), LaunchTube.State.PRIMED, "primed")
	f.button.begin_interaction()
	f.button.end_interaction()
	expect_eq(tube.state(), LaunchTube.State.PRIMED, "a press with the guard shut leaves it primed")
	f.guard.begin_interaction()
	f.guard.drive_to(f.guard.max_value)
	f.guard.end_interaction()
	expect(f.guard_open(), "guard lifted")
	f.button.begin_interaction()
	f.button.end_interaction()
	expect_eq(tube.state(), LaunchTube.State.EMPTY, "FIRE with the guard open fires the primed tube")
	st.queue_free()
	_free(a)
	item.queue_free()


func test_lamps_follow_the_tube() -> void:
	var a: Array = _tube()
	var tube: LaunchTube = a[0]
	var st: Node3D = _make(func(s: Node3D) -> void: (s.get_node("AftLamps") as TubeLamps).tube = tube)
	var empty: IndicatorLamp = st.get_node("AftEmpty") as IndicatorLamp
	var loaded: IndicatorLamp = st.get_node("AftLoaded") as IndicatorLamp
	var primed: IndicatorLamp = st.get_node("AftPrimed") as IndicatorLamp
	expect(empty.is_lit() and not loaded.is_lit() and not primed.is_lit(), "an empty tube lights EMPTY only")
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(a[2])
	item.drop_into(a[1])
	expect(loaded.is_lit() and not empty.is_lit() and not primed.is_lit(), "a loaded tube lights LOADED only")
	tube.request_prime()
	expect(primed.is_lit() and not loaded.is_lit() and not empty.is_lit(), "a primed tube lights PRIMED only")
	st.queue_free()
	_free(a)
	item.queue_free()


func test_size_within_the_reservation() -> void:
	var st: Node3D = _make()
	# Everything but the decoys, whose tilted boxes inflate an axis-aligned bound (the rack's own test checks them).
	var b: AABB = _bounds(st, st.get_node("Body"))
	for n: Node in st.get_children():
		if n.name != &"Body" and n.name != &"DecoyRack":
			b = b.merge(_bounds(st, n)) if _meshes(n).size() > 0 else b
	b = b.merge(_bounds(st, st.get_node("DecoyRack/Body")))
	expect(b.size.x <= MAX_ALONG_M, "at most 1.0 m along the hull (%.3f)" % b.size.x)
	expect(b.end.z <= MAX_DEPTH_M, "at most 450 mm deep (%.3f)" % b.end.z)
	expect(b.position.z >= -0.0001, "nothing behind the mount face")
	st.queue_free()


func test_everything_within_reach_of_the_shoulder() -> void:
	var st: Node3D = _make()
	var sh: Vector3 = _shoulder(st)
	for n: String in ["ForeFire", "AftFire", "AirGauge", "NoiseGauge"]:
		var d: float = _farthest(sh, _bounds(st, st.get_node(n)))
		expect(d <= REACH_M, "%s within reach of the shoulder (%.3f m)" % [n, d])
	var s: MeshInstance3D = st.get_node("StatusScreen") as MeshInstance3D
	var sb: AABB = st.global_transform.affine_inverse() * s.global_transform * s.get_aabb()
	expect(_farthest(sh, sb) <= REACH_M, "the status screen within reach (%.3f m)" % _farthest(sh, sb))
	var rack: Node3D = st.get_node("DecoyRack") as Node3D
	for i: int in range(1, 7):
		var shape: CollisionShape3D = rack.get_node("Decoy%d/Grab/Shape" % i) as CollisionShape3D
		var d: float = sh.distance_to(st.global_transform.affine_inverse() * shape.global_position)
		expect(d <= REACH_M, "cradle %d within reach of the shoulder (%.3f m)" % [i, d])
	st.queue_free()


func test_displays_face_the_eye_and_nothing_blocks_them() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var names: Array[String] = ["StatusScreen", "AirGauge", "NoiseGauge"]
	for t: String in TUBES:
		for n: String in ["Empty", "Loaded", "Primed"]:
			names.append("%s%s" % [t, n])
	for n: String in names:
		var node: Node3D = st.get_node(n) as Node3D
		var to_eye: Vector3 = (eye - node.position).normalized()
		var facing: Vector3 = (st.global_transform.affine_inverse().basis * node.global_transform.basis * Vector3.BACK).normalized()
		var ang: float = rad_to_deg(acos(clampf(facing.dot(to_eye), -1.0, 1.0)))
		expect(ang <= 60.0, "%s faces the eye within 60 degrees (%.0f)" % [n, ang])
	st.queue_free()


func test_grab_boxes_are_apart() -> void:
	var st: Node3D = _make()
	var boxes: Array[AABB] = []
	var owners: Array[Node] = []
	var stack: Array[Node] = [st]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		var sb: StaticBody3D = c as StaticBody3D
		if sb == null or sb.collision_layer != 2:
			continue
		for sc: Node in sb.get_children():
			var cs: CollisionShape3D = sc as CollisionShape3D
			var bs: BoxShape3D = cs.shape as BoxShape3D if cs != null else null
			if bs != null:
				boxes.append(cs.global_transform * AABB(-bs.size * 0.5, bs.size))
				owners.append(sb)
	expect(boxes.size() >= 10, "grab boxes found (%d)" % boxes.size())
	var rack: Node = st.get_node("DecoyRack")
	for i: int in range(boxes.size()):
		for j: int in range(i + 1, boxes.size()):
			if rack.is_ancestor_of(owners[i]) and rack.is_ancestor_of(owners[j]):
				continue   # the rack's own cradles are tested with the rack
			expect(not boxes[i].intersects(boxes[j]), "grab boxes %s and %s apart" % [owners[i].get_path(), owners[j].get_path()])
	st.queue_free()


## The lit lamps and the screen readout under the stealth red cabin light: each emits its own swatch, the panel body
## takes the red light. Contrast ratio (L1 + 0.05) / (L2 + 0.05) at least 3:1.
func test_lamps_and_screen_read_under_the_red_cabin_light() -> void:
	var pal: Palette = Palette.main()
	var body_role: RoleMaterial = RoleMaterial.lookup("interior_panel")
	expect(body_role != null, "the panel body takes the interior_panel role")
	var red: Color = pal.color(&"light_stealth_red")
	var body: Color = pal.color(body_role.swatch)
	var lit: Color = Color(body.r * red.r, body.g * red.g, body.b * red.b)
	var body_l: float = _lum(lit)
	var emitters: Dictionary = {}
	for role: String in ["indicator_alarm", "indicator_warn", "indicator_ok"]:
		var rm: RoleMaterial = RoleMaterial.lookup(role)
		expect(rm != null and rm.glow != &"", "%s glows an indicator swatch" % role)
		emitters[role] = pal.color(rm.glow)
	var st: Node3D = _make()
	var screen: DecoyStatusScreen = st.get_node("StatusScreen") as DecoyStatusScreen
	expect(Palette.in_information_band(pal.color(screen.ink_swatch)), "the screen's readout ink is the cyan band")
	emitters["screen readout"] = pal.color(screen.ink_swatch)
	for k: String in emitters:
		var ratio: float = (_lum(emitters[k] as Color) + 0.05) / (body_l + 0.05)
		expect(ratio >= CONTRAST_MIN, "%s against the panel under red light is %.1f:1, at least 3:1" % [k, ratio])
	st.queue_free()


func test_lamp_scenes_use_indicator_roles() -> void:
	var st: Node3D = _make()
	var want: Dictionary = {"Empty": "indicator_alarm", "Loaded": "indicator_warn", "Primed": "indicator_ok"}
	for t: String in TUBES:
		for n: String in want:
			var node: Node = st.get_node("%s%s" % [t, n])
			expect(node.scene_file_path.contains("led_strip"), "%s%s is an LED strip" % [t, n])
	st.queue_free()
