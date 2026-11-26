extends TestCase
## The kit SCAN module: a ScanModule on the science module frame, with a ring screen and an arm switch.

const SCENE: String = "res://assets/models/kit/scan_module/scan_module.tscn"
const BAY_WIDTH: float = 0.35
const MAX_TRIS_STAND_OUT: float = 0.130


func _make() -> ScanModule:
	var m: ScanModule = (load(SCENE) as PackedScene).instantiate() as ScanModule
	runner.add_child(m)
	return m


func _bounds(n: Node3D, root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null and mi.mesh != null:
			var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_has_the_scan_module_script_and_wiring() -> void:
	var m: ScanModule = _make()
	expect(m != null, "root is a ScanModule")
	expect(m.module_type == ModuleLoadout.Type.SCAN, "it is the SCAN type")
	expect(m.arm_switch != null and m.arm_switch == m.get_node_or_null("ArmSwitch"), "arm_switch is the ArmSwitch node")
	expect(m.get_node_or_null("Frame") != null, "the module frame is present")
	m.queue_free()


func test_switch_works_at_both_ends() -> void:
	var m: ScanModule = _make()
	var sw: SwitchLever = m.arm_switch
	expect(not m.armed, "stopped at the start")
	sw.host_set_value(sw.max_value)
	expect(m.armed, "switch on arms the module")
	sw.host_set_value(sw.min_value)
	expect(not m.armed, "switch off stops it")
	m.toggle_armed()
	expect(sw.get_value() >= sw.max_value, "arming the module throws the switch on")
	m.set_powered(false)
	expect(not m.armed and sw.get_value() <= sw.min_value, "a power loss throws the switch off")
	sw.host_set_value(sw.max_value)
	expect(not m.armed and sw.get_value() <= sw.min_value, "unpowered, the switch will not stay on")
	m.queue_free()


func test_screen_is_drawn_facing_the_eye() -> void:
	var m: ScanModule = _make()
	var s: ScanScreen = m.get_node("Screen") as ScanScreen
	expect(s != null and s.mesh is QuadMesh, "the Screen is a ScanScreen quad")
	expect(s.global_transform.basis.z.normalized().dot(Vector3.BACK) > 0.999, "the quad faces +Z")
	expect(s.drawn_fill >= 0.0, "the ring has been drawn")
	var bezel: AABB = _bounds(m.get_node("Bezel") as Node3D, m)
	expect(s.position.z > bezel.position.z and s.position.z < bezel.end.z, "the screen is recessed in the bezel")
	expect(absf(s.position.x - bezel.get_center().x) < 0.001, "the screen is centred in the bezel")
	s.draw_ring(0.25)
	var c: int = s.resolution / 2
	var lit: Color = s.image.get_pixel(c, int(float(c) * 0.15))
	var dim: Color = s.image.get_pixel(c, s.resolution - 1 - int(float(c) * 0.15))
	expect(lit != dim, "the filled and unfilled ends of the ring differ")
	m.set_powered(false)
	s.refresh()
	expect(not s.range_label.visible, "the readout is dark when unpowered")
	m.queue_free()


func test_fits_the_bay_and_reaches() -> void:
	var m: ScanModule = _make()
	var box: AABB = _bounds(m, m)
	expect(box.size.x <= BAY_WIDTH + 0.001, "within the 0.35 m bay: %s" % box)
	expect(box.position.z >= -0.001, "nothing behind the mount face: %s" % box)
	expect(box.end.z <= MAX_TRIS_STAND_OUT + 0.001, "stands out at most 130 mm: %s" % box)
	var sw: AABB = _bounds(m.arm_switch, m)
	var screen: Vector3 = (m.get_node("Screen") as Node3D).position
	expect(absf(sw.get_center().x - screen.x) > 0.08, "the switch sits apart from the screen")
	m.queue_free()
