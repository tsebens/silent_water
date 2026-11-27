extends TestCase
## The decoy scene: modelled body with DecoyItem bound, lying along -Z.

const SCENE: String = "res://assets/models/furniture/decoy/decoy.tscn"


func _make() -> DecoyItem:
	var d: DecoyItem = (load(SCENE) as PackedScene).instantiate() as DecoyItem
	runner.add_child(d)
	return d


func _body_box(d: DecoyItem) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for n: Node in d.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var b: AABB = d.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_root_is_a_decoy_item() -> void:
	var d: DecoyItem = _make()
	expect(d != null, "root is a DecoyItem")
	d.queue_free()


func test_size_and_axis() -> void:
	var d: DecoyItem = _make()
	var b: AABB = _body_box(d)
	expect(b.size.z > 0.52 and b.size.z < 0.58, "about 55 cm long: %f" % b.size.z)
	expect(b.size.x > 0.15 and b.size.x < 0.17, "about 16 cm across: %f" % b.size.x)
	expect_near(b.position.z + b.size.z / 2.0, 0.0, 0.01, "centred on the origin along Z")
	d.queue_free()


func test_handle_is_on_top() -> void:
	var d: DecoyItem = _make()
	var b: AABB = _body_box(d)
	expect(b.end.y > 0.1 and b.end.y < 0.12, "handle stands above the body: %f" % b.end.y)
	expect(b.position.y > -0.085, "nothing below the body: %f" % b.position.y)
	d.queue_free()


func test_it_carries_a_grab_box() -> void:
	var d: DecoyItem = _make()
	var g: StaticBody3D = d.get_node("Grab") as StaticBody3D
	expect(g != null and g.collision_layer == 2, "grab body on the interaction layer")
	d.queue_free()
