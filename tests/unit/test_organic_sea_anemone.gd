extends TestCase
## The generated sea anemone: one static GLB, no script, 15 cm tall and across, base on Y=0, two palette surfaces.

const SCENE: String = "res://assets/models/organics/sea_anemone/sea_anemone.tscn"


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


func test_bounding_box() -> void:
	var a: Node3D = _make()
	var m: MeshInstance3D = _meshes(a)[0]
	var b: AABB = a.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
	expect_near(b.position.y, 0.0, 1e-4, "base on Y=0")
	expect(b.end.y > 0.1425 and b.end.y < 0.1575, "about 15 cm tall: %f" % b.end.y)
	expect(b.size.x > 0.135 and b.size.x < 0.165 and b.size.z > 0.135 and b.size.z < 0.165, "about 15 cm across: %s" % b.size)
	expect_near(b.position.x + b.size.x / 2.0, 0.0, 0.003, "centred on X")
	expect_near(b.position.z + b.size.z / 2.0, 0.0, 0.003, "centred on Z")
	a.queue_free()


func test_two_surfaces_named_for_roles() -> void:
	var a: Node3D = _make()
	var mesh: Mesh = _meshes(a)[0].mesh
	expect_eq(mesh.get_surface_count(), 2)
	var names: Array[String] = []
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		names.append(mat.resource_name if mat != null else "")
	expect(names.has("anemone_column"), "column role surface: %s" % [names])
	expect(names.has("anemone_tentacle"), "tentacle role surface: %s" % [names])
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
