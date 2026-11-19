extends Node
## Developer log (autoload `DevLog`). Captures everything the engine prints,
## warns or errors into a ring buffer for the developer overlay, and relays
## host game events to every peer so clients see them too.

const MAX_LINES: int = 400

enum Kind { MESSAGE, WARNING, ERROR, EVENT }


class Capture extends Logger:
	var owner_log: Node

	func _log_message(message: String, error: bool) -> void:
		var text: String = message.strip_edges()
		if text == "":
			return
		var kind: int = Kind.ERROR if error else Kind.MESSAGE
		if text.begins_with("[log]"):
			kind = Kind.EVENT
		owner_log.call_thread_safe(&"_append", kind, text)

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var what: String = rationale if rationale != "" else code
		var kind: int = Kind.WARNING if error_type == Logger.ERROR_TYPE_WARNING else Kind.ERROR
		owner_log.call_thread_safe(&"_append", kind, "%s (%s:%d)" % [what, file.get_file(), line])


## [[kind, text, time_sec], ...], oldest first.
var lines: Array = []
## Bumped on every new line, so the overlay knows when to redraw.
var revision: int = 0

var _capture: Capture


func _ready() -> void:
	_capture = Capture.new()
	_capture.owner_log = self
	OS.add_logger(_capture)


func _exit_tree() -> void:
	if _capture != null:
		OS.remove_logger(_capture)


## Host: sends a game event line to every client's developer log.
func broadcast_event(text: String) -> void:
	if multiplayer.is_server() and Net.is_online() and not multiplayer.get_peers().is_empty():
		_rpc_event.rpc(text)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_event(text: String) -> void:
	_append(Kind.EVENT, "[host] " + text)


func _append(kind: int, text: String) -> void:
	lines.append([kind, text, Time.get_ticks_msec() / 1000.0])
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
	revision += 1
