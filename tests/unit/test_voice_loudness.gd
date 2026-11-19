extends TestCase


func _tone(rms: float, n: int = 2205) -> PackedFloat32Array:
	# A sine with the given RMS (amplitude = rms * sqrt 2).
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for i: int in range(n):
		out[i] = rms * sqrt(2.0) * sin(TAU * 220.0 * float(i) / 22050.0)
	return out


func test_silence_is_zero() -> void:
	expect_eq(VoiceLoudness.intensity_from_samples(PackedFloat32Array()), 0.0)
	expect_eq(VoiceLoudness.intensity_from_samples(_tone(0.001)), 0.0, "below the gate")


func test_speech_levels() -> void:
	var normal: float = NoiseLevel.to_db(VoiceLoudness.intensity_from_samples(_tone(0.07)))
	var whisper: float = NoiseLevel.to_db(VoiceLoudness.intensity_from_samples(_tone(0.01)))
	var shout: float = NoiseLevel.to_db(VoiceLoudness.intensity_from_samples(_tone(0.3)))
	expect_near(normal, 74.7, 1.0, "normal speech")
	expect(whisper < Acoustics.OCEAN_BASE_DB, "a whisper (%f dB) should hide under the ocean" % whisper)
	expect_near(shout, 87.3, 1.0, "shout")


func test_to_mono() -> void:
	var m: PackedFloat32Array = VoiceLoudness.to_mono(PackedVector2Array([Vector2(1, 0), Vector2(0.5, 0.5)]))
	expect_near(m[0], 0.5)
	expect_near(m[1], 0.5)
