extends TestCase
## The kit bat toggle: a lit SwitchLever on a 1x2 base, a ridged paddle in a recessed bay with an LED loop round it.

const SCENE: String = "res://assets/models/kit/bat_toggle/bat_toggle.tscn"


func _make() -> SwitchLever:
	var s: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(s)
	return s


func _lamp(s: SwitchLever) -> IndicatorLamp:
	return s.get_node("IndicatorLamp") as IndicatorLamp


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


func test_wiring_is_present() -> void:
	var s: SwitchLever = _make()
	expect(s != null, "root is a SwitchLever")
	expect(s.indicator != null and s.indicator == _lamp(s), "indicator points at the IndicatorLamp node")
	expect(_lamp(s).lamp != null, "the loop's lens mesh is set")
	expect(_lamp(s).get_node_or_null("Lens") != null, "loop GLB sits under IndicatorLamp")
	expect(s.pivot != null and s.get_node_or_null("Pivot/Paddle") != null, "paddle hangs on the pivot")
	s.queue_free()


func test_loop_follows_the_switch_with_no_setup() -> void:
	var s: SwitchLever = _make()
	expect(not _lamp(s).is_lit(), "dark at off")
	s.host_set_value(s.max_value)
	expect(_lamp(s).is_lit(), "lit at on")
	var mat: BaseMaterial3D = _lamp(s).lamp.material_override as BaseMaterial3D
	expect(mat != null and mat.emission_enabled, "lit loop emits")
	s.host_set_value(s.min_value)
	expect(not _lamp(s).is_lit(), "dark again at off")
	s.queue_free()


func test_both_ends_of_travel_are_reached() -> void:
	var s: SwitchLever = _make()
	s.host_set_value(s.max_value)
	expect_near(s.pivot.rotation.x, -deg_to_rad(s.swing_deg * 0.5), 1e-4, "on: upper end in")
	s.host_set_value(s.min_value)
	expect_near(s.pivot.rotation.x, deg_to_rad(s.swing_deg * 0.5), 1e-4, "off: upper end out")
	s.queue_free()


func test_click_flips_the_switch_and_its_loop() -> void:
	var s: SwitchLever = _make()
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.max_value, "click: on")
	expect(_lamp(s).is_lit(), "loop lit")
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.min_value, "second click: off")
	expect(not _lamp(s).is_lit(), "loop dark")
	s.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var s: SwitchLever = _make()
	var worst: float = 0.0
	for v: float in [s.min_value, s.max_value]:
		s.host_set_value(v)
		var b: AABB = _bounds(s, s)
		expect(b.size.x <= 0.0561 and b.size.y <= 0.1161, "within the 56 x 116 mm footprint: %s" % b)
		expect(b.position.z >= -0.0001, "nothing behind the mount face: %s" % b)
		worst = maxf(worst, b.end.z)
	expect(worst <= 0.0251, "no more than 25 mm out at either end: %f" % worst)
	expect(worst >= 0.0235, "stands out near the stated 25 mm at its extreme: %f" % worst)
	var paddle: AABB = _bounds(s.get_node("Pivot") as Node3D, s)
	expect(paddle.size.y < 0.062 and paddle.size.x < 0.026, "paddle inside the 26 x 62 mm bay: %s" % paddle)
	s.queue_free()
