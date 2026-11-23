class_name AssetBackendRunner
extends Node
## Runs `asset <args>` off the main thread so the editor never blocks on a network call.
## Emits `started` then `finished`; `finished` always fires on the main thread.

signal started(args: PackedStringArray)
signal finished(args: PackedStringArray, result: AssetBackendResult)
## One line the running command wrote to stderr (the backend's progress), on the main thread.
signal progress(line: String)

## Executable and leading arguments; `asset` and the command follow.
var executable: String = "uv"
var base_args: PackedStringArray = PackedStringArray(["run", "--project", "tools/asset_pipeline", "asset"])
## Working directory for the process (the project root).
var working_dir: String = ""

var busy: bool = false
var _thread: Thread


func run(args: PackedStringArray) -> bool:
	if busy:
		return false
	busy = true
	started.emit(args)
	_thread = Thread.new()
	_thread.start(_work.bind(args))
	return true


func _work(args: PackedStringArray) -> void:
	var full: PackedStringArray = base_args + args
	var output: Array = []
	var cwd: String = working_dir if working_dir != "" else ProjectSettings.globalize_path("res://")
	var code: int = _execute(executable, full, cwd, output)
	var text: String = ""
	for chunk: Variant in output:
		text += str(chunk)
	var result: AssetBackendResult
	# A process that cannot be exec'd exits non-zero with no output at all.
	if (code == -1 or code > 0) and text.strip_edges() == "":
		result = AssetBackendResult.failed_to_start(
			"could not start '%s' (exit %d; is it installed and on PATH?)" % [executable, code]
		)
	else:
		result = AssetBackendResult.parse(code, text)
	_done.call_deferred(args, result)


## Godot's OS.execute has no cwd, so the backend is told the project root through
## ASSET_PIPELINE_ROOT. The pipes are non-blocking, so both are polled until the process
## exits (then drained once more): stderr lines are reported live as progress, and stdout
## is collected for the single JSON object. Returns -1 with no output when it cannot start.
func _execute(exe: String, full: PackedStringArray, cwd: String, output: Array) -> int:
	OS.set_environment("ASSET_PIPELINE_ROOT", cwd.trim_suffix("/"))
	var proc: Dictionary = OS.execute_with_pipe(exe, full, false)
	if proc.is_empty():
		return -1
	var out_pipe: FileAccess = proc["stdio"]
	var err_pipe: FileAccess = proc["stderr"]
	var pid: int = int(proc["pid"])
	var out_text: String = ""
	var err_text: String = ""
	var running: bool = true
	while true:
		running = OS.is_process_running(pid)
		var got: bool = false
		while true:
			var chunk: String = out_pipe.get_line()
			if chunk == "" and out_pipe.get_error() != OK:
				break
			out_text += chunk + "\n"
			got = true
		while true:
			var line: String = err_pipe.get_line()
			if line == "" and err_pipe.get_error() != OK:
				break
			err_text += line + "\n"
			_report_stderr(line)
			got = true
		if not running and not got:
			break
		if not got:
			OS.delay_msec(20)
	var code: int = OS.get_process_exit_code(pid)
	output.append(out_text)
	# A failure may print its reason only to stderr; keep it so the panel can show it.
	if code != 0:
		output.append(err_text)
	return code


## Forwards one stderr line to the main thread; blank lines are not progress.
func _report_stderr(line: String) -> void:
	if line.strip_edges() != "":
		progress.emit.call_deferred(line.strip_edges())


func _done(args: PackedStringArray, result: AssetBackendResult) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	finished.emit(args, result)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
