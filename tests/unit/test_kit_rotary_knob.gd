extends TestCase
## The kit rotary knob: static and decorative. No script, no grab box.

const SCENE: String = "res://assets/models/kit/rotary_knob/rotary_knob.tscn"


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_has_no_script_and_no_grab_box() -> void:
	var k: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(k)
	expect(k.get_script() == null, "no script on the root")
	expect(k.get_node_or_null("Grab") == null, "no grab box")
	var bodies: Array[Node] = k.find_children("*", "CollisionObject3D", true, false)
	expect_eq(bodies.size(), 0, "no collision objects anywhere")
	k.queue_free()


func test_head_turns_on_a_pivot_about_z() -> void:
	var k: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(k)
	var pivot: Node3D = k.get_node("Pivot") as Node3D
	expect(pivot != null and pivot.get_node_or_null("Head") != null, "head under a pivot")
	k.queue_free()


func test_meshes_fit_the_stated_footprint() -> void:
	var k: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(k)
	var ms: Array[MeshInstance3D] = []
	_meshes(k, ms)
	expect(ms.size() >= 2, "collar and head meshes")
	for m: MeshInstance3D in ms:
		var box: AABB = k.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		expect(box.size.x <= 0.0401 and box.size.y <= 0.0401, "within 40 mm: %s" % box)
		expect(box.position.z >= -0.0001 and box.end.z <= 0.0301, "stands out at most 30 mm: %s" % box)
	k.queue_free()
