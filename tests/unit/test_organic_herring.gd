extends TestCase
## The herring scene: a static modelled fish, no script, about 25 cm long, nose toward +Z.

const SCENE: String = "res://assets/models/organics/herring/herring.tscn"


func _body_box(root: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var b: AABB = root.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_scene_loads_with_no_script() -> void:
	var ps: PackedScene = load(SCENE) as PackedScene
	expect(ps != null, "herring scene loads")
	var h: Node3D = ps.instantiate() as Node3D
	runner.add_child(h)
	expect(h.get_script() == null, "root has no script")
	for n: Node in h.find_children("*", "Node", true, false):
		expect(n.get_script() == null, "no script on %s" % n.name)
	h.queue_free()


func test_length_and_centring() -> void:
	var h: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(h)
	var b: AABB = _body_box(h)
	expect(b.size.z > 0.24 and b.size.z < 0.26, "about 25 cm long: %f" % b.size.z)
	expect(b.size.z > b.size.x and b.size.z > b.size.y, "longest along Z")
	expect_near(b.get_center().x, 0.0, 0.005, "centred in X")
	expect_near(b.get_center().y, 0.0, 0.005, "centred in Y")
	expect_near(b.get_center().z, 0.0, 0.005, "centred in Z")
	h.queue_free()


func test_nose_toward_plus_z() -> void:
	var h: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(h)
	# the tail's tall fork makes the -Z end tall; the nose end is low
	var tall_front: float = 0.0
	var tall_back: float = 0.0
	for n: Node in h.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var t: Transform3D = h.global_transform.affine_inverse() * m.global_transform
		var arrays: Array = m.mesh.surface_get_arrays(0)
		for i: int in range(m.mesh.get_surface_count()):
			arrays = m.mesh.surface_get_arrays(i)
			for v: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = t * v
				if p.z > 0.1:
					tall_front = maxf(tall_front, absf(p.y))
				elif p.z < -0.1:
					tall_back = maxf(tall_back, absf(p.y))
	expect(tall_back > tall_front * 0.5, "fork at -Z reaches high (%f vs %f)" % [tall_back, tall_front])
	expect(tall_front < 0.045, "the head end is slim (%f)" % tall_front)
	h.queue_free()
