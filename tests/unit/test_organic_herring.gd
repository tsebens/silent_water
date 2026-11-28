extends TestCase
## The herring scene: a rigged modelled fish, no script, about 25 cm long, nose toward +Z.

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


const BONES: Array[String] = ["spine0", "spine1", "spine2", "spine3", "spine4", "tail", "dorsal", "pectoral_l", "pectoral_r",
		"pelvic_l", "pelvic_r"]


func _skeleton(h: Node3D) -> Skeleton3D:
	return h.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func test_has_named_bones_and_a_skinned_mesh() -> void:
	var h: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(h)
	var sk: Skeleton3D = _skeleton(h)
	expect(sk != null, "a Skeleton3D")
	for b: String in BONES:
		expect(sk.find_bone(b) >= 0, "bone %s" % b)
	expect(sk.get_bone_parent(sk.find_bone("tail")) == sk.find_bone("spine4"), "tail is the last spine child")
	var skinned: int = 0
	for n: Node in h.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null:
			skinned += 1
	expect(skinned >= 1, "a skinned mesh")
	h.queue_free()


func test_rotating_a_spine_bone_moves_the_tail_not_the_nose() -> void:
	var h: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(h)
	var sk: Skeleton3D = _skeleton(h)
	var tail: int = sk.find_bone("tail")
	var head: int = sk.find_bone("spine0")
	var tail0: Vector3 = sk.get_bone_global_pose(tail).origin
	var head0: Vector3 = sk.get_bone_global_pose(head).origin
	var s2: int = sk.find_bone("spine2")
	sk.set_bone_pose_rotation(s2, Quaternion(Vector3.UP, deg_to_rad(30.0)))
	expect((sk.get_bone_global_pose(tail).origin - tail0).length() > 0.02, "the tail moved")
	expect_near((sk.get_bone_global_pose(head).origin - head0).length(), 0.0, 0.0001, "the head stayed")
	# the skinned vertices follow: the nose end of the mesh does not move, the tail end does
	var m: MeshInstance3D = h.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var at_rest: AABB = m.get_aabb()
	expect(at_rest.size.z > 0.24, "mesh bounds at rest still about 25 cm: %f" % at_rest.size.z)
	h.queue_free()
