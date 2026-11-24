extends TestCase
## Behaviours added for the scene-assembly spike (#345): a momentary push
## button and the hydrophone trackball.


func test_push_button_is_momentary() -> void:
	var b: PushButton = PushButton.new()
	expect_eq(b._drag_to_value(0.0, Vector2(5, 5)), b.max_value, "pressed while held")
	expect_eq(b._release_value(b.max_value), b.min_value, "springs back on release")
	b.free()


func test_push_button_plunger_sinks_into_the_panel() -> void:
	var b: PushButton = PushButton.new()
	var p: Node3D = Node3D.new()
	p.position = Vector3(0, 0, 0.01)
	b.add_child(p)
	b.plunger = p
	b.travel = 0.004
	b._apply_visual(b.max_value)
	expect_near(p.position.z, 0.006, 1e-6, "pressed: 4 mm in")
	b._apply_visual(b.min_value)
	expect_near(p.position.z, 0.01, 1e-6, "released: back at rest")
	b.free()


func test_trackball_drag_right_is_clockwise() -> void:
	var t: Trackball = Trackball.new()
	t.degrees_per_px = 0.5
	expect_near(t._drag_to_value(10.0, Vector2(20, -7)), 20.0, 1e-6, "20 px right = +10 degrees, vertical ignored")
	expect_near(t._drag_to_value(10.0, Vector2(-40, 0)), -10.0, 1e-6)
	t.free()


func test_trackball_bearing_wraps_like_the_wheel() -> void:
	var t: Trackball = Trackball.new()
	t.state = InteractableState.new(t.min_value, t.max_value, -30.0)
	expect_near(t.bearing_deg(), 330.0, 1e-4)
	t.free()


func test_trackball_ball_rolls_with_the_bearing() -> void:
	var t: Trackball = Trackball.new()
	var ball: Node3D = Node3D.new()
	t.add_child(ball)
	t.ball = ball
	t.ball_deg_per_bearing_deg = 3.0
	t._apply_visual(30.0)
	expect_near(rad_to_deg(ball.rotation.y), 90.0, 1e-3, "30 degrees of bearing turns the ball a quarter turn")
	t.free()
