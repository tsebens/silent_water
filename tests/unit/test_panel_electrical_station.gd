extends TestCase
## The generated electrical station (docs/asset_process.md, brief #534): nine breaker modules with the right circuits
## and labels, the generator toggle with its link, RUNNING lamp and HEAT gauge, the battery bar and LOAD meter, the
## spares drawer; every control within reach of the shoulder, every lamp and display in view of the eye.

const SCENE: String = "res://assets/models/panels/electrical_station/electrical_station.tscn"
const REACH_M: float = 1.1
const SHOULDER_DROP_M: float = 0.25
const BREAKERS: Array[Array] = [
	["BreakerMotor", PowerSystem.Circuit.MOTOR, "MOTOR"],
	["BreakerThrusters", PowerSystem.Circuit.THRUSTERS, "THRUSTERS"],
	["BreakerBilgePump", PowerSystem.Circuit.BILGE_PUMP, "BILGE PUMP"],
	["BreakerCabinLts", PowerSystem.Circuit.CABIN_LTS, "CABIN LTS"],
	["BreakerExtLts", PowerSystem.Circuit.EXT_LTS, "EXT LTS"],
	["BreakerSonar", PowerSystem.Circuit.SONAR, "SONAR"],
	["BreakerFans", PowerSystem.Circuit.FANS, "FANS"],
	["BreakerHelm", PowerSystem.Circuit.HELM, "HELM"],
	["BreakerDisplays", PowerSystem.Circuit.DISPLAYS, "DISPLAYS"],
]


func _make() -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
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


func test_scene_loads_with_no_script_of_its_own() -> void:
	var st: Node3D = _make()
	expect(st != null, "scene loads")
	expect(st.get_script() == null, "the panel adds no script")
	expect(st.get_node_or_null("Body") != null, "body present")
	st.queue_free()


func test_nine_breakers_with_circuits_and_labels() -> void:
	var st: Node3D = _make()
	for b: Array in BREAKERS:
		var br: BreakerSwitch = st.get_node_or_null(b[0] as String) as BreakerSwitch
		expect(br != null, "%s is a BreakerSwitch" % b[0])
		if br == null:
			continue
		expect_eq(br.circuit, b[1], "%s circuit" % b[0])
		expect_eq(br.label, b[2], "%s label" % b[0])
	var count: int = 0
	for c: Node in st.get_children():
		if c is BreakerSwitch:
			count += 1
	expect_eq(count, 9, "nine breakers")
	st.queue_free()


func test_breakers_are_a_three_by_three_grid() -> void:
	var st: Node3D = _make()
	var xs: Dictionary = {}
	var ys: Dictionary = {}
	for b: Array in BREAKERS:
		var p: Vector3 = (st.get_node(b[0] as String) as Node3D).position
		xs[snappedf(p.x, 0.001)] = true
		ys[snappedf(p.y, 0.001)] = true
	expect_eq(xs.size(), 3, "three columns")
	expect_eq(ys.size(), 3, "three rows")
	st.queue_free()


func test_generator_section() -> void:
	var st: Node3D = _make()
	var tog: SwitchLever = st.get_node_or_null("GeneratorToggle") as SwitchLever
	expect(tog != null, "GeneratorToggle is a SwitchLever")
	expect(tog != null and tog.scene_file_path.ends_with("guarded_toggle.tscn"), "the generator switch is the guarded toggle")
	var link: GeneratorLink = st.get_node_or_null("GeneratorLink") as GeneratorLink
	expect(link != null and link.switch_lever == tog, "GeneratorLink is tied to the toggle")
	var lamp: IndicatorLamp = st.get_node_or_null("RunningLamp") as IndicatorLamp
	expect(lamp != null, "RunningLamp is an IndicatorLamp")
	var drv: ThresholdLamp = st.get_node_or_null("RunningLampDriver") as ThresholdLamp
	expect(drv != null and drv.lamp == lamp, "the RUNNING lamp has its ThresholdLamp driver")
	if drv != null:
		expect_eq(drv.readout, &"generator_running", "RUNNING reads generator_running")
		expect_eq(drv.source_group, PowerSystem.GROUP, "RUNNING reads the power system")
	var heat: Gauge = st.get_node_or_null("HeatGauge") as Gauge
	expect(heat != null, "HeatGauge is a Gauge")
	if heat != null:
		expect_eq(heat.readout, &"generator_heat", "HEAT reads generator_heat")
		expect_eq(heat.source_group, PowerSystem.GROUP, "HEAT reads the power system")
		expect_eq(heat.title, "HEAT", "HEAT title")
	st.queue_free()


func test_battery_bar_is_descending() -> void:
	var st: Node3D = _make()
	var bar: LinearGauge = st.get_node_or_null("BatteryBar") as LinearGauge
	expect(bar != null, "BatteryBar is a LinearGauge")
	if bar != null:
		expect(bar.descending, "battery bar is descending (low is the alarm end)")
		expect_eq(bar.readout, &"battery_charge", "battery reads battery_charge")
		expect_eq(bar.source_group, PowerSystem.GROUP, "battery reads the power system")
		expect_eq(bar.swatch_for(1.0), &"light_ok", "a full battery is green")
		expect_eq(bar.swatch_for(0.1), &"light_alarm", "a nearly flat battery is red")
	st.queue_free()


func test_load_meter_has_a_red_zone() -> void:
	var st: Node3D = _make()
	var g: Gauge = st.get_node_or_null("LoadGauge") as Gauge
	expect(g != null, "LoadGauge is a Gauge")
	if g != null:
		expect_eq(g.readout, &"load", "LOAD reads load")
		expect_eq(g.source_group, PowerSystem.GROUP, "LOAD reads the power system")
		expect(not is_nan(g.zone_from) and g.zone_from > g.min_value and g.zone_from < g.max_value, "a zone starts inside the scale")
		expect_eq(g.zone_swatch, &"light_alarm", "the zone is red")
		expect(g.get_node_or_null("Zone") != null, "the zone is drawn")
	st.queue_free()


func test_spares_drawer_has_four_slots() -> void:
	var st: Node3D = _make()
	var dr: Node3D = st.get_node_or_null("SparesDrawer") as Node3D
	expect(dr != null, "SparesDrawer present")
	var d: SparesDrawer = dr.get_node_or_null("Drawer") as SparesDrawer if dr != null else null
	expect(d != null and d.slots.size() == 4, "the drawer has 4 slots")
	st.queue_free()


func test_size_floor_and_mount_face() -> void:
	var st: Node3D = _make()
	var box: AABB = _bounds(st, st)
	expect(box.size.x <= 1.2001, "at most 1.2 m wide (%.3f)" % box.size.x)
	expect(box.size.z <= 0.45, "at most 0.45 m deep (%.3f)" % box.size.z)
	expect(box.position.z >= -0.001, "nothing behind Z=0")
	var eye: Node3D = st.get_node("OperatorEye") as Node3D
	expect_near(eye.position.y, 0.55, 0.001, "eye height in the board frame")
	# The board's centre stands 1.1 m above the floor: knee (0.45 m) to head (1.75 m) height.
	expect(1.1 + box.position.y >= 0.45 - 0.001, "the board's foot is at knee height (%.2f m)" % (1.1 + box.position.y))
	expect(1.1 + box.end.y <= 1.75 + 0.001, "the board's top is at head height (%.2f m)" % (1.1 + box.end.y))
	st.queue_free()


func test_controls_within_reach_of_the_shoulder() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var shoulder: Vector3 = eye - Vector3(0.0, SHOULDER_DROP_M, 0.0)
	var controls: Array[Node3D] = [st.get_node("GeneratorToggle") as Node3D]
	for b: Array in BREAKERS:
		controls.append(st.get_node(b[0] as String) as Node3D)
	for c: Node3D in controls:
		var b: AABB = _bounds(st, c)
		# The control's farthest point from the shoulder, not just its origin.
		var far: float = 0.0
		for i: int in 8:
			far = maxf(far, shoulder.distance_to(b.get_endpoint(i)))
		expect(far <= REACH_M, "%s is %.2f m from the shoulder at its farthest" % [c.name, far])
	st.queue_free()


func _blocked(st: Node3D, eye: Vector3, to: Vector3, owner: Node) -> String:
	for c: Node in st.get_children():
		if c == owner or c.name == &"Body" or not (c is Node3D):
			continue
		for m: MeshInstance3D in _meshes(c):
			var b: AABB = st.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			if b.intersects_segment(eye, to):
				return "%s/%s" % [c.name, m.name]
	return ""


func test_lamps_and_displays_are_in_view_of_the_eye() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var targets: Array[Array] = []
	for b: Array in BREAKERS:
		var br: Node3D = st.get_node(b[0] as String) as Node3D
		var lamp: Node3D = br.get_node("IndicatorLamp") as Node3D
		targets.append([br, st.global_transform.affine_inverse() * lamp.global_position + Vector3(0, 0, 0.01), "%s lamp" % b[0]])
	var run: Node3D = st.get_node("RunningLamp") as Node3D
	targets.append([run, run.position + Vector3(0, 0, 0.005), "RunningLamp"])
	var bar: Node3D = st.get_node("BatteryBar") as Node3D
	for f: float in [0.0, 0.5, 1.0]:
		targets.append([bar, bar.position + Vector3(0, 0.2 * f, 0.007), "BatteryBar at %.1f" % f])
	for n: String in ["LoadGauge", "HeatGauge"]:
		var g: Node3D = st.get_node(n) as Node3D
		targets.append([g, g.position + Vector3(0, 0, 0.014), n])
	var d: AABB = _bounds(st, st.get_node("SparesDrawer"))
	targets.append([st.get_node("SparesDrawer"), d.get_center() + Vector3(0, 0, d.size.z / 2.0), "SparesDrawer"])
	for t: Array in targets:
		var by: String = _blocked(st, eye, t[1] as Vector3, t[0] as Node)
		expect(by == "", "%s is in view of the eye%s" % [t[2], "" if by == "" else " (blocked by %s)" % by])
		# Displays face the eye: the board is flat, so the angle from its normal to the eye stays modest.
		var v: Vector3 = (eye - (t[1] as Vector3)).normalized()
		expect(v.z > cos(deg_to_rad(70.0)), "%s faces the eye (%.0f deg off its normal)" % [t[2], rad_to_deg(acos(v.z))])
	st.queue_free()


func test_displays_face_out_of_the_board() -> void:
	var st: Node3D = _make()
	for n: String in ["LoadGauge", "HeatGauge", "BatteryBar", "RunningLamp", "SparesDrawer"]:
		var node: Node3D = st.get_node(n) as Node3D
		expect(node.global_transform.basis.z.dot(Vector3.BACK) > 0.999, "%s faces +Z" % n)
	st.queue_free()
