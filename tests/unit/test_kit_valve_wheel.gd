extends TestCase
## The generated valve wheel: a Valve with its wheel bound, inside the stated footprint, turning to both end angles.

const SCENE: String = "res://assets/models/kit/valve_wheel/valve_wheel.tscn"
const FOOTPRINT_X: float = 0.2001
const FOOTPRINT_Y: float = 0.1201
const STAND_OUT: float = 0.1301


func _make() -> Valve:
	var v: Valve = (load(SCENE) as PackedScene).instantiate() as Valve
	runner.add_child(v)
	return v


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_root_is_a_valve_with_the_wheel_bound() -> void:
	var v: Valve = _make()
	expect(v != null, "root is a Valve")
	expect(v.wheel != null and v.wheel.name == &"Wheel", "wheel bound")
	v.queue_free()


func test_mesh_fits_the_stated_footprint() -> void:
	var v: Valve = _make()
	var ms: Array[MeshInstance3D] = []
	_meshes(v, ms)
	expect(ms.size() >= 2, "body and wheel meshes")
	var all: AABB
	var first: bool = true
	for m: MeshInstance3D in ms:
		var box: AABB = v.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		all = box if first else all.merge(box)
		first = false
	expect(all.size.x <= FOOTPRINT_X and all.size.y <= FOOTPRINT_Y, "within 200 x 120 mm: %s" % all)
	expect(all.position.z >= -0.0001, "nothing behind the mount face: %s" % all)
	expect(all.end.z <= STAND_OUT, "stands out at most 130 mm: %s" % all)
	v.queue_free()


func test_wheel_reaches_its_two_end_angles() -> void:
	var v: Valve = _make()
	v.host_set_value(0.0)
	expect_near(v.wheel.rotation.z, 0.0, 0.0001, "closed")
	v.host_set_value(1.0)
	expect_near(v.wheel.rotation.z, -v.turns_full_range * TAU, 0.0001, "open")
	v.queue_free()


func test_grab_box_clears_the_wheel_rim() -> void:
	var v: Valve = _make()
	var grab: Node = v.get_node_or_null("Grab/Shape")
	expect(grab != null, "grab box present")
	var shape: BoxShape3D = (grab as CollisionShape3D).shape as BoxShape3D
	expect(shape.size.x >= 0.12 and shape.size.y >= 0.12, "grab box wider than the rim: %s" % shape.size)
	v.queue_free()
