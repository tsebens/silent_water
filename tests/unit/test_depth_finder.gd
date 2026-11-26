extends TestCase
## DepthFinder: the echo-sounder trace of the floor ahead, the sub marker, and following heading and depth.

var df: DepthFinder


func before_each() -> void:
	df = DepthFinder.new()
	df.columns = 11
	df.range_ahead = 100.0
	df.range_behind = 0.0
	df.depth_span = 100.0
	df.resolution = Vector2i(101, 101)
	runner.add_child(df)


func after_each() -> void:
	df.free()


## Heading 0 looks along -Z.
func _pose(heading_deg: float, pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(heading_deg)), pos)


func test_flat_floor() -> void:
	df.sample(_pose(0.0, Vector3(0, -50, 0)), func(_x: float, _z: float) -> float: return -80.0)
	expect_eq(df.heights.size(), 11)
	for h: float in df.heights:
		expect_near(h, -30.0, 0.001, "30 m below the sub everywhere")
	expect_eq(df.row_for(df.heights[5]), 80, "row of a floor 30 m below")


func test_slope_ahead() -> void:
	# Floor rises 0.5 m per metre travelled north (-Z).
	df.sample(_pose(0.0, Vector3(0, -50, 0)), func(_x: float, z: float) -> float: return -80.0 - 0.5 * z)
	expect_near(df.heights[0], -30.0, 0.001, "under the sub")
	expect_near(df.heights[10], 20.0, 0.001, "100 m ahead")
	expect(df.heights[3] < df.heights[7], "rises along the trace")
	expect(df.row_for(df.heights[10]) < df.row_for(df.heights[0]), "rises on screen")


func test_step_ahead() -> void:
	df.sample(_pose(0.0, Vector3(0, -50, 0)), func(_x: float, z: float) -> float: return -80.0 if z > -50.0 else -20.0)
	expect_near(df.heights[4], -30.0, 0.001, "before the step (40 m)")
	expect_near(df.heights[6], 30.0, 0.001, "after the step (60 m)")


func test_marker_position() -> void:
	expect_near(df.marker_x(), 0.0, 0.001, "nothing behind: marker at the left edge")
	expect_near(df.marker_y(), 50.0, 0.001, "mid-height")
	df.range_behind = 100.0
	expect_near(df.marker_x(), 50.0, 0.001, "equal ranges: marker mid-width")
	df.range_behind = 25.0
	df.range_ahead = 75.0
	expect_near(df.marker_x(), 25.0, 0.001, "a quarter of the way")


func test_follows_heading() -> void:
	var f: Callable = func(x: float, _z: float) -> float: return -80.0 + 0.2 * x
	df.sample(_pose(0.0, Vector3.ZERO), f)
	expect_near(df.heights[10], -80.0, 0.001, "north: x does not change")
	df.sample(_pose(90.0, Vector3.ZERO), f)
	expect_near(df.heights[10], -60.0, 0.001, "east: 100 m of x")
	df.sample(_pose(270.0, Vector3.ZERO), f)
	expect_near(df.heights[10], -100.0, 0.001, "west")


func test_follows_depth_between_updates() -> void:
	var f: Callable = func(_x: float, _z: float) -> float: return -80.0
	df.height_source = f
	df.update_from_pose(_pose(0.0, Vector3(0, -50, 0)))
	var row_a: int = df.row_for(df.heights[0])
	df.update_from_pose(_pose(0.0, Vector3(0, -70, 0)))
	expect_near(df.heights[0], -10.0, 0.001, "10 m below after diving 20 m")
	expect(df.row_for(df.heights[0]) < row_a, "floor moves up the screen as the sub dives")
	df.update_from_pose(_pose(90.0, Vector3(0, -70, 0)))
	expect_near(df.heights[0], -10.0, 0.001, "turning keeps depth")


func test_vertical_pose_keeps_heading() -> void:
	df.sample(_pose(90.0, Vector3.ZERO), func(_x: float, _z: float) -> float: return 0.0)
	var up: Transform3D = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	expect(df.heading_of(up).is_equal_approx(Vector3.RIGHT), "straight up keeps the last heading")


func test_trace_drawn_in_palette_colour() -> void:
	df.height_source = func(_x: float, _z: float) -> float: return -30.0
	df.update_from_pose(_pose(0.0, Vector3.ZERO))
	var c: Color = Palette.main().color(&"light_readout")
	expect(df.image.get_pixel(50, df.row_for(-30.0)).is_equal_approx(c), "floor line in light_readout")
	expect(df.image.get_pixel(df.pixel_x(0) + 0, roundi(df.marker_y())).is_equal_approx(c), "marker drawn")
