extends TestCase
## The kit rocker switch: a SwitchLever on a 1x2 base, a black paddle in an orange bezel, an LED strip on the paddle.

const SCENE: String = "res://assets/models/kit/rocker_switch/rocker_switch.tscn"


func _make() -> SwitchLever:
	var s: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(s)
	return s


func _strip(s: SwitchLever) -> IndicatorLamp:
	return s.get_node("Pivot/Paddle/LedStrip") as IndicatorLamp


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


## The paddle's own meshes only (not the strip), in the switch's frame.
func _paddle_bounds(s: SwitchLever) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for c: Node in (s.get_node("Pivot/Paddle") as Node3D).get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null:
			var b: AABB = s.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out


func test_wiring_is_present() -> void:
	var s: SwitchLever = _make()
	expect(s != null, "root is a SwitchLever")
	expect(s.indicator != null and s.indicator == _strip(s), "indicator points at the paddle's strip")
	expect(_strip(s).lamp != null, "the strip's lens mesh is set")
	expect(s.pivot != null and s.get_node_or_null("Pivot/Paddle") != null, "paddle hangs on the pivot")
	expect(s.get_node_or_null("IndicatorLamp") == null, "no round lamp")
	s.queue_free()


func test_strip_follows_the_switch_with_no_setup() -> void:
	var s: SwitchLever = _make()
	expect(not _strip(s).is_lit(), "dark at off")
	s.host_set_value(s.max_value)
	expect(_strip(s).is_lit(), "lit at on")
	var mat: BaseMaterial3D = _strip(s).lamp.material_override as BaseMaterial3D
	expect(mat != null and mat.emission_enabled, "lit strip emits")
	s.host_set_value(s.min_value)
	expect(not _strip(s).is_lit(), "dark again at off")
	s.queue_free()


func test_on_presses_the_upper_half_in() -> void:
	var s: SwitchLever = _make()
	for at_max: bool in [true, false]:
		s.host_set_value(s.max_value if at_max else s.min_value)
		var p: AABB = _paddle_bounds(s)
		var mid: float = p.position.y + p.size.y * 0.5
		# The paddle's front face is a plane tilted about the pivot: sample its depth in each half.
		var front_upper: float = s.to_local(s.get_node("Pivot/Paddle").to_global(Vector3(0.0, 0.009, 0.002))).z
		var front_lower: float = s.to_local(s.get_node("Pivot/Paddle").to_global(Vector3(0.0, -0.009, 0.002))).z
		expect(mid > -0.001 and mid < 0.001, "paddle is centred on its pivot in Y: %f" % mid)
		if at_max:
			expect(front_upper < front_lower, "on: upper half is deeper in Z than the lower half (%f < %f)" % [front_upper, front_lower])
		else:
			expect(front_upper > front_lower, "off: lower half is deeper in Z than the upper half (%f > %f)" % [front_lower, front_upper])
	s.queue_free()


func test_strip_stays_in_the_upper_half_at_both_ends() -> void:
	var s: SwitchLever = _make()
	for v: float in [s.min_value, s.max_value]:
		s.host_set_value(v)
		var pad: Node3D = s.get_node("Pivot/Paddle") as Node3D
		var b: AABB = pad.global_transform.affine_inverse() * _strip(s).lamp.global_transform * _strip(s).lamp.get_aabb()
		expect(b.position.y > 0.0 and b.end.y < 0.018, "strip in the paddle's upper half: %s" % b)
		expect(b.position.x > -0.010 and b.end.x < 0.010, "strip within the paddle's width: %s" % b)
	s.queue_free()


func test_click_flips_the_rocker() -> void:
	var s: SwitchLever = _make()
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.max_value, "click: on")
	expect(_strip(s).is_lit(), "strip lit")
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.min_value, "second click: off")
	expect(not _strip(s).is_lit(), "strip dark")
	s.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var s: SwitchLever = _make()
	for v: float in [s.min_value, s.max_value]:
		s.host_set_value(v)
		var b: AABB = _bounds(s, s)
		expect(b.size.x <= 0.0561 and b.size.y <= 0.1161, "within the 56 x 116 mm footprint: %s" % b)
		expect(b.position.z >= -0.0001, "nothing behind the mount face: %s" % b)
		expect(b.end.z <= 0.0201, "low profile, no more than 20 mm out: %s" % b)
		var pad: AABB = _paddle_bounds(s)
		expect(pad.position.x >= -0.012 and pad.end.x <= 0.012 and pad.position.y >= -0.021 and pad.end.y <= 0.021,
				"paddle inside the bezel opening: %s" % pad)
	s.queue_free()
