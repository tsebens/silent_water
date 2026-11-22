class_name AssetBackendRunner
extends Node
## Runs `asset <args>` off the main thread so the editor never blocks on a network call.
## Emits `started` then `finished`; `finished` always fires on the main thread.

signal started(args: PackedStringArray)
signal finished(args: PackedStringArray, result: AssetBackendResult)

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
	if code == -1 and text == "":
		result = AssetBackendResult.failed_to_start(
			"could not start '%s' (is it installed and on PATH?)" % executable
		)
	else:
		result = AssetBackendResult.parse(code, text)
	_done.call_deferred(args, result)


## `cd` into the project root via a shell-free wrapper: Godot's OS.execute has no cwd,
## so the backend is told the root through ASSET_PIPELINE_ROOT instead.
func _execute(exe: String, full: PackedStringArray, cwd: String, output: Array) -> int:
	OS.set_environment("ASSET_PIPELINE_ROOT", cwd.trim_suffix("/"))
	return OS.execute(exe, full, output, true)


func _done(args: PackedStringArray, result: AssetBackendResult) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	finished.emit(args, result)


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
