extends TestCase
## The sea star scene: a static faceted mesh, about 25 cm across, on the floor, one arm toward +Z.

const SCENE: String = "res://assets/models/organics/sea_star/sea_star.tscn"


func _box(n: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for m: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var b: AABB = n.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _make() -> Node3D:
	var s: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(s)
	return s


func test_scene_loads_with_no_script() -> void:
	var s: Node3D = _make()
	expect(s != null, "scene loads")
	expect(s.get_script() == null, "no script on the root")
	for n: Node in s.find_children("*", "", true, false):
		expect(n.get_script() == null, "no script on %s" % n.name)
	s.queue_free()


func test_about_25_cm_across() -> void:
	var s: Node3D = _make()
	var b: AABB = _box(s)
	expect(b.size.x > 0.23 and b.size.x < 0.27, "tip to tip about 25 cm: %f" % b.size.x)
	expect(b.size.y < 0.05, "low profile: %f" % b.size.y)
	expect_near(b.position.x + b.size.x / 2.0, 0.0, 0.005, "centred in X")
	s.queue_free()


func test_rests_on_the_floor() -> void:
	var s: Node3D = _make()
	expect_near(_box(s).position.y, 0.0, 0.001, "lowest point on Y=0")
	s.queue_free()


func test_one_arm_points_toward_plus_z() -> void:
	var s: Node3D = _make()
	var b: AABB = _box(s)
	expect(b.end.z > 0.12 and b.end.z < 0.14, "an arm tip on +Z: %f" % b.end.z)
	expect(b.position.z > -0.12 and b.position.z < -0.09, "the opposite side holds two arms, not one: %f" % b.position.z)
	s.queue_free()
