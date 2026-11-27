extends TestCase
## The generated engineering station (docs/asset_process.md, brief #530): the FLOOD and BLOW wheels, the three bound
## gauges (tank, air, bilge level), the noise gauge, the BILGE PUMP toggle with its lamp, the guarded drop-weights button
## and the manual pump; every control within reach of the shoulder, every gauge and the lamp in view of the eye.

const SCENE: String = "res://assets/models/panels/engineering_station/engineering_station.tscn"
const REACH_M: float = 1.1
const SHOULDER_DROP_M: float = 0.25
const AISLE_MIN_M: float = 0.8
const CONTROLS: Array[String] = ["FloodWheel", "BlowWheel", "DropWeights", "BilgeSwitch", "HandPump"]
const GAUGES: Array[String] = ["TankGauge", "AirGauge", "BilgeGauge", "NoiseGauge"]


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
	expect(st.get_script() == null, "the panel adds no script")
	expect(st.get_node_or_null("Body") != null, "body present")
	st.queue_free()


func test_two_valve_wheels() -> void:
	var st: Node3D = _make()
	var flood: Valve = st.get_node_or_null("FloodWheel") as Valve
	var blow: Valve = st.get_node_or_null("BlowWheel") as Valve
	expect(flood != null and blow != null, "FloodWheel and BlowWheel are Valves")
	if flood != null and blow != null:
		expect_eq(flood.label, "FLOOD", "FLOOD label")
		expect_eq(blow.label, "BLOW", "BLOW label")
		expect(flood.wheel != null and blow.wheel != null, "both wheels bound")
		expect_near(flood.position.y, blow.position.y, 0.0001, "both wheels on the same pipe")
		expect(flood.position.x < blow.position.x, "FLOOD to the left of BLOW")
	var count: int = 0
	for c: Node in st.get_children():
		if c is Valve:
			count += 1
	expect_eq(count, 2, "two valve wheels")
	st.queue_free()


func test_bound_gauges_have_the_right_readouts() -> void:
	var st: Node3D = _make()
	var want: Dictionary = {
		"TankGauge": [&"tank_fraction", "TANK LEVEL"],
		"AirGauge": [&"air_fraction", "AIR REMAINING"],
		"BilgeGauge": [&"bilge_water_t", "BILGE LEVEL"],
	}
	for n: String in want:
		var g: Gauge = st.get_node_or_null(n) as Gauge
		expect(g != null, "%s is a Gauge" % n)
		if g == null:
			continue
		var w: Array = want[n] as Array
		expect_eq(g.readout, w[0] as StringName, "%s readout" % n)
		expect_eq(g.title, w[1] as String, "%s title" % n)
		expect_eq(g.source_group, &"sub_readouts", "%s reads the sub's readouts" % n)
		expect(g.max_value > g.min_value, "%s has a scale" % n)
	var tank: Gauge = st.get_node("TankGauge") as Gauge
	var air: Gauge = st.get_node("AirGauge") as Gauge
	expect_eq(tank.max_value, 1.0, "tank scale is a fraction")
	expect_eq(air.max_value, 1.0, "air scale is a fraction")
	expect(tank.position.x < air.position.x and is_equal_approx(tank.position.y, air.position.y), "TANK left of AIR, side by side")
	st.queue_free()


func test_noise_gauge_is_the_shared_repeater() -> void:
	var st: Node3D = _make()
	var g: Gauge = st.get_node_or_null("NoiseGauge") as Gauge
	expect(g != null, "NoiseGauge is a Gauge")
	if g != null:
		expect_eq(g.source_group, &"acoustics_readouts", "NOISE reads the acoustics readouts")
		expect_eq(g.readout, &"sub_db", "NOISE reads sub_db")
		expect_eq(g.readout_b, &"ambient_db", "NOISE has the ocean needle")
	st.queue_free()


func test_bilge_switch_has_its_lamp() -> void:
	var st: Node3D = _make()
	var sw: SwitchLever = st.get_node_or_null("BilgeSwitch") as SwitchLever
	expect(sw != null, "BilgeSwitch is a SwitchLever")
	if sw != null:
		expect(sw.scene_file_path.ends_with("lit_toggle.tscn"), "it is the lit toggle")
		expect_eq(sw.label, "BILGE PUMP", "BILGE PUMP label")
		expect(sw.indicator != null, "the RUNNING lamp is wired to the switch")
	st.queue_free()


func test_drop_weights_button_and_hand_pump_present() -> void:
	var st: Node3D = _make()
	var dw: DropWeightsButton = st.get_node_or_null("DropWeights") as DropWeightsButton
	expect(dw != null, "DropWeights is a DropWeightsButton")
	if dw != null:
		expect(dw.guard != null and dw.button != null, "guard and button wired")
	var hp: HandPump = st.get_node_or_null("HandPump") as HandPump
	expect(hp != null, "HandPump present")
	st.queue_free()


func test_size_and_mount_face() -> void:
	var st: Node3D = _make()
	var box: AABB = _bounds(st, st)
	expect(box.size.x <= 1.2001, "at most 1.2 m along the hull (%.3f)" % box.size.x)
	expect(box.position.z >= -0.001, "nothing behind Z=0 (%.4f)" % box.position.z)
	var eye: Node3D = st.get_node("OperatorEye") as Node3D
	expect_near(eye.position.y, 0.55, 0.001, "eye height")
	expect_near(eye.position.z, 0.5, 0.001, "eye distance out")
	st.queue_free()


func test_controls_within_reach_of_the_shoulder() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var shoulder: Vector3 = eye - Vector3(0.0, SHOULDER_DROP_M, 0.0)
	for n: String in CONTROLS:
		var c: Node3D = st.get_node(n) as Node3D
		var b: AABB = _bounds(st, c)
		var far: float = 0.0
		for i: int in 8:
			far = maxf(far, shoulder.distance_to(b.get_endpoint(i)))
		expect(far <= REACH_M, "%s is %.2f m from the shoulder at its farthest" % [n, far])
	st.queue_free()


func _blocked(st: Node3D, eye: Vector3, to: Vector3, owner: Node) -> String:
	for c: Node in st.get_children():
		if c == owner or c.name == &"Body" or not (c is Node3D) or c.name == &"OperatorEye":
			continue
		for m: MeshInstance3D in _meshes(c):
			var b: AABB = st.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			if b.intersects_segment(eye, to):
				return "%s/%s" % [c.name, m.name]
	return ""


func test_gauges_and_lamp_are_in_view_of_the_eye_and_face_it() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var targets: Array[Array] = []
	for n: String in GAUGES:
		var g: Node3D = st.get_node(n) as Node3D
		targets.append([g, g.position + g.transform.basis.z * 0.014, n])
	var sw: Node3D = st.get_node("BilgeSwitch") as Node3D
	targets.append([sw, sw.position + sw.transform.basis.y * 0.052 + sw.transform.basis.z * 0.006, "BilgeSwitch lamp"])
	for t: Array in targets:
		var by: String = _blocked(st, eye, t[1] as Vector3, t[0] as Node)
		expect(by == "", "%s is in view of the eye%s" % [t[2], "" if by == "" else " (blocked by %s)" % by])
		var normal: Vector3 = ((t[0] as Node3D).transform.basis.z).normalized()
		var v: Vector3 = (eye - (t[1] as Vector3)).normalized()
		expect(normal.dot(v) > cos(deg_to_rad(60.0)), "%s faces the eye (%.0f deg off its normal)" % [t[2], rad_to_deg(acos(normal.dot(v)))])
	st.queue_free()


func test_displays_face_out_or_toward_the_eye_never_down() -> void:
	var st: Node3D = _make()
	for n: String in GAUGES:
		var g: Node3D = st.get_node(n) as Node3D
		expect(g.transform.basis.z.y >= 0.0, "%s does not face down" % n)
	for n: String in ["TankGauge", "AirGauge"]:
		expect((st.get_node(n) as Node3D).global_transform.basis.z.dot(Vector3.BACK) > 0.999, "%s faces +Z" % n)
	st.queue_free()


func test_pump_sweep_leaves_the_aisle() -> void:
	var st: Node3D = _make()
	var hp: HandPump = st.get_node("HandPump") as HandPump
	var deepest: float = 0.0
	for v: float in [0.0, 1.0]:
		hp.host_set_value(v)
		deepest = maxf(deepest, _bounds(st, hp).end.z)
	expect(deepest <= 0.7, "the pump's sweep stays within 0.7 m of the hull (%.3f)" % deepest)
	# The hull's clear width at the ballast station (a tenth off for the narrower section at the pump's height).
	var width: float = 2.0 * SubLayout.hull_inner_half(3.275).x * 0.9
	expect(width - deepest >= AISLE_MIN_M, "at least %.1f m of aisle is clear of the sweep (%.2f m)" % [AISLE_MIN_M, width - deepest])
	st.queue_free()


func test_controls_work_in_place() -> void:
	var st: Node3D = _make()
	var flood: Valve = st.get_node("FloodWheel") as Valve
	flood.host_set_value(flood.max_value)
	expect_near(flood.get_normalized(), 1.0, 0.001, "FLOOD turns to open")
	flood.host_set_value(flood.min_value)
	expect_near(flood.get_normalized(), 0.0, 0.001, "FLOOD turns shut")
	var sw: SwitchLever = st.get_node("BilgeSwitch") as SwitchLever
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.max_value, "a click turns the bilge pump on")
	expect(sw.indicator.is_lit(), "and its RUNNING lamp lights")
	var dw: DropWeightsButton = st.get_node("DropWeights") as DropWeightsButton
	expect(not dw.guard_open(), "the drop-weights guard starts closed")
	dw.guard.host_set_value(dw.guard.max_value)
	expect(dw.guard_open(), "the guard lifts in place")
	var hp: HandPump = st.get_node("HandPump") as HandPump
	hp.step(0.1, true)
	expect(hp.phase == HandPump.Phase.DOWN, "holding the lever starts the down stroke")
	st.queue_free()


func test_pump_lever_comes_out_toward_the_player() -> void:
	var st: Node3D = _make()
	var hp: HandPump = st.get_node("HandPump") as HandPump
	expect(hp.transform.basis.z.dot(Vector3.BACK) > 0.999, "the lever runs out along +Z, toward the player")
	st.queue_free()


func test_wheels_sit_inline_on_the_horizontal_pipe_runs_outside_the_risers() -> void:
	var st: Node3D = _make()
	var flood: Node3D = st.get_node("FloodWheel") as Node3D
	var blow: Node3D = st.get_node("BlowWheel") as Node3D
	expect_near(flood.position.x, -blow.position.x, 0.0001, "the two pipes are mirrored")
	var tank: Node3D = st.get_node("TankGauge") as Node3D
	var air: Node3D = st.get_node("AirGauge") as Node3D
	expect(tank.position.x > flood.position.x + 0.1 and air.position.x < blow.position.x - 0.1, "the gauges sit between the two bends")
	var console_w: float = _bounds(st, st.get_node("DropWeights")).size.x
	expect(console_w > 0.0, "the console carries the drop-weights button")
	st.queue_free()
