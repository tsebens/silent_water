extends TestCase
## The chart, the holograms and the headset take their colours from the palette (docs/palette.md): changing a
## swatch changes what the map code asks for.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func _holo_color(node: Node3D) -> Color:
	var mat: ShaderMaterial = (node as MeshInstance3D).material_override as ShaderMaterial
	return mat.get_shader_parameter(&"holo_color") as Color


func test_pin_kinds_follow_their_swatches() -> void:
	var pal: Palette = Palette.main()
	var marker: Color = pal.color(&"light_marker")
	var alarm: Color = pal.color(&"light_alarm")
	expect(MapModel.kind_color(MapModel.Kind.WAYPOINT).is_equal_approx(marker), "waypoints are marker purple")
	expect(MapModel.kind_color(MapModel.Kind.DANGER).is_equal_approx(alarm), "danger is alarm red")
	expect(MapModel.kind_color(MapModel.Kind.CONTACT).is_equal_approx(pal.color(&"light_warn")), "a contact is unknown yellow")
	pal.set_color(&"light_marker", Color(0.2, 0.3, 0.4))
	pal.set_color(&"light_alarm", Color(0.9, 0.1, 0.5))
	expect(MapModel.kind_color(MapModel.Kind.NOTE).is_equal_approx(Color(0.2, 0.3, 0.4)), "notes follow light_marker")
	expect(MapModel.kind_color(MapModel.Kind.APEX).is_equal_approx(Color(0.9, 0.1, 0.5)), "apex follows light_alarm")
	pal.set_color(&"light_marker", marker)
	pal.set_color(&"light_alarm", alarm)
	expect(MapModel.kind_color(MapModel.Kind.NOTE).is_equal_approx(marker), "restored")


func test_the_hologram_draws_pins_in_the_palette_colours() -> void:
	var pal: Palette = Palette.main()
	var marker: Color = pal.color(&"light_marker")
	var alarm: Color = pal.color(&"light_alarm")
	var game: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	var model: MapModel = game.get_node("MapModel") as MapModel
	var holo: HoloMap = game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	pal.set_color(&"light_marker", Color(0.2, 0.3, 0.4))
	pal.set_color(&"light_alarm", Color(0.9, 0.1, 0.5))
	model.add_pin(Vector3(10, -50, -100), MapModel.Kind.DANGER)
	model.add_pin(Vector3(20, -60, -120), MapModel.Kind.WAYPOINT)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	var colours: Array[Color] = []
	for n: Node3D in holo.pin_markers():
		colours.append(_holo_color(n))
	expect(colours.size() == 2, "two pins drawn (%d)" % colours.size())
	expect(colours.any(func(c: Color) -> bool: return c.is_equal_approx(Color(0.9, 0.1, 0.5))), "danger pin follows light_alarm")
	expect(colours.any(func(c: Color) -> bool: return c.is_equal_approx(Color(0.2, 0.3, 0.4))), "waypoint pin follows light_marker")
	pal.set_color(&"light_marker", marker)
	pal.set_color(&"light_alarm", alarm)
	game.end_session()
	game.free()


func test_chart_and_holo_use_the_readout_swatch() -> void:
	expect(HoloMap.readout_color().is_equal_approx(Palette.main().color(&"light_readout")), "readout cyan")


func test_no_colour_literals_in_the_map_and_sonar_code() -> void:
	for f: String in ["res://src/map/flat_chart.gd", "res://src/map/holo_map.gd", "res://src/map/map_model.gd", "res://src/sonar/headset.tscn"]:
		expect(not FileAccess.get_file_as_string(f).contains("Color("), "%s has no Color( literal" % f)
