class_name SessionLog
extends Node
## Host-side record of a session for the post-game talk ("what gave us
## away?"). Writes key events with timestamps to
## user://logs/session_<date>.txt and echoes them to the console.
##
## Logged: dive start and result, every apex ladder change with the SNR it
## heard and the loudest things in the sub at that moment, hull strikes, near
## misses, leaks, patches, the scan, and loud moments (> 85 dB).

const LOUD_DB: float = 85.0
const LOUD_COOLDOWN_SEC: float = 5.0
## Noise changes are logged in steps of this many dB (developer console).
const NOISE_STEP_DB: float = 5.0
const NOISE_LOG_MIN_GAP_SEC: float = 1.0

@export var controller: SubController
@export var apex: ApexMonster
@export var leaks: LeakSystem
@export var scan: ScanObjective
@export var director: DiveDirector
## Names to print instead of peer ids (filled from launch names if known).
var crew_names: Dictionary = {}

## Drop-weight releases recorded this dive (the dive's results).
var drops_recorded: int = 0

var _file: FileAccess
var _t: float = 0.0
var _loud_cooldown: float = 0.0
var _path: String = ""
var _noise_band: int = -999
var _noise_gap: float = 0.0
var _apex_hears: bool = false
var _apex_active: bool = true


func _ready() -> void:
	add_to_group(&"session_log")
	apex.state_changed.connect(_on_apex_state)
	apex.near_miss.connect(func(d: float) -> void: write("NEAR MISS  apex passed %.0f m away" % d))
	controller.hull_strike.connect(func(speed: float) -> void: write("HULL STRIKE  %.1f m/s at %.0f m" % [speed, controller.depth]))
	leaks.leak_opened.connect(func(where: String) -> void: write("LEAK  opened at %s" % where))
	leaks.leak_patched.connect(func(q: float, hold: float) -> void: write("PATCH  quality %.0f%%, holds ~%.0f s" % [q * 100.0, hold]))
	scan.scan_started.connect(func() -> void: write("SCANNER ON  at %.0f m, %.0f m from the array" % [controller.depth, controller.model.position.distance_to(scan.target.position)]))
	scan.scan_completed.connect(func() -> void: write("ARRAY SCANNED"))
	director.dive_lost.connect(func() -> void: write("SUB LOST  after %s, max depth %.0f m" % [_clock(director.dive_time), director.max_depth]))
	director.dive_complete.connect(func() -> void: write("DIVE COMPLETE  in %s, max depth %.0f m" % [_clock(director.dive_time), director.max_depth]))
	director.dive_reset.connect(func() -> void:
		drops_recorded = 0
		write("---- NEW DIVE ----"))


## Host: opens the log file. Called when a session starts.
func open_log() -> void:
	if not multiplayer.is_server() or _file != null:
		return
	DirAccess.make_dir_recursive_absolute("user://logs")
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	_path = "user://logs/session_%s.txt" % stamp
	_file = FileAccess.open(_path, FileAccess.WRITE)
	write("SESSION START  log: %s" % ProjectSettings.globalize_path(_path))


func close_log() -> void:
	if _file != null:
		write("SESSION END")
		_file.close()
		_file = null


## Records a drop-weights release (the hook a cost can attach to later).
func record_drop_weights(mass_t: float, depth_m: float) -> void:
	drops_recorded += 1
	write("DROP WEIGHTS  released %.1f t at %.0f m" % [mass_t, depth_m])


func log_path() -> String:
	return _path


func write(line: String) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var entry: String = "[%s] %s" % [_clock(_t), line]
	print("[log] " + entry)
	DevLog.broadcast_event(entry)
	if _file != null:
		_file.store_line(entry)
		_file.flush()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_t += delta
	_loud_cooldown = maxf(_loud_cooldown - delta, 0.0)
	if Acoustics.sub_db() >= LOUD_DB and _loud_cooldown <= 0.0:
		_loud_cooldown = LOUD_COOLDOWN_SEC
		write("LOUD  %.0f dB: %s" % [Acoustics.sub_db(), _top_sources_text()])
	_log_noise_steps(delta)
	_log_apex_hearing()


## Developer console: a line whenever the sub's noise crosses a 5 dB step.
func _log_noise_steps(delta: float) -> void:
	_noise_gap = maxf(_noise_gap - delta, 0.0)
	var band: int = int(floor(Acoustics.sub_db() / NOISE_STEP_DB))
	if band == _noise_band or _noise_gap > 0.0:
		return
	var rising: bool = band > _noise_band
	_noise_band = band
	_noise_gap = NOISE_LOG_MIN_GAP_SEC
	var masked: String = "masked" if Acoustics.is_masked() else "EXPOSED"
	if Acoustics.sub_intensity <= 0.0:
		write("NOISE silent")
		return
	write("NOISE %s %.0f dB (ocean %.0f, %s): %s" % [
		"up to" if rising else "down to", Acoustics.sub_db(), Acoustics.ambient_db(), masked, _top_sources_text()])


## Developer console: when the apex starts and stops hearing the sub.
func _log_apex_hearing() -> void:
	if apex.active != _apex_active:
		_apex_active = apex.active
		write("APEX %s (developer switch)" % ("ENABLED" if apex.active else "DISABLED"))
	var hears: bool = apex.active and apex.brain.last_snr_db > 0.0
	if hears == _apex_hears:
		return
	_apex_hears = hears
	if hears:
		write("APEX HEARS US  %+.0f dB SNR at %.0f m. Loudest aboard: %s" % [
			apex.brain.last_snr_db, apex.position.distance_to(controller.model.position), _top_sources_text()])
	else:
		write("APEX LOST US  (below its noise floor)")


func _on_apex_state(new_state: int) -> void:
	var dist: float = apex.position.distance_to(controller.model.position)
	write("APEX %s  %.0f m away, heard us at %+.0f dB SNR. Loudest aboard: %s" % [
		SuspicionModel.state_name(new_state as SuspicionModel.State), dist, apex.brain.last_snr_db, _top_sources_text()])


func _top_sources_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item: Array in Acoustics.top_sources(3):
		parts.append("%s %.0f dB" % [_pretty(String(item[0])), float(item[1])])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _pretty(label: String) -> String:
	if label.begins_with("voice:"):
		var peer: int = int(label.substr(6))
		return "voice (%s)" % crew_names.get(peer, "peer %d" % peer)
	if label.begins_with("footsteps:"):
		var peer2: int = int(label.substr(10))
		return "footsteps (%s)" % crew_names.get(peer2, "peer %d" % peer2)
	return label


static func _clock(seconds: float) -> String:
	var s: int = int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
