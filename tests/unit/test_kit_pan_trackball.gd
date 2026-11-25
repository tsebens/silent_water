extends TestCase
## The kit pan trackball (generated): a PanBall on the trackball's ring and 2x2 base.

const SCENE: String = "res://assets/models/kit/pan_trackball/pan_trackball.tscn"


func _make() -> PanBall:
	var t: PanBall = (load(SCENE) as PackedScene).instantiate() as PanBall
	runner.add_child(t)
	return t


func test_scene_wires_the_ball() -> void:
	var t: PanBall = _make()
	expect(t.ball != null, "ball is set")
	expect_eq(t.ball.name, &"Ball")
	t.queue_free()


func test_ball_rests_on_the_ring_inside_the_footprint() -> void:
	var t: PanBall = _make()
	var ball: MeshInstance3D = t.get_node("Ball").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var aabb: AABB = ball.get_aabb()
	var ring: MeshInstance3D = t.get_node("Body").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var r: AABB = ring.get_aabb()
	expect_near(aabb.size.x, 0.056, 0.002, "ball is about 56 mm across")
	expect(t.ball.position.z - aabb.size.x * 0.5 > 0.0, "ball clears the panel")
	expect(r.size.x <= 0.116 and r.size.y <= 0.116, "ring fits the 116 mm footprint")
	expect(aabb.size.x < r.size.x, "ball is narrower than the ring")
	t.queue_free()


func test_rolling_emits_and_turns_the_ball() -> void:
	var t: PanBall = _make()
	var before: Basis = t.ball.transform.basis
	t._roll_ball(Vector2(0.3, 0.0))
	expect(not t.ball.transform.basis.is_equal_approx(before), "ball turned")
	t.queue_free()
