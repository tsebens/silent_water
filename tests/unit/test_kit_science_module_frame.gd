extends TestCase
## The science module frame: a static chassis that fits a 0.35 m bay.

const SCENE: String = "res://assets/models/kit/science_module_frame/science_module_frame.tscn"
const BAY_WIDTH: float = 0.35
const STAND_OUT: float = 0.100


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_loads_without_a_script() -> void:
	var frame: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(frame)
	expect(frame != null, "scene loads")
	expect(frame.get_script() == null, "static: no script")
	frame.queue_free()


func test_meshes_fit_the_bay_and_stand_out() -> void:
	var frame: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(frame)
	var meshes: Array[MeshInstance3D] = []
	_meshes(frame, meshes)
	expect(meshes.size() > 0, "has meshes")
	var total: AABB
	var first: bool = true
	for m: MeshInstance3D in meshes:
		var b: AABB = frame.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		total = b if first else total.merge(b)
		first = false
	expect(total.size.x <= BAY_WIDTH + 0.001, "within the 0.35 m bay: %s" % total)
	expect(total.position.z >= -0.001, "nothing behind the mount face: %s" % total)
	expect(total.end.z > 0.06, "stands out of the bay: %s" % total)
	expect(total.end.z <= STAND_OUT + 0.001, "stands out at most 100 mm: %s" % total)
	frame.queue_free()
