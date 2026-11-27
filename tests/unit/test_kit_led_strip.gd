extends TestCase
## The kit LED strips (ok, warn, alarm): a flat lens under an IndicatorLamp, lit by its script.

const DIR: String = "res://assets/models/kit/"
const SLUGS: Array[String] = ["led_strip", "led_strip_warn", "led_strip_alarm"]
const FOOTPRINT_M: Vector2 = Vector2(0.040, 0.003)
const STAND_OUT_M: float = 0.0013


func _make(slug: String) -> IndicatorLamp:
	var l: IndicatorLamp = (load("%s%s/%s.tscn" % [DIR, slug, slug]) as PackedScene).instantiate() as IndicatorLamp
	runner.add_child(l)
	return l


func test_each_scene_is_an_indicator_lamp_with_a_lens() -> void:
	for slug: String in SLUGS:
		var l: IndicatorLamp = _make(slug)
		expect(l != null, "%s: root is an IndicatorLamp" % slug)
		expect(l.lamp != null, "%s: lamp mesh set" % slug)
		expect(l.get_node_or_null("IndicatorLamp") == null, "%s: no nested lamp" % slug)
		expect(l.lamp.mesh.get_surface_count() == 1, "%s: one surface" % slug)
		l.queue_free()


func test_dark_by_default_and_lit_after_set_lit() -> void:
	for slug: String in SLUGS:
		var l: IndicatorLamp = _make(slug)
		expect(not l.is_lit(), "%s: starts unlit" % slug)
		var mat: BaseMaterial3D = l.lamp.get_active_material(0) as BaseMaterial3D
		expect(mat != null and not mat.emission_enabled, "%s: dark by default" % slug)
		l.set_lit(true)
		mat = l.lamp.material_override as BaseMaterial3D
		expect(mat != null and mat.emission_enabled, "%s: lit after set_lit(true)" % slug)
		l.set_lit(false)
		mat = l.lamp.material_override as BaseMaterial3D
		expect(mat != null and not mat.emission_enabled, "%s: dark again" % slug)
		l.queue_free()


func test_lens_role_colours_differ() -> void:
	var colours: Array[Color] = []
	for slug: String in SLUGS:
		var l: IndicatorLamp = _make(slug)
		var mat: BaseMaterial3D = l.lamp.get_active_material(0) as BaseMaterial3D
		colours.append(mat.emission)
		l.queue_free()
	expect(colours[0] != colours[1] and colours[1] != colours[2] and colours[0] != colours[2],
			"ok, warn and alarm lenses are three different colours")


func test_fits_the_stated_footprint() -> void:
	for slug: String in SLUGS:
		var l: IndicatorLamp = _make(slug)
		var box: AABB = l.global_transform.affine_inverse() * l.lamp.global_transform * l.lamp.get_aabb()
		expect(box.size.x <= FOOTPRINT_M.x + 0.0001 and box.size.y <= FOOTPRINT_M.y + 0.0001,
				"%s: within 40 x 3 mm: %s" % [slug, box])
		expect(box.position.z >= -0.0001 and box.end.z <= STAND_OUT_M + 0.0001, "%s: flat, back on Z=0: %s" % [slug, box])
		l.queue_free()


func test_length_is_set_by_scale_on_the_instance() -> void:
	var l: IndicatorLamp = _make("led_strip")
	l.scale = Vector3(2.0, 1.0, 1.0)
	var box: AABB = l.global_transform.affine_inverse() * l.lamp.global_transform * l.lamp.get_aabb()
	expect(absf(box.size.x - 0.040) < 0.0001, "unscaled bounds stay 40 mm in local space: %s" % box)
	expect(absf((l.global_transform * l.lamp.get_aabb()).size.x - 0.080) < 0.0005, "scale.x 2 gives an 80 mm bar")
	l.queue_free()
