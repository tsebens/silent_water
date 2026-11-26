extends TestCase
## The shared control base plate: each size's footprint and triangle count.

const DIR: String = "res://assets/models/kit/control_base/"


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c: Node in n.get_children():
		_meshes(c, out)


func _measure(size: String) -> Dictionary:
	var scene: PackedScene = load(DIR + "control_base_%s.glb" % size)
	var root: Node = scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var tris: int = 0
	var box: AABB = AABB()
	var first: bool = true
	for m: MeshInstance3D in meshes:
		tris += m.mesh.get_faces().size() / 3
		var b: AABB = m.transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	return {"tris": tris, "size": box.size}


func test_1x3_footprint_and_triangles() -> void:
	var m: Dictionary = _measure("1x3")
	expect_near((m.size as Vector3).x, 0.056, 1e-4, "56 mm wide")
	expect_near((m.size as Vector3).y, 0.176, 1e-4, "176 mm tall")
	expect_eq(m.tris, 124, "1x3 triangle count")


func test_other_sizes_unchanged() -> void:
	var expected: Dictionary = {"1x1": 56.0, "1x2": 116.0, "2x2": 116.0}
	for k: String in expected:
		var m: Dictionary = _measure(k)
		expect_near((m.size as Vector3).y, expected[k] / 1000.0, 1e-4, k + " height")
		expect_eq(m.tris, 124, k + " triangle count")
