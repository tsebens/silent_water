extends TestCase
## The generated science bay (docs/asset_process.md, brief #529): three module bays in a raked row over a hand ledge,
## the default fit SCAN, SWEEP, CAMERA, the shared noise repeater and the operator's markers. Every function's control
## present, grab boxes apart, displays facing the eye, reach from the shoulder, any module in any bay, an empty bay.

const SCENE: String = "res://assets/models/stations/science_bay/science_bay.tscn"
const MODULE_SCENES: Array[String] = [
	"res://assets/models/kit/scan_module/scan_module.tscn",
	"res://assets/models/kit/sweep_module/sweep_module.tscn",
	"res://assets/models/kit/probe_module/probe_module.tscn",
	"res://assets/models/kit/camera_module/camera_module.tscn",
]
const REACH_M: float = 1.1
const SHOULDER_DROP_M: float = 0.25
const WAIST_Y_M: float = -0.1
const MAX_ALONG_M: float = 1.2
const MAX_DEEP_M: float = 0.45
const FACE_MAX_DEG: float = 60.0
const BAYS: Array[String] = ["Bay0", "Bay1", "Bay2"]


func _make() -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(st)
	return st


## The AABB of every mesh under `n`, in the station's frame (an empty AABB when there is none).
func _bounds(st: Node3D, n: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null and mi.mesh != null:
			var b: AABB = st.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func _module(st: Node3D, bay: String) -> Node3D:
	return st.get_node(bay).get_node("Module") as Node3D


## Replaces bay `bay`'s module with scene `path`, as a loadout change would.
func _fit(st: Node3D, bay: String, path: String) -> Node3D:
	var b: Node3D = st.get_node(bay) as Node3D
	var old: Node = b.get_node("Module")
	b.remove_child(old)
	old.free()
	var m: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	m.name = &"Module"
	b.add_child(m)
	return m


func test_scene_loads_with_no_script_of_its_own() -> void:
	var st: Node3D = _make()
	expect(st.get_script() == null, "the panel adds no script (the placement arc wraps it in ScienceStation)")
	for n: String in ["Body", "NoiseGauge", "OperatorEye", "OperatorPoint"] + BAYS:
		expect(st.get_node_or_null(n) != null, "%s present" % n)
	st.queue_free()


func test_default_fit_is_scan_sweep_camera_left_to_right() -> void:
	var st: Node3D = _make()
	expect(_module(st, "Bay0") is ScanModule, "bay 0 holds SCAN")
	expect(_module(st, "Bay1") is SweepModule, "bay 1 holds SWEEP")
	expect(_module(st, "Bay2") is CameraModule, "bay 2 holds CAMERA")
	expect((st.get_node("Bay0") as Node3D).position.x < (st.get_node("Bay1") as Node3D).position.x, "bays run left to right")
	expect((st.get_node("Bay1") as Node3D).position.x < (st.get_node("Bay2") as Node3D).position.x, "bays run left to right")
	st.queue_free()


func test_every_function_has_its_control_or_display() -> void:
	var st: Node3D = _make()
	var scan: ScanModule = _module(st, "Bay0") as ScanModule
	expect(scan.arm_switch != null, "SCAN: the arm switch is wired")
	var sweep: Node = _module(st, "Bay1")
	expect(sweep.get_node_or_null("ArmSwitch") is SwitchLever, "SWEEP: arm switch present")
	expect(sweep.get_node_or_null("Screen") != null, "SWEEP: coverage screen present")
	var cam: Node = _module(st, "Bay2")
	expect(cam.get_node_or_null("Shutter") is PushButton, "CAMERA: shutter present")
	expect(cam.get_node_or_null("LightMeter") is LinearGauge, "CAMERA: light meter present")
	expect(cam.get_node_or_null("StillnessMeter") is LinearGauge, "CAMERA: stillness meter present")
	var noise: Gauge = st.get_node("NoiseGauge") as Gauge
	expect(noise != null, "NoiseGauge is a Gauge")
	if noise != null:
		expect_eq(noise.source_group, &"acoustics_readouts", "NOISE reads the acoustics readouts")
		expect_eq(noise.readout, &"sub_db", "NOISE reads sub_db")
		expect_eq(noise.readout_b, &"ambient_db", "NOISE has the ocean needle")
	st.queue_free()


func test_size_and_mount_face() -> void:
	var st: Node3D = _make()
	var box: AABB = _bounds(st, st)
	expect(box.size.x <= MAX_ALONG_M + 0.0001, "at most 1.2 m along the hull (%.3f)" % box.size.x)
	expect(box.end.z <= MAX_DEEP_M + 0.0001, "at most 0.45 m deep (%.3f)" % box.end.z)
	expect(box.position.z >= -0.001, "nothing behind Z=0 (%.4f)" % box.position.z)
	expect(box.position.y >= -1.1001, "nothing below the floor")
	var eye: Node3D = st.get_node("OperatorEye") as Node3D
	expect_near(eye.position.y, 0.55, 0.001, "eye height")
	expect_near(eye.position.z, 0.5, 0.001, "eye distance out")
	expect_near((st.get_node("OperatorPoint") as Node3D).position.y, -1.1, 0.001, "the operator's feet on the floor")
	st.queue_free()


func test_modules_sit_between_waist_and_eye() -> void:
	var st: Node3D = _make()
	var eye_y: float = (st.get_node("OperatorEye") as Node3D).position.y
	for bay: String in BAYS:
		var b: AABB = _bounds(st, _module(st, bay))
		expect(b.position.y >= WAIST_Y_M, "%s: lowest point %.2f at or above the waist" % [bay, b.position.y])
		expect(b.end.y <= eye_y, "%s: highest point %.2f at or below the eye" % [bay, b.end.y])
	st.queue_free()


func test_grab_boxes_apart() -> void:
	var st: Node3D = _make()
	var names: Array[String] = ["Bay0", "Bay1", "Bay2", "NoiseGauge"]
	var boxes: Array[AABB] = []
	for n: String in names:
		boxes.append(_bounds(st, st.get_node(n)))
	for a: int in names.size():
		for b: int in range(a + 1, names.size()):
			var grown: AABB = boxes[a].grow(0.0099)
			expect(not grown.intersects(boxes[b]), "%s and %s at least 10 mm apart" % [names[a], names[b]])
	st.queue_free()


func test_controls_within_reach_of_the_shoulder() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var shoulder: Vector3 = eye - Vector3(0.0, SHOULDER_DROP_M, 0.0)
	for n: String in BAYS + ["NoiseGauge"]:
		var b: AABB = _bounds(st, st.get_node(n))
		var far: float = 0.0
		for i: int in 8:
			far = maxf(far, shoulder.distance_to(b.get_endpoint(i)))
		expect(far <= REACH_M, "%s is %.2f m from the shoulder at its farthest" % [n, far])
	st.queue_free()


func _blocked(st: Node3D, eye: Vector3, to: Vector3, owner: Node) -> String:
	for n: String in BAYS + ["NoiseGauge"]:
		var c: Node = st.get_node(n)
		if c == owner:
			continue
		if _bounds(st, c).intersects_segment(eye, to):
			return n
	return ""


func test_displays_are_in_view_of_the_eye_and_face_it() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	for n: String in BAYS + ["NoiseGauge"]:
		var node: Node3D = st.get_node(n) as Node3D
		var z: float = 0.056 if n != "NoiseGauge" else 0.014
		var points: Array[Vector3] = [node.position + node.transform.basis.z * z]
		if n != "NoiseGauge":
			points.append(node.position + node.transform.basis * Vector3(-0.11, 0.04, z))
			points.append(node.position + node.transform.basis * Vector3(0.11, 0.04, z))
		for p: Vector3 in points:
			var by: String = _blocked(st, eye, p, node)
			expect(by == "", "%s is in view of the eye%s" % [n, "" if by == "" else " (blocked by %s)" % by])
			var normal: Vector3 = node.transform.basis.z.normalized()
			var v: Vector3 = (eye - p).normalized()
			expect(normal.dot(v) > cos(deg_to_rad(FACE_MAX_DEG)), "%s faces the eye (%.0f deg off its normal)" % [n, rad_to_deg(acos(normal.dot(v)))])
	st.queue_free()


func test_a_different_loadout_fits_any_bay() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var shoulder: Vector3 = eye - Vector3(0.0, SHOULDER_DROP_M, 0.0)
	for bay: String in BAYS:
		var anchor: Node3D = st.get_node(bay) as Node3D
		for path: String in MODULE_SCENES:
			var m: Node3D = _fit(st, bay, path)
			var b: AABB = _bounds(st, m)
			var tag: String = "%s in %s" % [path.get_file().get_basename(), bay]
			expect(b.size.x <= 0.35, "%s: %.3f m wide fits the bay" % [tag, b.size.x])
			expect(absf(b.get_center().x - anchor.position.x) < 0.01, "%s: centred in its bay" % tag)
			expect(b.position.y >= WAIST_Y_M and b.end.y <= eye.y, "%s: between waist and eye" % tag)
			expect(b.end.z <= MAX_DEEP_M, "%s: within the station's depth" % tag)
			var far: float = 0.0
			for i: int in 8:
				far = maxf(far, shoulder.distance_to(b.get_endpoint(i)))
			expect(far <= REACH_M, "%s: %.2f m from the shoulder at its farthest" % [tag, far])
			for other: String in BAYS:
				if other != bay:
					expect(not b.grow(0.0099).intersects(_bounds(st, _module(st, other))), "%s: clear of %s" % [tag, other])
	st.queue_free()


func test_an_empty_bay_renders() -> void:
	var st: Node3D = _make()
	var anchor: Node3D = st.get_node("Bay1") as Node3D
	var mod: Node = anchor.get_node("Module")
	anchor.remove_child(mod)
	mod.free()
	var body: AABB = _bounds(st, st.get_node("Body"))
	expect(body.size.x > 0.0, "the housing has meshes")
	var pocket: Vector3 = anchor.position - anchor.transform.basis.z * 0.03
	expect(body.has_point(pocket), "the empty bay's pocket lies in the housing's meshes")
	# The pocket is open: the housing's own mesh has a surface for the dark liner, apart from the panel colour.
	var surfaces: int = 0
	var stack: Array[Node] = [st.get_node("Body")]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null and mi.mesh != null:
			surfaces += mi.mesh.get_surface_count()
		stack.append_array(c.get_children())
	expect(surfaces >= 3, "housing, liners and trim are separate surfaces (%d)" % surfaces)
	st.queue_free()


func test_modules_stand_proud_of_the_face_and_pockets_are_set_back() -> void:
	var st: Node3D = _make()
	for bay: String in BAYS:
		var anchor: Node3D = st.get_node(bay) as Node3D
		expect(anchor.transform.basis.z.y > 0.1, "%s faces up toward the eye (raked back)" % bay)
		expect(anchor.transform.basis.z.dot(Vector3.BACK) > 0.9, "%s still faces out into the aisle" % bay)
		expect_near(_module(st, bay).position.length(), 0.0, 0.0001, "the module is at its anchor")
	st.queue_free()


func test_controls_work_in_place() -> void:
	var st: Node3D = _make()
	var scan: ScanModule = _module(st, "Bay0") as ScanModule
	var sw: SwitchLever = scan.arm_switch
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.max_value, "a click throws SCAN's arm switch")
	var shutter: PushButton = _module(st, "Bay2").get_node("Shutter") as PushButton
	shutter.begin_interaction()
	shutter.click_action()
	expect_eq(shutter.get_value(), shutter.max_value, "the shutter presses")
	shutter.end_interaction()
	expect_eq(shutter.get_value(), shutter.min_value, "and springs back")
	st.queue_free()


func test_housing_is_shallow_with_an_upper_panel_holding_the_noise_gauge() -> void:
	var st: Node3D = _make()
	var box: AABB = _bounds(st, st)
	expect(box.end.z <= 0.25, "the whole station stands at most 0.25 m out (%.3f)" % box.end.z)
	var body: AABB = _bounds(st, st.get_node("Body"))
	expect(body.end.z <= 0.21, "the housing alone is shallow (%.3f)" % body.end.z)
	var gauge: AABB = _bounds(st, st.get_node("NoiseGauge"))
	for bay: String in BAYS:
		expect(gauge.position.y > _bounds(st, _module(st, bay)).end.y, "the noise gauge is on the upper panel, above %s" % bay)
	st.queue_free()


func test_modules_sit_in_bays_with_a_narrow_gap_all_round() -> void:
	var st: Node3D = _make()
	for bay: String in BAYS:
		var anchor: Node3D = st.get_node(bay) as Node3D
		var plate: AABB = _bounds(st, _module(st, bay))
		expect(plate.size.x >= 0.33 and plate.size.x <= 0.35, "%s: the module is about 0.34 m wide (%.3f)" % [bay, plate.size.x])
		# the module's rear mount is inside the housing: its back, 0.044 m behind the plate, is behind the housing's front face
		var back: Vector3 = anchor.position + anchor.transform.basis.z * 0.0
		var body: AABB = _bounds(st, st.get_node("Body"))
		expect(body.has_point(back - anchor.transform.basis.z * 0.01), "%s: the module's back lies inside the housing" % bay)
	st.queue_free()
