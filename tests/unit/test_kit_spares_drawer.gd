extends TestCase
## The kit spares drawer: four slot nodes for stand-in breaker modules, driven by SparesDrawer.

const SCENE: String = "res://assets/models/kit/spares_drawer/spares_drawer.tscn"
const SLOT_NAMES: Array[String] = ["Spare1", "Spare2", "Spare3", "Spare4"]


func _make() -> Node3D:
	var s: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(s)
	return s


func _bounds(root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null:
			var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_root_and_slots() -> void:
	var s: Node3D = _make()
	expect(s.name == &"SparesDrawer", "root is SparesDrawer")
	var d: SparesDrawer = s.get_node_or_null("Drawer") as SparesDrawer
	expect(d != null, "Drawer node carries SparesDrawer")
	if d != null:
		expect(d.slots.size() == 4, "4 slots wired: %d" % d.slots.size())
		for i: int in d.slots.size():
			expect(d.slots[i] != null and d.slots[i].name == SLOT_NAMES[i], "slot %d is %s" % [i, SLOT_NAMES[i]])
	for n: String in SLOT_NAMES:
		expect(s.get_node_or_null(n) != null, "%s present" % n)
	s.queue_free()


func test_slots_follow_the_readout() -> void:
	var s: Node3D = _make()
	var d: SparesDrawer = s.get_node("Drawer") as SparesDrawer
	d.power = null
	d.refresh()
	for sl: Node3D in d.slots:
		expect(not sl.visible, "no power system: no spares shown")
	s.queue_free()


func test_meshes_fit_the_footprint() -> void:
	var s: Node3D = _make()
	var b: AABB = _bounds(s)
	expect(b.size.x <= 0.9001, "at most 0.9 m wide: %s" % b)
	expect(b.size.y <= 0.2501, "at most 0.25 m tall: %s" % b)
	expect(b.position.z >= -0.0001 and b.end.z <= 0.3001, "within 0.3 m out, nothing behind: %s" % b)
	s.queue_free()
