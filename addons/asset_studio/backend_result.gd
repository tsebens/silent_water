class_name AssetBackendResult
extends RefCounted
## One finished backend command: parsed from the process exit code and output.
## `error` is the backend's own message, verbatim, so the panel can show it as is.

var ok: bool = false
var error: String = ""
var data: Dictionary = {}
var exit_code: int = 0


## Joins a manifest path (repo-relative, forward slashes on every OS) to the project root.
## Backslashes are tolerated so a manifest written before paths were normalised still loads.
static func project_path(root: String, rel: String) -> String:
	return root.path_join(rel.replace("\\", "/"))


## `output` is stdout (and stderr, if the caller merged it). The backend prints one JSON
## object; anything else is surfaced as the error text, unmodified.
static func parse(exit_code_: int, output: String) -> AssetBackendResult:
	var r: AssetBackendResult = AssetBackendResult.new()
	r.exit_code = exit_code_
	var parsed: Variant = _last_json_object(output)
	if parsed is Dictionary:
		r.data = parsed as Dictionary
		var backend_ok: bool = bool(r.data.get("ok", exit_code_ == 0))
		r.ok = backend_ok and exit_code_ == 0
		if not r.ok:
			r.error = str(r.data.get("error", output.strip_edges()))
			if r.error == "" and r.data.has("failed"):
				r.error = "failed: %s" % str(r.data["failed"])
		return r
	r.ok = false
	r.error = output.strip_edges()
	if r.error == "":
		r.error = "backend exited with code %d and printed nothing" % exit_code_
	return r


static func failed_to_start(message: String) -> AssetBackendResult:
	var r: AssetBackendResult = AssetBackendResult.new()
	r.exit_code = -1
	r.error = message
	return r


## The backend prints a single JSON line, but tools it launches (uv, Blender) may print
## before it. Take the last line that parses as an object.
static func _last_json_object(output: String) -> Variant:
	var lines: PackedStringArray = output.strip_edges().split("\n")
	for i: int in range(lines.size() - 1, -1, -1):
		var line: String = lines[i].strip_edges()
		if not line.begins_with("{"):
			continue
		var v: Variant = JSON.parse_string(line)
		if v is Dictionary:
			return v
	return null
