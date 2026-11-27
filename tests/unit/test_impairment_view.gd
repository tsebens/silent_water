extends TestCase
## Bad-air view: blur and vignette amounts, the periodic blur envelope, and
## activity only for the rendering camera.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


func _p() -> ImpairmentParams:
	return ImpairmentParams.new()


func test_amounts_follow_strength() -> void:
	var p: ImpairmentParams = _p()
	expect_eq(ImpairmentView.blur_amount(0.0, p), 0.0)
	expect_eq(ImpairmentView.blur_amount(1.0, p), p.blur_at_full)
	expect(ImpairmentView.blur_amount(0.5, p) < ImpairmentView.blur_amount(0.8, p), "blur rises")
	expect_eq(ImpairmentView.vignette_amount(p.vignette_start_strength, p), 0.0, "no vignette at the start")
	expect_eq(ImpairmentView.vignette_amount(0.1, p), 0.0)
	expect_eq(ImpairmentView.vignette_amount(1.0, p), p.vignette_at_full)
	expect(ImpairmentView.vignette_amount(0.5, p) < ImpairmentView.vignette_amount(0.9, p), "vignette narrows")


func test_envelope_zero_without_strength() -> void:
	for i: int in 200:
		expect_eq(ImpairmentView.blur_envelope(0.0, float(i) * 0.7), 0.0)


func test_envelope_longer_and_more_frequent() -> void:
	expect(ImpairmentView.period_for(0.8) < ImpairmentView.period_for(0.2), "more frequent")
	expect(ImpairmentView.on_time_for(0.8) > ImpairmentView.on_time_for(0.2), "longer")
	# Time spent blurred over a fixed span grows with strength.
	var lo: int = 0
	var hi: int = 0
	for i: int in 6000:
		var t: float = float(i) * 0.05
		if ImpairmentView.blur_envelope(0.2, t) > 0.0:
			lo += 1
		if ImpairmentView.blur_envelope(0.8, t) > 0.0:
			hi += 1
	expect(hi > lo * 2, "blurred more of the time: %d vs %d" % [hi, lo])


func test_envelope_smooth() -> void:
	for s: float in [0.05, 0.35, 0.85, 1.0]:
		var prev: float = ImpairmentView.blur_envelope(s, 0.0)
		for i: int in range(1, 20000):
			var e: float = ImpairmentView.blur_envelope(s, float(i) * 0.01)
			expect(absf(e - prev) < 0.05, "step at s=%.2f t=%.2f" % [s, float(i) * 0.01])
			prev = e
	# And smooth across strength at a fixed time.
	var prev_s: float = ImpairmentView.blur_envelope(0.01, 1.0)
	for i: int in range(2, 100):
		var e2: float = ImpairmentView.blur_envelope(float(i) * 0.01, 1.0)
		expect(absf(e2 - prev_s) < 0.3, "strength step at %d" % i)
		prev_s = e2


func test_inactive_for_non_local_camera() -> void:
	var cam: Camera3D = Camera3D.new()
	runner.add_child(cam)
	cam.current = false
	var view: ImpairmentView = ImpairmentView.new()
	view.params = _p()
	view.camera_path = view.get_path_to(cam) if view.is_inside_tree() else NodePath()
	var quad: MeshInstance3D = MeshInstance3D.new()
	quad.name = "Quad"
	view.add_child(quad)
	cam.add_child(view)
	view.camera_path = ^".."
	view._ready()
	DevSettings.impairment_level = 4
	view._process(0.1)
	expect_eq(view.blur, 0.0, "no blur for a non-local camera")
	expect_eq(view.vignette, 0.0)
	expect(not quad.visible, "quad hidden")
	cam.current = true
	view._process(0.1)
	expect(view.vignette > 0.0, "forced level shows on the rendering camera")
	expect(quad.visible, "quad shown")
	DevSettings.impairment_level = -1
	cam.queue_free()


func test_dev_override_cycles_levels() -> void:
	DevSettings.impairment_level = -1
	expect_eq(DevSettings.forced_impairment(), -1.0)
	var seen: Array[float] = []
	for i: int in DevSettings.IMPAIRMENT_LEVELS.size():
		DevSettings.cycle_impairment_level()
		seen.append(DevSettings.forced_impairment())
	expect_eq(seen, Array(DevSettings.IMPAIRMENT_LEVELS), "each rung in turn")
	expect_eq(DevSettings.cycle_impairment_level(), -1, "then off")


func test_shader_has_no_distortion_or_literals() -> void:
	var f: FileAccess = FileAccess.open("res://src/player/impairment_view.gdshader", FileAccess.READ)
	var code: PackedStringArray = PackedStringArray()
	for line: String in f.get_as_text().split("\n"):
		if not line.strip_edges().begins_with("//"):
			code.append(line)
	var src: String = "\n".join(code).to_lower()
	for term: String in ["fov", "fisheye", "distort", "projection"]:
		expect(not src.contains(term), "no %s term" % term)
	var literal: RegEx = RegEx.create_from_string("vec[34]\\(\\s*[0-9.]+\\s*,")
	expect(literal.search(src) == null, "no colour literals")


func test_player_scene_has_view() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	expect(player.get_node_or_null("Head/Camera3D/ImpairmentView") is ImpairmentView, "view in scene")
	player.free()
