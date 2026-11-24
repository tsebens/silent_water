extends TestCase
## The shared dial instrument. Its shape comes from generated solids that every
## gauge instances, so a change to them reaches every scene; what varies per
## gauge is an export.

const INTERIOR: String = "res://src/sub/interior.tscn"
const CONSOLE: String = "res://assets/models/stations/sonar_console/sonar_console.tscn"


func _gauge(configure: Callable = Callable()) -> Gauge:
	var g: Gauge = Gauge.new()
	if configure.is_valid():
		configure.call(g)
	runner.add_child(g)
	return g


func _body_mesh(g: Gauge) -> Mesh:
	for child: Node in g.get_node("Body").get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


func _gauges_in(scene_path: String) -> Array[Gauge]:
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	runner.add_child(root)
	var out: Array[Gauge] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Gauge:
			out.append(n as Gauge)
		stack.append_array(n.get_children())
	out[0].set_meta(&"scene_root", root)
	return out


func test_builds_its_parts() -> void:
	var g: Gauge = _gauge()
	for part: String in ["Body", "Face", "Marks", "Needle", "Title"]:
		expect(g.get_node_or_null(part) != null, "%s built" % part)
	expect(g.get_node_or_null("NeedleB") == null, "no second needle unless readout_b is set")
	g.queue_free()
	var two: Gauge = _gauge(func(x: Gauge) -> void: x.readout_b = &"ambient_db")
	expect(two.get_node_or_null("NeedleB") != null, "second needle with readout_b")
	two.queue_free()


func test_radius_scales_the_dial_but_not_its_depth() -> void:
	var g: Gauge = _gauge(func(x: Gauge) -> void: x.radius = 0.05)
	var body: Node3D = g.get_node("Body") as Node3D
	expect_near(body.scale.x, 0.5, 1e-5)
	expect_near(body.scale.y, 0.5, 1e-5)
	expect_near(body.scale.z, 1.0, 1e-5, "every gauge mounts at the same depth")
	g.queue_free()


func test_every_gauge_shares_one_body_mesh() -> void:
	var a: Gauge = _gauge(func(x: Gauge) -> void: x.radius = 0.05)
	var b: Gauge = _gauge(func(x: Gauge) -> void: x.radius = 0.13)
	expect(_body_mesh(a) != null and _body_mesh(a) == _body_mesh(b), "one mesh resource behind every gauge")
	var shared: Mesh = _body_mesh(a)
	for pair: Array in [[INTERIOR, 19], [CONSOLE, 4]]:
		var gauges: Array[Gauge] = _gauges_in(pair[0])
		expect_eq(gauges.size(), pair[1], "gauges in %s" % pair[0])
		for g: Gauge in gauges:
			expect(_body_mesh(g) == shared, "%s uses the shared solids" % g.name)
		(gauges[0].get_meta(&"scene_root") as Node).queue_free()
	a.queue_free()
	b.queue_free()


func test_scale_is_symmetric_about_the_top_by_default() -> void:
	var g: Gauge = _gauge(func(x: Gauge) -> void: x.sweep_deg = 180.0)
	expect_near(rad_to_deg(g._angle_for(0.0)), 90.0, 1e-4, "minimum at 9 o'clock")
	expect_near(rad_to_deg(g._angle_for(1.0)), -90.0, 1e-4, "maximum at 3 o'clock")
	var mid: Vector3 = Gauge._dir(g._angle_for(0.5))
	expect(mid.is_equal_approx(Vector3.UP), "middle straight up")
	g.queue_free()


func test_sweep_center_moves_where_the_scale_starts_and_stops() -> void:
	var g: Gauge = _gauge(func(x: Gauge) -> void:
		x.sweep_deg = 90.0
		x.sweep_center_deg = 90.0)
	expect(Gauge._dir(g._angle_for(0.5)).is_equal_approx(Vector3.RIGHT), "middle at 3 o'clock")
	var start: Vector3 = Gauge._dir(g._angle_for(0.0))
	var stop: Vector3 = Gauge._dir(g._angle_for(1.0))
	expect(start.is_equal_approx(Vector3(1, 1, 0).normalized()), "starts at half past one (%s)" % start)
	expect(stop.is_equal_approx(Vector3(1, -1, 0).normalized()), "stops at half past four (%s)" % stop)
	g.queue_free()


func test_marks_follow_the_divisions() -> void:
	var g: Gauge = _gauge(func(x: Gauge) -> void:
		x.major_divisions = 5
		x.minor_per_division = 1)
	var mesh: Mesh = (g.get_node("Marks") as MeshInstance3D).mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	expect_eq(verts.size(), 11 * 6, "5 divisions with one short mark between: 11 marks")
	g.queue_free()
	var compass: Gauge = _gauge(func(x: Gauge) -> void: x.wraps = true)
	verts = (compass.get_node("Marks") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	expect_eq(verts.size(), 8 * 6, "a wrapping dial is marked all the way round, with no doubled mark")
	compass.queue_free()


func test_small_dials_get_smaller_text() -> void:
	var small: Gauge = _gauge(func(x: Gauge) -> void: x.radius = 0.055)
	var big: Gauge = _gauge(func(x: Gauge) -> void: x.radius = 0.12)
	var ts: float = (small.get_node("Title") as Label3D).pixel_size
	var tb: float = (big.get_node("Title") as Label3D).pixel_size
	expect(ts < tb * 0.5, "title on a 55 mm dial is under half the size of a 120 mm dial's")
	small.queue_free()
	big.queue_free()
