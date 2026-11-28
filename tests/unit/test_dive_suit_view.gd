extends TestCase
## Dive-suit helmet frame: narrowing follows the model, warning tint follows air,
## drawn only for the rendering camera, palette colours only.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


func test_player_scene_has_view() -> void:
	var player: Node = PLAYER_SCENE.instantiate()
	expect(player.get_node_or_null("Head/Camera3D/DiveSuitView") is DiveSuitView, "view in scene")
	player.free()


func test_narrowing_follows_model() -> void:
	var view: DiveSuitView = DiveSuitView.new()
	runner.add_child(view)
	var m: DiveSuitModel = DiveSuitModel.new()
	view._apply(m)
	expect_eq(view.narrowing, 0.0, "off: none")
	m.set_worn(true)
	view._apply(m)
	expect_near(view.narrowing, m.params.view_narrowing_worn)
	m.params.view_narrowing_worn = 0.6
	view._apply(m)
	expect_near(view.narrowing, 0.6, 0.0001, "follows the param")
	view._apply(null)
	expect_eq(view.narrowing, 0.0)
	view.free()


func test_warning_follows_air_and_swatch() -> void:
	var view: DiveSuitView = DiveSuitView.new()
	runner.add_child(view)
	var m: DiveSuitModel = DiveSuitModel.new()
	m.set_worn(true)
	view._apply(m)
	expect_eq(view.warning, DiveSuitModel.WARN_NONE)
	expect_eq(view.swatch_for(view.warning), view.frame_swatch)
	m.air = m.params.air_capacity_seconds * m.params.low_air_fraction
	view._apply(m)
	expect_eq(view.warning, DiveSuitModel.WARN_LOW)
	expect_eq(view.swatch_for(view.warning), view.low_swatch)
	m.air = 0.0
	view._apply(m)
	expect_eq(view.swatch_for(view.warning), view.critical_swatch)
	view.free()


func test_hidden_unless_worn_and_rendering() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.name = "1"
	runner.add_child(player)
	player.set_physics_process(false)
	var view: DiveSuitView = player.get_node("Head/Camera3D/DiveSuitView") as DiveSuitView
	var quad: MeshInstance3D = view.get_node("Quad") as MeshInstance3D
	view._process(0.1)
	expect(not quad.visible, "hidden with no suit")
	var suit: DiveSuit = DiveSuit.new()
	runner.add_child(suit)
	suit.set_physics_process(false)
	player.put_on(suit)
	suit.model.set_worn(true)
	player._camera.current = false
	view._process(0.1)
	expect(not quad.visible, "hidden for a non-rendering camera")
	player._camera.current = true
	view._process(0.1)
	expect(quad.visible, "shown while worn")
	expect(view.narrowing > 0.0)
	player.take_off()
	suit.model.set_worn(false)
	view._process(0.1)
	expect(not quad.visible, "hidden after take-off")
	suit.free()
	player.free()


func test_shader_has_no_colour_literals_or_distortion() -> void:
	var f: FileAccess = FileAccess.open("res://src/player/dive_suit_view.gdshader", FileAccess.READ)
	var code: PackedStringArray = PackedStringArray()
	for line: String in f.get_as_text().split("\n"):
		if not line.strip_edges().begins_with("//"):
			code.append(line)
	var src: String = "\n".join(code).to_lower()
	for term: String in ["fov", "fisheye", "distort", "projection"]:
		expect(not src.contains(term), "no %s term" % term)
	var literal: RegEx = RegEx.create_from_string("vec[34]\\(\\s*[0-9.]+\\s*,")
	expect(literal.search(src) == null, "no colour literals")
