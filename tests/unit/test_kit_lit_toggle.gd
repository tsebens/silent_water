extends TestCase
## The kit lit toggle: an unguarded SwitchLever on a 1x3 base with an indicator lamp above it.

const SCENE: String = "res://assets/models/kit/lit_toggle/lit_toggle.tscn"


func _make() -> SwitchLever:
	var s: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(s)
	return s


func _lamp(s: SwitchLever) -> IndicatorLamp:
	return s.get_node("IndicatorLamp") as IndicatorLamp


func test_wiring_is_present() -> void:
	var s: SwitchLever = _make()
	expect(s != null, "root is a SwitchLever")
	expect(s.indicator != null and s.indicator == _lamp(s), "indicator points at the IndicatorLamp node")
	expect(_lamp(s).lamp != null, "the lamp's lens mesh is set")
	expect(_lamp(s).get_node_or_null("Lens") != null, "lens GLB sits under IndicatorLamp")
	expect(s.pivot != null and s.get_node_or_null("Pivot/Bat") != null, "bat hangs on the pivot")
	s.queue_free()


func test_lamp_follows_the_switch_with_no_setup() -> void:
	var s: SwitchLever = _make()
	expect(not _lamp(s).is_lit(), "dark at off")
	s.host_set_value(s.max_value)
	expect(_lamp(s).is_lit(), "lit at on")
	var mat: BaseMaterial3D = _lamp(s).lamp.material_override as BaseMaterial3D
	expect(mat != null and mat.emission_enabled, "lit lens emits")
	s.host_set_value(s.min_value)
	expect(not _lamp(s).is_lit(), "dark again at off")
	s.queue_free()


func test_bat_works_at_both_ends() -> void:
	var s: SwitchLever = _make()
	s.host_set_value(s.max_value)
	expect_near(s.pivot.rotation.x, -deg_to_rad(s.swing_deg * 0.5), 1e-4, "on: bat up")
	s.host_set_value(s.min_value)
	expect_near(s.pivot.rotation.x, deg_to_rad(s.swing_deg * 0.5), 1e-4, "off: bat down")
	expect_eq(s._release_value(0.8), s.max_value, "snaps to on")
	expect_eq(s._release_value(0.2), s.min_value, "snaps to off")
	s.queue_free()


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


func test_footprint_and_stand_out_match_the_entry() -> void:
	var s: SwitchLever = _make()
	s.host_set_value(s.min_value)
	var b: AABB = _bounds(s, s)
	expect(b.size.x <= 0.0561 and b.size.y <= 0.1761, "within the 56 x 176 mm footprint: %s" % b)
	expect(b.position.z >= -0.0001, "nothing behind the mount face: %s" % b)
	expect(b.end.z <= 0.0561, "no more than 56 mm out: %s" % b)
	var bat: AABB = _bounds(s.get_node("Pivot") as Node3D, s)
	expect(bat.end.z > 0.0559 - 0.012, "bat tip stands out near the stated 56 mm at its extreme: %s" % bat)
	expect(_bounds(_lamp(s), s).position.y > bat.end.y, "lamp sits above the bat's swing")
	s.queue_free()
