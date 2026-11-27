extends TestCase
## DecoyStatusScreen: rows of bearing and distance from the sub pose, and the intensity-based noise bar.

var scr: DecoyStatusScreen


func before_each() -> void:
	scr = DecoyStatusScreen.new()
	runner.add_child(scr)


func after_each() -> void:
	scr.free()


func test_no_decoys_only_heading() -> void:
	scr.update_from_pose(Transform3D.IDENTITY, PackedVector3Array())
	expect_eq(scr.rows.size(), 0, "no rows")
	var face: Color = Palette.main().color(scr.face_swatch)
	var ink: Color = Palette.main().color(scr.ink_swatch)
	var inked: int = 0
	for y: int in range(scr.resolution.y):
		for x: int in range(scr.resolution.x):
			if scr.image.get_pixel(x, y) != face:
				inked += 1
				expect(y < DecoyStatusScreen.HEADER_H, "only the heading is drawn")
	expect(inked > 0, "heading present")
	expect(scr.image.get_pixel(10, DecoyStatusScreen.HEADER_H - 2).is_equal_approx(ink), "heading in ink")


func test_two_decoys_bearing_and_distance() -> void:
	# Sub at (10, -50, 0) facing east (+X): yaw -90 degrees.
	var pose: Transform3D = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(10, -50, 0))
	var pts: PackedVector3Array = PackedVector3Array([Vector3(10, -50, 30), Vector3(40, -50, 0)])
	scr.update_from_pose(pose, pts)
	expect_eq(scr.rows.size(), 2, "two rows")
	# (10,-50,30) is south of the sub, which faces east: to starboard, 90 degrees.
	expect_eq(int(scr.rows[0]["bearing"]), 90, "south decoy to starboard")
	expect_near(float(scr.rows[0]["distance"]), 30.0, 0.001, "30 m")
	expect_eq(int(scr.rows[1]["bearing"]), 0, "east decoy dead ahead")
	expect_near(float(scr.rows[1]["distance"]), 30.0, 0.001, "30 m")
	expect_eq(int(scr.rows[0]["number"]), 1)
	expect_eq(int(scr.rows[1]["number"]), 2)


func test_bearing_wraps() -> void:
	expect_eq(DecoyStatusScreen.bearing_of(Vector3(0, 0, 5)), 180, "astern")
	expect_eq(DecoyStatusScreen.bearing_of(Vector3(-5, 0, 0)), 270, "port")


func test_noise_from_intensity() -> void:
	var at_1: float = scr.heard_intensity(1.0)
	expect_near(at_1, scr.sound_type.intensity, 1e-9, "type intensity at 1 m")
	var at_100: float = scr.heard_intensity(100.0)
	expect_near(at_100, scr.sound_type.intensity / pow(100.0, NoiseLevel.SPREADING_EXPONENT), 1e-12, "spreading loss")
	var want: float = clampf((NoiseLevel.to_db(at_100) - (scr.bar_top_db - scr.bar_span_db)) / scr.bar_span_db, 0.0, 1.0)
	expect_near(scr.bar_fraction(at_100), want, 1e-6, "bar from intensity")
	expect(scr.bar_fraction(at_1) >= scr.bar_fraction(at_100), "louder when nearer")
	expect_near(scr.bar_fraction(0.0), 0.0, 1e-6, "silent")
	expect(scr.bar_fraction(1e9) <= 1.0, "clamped")


func test_row_cap() -> void:
	var pts: PackedVector3Array = PackedVector3Array()
	for i: int in range(scr.max_rows + 3):
		pts.append(Vector3(0, 0, -float(i + 1)))
	scr.update_from_pose(Transform3D.IDENTITY, pts)
	expect_eq(scr.rows.size(), scr.max_rows, "capped")


func test_unpowered_is_dark() -> void:
	scr.powered = false
	scr.update_from_pose(Transform3D.IDENTITY, PackedVector3Array([Vector3(0, 0, -10)]))
	var face: Color = Palette.main().color(scr.face_swatch)
	var lit: int = 0
	for y: int in range(scr.resolution.y):
		for x: int in range(scr.resolution.x):
			if scr.image.get_pixel(x, y) != face:
				lit += 1
	expect_eq(lit, 0, "dark")
