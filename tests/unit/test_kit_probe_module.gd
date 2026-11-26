extends TestCase
## The kit probe module: a ProbeModule on the science frame, with a cable reel, depth counter, point list and winch switch.

const SCENE: String = "res://assets/models/kit/probe_module/probe_module.tscn"
const BAY_WIDTH: float = 0.35
const STAND_OUT: float = 0.125


func _make() -> ProbeModule:
	var m: ProbeModule = (load(SCENE) as PackedScene).instantiate() as ProbeModule
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
	var m: ProbeModule = _make()
	expect(m != null, "root is a ProbeModule")
	expect(m.module_type == ModuleLoadout.Type.PROBE, "it is the PROBE type")
	expect(m.get_node_or_null("Frame") != null, "chassis present")
	expect(m.get_node_or_null("Face") != null, "face (counter and list screens) present")
	m.queue_free()


func test_reel_pivot_turns() -> void:
	var m: ProbeModule = _make()
	var pivot: Node3D = m.get_node_or_null("ReelPivot") as Node3D
	var reel: Node3D = m.get_node_or_null("ReelPivot/Reel") as Node3D
	expect(pivot != null and reel != null, "reel sits under its pivot")
	var before: Vector3 = reel.global_transform.basis.y
	pivot.rotation.z = PI / 2.0
	var after: Vector3 = reel.global_transform.basis.y
	expect(before.distance_to(after) > 1.0, "turning the pivot turns the reel: %s -> %s" % [before, after])
	var b: AABB = _bounds(reel, m)
	var centre: Vector3 = b.get_center()
	expect(absf(centre.x - pivot.position.x) < 0.005 and absf(centre.y - pivot.position.y) < 0.005,
		"reel turns about its own axis: %s vs %s" % [centre, pivot.position])
	expect(b.position.z > 0.056, "reel stays in front of the face plate: %s" % b)
	m.queue_free()


func test_counter_reads_depth() -> void:
	var m: ProbeModule = _make()
	var o: ProbeObjective = ProbeObjective.new()
	m.objective = o
	o.module = m
	m.armed = true
	expect_eq(m.counter_m(), 0.0, "counter at zero with the line in")
	o.nudge(1)
	expect(m.counter_m() > 0.0, "counter reads line out after lowering")
	expect_eq(m.counter_m(), o.counter(), "module counter is the objective's")
	var pivot: Node3D = m.get_node("ReelPivot") as Node3D
	pivot.rotation.z = m.reel_angle()
	expect(is_equal_approx(pivot.rotation.z, o.reel_angle()), "reel angle follows the line")
	o.free()
	m.queue_free()


func test_switch_works() -> void:
	var m: ProbeModule = _make()
	var sw: SwitchLever = m.get_node_or_null("WinchSwitch") as SwitchLever
	expect(sw != null, "winch switch is a SwitchLever")
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


func test_fits_the_bay() -> void:
	var m: ProbeModule = _make()
	var b: AABB = _bounds(m, m)
	expect(b.size.x <= BAY_WIDTH + 0.001, "within the 0.35 m bay: %s" % b)
	expect(b.position.z >= -0.001, "nothing behind the mount face: %s" % b)
	expect(b.end.z <= STAND_OUT + 0.001, "stands out at most 125 mm: %s" % b)
	m.queue_free()
