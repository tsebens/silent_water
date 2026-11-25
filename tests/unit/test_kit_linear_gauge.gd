extends TestCase
## The kit linear gauge: modelled slot and bar driven by LinearGauge.

const SCENE: String = "res://assets/models/kit/linear_gauge/linear_gauge.tscn"


func _make() -> LinearGauge:
	var g: LinearGauge = (load(SCENE) as PackedScene).instantiate() as LinearGauge
	runner.add_child(g)
	return g


func _bar_box(g: LinearGauge) -> AABB:
	var fill: Node3D = g.get_node("Bar/Fill") as Node3D
	var mesh: MeshInstance3D = fill.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return g.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()


func test_script_is_bound_and_builds_no_second_track() -> void:
	var g: LinearGauge = _make()
	expect(g != null, "root is a LinearGauge")
	expect(g.get_node_or_null("Track") == null, "the modelled body is the track")
	expect(g.get_node_or_null("Grab") == null, "a display: no grab box")
	g.queue_free()


func test_bar_moves_with_the_readout() -> void:
	var g: LinearGauge = _make()
	g.show_fraction(1.0)
	var full: AABB = _bar_box(g)
	expect_near(full.position.y, 0.0, 1e-4, "bar stands on the origin")
	expect_near(full.end.y, g.track_height, 1e-4, "full bar is the track height")
	g.show_fraction(0.5)
	expect_near(_bar_box(g).end.y, g.track_height * 0.5, 1e-4, "half the readout, half the bar")
	expect_near(_bar_box(g).position.y, 0.0, 1e-4, "bottom stays put")
	g.queue_free()


func test_bar_sits_inside_the_stated_footprint() -> void:
	var g: LinearGauge = _make()
	g.show_fraction(1.0)
	var b: AABB = _bar_box(g)
	expect(b.size.x <= 0.016 and b.end.z <= 0.006, "bar inside the slot and behind the plate front: %s" % b)
	expect(b.position.z >= 0.0, "bar in front of the mount face")
	g.queue_free()


func test_colour_still_steps() -> void:
	var g: LinearGauge = _make()
	g.show_fraction(0.9)
	var mesh: MeshInstance3D = g.find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return g.get_node("Bar").is_ancestor_of(n))[0] as MeshInstance3D
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	expect(mat.albedo_color.is_equal_approx(Palette.main().color(g.alarm_swatch)), "alarm colour above 85%")
	g.queue_free()
