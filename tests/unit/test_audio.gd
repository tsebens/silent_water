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
