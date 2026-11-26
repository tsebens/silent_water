extends TestCase
## The kit navball scene: a Navball root with its ball as a separate node, the digit windows' labels, the dome and
## reticle in front of the ball, and meshes that fit the stated footprint and stand-out.

const SCENE: String = "res://assets/models/kit/navball/navball.tscn"


func _make() -> Node3D:
	var n: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(n)
	return n


func _box(n: Node3D, path: String) -> AABB:
	var box: AABB
	var first: bool = true
	for m: Node in n.get_node(path).find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var b: AABB = n.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_root_is_a_navball_with_a_separate_ball_node() -> void:
	var n: Node3D = _make()
	expect(n is Navball, "root is a Navball")
	var ball: MeshInstance3D = n.get_node_or_null("Ball/NavballBall") as MeshInstance3D
	expect(ball != null, "the ball is its own mesh node")
	expect(ball.get_parent() != n.get_node("Housing"), "the ball is not part of the housing")
	expect((n as Navball).ball_path == ^"Ball/NavballBall", "the script turns that node")
	expect(ball.material_override is ShaderMaterial, "the script applied the mask material")
	n.queue_free()


func test_no_digit_windows_or_label_plate() -> void:
	var n: Node3D = _make()
	expect(n.find_children("*", "Label3D", true, false).is_empty(), "no digit windows or label plate")
	expect(n.get_node_or_null("HDG") == null and n.get_node_or_null("PITCH") == null, "no HDG or PITCH nodes")
	n.queue_free()


func test_mask_is_drawn_from_outside() -> void:
	var n: Node3D = _make()
	var ball: MeshInstance3D = n.get_node("Ball/NavballBall") as MeshInstance3D
	var m: ShaderMaterial = ball.material_override as ShaderMaterial
	expect(m.shader.code.contains("cull_back") and not m.shader.code.contains("cull_front"), "the ball is drawn from outside")
	n.queue_free()


func test_ball_turns_with_the_sub() -> void:
	var n: Node3D = _make()
	var nav: Navball = n as Navball
	var ball: Node3D = n.get_node("Ball/NavballBall") as Node3D
	nav.apply_pose(Transform3D(Basis(Vector3.UP, 0.7), Vector3.ZERO))
	expect(ball.basis.is_equal_approx(Basis(Vector3.UP, -0.7)), "the ball is the inverse of the sub's turn")
	expect(ball.get_parent().get_parent() == n, "and the ball's node stays put")
	n.queue_free()


func test_ball_is_inside_the_dome_and_the_reticle_between() -> void:
	var n: Node3D = _make()
	var ball: MeshInstance3D = n.get_node("Ball/NavballBall") as MeshInstance3D
	var r: float = ball.get_aabb().size.x * 0.5
	var tip: float = n.get_node("Ball").position.z + r
	var dome: AABB = _box(n, "Dome")
	var reticle: AABB = _box(n, "Reticle")
	expect(r >= 0.0815 and r <= 0.0825, "the ball is about 164 mm across")
	expect(dome.end.z > tip + 0.004, "the dome stands clear of the ball's front")
	expect(dome.end.x > r and dome.position.x < -r, "the dome is wider than the ball")
	expect(reticle.end.z > tip - 0.001 and reticle.end.z < dome.end.z, "the reticle is in front of the ball and behind the dome")
	expect(reticle.size.x < 2.0 * r / 6.0 and reticle.size.x > 2.0 * r / 12.0, "the reticle is about an eighth of the ball wide")
	n.queue_free()


func test_meshes_fit_footprint_and_stand_out() -> void:
	var n: Node3D = _make()
	var housing: AABB = _box(n, "Housing")
	expect(absf(housing.position.z) < 0.0005, "the housing's back is on Z=0")
	expect(housing.size.x <= 0.2451 and housing.size.y <= 0.2451, "within the 245 mm footprint")
	expect(absf(housing.get_center().x) < 0.001 and absf(housing.get_center().y) < 0.001, "centred on the origin")
	var all: AABB = housing.merge(_box(n, "Dome")).merge(_box(n, "Reticle"))
	expect(all.size.x <= 0.2451 and all.size.y <= 0.2451, "nothing wider than the plate")
	expect(all.end.z <= 0.1251 and all.end.z >= 0.11, "stand-out within the stated 125 mm")
	n.queue_free()
