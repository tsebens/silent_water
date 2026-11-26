extends TestCase
## Navball: ball orientation from the render pose, digit text, shader colours.

var frame: SubFrame
var nav: Navball
var ball: MeshInstance3D


func before_each() -> void:
	frame = SubFrame.new()
	runner.add_child(frame)
	nav = Navball.new()
	ball = MeshInstance3D.new()
	ball.name = "Ball"
	nav.add_child(ball)
	runner.add_child(nav)


func after_each() -> void:
	nav.free()
	frame.free()


func _pose(heading: float, pitch: float, roll: float) -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(heading)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) \
		* Basis(Vector3.FORWARD, deg_to_rad(roll))


func _check_pose(heading: float, pitch: float, roll: float) -> void:
	frame.sub_transform = Transform3D(_pose(heading, pitch, roll), Vector3(3, -20, 5))
	frame._process(0.0)
	nav.apply_pose(frame.render_transform())
	var b: Basis = ball.basis
	var inv: Basis = frame.render_transform().basis.inverse()
	var tag: String = "%d/%d/%d" % [heading, pitch, roll]
	expect(b.is_equal_approx(inv), "ball basis is the inverse of the pose at " + tag)
	# World north and up, expressed in the sub frame, are what the ball's own N and apex map to.
	expect((b * Vector3.FORWARD).is_equal_approx(inv * Vector3.FORWARD), "north " + tag)
	expect((b * Vector3.UP).is_equal_approx(inv * Vector3.UP), "apex to world up " + tag)
	# And the pose carries it back: ball frame vector -> sub frame -> world is the identity.
	expect((frame.render_transform().basis * b * Vector3.FORWARD).is_equal_approx(Vector3.FORWARD), "round trip " + tag)


func test_basis_is_inverse_of_pose() -> void:
	_check_pose(47.0, -10.0, 15.0)


func test_basis_at_extreme_pitch_and_full_roll() -> void:
	_check_pose(47.0, 30.0, 180.0)
	_check_pose(310.0, -30.0, 180.0)
	_check_pose(0.0, 30.0, -170.0)


func test_mounting_offset_applies() -> void:
	nav.mount_rotation_deg = Vector3(0.0, 90.0, 0.0)
	var b: Basis = nav.ball_basis(Basis.IDENTITY)
	expect((b * Vector3.FORWARD).is_equal_approx(Basis.from_euler(Vector3(0, PI / 2, 0)) * Vector3.FORWARD))


func test_heading_text() -> void:
	expect_eq(Navball.heading_text(0.0), "000")
	expect_eq(Navball.heading_text(7.0), "007")
	expect_eq(Navball.heading_text(359.0), "359")
	expect_eq(Navball.heading_text(360.0), "000")
	expect_eq(Navball.heading_text(359.6), "000")


func test_pitch_text() -> void:
	expect_eq(Navball.pitch_text(-8.0), "-8")
	expect_eq(Navball.pitch_text(0.0), "0")
	expect_eq(Navball.pitch_text(12.0), "+12")
	expect_eq(Navball.pitch_text(-0.2), "0")


func test_material_uses_palette_and_compiles() -> void:
	var m: ShaderMaterial = nav.material
	expect(m != null and m.shader != null, "shader assigned")
	expect_eq(ball.material_override, m, "applied to the ball node")
	var pal: Palette = Palette.main()
	expect_eq(m.get_shader_parameter(&"mark_color"), pal.color(nav.mark_swatch))
	expect_eq(m.get_shader_parameter(&"upper_color"), pal.color(nav.upper_swatch))
	expect_eq(m.get_shader_parameter(&"lower_color"), pal.color(nav.lower_swatch))
	expect(m.get_shader_parameter(&"mask") is Texture2D, "mask texture set")
	expect(m.shader.get_shader_uniform_list().size() >= 4, "shader parsed")
