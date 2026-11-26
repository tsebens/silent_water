extends TestCase
## The kit sweep module: a SweepModule on the science frame, with a coverage-grid screen and an arm switch.

const SCENE: String = "res://assets/models/kit/sweep_module/sweep_module.tscn"
const BAY_WIDTH: float = 0.35
const STAND_OUT: float = 0.125


func _make() -> SweepModule:
	var m: SweepModule = (load(SCENE) as PackedScene).instantiate() as SweepModule
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
	var m: SweepModule = _make()
	expect(m != null, "root is a SweepModule")
	expect(m.module_type == ModuleLoadout.Type.SWEEP, "it is the SWEEP type")
	expect(m.get_node_or_null("Frame") != null, "chassis present")
	m.queue_free()


func test_switch_works() -> void:
	var m: SweepModule = _make()
	var sw: SwitchLever = m.get_node_or_null("ArmSwitch") as SwitchLever
	expect(sw != null, "arm switch is a SwitchLever")
	sw.value_changed.connect(func(_v: float) -> void: m.toggle_armed())
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.max_value, "click: switch on")
	expect(m.armed, "switch on arms the module")
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect_eq(sw.get_value(), sw.min_value, "second click: switch off")
	expect(not m.armed, "switch off disarms it")
	m.queue_free()


func test_screen_is_drawn_and_faces_the_eye() -> void:
	var m: SweepModule = _make()
	var screen: Node3D = m.get_node_or_null("Screen") as Node3D
	expect(screen != null, "screen node present")
	var b: AABB = _bounds(screen, m)
	expect(b.size.x > 0.15 and b.size.y > 0.15, "screen is large enough to read: %s" % b)
	expect(b.position.z > 0.05, "screen sits in front of the face plate: %s" % b)
	var meshes: int = 0
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			meshes += 1
		stack.append_array(c.get_children())
	expect(meshes > 0, "screen has meshes")
	m.queue_free()


func test_fits_the_bay() -> void:
	var m: SweepModule = _make()
	var b: AABB = _bounds(m, m)
	expect(b.size.x <= BAY_WIDTH + 0.001, "within the 0.35 m bay: %s" % b)
	expect(b.position.z >= -0.001, "nothing behind the mount face: %s" % b)
	expect(b.end.z <= STAND_OUT + 0.001, "stands out at most 125 mm: %s" % b)
	m.queue_free()
