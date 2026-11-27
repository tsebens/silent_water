extends TestCase


func _peak(wav: AudioStreamWAV) -> float:
	var peak: int = 0
	for i: int in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return float(peak) / 32767.0


func test_sounds_generate_with_sane_levels() -> void:
	var sounds: Dictionary = {
		"engine_hum": ProceduralSounds.engine_hum(),
		"hiss": ProceduralSounds.hiss(),
		"gurgle": ProceduralSounds.gurgle(),
		"clank": ProceduralSounds.clank(),
		"thud": ProceduralSounds.thud(),
		"step": ProceduralSounds.step(),
		"swim": ProceduralSounds.swim(),
		"moan": ProceduralSounds.moan(),
		"pulse": ProceduralSounds.pulse(),
		"grunt": ProceduralSounds.grunt(),
		"roar": ProceduralSounds.roar(),
		"vent": ProceduralSounds.vent(),
		"rumble": ProceduralSounds.rumble(),
		"creak": ProceduralSounds.creak(),
		"surface_wash": ProceduralSounds.surface_wash(),
	}
	for key: String in sounds:
		var wav: AudioStreamWAV = sounds[key]
		expect(wav != null and wav.data.size() > 0, key + " generated")
		var peak: float = _peak(wav)
		expect(peak > 0.2 and peak <= 1.0, "%s peak %f" % [key, peak])


func test_loops_loop_and_one_shots_dont() -> void:
	expect_eq(ProceduralSounds.engine_hum().loop_mode, AudioStreamWAV.LOOP_FORWARD)
	expect_eq(ProceduralSounds.hiss().loop_mode, AudioStreamWAV.LOOP_FORWARD)
	expect_eq(ProceduralSounds.clank().loop_mode, AudioStreamWAV.LOOP_DISABLED)


func test_sounds_are_cached() -> void:
	expect(ProceduralSounds.clank() == ProceduralSounds.clank())


func test_volume_mapping_matches_noise_scale() -> void:
	expect_near(SubAudio.volume_for(1.0), 0.0)
	expect_near(SubAudio.volume_for(0.01), -20.0)
	expect_near(SubAudio.volume_for(NoiseLevel.from_db(62.0)), -38.0, 0.001)


func test_wash_gain_peaks_at_surface_and_fades_with_depth() -> void:
	expect_near(SubAudio.wash_gain(0.0), 1.0)
	var prev: float = SubAudio.wash_gain(0.0)
	for d: int in range(1, int(SubAudio.WASH_DEPTH) + 1):
		var g: float = SubAudio.wash_gain(float(d))
		expect(g < prev, "gain falls at %d m" % d)
		prev = g
	expect_eq(SubAudio.wash_gain(SubAudio.WASH_DEPTH), 0.0)
	expect_eq(SubAudio.wash_gain(SubAudio.WASH_DEPTH + 50.0), 0.0)
	expect_eq(SubAudio.wash_gain(-3.0), 1.0)


func test_surface_wash_loops() -> void:
	expect_eq(ProceduralSounds.surface_wash().loop_mode, AudioStreamWAV.LOOP_FORWARD)


func test_impact_type_carries_the_thud_on_the_felt_bus() -> void:
	var t: SoundType = Acoustics.IMPACT_TYPE
	expect(t.has_stream(), "impact type has a stream")
	expect_eq(t.bus, AudioBuses.FELT)
	expect_near(t.volume_db, 0.0)
	var thud: AudioStreamWAV = t.stream as AudioStreamWAV
	expect(thud != null and thud.data.size() == ProceduralSounds.thud().data.size(), "stream is the thud")


func test_strike_plays_impact_stream_at_prior_level() -> void:
	var a: SubAudio = SubAudio.new()
	runner.add_child(a)
	var p: AudioStreamPlayer = a.play_strike(6.0)
	expect(p != null, "strike player made")
	expect(p.stream == Acoustics.IMPACT_TYPE.stream, "plays the type's stream")
	expect_eq(p.bus, AudioBuses.FELT)
	expect_near(p.volume_db, SubAudio.volume_for(SubController.STRIKE_INTENSITY * 36.0), 0.001)
	a.queue_free()
