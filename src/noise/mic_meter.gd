class_name MicMeter
extends Node
## Measures the local player's mic and reports its loudness to the host
## [Acoustics] about ten times a second. The mic feeds a private bus whose
## output is silenced, so players never hear themselves.
##
## Debug: hold F3 to simulate normal speech, Shift+F3 to simulate shouting.
## The `--fake-voice-db <db>` launch arg reports a constant level (tests).

const BUS_NAME: StringName = &"MicCapture"
const REPORT_HZ: float = 10.0
const FAKE_TALK_DB: float = 75.0
const FAKE_SHOUT_DB: float = 87.0

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _accum: float = 0.0
var _fake_db: float = -1.0
var _samples: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--fake-voice-db")
	if i != -1 and i + 1 < args.size():
		_fake_db = float(args[i + 1])
	_setup_capture()


func _setup_capture() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		push_warning("MicMeter: audio input disabled in project settings")
		return
	var bus: int = AudioServer.get_bus_index(BUS_NAME)
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS_NAME)
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus, _capture)
		# Silence the bus after the capture so the mic is never played back.
		var silence: AudioEffectAmplify = AudioEffectAmplify.new()
		silence.volume_db = -80.0
		AudioServer.add_bus_effect(bus, silence)
	else:
		_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	_player.play()


func _process(delta: float) -> void:
	if _capture != null and _capture.get_frames_available() > 0:
		_samples.append_array(VoiceLoudness.to_mono(_capture.get_buffer(_capture.get_frames_available())))
	_accum += delta
	if _accum < 1.0 / REPORT_HZ:
		return
	_accum = 0.0
	Acoustics.report_voice(_current_intensity())
	_samples.clear()


func _current_intensity() -> float:
	if Input.is_key_pressed(KEY_F3):
		return NoiseLevel.from_db(FAKE_SHOUT_DB if Input.is_key_pressed(KEY_SHIFT) else FAKE_TALK_DB)
	if _fake_db > 0.0:
		return NoiseLevel.from_db(_fake_db)
	return VoiceLoudness.intensity_from_samples(_samples)
