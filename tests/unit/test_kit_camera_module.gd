extends TestCase
## The kit camera module: a CameraModule on the science frame, with a hooded viewfinder, two meters and a shutter.

const SCENE: String = "res://assets/models/kit/camera_module/camera_module.tscn"
const BAY_WIDTH: float = 0.35
const STAND_OUT: float = 0.125


func _make() -> CameraModule:
	var m: CameraModule = (load(SCENE) as PackedScene).instantiate() as CameraModule
	runner.add_child(m)
	return m


func _bounds(n: Node3D, root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null:
			var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_script_is_present() -> void:
	var m: CameraModule = _make()
	expect(m != null, "root is a CameraModule")
	expect(m.module_type == ModuleLoadout.Type.CAMERA, "it is the CAMERA type")
	expect(m.get_node_or_null("Frame") != null, "chassis present")
	expect(m.get_node_or_null("Face") != null, "face (viewfinder and hood) present")
	m.queue_free()


func test_shutter_springs_back() -> void:
	var m: CameraModule = _make()
	var b: PushButton = m.get_node_or_null("Shutter") as PushButton
	expect(b != null, "shutter is a PushButton")
	b.begin_interaction()
	b.click_action()
	expect_eq(b.get_value(), b.max_value, "pressed: held")
	b.end_interaction()
	expect_eq(b.get_value(), b.min_value, "released: springs back")
	m.queue_free()


func test_indicators_are_wired() -> void:
	var m: CameraModule = _make()
	for pair: Array in [["LightMeter", &"light"], ["StillnessMeter", &"stillness"]]:
		var g: LinearGauge = m.get_node_or_null(pair[0] as String) as LinearGauge
		expect(g != null, "%s is a LinearGauge" % pair[0])
		expect_eq(g.source_group, &"camera_modules", "%s reads the camera modules" % pair[0])
		expect_eq(g.readout, pair[1] as StringName, "%s shows its readout" % pair[0])
		expect(m.is_in_group(g.source_group), "the module is in the group the gauge reads")
		expect_eq(m.readout(g.readout), 0.0, "%s readout resolves (no objective: zero)" % pair[0])
	m.queue_free()


func test_hood_stays_in_its_bay() -> void:
	var m: CameraModule = _make()
	var hood: AABB = _bounds(m.get_node("Face") as Node3D, m)
	expect(hood.position.x >= -BAY_WIDTH / 2.0 and hood.end.x <= BAY_WIDTH / 2.0, "hood within its own bay width: %s" % hood)
	var b: Node3D = m.get_node("Shutter") as Node3D
	expect(b.position.x - 0.012 > hood.end.x, "shutter clear of the hood: %s vs %s" % [b.position, hood])
	m.queue_free()


func test_fits_the_bay() -> void:
	var m: CameraModule = _make()
	var b: AABB = _bounds(m, m)
	expect(b.size.x <= BAY_WIDTH + 0.001, "within the 0.35 m bay: %s" % b)
	expect(b.position.z >= -0.001, "nothing behind the mount face: %s" % b)
	expect(b.end.z <= STAND_OUT + 0.001, "stands out at most 125 mm: %s" % b)
	m.queue_free()
