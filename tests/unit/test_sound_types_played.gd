extends TestCase
## The bilge pump and scanner play from shared sound types, once, with no
## ad-hoc players of their own and no field events.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func _has_own_player(n: Node) -> bool:
	for c: Node in n.get_children():
		if c is AudioStreamPlayer3D:
			return true
	return false


func test_types_match_the_old_players() -> void:
	var pump: SoundType = load("res://src/noise/sound_types/bilge_pump.tres") as SoundType
	expect_near(pump.pitch_scale, 1.6, 0.0001, "gurgle pitch")
	expect_near(pump.volume_db, SubAudio.volume_for(LeakSystem.PUMP_INTENSITY), 0.001, "pump volume")
	expect(pump.get_stream() == ProceduralSounds.gurgle(), "pump plays the gurgle")
	var sc: SoundType = load("res://src/noise/sound_types/scanner.tres") as SoundType
	expect_near(sc.volume_db, SubAudio.volume_for(ScanObjective.SCAN_INTENSITY), 0.001, "scanner volume")
	expect(sc.get_stream() == ProceduralSounds.scanner(), "scanner plays the scanner stream")
	for t: SoundType in [pump, sc]:
		expect_eq(t.bus, AudioBuses.INSIDE)
		expect_near(t.unit_size, SubAudio.UNIT_SIZE, 0.0001, "unit size")


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_scanner_emitter_follows_scanner_on() -> void:
	var game: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	await _frames(3)
	var scan: ScanObjective = game.get_node("ScanObjective") as ScanObjective
	var leaks: LeakSystem = game.get_node("LeakSystem") as LeakSystem
	expect(not _has_own_player(scan), "scan objective has no player of its own")
	expect(not _has_own_player(leaks), "leak system has no player of its own")
	expect(not scan.scanner_emitter().field_events, "scanner emits no field events")
	var sw: Lever = game.get_node("Interior/Stations/Science/Station/Panel/Bay0/Module/ArmSwitch") as Lever
	scan._process(0.0)
	expect(not scan.scanner_emitter().active, "idle while off")
	sw.host_set_value(1.0)
	await _frames(3)
	scan._process(0.0)
	expect(scan.scanner_on(), "scanner on")
	expect(scan.scanner_emitter().active, "emitter active while on")
	sw.host_set_value(0.0)
	await _frames(3)
	scan._process(0.0)
	expect(not scan.scanner_emitter().active, "idle again")
	game.free()
