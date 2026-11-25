extends TestCase
## The kit indicator lamp: bezel and lens driven by IndicatorLamp.

const SCENE: String = "res://assets/models/kit/indicator_lamp/indicator_lamp.tscn"


func _make() -> IndicatorLamp:
	var l: IndicatorLamp = (load(SCENE) as PackedScene).instantiate() as IndicatorLamp
	runner.add_child(l)
	return l


func test_script_and_lens_are_wired() -> void:
	var l: IndicatorLamp = _make()
	expect(l != null, "root is an IndicatorLamp")
	expect(l.lamp != null, "lamp mesh set")
	expect(l.get_node_or_null("Grab") == null, "a display: no grab box")
	l.queue_free()


func test_lighting_switches_emission() -> void:
	var l: IndicatorLamp = _make()
	expect(not l.is_lit(), "starts unlit")
	l.set_lit(true)
	var mat: BaseMaterial3D = l.lamp.material_override as BaseMaterial3D
	expect(mat != null and mat.emission_enabled, "lit: emission on")
	l.set_lit(false)
	mat = l.lamp.material_override as BaseMaterial3D
	expect(mat != null and not mat.emission_enabled, "unlit: emission off")
	l.queue_free()


func test_fits_the_stated_footprint() -> void:
	var l: IndicatorLamp = _make()
	var box: AABB = l.global_transform.affine_inverse() * l.lamp.global_transform * l.lamp.get_aabb()
	expect(box.size.x <= 0.0201 and box.size.y <= 0.0201, "lens within 20 mm: %s" % box)
	expect(box.end.z <= 0.0081, "stands out at most 8 mm: %s" % box)
	l.queue_free()
