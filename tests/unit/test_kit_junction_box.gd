extends TestCase
## The kit junction box: a static body GLB with a marked spark anchor.

const SCENE: String = "res://assets/models/kit/junction_box/junction_box.tscn"
const FOOTPRINT: Vector2 = Vector2(0.220, 0.232)
const STAND_OUT: float = 0.102


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_loads_without_a_script_and_has_the_anchor() -> void:
	var box: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(box)
	expect(box != null, "scene loads")
	expect(box.get_script() == null, "static: no script")
	expect(box.get_node_or_null("SparkAnchor") is Marker3D, "SparkAnchor marker present")
	box.queue_free()


func test_meshes_fit_the_footprint_and_stand_out() -> void:
	var box: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(box)
	var meshes: Array[MeshInstance3D] = []
	_meshes(box, meshes)
	expect(meshes.size() > 0, "has meshes")
	var total: AABB
	var first: bool = true
	for m: MeshInstance3D in meshes:
		var b: AABB = box.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		total = b if first else total.merge(b)
		first = false
	expect(total.size.x <= FOOTPRINT.x + 0.001 and total.size.y <= FOOTPRINT.y + 0.001, "within footprint: %s" % total)
	expect(total.position.z >= -0.001, "nothing behind the mount face: %s" % total)
	expect(total.end.z <= STAND_OUT + 0.001, "stands out at most 102 mm: %s" % total)
	var anchor: Node3D = box.get_node("SparkAnchor") as Node3D
	expect(anchor.position.z >= total.end.z - 0.002, "anchor sits on the front of the lid")
	box.queue_free()
