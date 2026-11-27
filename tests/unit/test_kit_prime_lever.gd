extends TestCase
## The generated prime lever: a SwitchLever whose off end holds the arm up and whose on end (primed) holds it down.

const SCENE: String = "res://assets/models/kit/prime_lever/prime_lever.tscn"
const ARM_LEN: float = 0.210
## Arm elevation in degrees above the +Z mount axis at the two ends (component.yaml swing_envelope).
const UP_DEG: float = 50.0
const DOWN_DEG: float = -30.0


func _make() -> SwitchLever:
	var s: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(s)
	return s


## The grip's centre in the root's frame: the pivot's transform applied to the arm's end (arm mid-throw is 10 deg up).
func _grip(s: SwitchLever) -> Vector3:
	var lift: float = deg_to_rad(10.0)
	return s.pivot.transform * Vector3(0.0, ARM_LEN * sin(lift), ARM_LEN * cos(lift))


func _elevation(s: SwitchLever) -> float:
	var g: Vector3 = _grip(s) - s.pivot.position
	return rad_to_deg(atan2(g.y, g.z))


func test_root_is_a_switch_lever_with_the_arm_bound() -> void:
	var s: SwitchLever = _make()
	expect(s != null, "root is a SwitchLever")
	expect(s.pivot != null and s.pivot.name == &"Pivot", "pivot bound")
	expect(s.pivot.get_node_or_null("Arm") != null, "arm under the pivot")
	s.queue_free()


func test_both_states_are_read() -> void:
	var s: SwitchLever = _make()
	expect_eq(s.get_value(), s.min_value, "starts off")
	expect_near(_elevation(s), UP_DEG, 0.01, "off: arm up")
	s.host_set_value(s.max_value)
	expect_eq(s.get_value(), s.max_value, "on reads back")
	expect_near(_elevation(s), DOWN_DEG, 0.01, "on (primed): arm down")
	expect(_grip(s).y < 0.0, "grip below the pivot axis when primed")
	s.host_set_value(s.min_value)
	expect(_grip(s).y > 0.0, "grip above the axis at off")
	s.queue_free()


func test_throw_snaps_and_stays_down() -> void:
	var s: SwitchLever = _make()
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.max_value, "a throw sets it on")
	expect_near(_elevation(s), DOWN_DEG, 0.01, "and the arm stays down")
	s.begin_interaction()
	s.click_action()
	s.end_interaction()
	expect_eq(s.get_value(), s.min_value, "a second throw lifts it off")
	s.queue_free()


func test_arm_is_long_and_grip_is_orange() -> void:
	var s: SwitchLever = _make()
	var arm: Node = s.pivot.get_node("Arm")
	var mi: MeshInstance3D = _first_mesh(arm)
	expect(mi != null, "arm has a mesh")
	expect_eq(mi.mesh.get_surface_count(), 2, "arm and grip are two surfaces")
	var size: AABB = mi.get_aabb()
	expect(size.size.z > 0.2, "arm reads long (%s)" % size.size)
	expect(size.size.x >= 0.05, "grip is at least 50 mm across")
	s.queue_free()


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c: Node in n.get_children():
		var m: MeshInstance3D = _first_mesh(c)
		if m != null:
			return m
	return null
