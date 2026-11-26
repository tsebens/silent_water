extends TestCase
## Gauge zone: none by default; with zone_from it is a band from there to max_value in a palette swatch.


func _gauge(zone_from: float) -> Gauge:
	var g: Gauge = Gauge.new()
	g.zone_from = zone_from
	runner.add_child(g)
	return g


func test_no_zone_by_default() -> void:
	var g: Gauge = _gauge(NAN)
	expect(g.get_node_or_null("Zone") == null, "no Zone node when zone_from is unset")
	expect(g.get_node_or_null("Marks") != null, "rest of the dial still built")


func test_zone_runs_to_max_value() -> void:
	var g: Gauge = _gauge(80.0)
	var zone: MeshInstance3D = g.get_node_or_null("Zone") as MeshInstance3D
	expect(zone != null, "Zone node exists")
	if zone == null:
		return
	var verts: PackedVector3Array = zone.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo: float = INF
	var hi: float = -INF
	var tmin: float = INF
	var tmax: float = -INF
	for v: Vector3 in verts:
		# Recover the scale fraction from the vertex angle.
		var ang: float = atan2(-v.x, v.y)
		var t: float = (deg_to_rad(g.sweep_deg * 0.5 - g.sweep_center_deg) - ang) / deg_to_rad(g.sweep_deg)
		tmin = minf(tmin, t)
		tmax = maxf(tmax, t)
		lo = minf(lo, v.length())
		hi = maxf(hi, v.length())
	expect_near(tmin, 0.8, 0.01, "zone starts at zone_from")
	expect_near(tmax, 1.0, 0.01, "zone ends at max_value")
	expect(hi <= g.radius, "band inside the dial")


func test_zone_uses_swatch() -> void:
	var g: Gauge = _gauge(80.0)
	var zone: MeshInstance3D = g.get_node("Zone") as MeshInstance3D
	var m: StandardMaterial3D = zone.material_override as StandardMaterial3D
	expect(m.albedo_color.is_equal_approx(Palette.main().color(&"light_alarm")), "default swatch is light_alarm")
	var g2: Gauge = Gauge.new()
	g2.zone_from = 50.0
	g2.zone_swatch = &"light_warn"
	runner.add_child(g2)
	var m2: StandardMaterial3D = (g2.get_node("Zone") as MeshInstance3D).material_override as StandardMaterial3D
	expect(m2.albedo_color.is_equal_approx(Palette.main().color(&"light_warn")), "given swatch used")
