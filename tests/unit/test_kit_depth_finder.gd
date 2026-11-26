extends TestCase
## The kit depth finder scene: the DepthFinder quad is bound and faces +Z inside the bezel, and the housing fits its
## stated footprint and stand-out with its back on Z=0.

const SCENE: String = "res://assets/models/kit/depth_finder/depth_finder.tscn"


func _make() -> Node3D:
	var n: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(n)
	return n


func _housing_box(n: Node3D) -> AABB:
	var box: AABB
	var first: bool = true
	for m: Node in n.get_node("Housing").find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var b: AABB = n.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_screen_is_a_depth_finder_facing_plus_z() -> void:
	var n: Node3D = _make()
	var d: DepthFinder = n.get_node("DepthFinder") as DepthFinder
	expect(d != null, "DepthFinder node is a DepthFinder")
	expect(d.get_node_or_null("../Housing") != null, "Housing exists")
	expect(d.global_transform.basis.z.normalized().dot(Vector3.BACK) > 0.999, "the quad's front faces +Z")
	n.queue_free()


func test_screen_sits_inside_the_bezel() -> void:
	var n: Node3D = _make()
	var d: DepthFinder = n.get_node("DepthFinder") as DepthFinder
	var box: AABB = _housing_box(n)
	expect(d.position.z > 0.0 and d.position.z < box.end.z, "the screen is behind the bezel's front")
	expect(d.screen_size.x <= box.size.x and d.screen_size.y <= box.size.y, "the screen is inside the bezel")
	n.queue_free()


func test_meshes_fit_footprint_and_stand_out() -> void:
	var n: Node3D = _make()
	var box: AABB = _housing_box(n)
	expect(absf(box.position.z) < 0.0005, "back on Z=0")
	expect(box.size.x <= 0.2761 and box.size.y <= 0.1561, "within the 276 x 156 mm footprint")
	expect(box.size.x >= 0.27 and box.size.y >= 0.15, "the bezel fills the footprint")
	expect(box.end.z <= 0.0251 and box.end.z >= 0.02, "stand-out within 25 mm")
	expect(absf(box.get_center().x) < 0.001 and absf(box.get_center().y) < 0.001, "centred on the origin")
	n.queue_free()
