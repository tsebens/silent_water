extends TestCase
## The generated seaweed clump: one static GLB, no script, about 0.5 m tall, base on Y=0, leaning toward +X, three palette surfaces.

const SCENE: String = "res://assets/models/organics/seaweed/seaweed.tscn"


func _make() -> Node3D:
	var n: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(n)
	return n


func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func test_no_script_one_mesh() -> void:
	var a: Node3D = _make()
	expect(a.get_script() == null, "the root carries no script")
	expect_eq(_meshes(a).size(), 1)
	a.queue_free()


func test_bounding_box_and_lean() -> void:
	var a: Node3D = _make()
	var m: MeshInstance3D = _meshes(a)[0]
	var xf: Transform3D = a.global_transform.affine_inverse() * m.global_transform
	var b: AABB = xf * m.get_aabb()
	expect_near(b.position.y, 0.0, 1e-4, "base on Y=0")
	expect(b.end.y > 0.475 and b.end.y < 0.525, "about 50 cm tall: %f" % b.end.y)
	expect(b.position.x < 0.0 and b.end.x > 0.0 and b.position.z < 0.0 and b.end.z > 0.0, "bounds enclose the holdfast: %s" % b)
	# the upper half's mean vertex X is positive: the clump leans toward +X
	var sum: float = 0.0
	var n: int = 0
	for i: int in m.mesh.get_surface_count():
		for v: Vector3 in m.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var p: Vector3 = xf * v
			if p.y > b.end.y / 2.0:
				sum += p.x
				n += 1
	expect(n > 0 and sum / float(n) > 0.0, "upper half leans toward +X")
	a.queue_free()


func test_three_surfaces_named_for_roles() -> void:
	var a: Node3D = _make()
	var mesh: Mesh = _meshes(a)[0].mesh
	expect_eq(mesh.get_surface_count(), 3)
	var names: Array[String] = []
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		names.append(mat.resource_name if mat != null else "")
	for role: String in ["seaweed_stipe", "seaweed_frond", "seaweed_bladder"]:
		expect(names.has(role), "%s surface: %s" % [role, names])
	a.queue_free()


func test_triangle_count_in_budget() -> void:
	var a: Node3D = _make()
	var mesh: Mesh = _meshes(a)[0].mesh
	var tris: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		tris += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	expect(tris > 0 and tris <= 8000, "triangles within budget: %d" % tris)
	a.queue_free()
