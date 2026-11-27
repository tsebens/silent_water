extends TestCase
## Decoy and launch sound types, and the DECOY map kind (#747).

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func test_sound_types_load() -> void:
	var decoy: SoundType = load("res://src/noise/sound_types/decoy.tres") as SoundType
	var thump: SoundType = load("res://src/noise/sound_types/launch_thump.tres") as SoundType
	expect(decoy != null and thump != null, "both load as SoundType")
	expect(decoy.kind == &"decoy", "decoy kind")
	expect(not decoy.is_one_off() and decoy.has_stream(), "decoy is continuous with a stream")
	expect(thump.is_one_off() and thump.has_stream(), "thump is a one-off with a stream")
	var base: SoundType = load("res://src/noise/sound_types/pump_hum.tres") as SoundType
	expect(decoy.intensity > base.intensity, "decoy is loud")


func test_decoy_kind_tables() -> void:
	expect(MapModel.KIND_NAMES.size() == MapModel.Kind.size(), "names cover the enum")
	expect(MapModel.KIND_SWATCHES.size() == MapModel.Kind.size(), "swatches cover the enum")
	expect(MapModel.Kind.DECOY == MapModel.Kind.size() - 1, "DECOY is last")
	expect(MapModel.KIND_SWATCHES[MapModel.Kind.DECOY] == &"light_marker", "decoy swatch")


func test_decoy_pin_kept_and_clamped_and_drawn() -> void:
	var game: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	var model: MapModel = game.get_node("MapModel") as MapModel
	model.add_pin(Vector3(10, -50, -100), MapModel.Kind.DECOY)
	model.add_pin(Vector3(20, -50, -100), 99)
	expect(int(model.pins[0]["kind"]) == MapModel.Kind.DECOY, "decoy kept")
	expect(int(model.pins[1]["kind"]) == MapModel.Kind.DECOY, "out of range clamps to decoy")
	var holo: HoloMap = game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	var chart: FlatChart = game.get_node("Interior/Stations/Sonar/ScreenMount/Chart") as FlatChart
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	chart.canvas.queue_redraw()
	await runner.get_tree().process_frame
	expect(holo.pin_markers().size() == 2, "holo draws both decoy pins (%d)" % holo.pin_markers().size())
	expect(chart.canvas != null, "flat chart drew")
	game.end_session()
	game.free()
