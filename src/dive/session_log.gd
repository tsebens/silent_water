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

@export var controller: SubController
@export var apex: ApexMonster
@export var leaks: LeakSystem
@export var scan: ScanObjective
@export var director: DiveDirector
## Names to print instead of peer ids (filled from launch names if known).
var crew_names: Dictionary = {}

var _file: FileAccess
var _t: float = 0.0
var _loud_cooldown: float = 0.0
var _path: String = ""


func _ready() -> void:
	apex.state_changed.connect(_on_apex_state)
	apex.near_miss.connect(func(d: float) -> void: write("NEAR MISS  apex passed %.0f m away" % d))
	controller.hull_strike.connect(func(speed: float) -> void: write("HULL STRIKE  %.1f m/s at %.0f m" % [speed, controller.depth]))
	leaks.leak_opened.connect(func(where: String) -> void: write("LEAK  opened at %s" % where))
	leaks.leak_patched.connect(func(q: float, hold: float) -> void: write("PATCH  quality %.0f%%, holds ~%.0f s" % [q * 100.0, hold]))
	scan.scan_started.connect(func() -> void: write("SCANNER ON  at %.0f m, %.0f m from the array" % [controller.depth, controller.model.position.distance_to(scan.target.position)]))
	scan.scan_completed.connect(func() -> void: write("ARRAY SCANNED"))
	director.dive_lost.connect(func() -> void: write("SUB LOST  after %s, max depth %.0f m" % [_clock(director.dive_time), director.max_depth]))
	director.dive_complete.connect(func() -> void: write("DIVE COMPLETE  in %s, max depth %.0f m" % [_clock(director.dive_time), director.max_depth]))
	director.dive_reset.connect(func() -> void: write("---- NEW DIVE ----"))


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


func log_path() -> String:
	return _path


func write(line: String) -> void:
	if not multiplayer.is_server():
		return
	var entry: String = "[%s] %s" % [_clock(_t), line]
	print("[log] " + entry)
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
