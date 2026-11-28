extends TestCase
## The dev overlay's sound field text.


func test_placeholders_when_empty() -> void:
	var events: Array[Dictionary] = []
	var mems: Array[SoundMemory] = []
	var text: String = "\n".join(DevOverlay.sound_field_lines(events, mems, 10.0))
	expect(text.contains("EVENTS") and text.contains("none yet"), text)
	expect(text.contains("MEMORIES") and text.contains("none"), text)


func test_lists_events_and_memories() -> void:
	var events: Array[Dictionary] = [{"time": 8.0, "position": Vector3(1, -20, 3), "intensity": 1.0, "kind": &"impact", "heard": 2}]
	var m: SoundMemory = SoundMemory.new()
	m.position = Vector3(5, -30, 7)
	m.time = 9.0
	m.intensity = NoiseLevel.from_db(70.0)
	m.kind = &"sub"
	m.uncertainty = 12.0
	var mems: Array[SoundMemory] = [m]
	var text: String = "\n".join(DevOverlay.sound_field_lines(events, mems, 10.0))
	expect(text.contains("impact") and text.contains("100 dB") and text.contains("(1, -20, 3)") and text.contains("heard by 2"), text)
	expect(text.contains("sub") and text.contains("70 dB") and text.contains("±12 m") and text.contains("1.0 s ago"), text)
	expect(not text.contains("none"), text)


func test_acoustics_records_recent_events_capped() -> void:
	Acoustics.reset()
	for i: int in Acoustics.RECENT_EVENTS_MAX + 3:
		Acoustics.emit_raw(Vector3(i, 0, 0), 1.0, &"probe")
	expect_eq(Acoustics.recent_events.size(), Acoustics.RECENT_EVENTS_MAX)
	expect_eq((Acoustics.recent_events.back()["position"] as Vector3).x, float(Acoustics.RECENT_EVENTS_MAX + 2))
	Acoustics.reset()


func test_stats_show_render_offset() -> void:
	var g: Game = load("res://src/game/game.tscn").instantiate() as Game
	runner.add_child(g)
	var text: String = DevOverlay.stats_text(g)
	expect(text.contains("rendered sea %.2f m below" % OceanSurface.render_offset_m()), text)
	g.free()
