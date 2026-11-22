class_name AssetModelModel
extends RefCounted
## View model for the Model tab: the mesh runs of one asset (raw provider results for the
## bake-off and cleaned meshes), the gate report, and the preview state (light, wireframe,
## turntable). It holds state and builds backend arguments; the SubViewport is the panel's.

const LIGHT_WHITE: StringName = &"white"
const LIGHT_RED: StringName = &"red"
const TURNTABLE_DEG_PER_SEC: float = 24.0
## How many runs can be shown side by side.
const MAX_COMPARE: int = 3

var slug: String = ""
var runs: Array[Dictionary] = []
var three_d_providers: PackedStringArray = PackedStringArray()
var default_provider: String = ""
var compare_ids: PackedStringArray = PackedStringArray()
var light: StringName = LIGHT_WHITE
var wireframe: bool = false
var turntable: bool = true
var angle_deg: float = 0.0
var _reports: Dictionary = {}


## `reports` maps a gate report's repo-relative path to its parsed JSON.
func load_asset(asset: Dictionary, providers: Dictionary = {}, selected: Dictionary = {}, reports: Dictionary = {}) -> void:
	slug = str(asset.get("slug", ""))
	_reports = reports
	var cleaned: Dictionary = {}
	for c: Variant in asset.get("cleanups", []):
		cleaned[str((c as Dictionary).get("id", ""))] = c
	var checks: Dictionary = {}
	for c: Variant in asset.get("checks", []):
		checks[str((c as Dictionary).get("id", ""))] = c  # the newest check of a mesh wins
	var exported: Dictionary = {}
	for x: Variant in asset.get("exports", []):
		exported[str((x as Dictionary).get("id", ""))] = true
	runs.clear()
	for e: Variant in asset.get("lineage", []):
		var d: Dictionary = e
		if str(d.get("kind", "")) != "mesh":
			continue
		var id: String = str(d.get("id", ""))
		var cleanup: Dictionary = cleaned.get(id, {})
		var check: Dictionary = checks.get(id, {})
		var triangles: int = int((cleanup.get("result", {}) as Dictionary).get("triangles", 0))
		var report: Dictionary = _reports.get(str(check.get("report", "")), {})
		if triangles == 0 and not report.is_empty():
			for g: Variant in report.get("gates", []):
				if str((g as Dictionary).get("name", "")) == "triangles":
					triangles = int((g as Dictionary).get("value", 0))
		runs.append({
			"id": id,
			"path": str(d.get("path", "")),
			"provider": str(d.get("provider", "")),
			"model": str(d.get("model", "")),
			"parent": d.get("parent"),
			"stage": "cleaned" if cleaned.has(id) else "raw",
			"triangles": triangles,
			"checked": not check.is_empty(),
			"gate_ok": bool(check.get("ok", false)),
			"failed": PackedStringArray(check.get("failed", [])),
			"report": str(check.get("report", "")),
			"exported": exported.has(id),
			"caption": "%s · %s %s" % [id, d.get("provider", ""), "cleaned" if cleaned.has(id) else "raw"],
		})
	three_d_providers = PackedStringArray()
	for n: Variant in providers.get("three_d", []):
		three_d_providers.append(str(n))
	default_provider = str(selected.get("three_d", ""))
	# Keep only comparisons that still exist; start with the newest run.
	var keep: PackedStringArray = PackedStringArray()
	for id: String in compare_ids:
		if not run(id).is_empty():
			keep.append(id)
	compare_ids = keep
	if compare_ids.is_empty() and not runs.is_empty():
		compare_ids.append(str(runs[-1]["id"]))


func run(id: String) -> Dictionary:
	for r: Dictionary in runs:
		if r["id"] == id:
			return r
	return {}


## Adds or removes a run from the side-by-side set. Returns false when the set is full
## or the run is unknown; the last remaining run cannot be removed.
func toggle_compare(id: String) -> bool:
	if run(id).is_empty():
		return false
	var idx: int = compare_ids.find(id)
	if idx >= 0:
		if compare_ids.size() == 1:
			return false
		compare_ids.remove_at(idx)
		return true
	if compare_ids.size() >= MAX_COMPARE:
		return false
	compare_ids.append(id)
	return true


## The gate report of a run as rows: name, ok, value, limit, detail. Empty if none loaded.
func gate_rows(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var report: Dictionary = _reports.get(str(run(id).get("report", "")), {})
	for g: Variant in report.get("gates", []):
		var d: Dictionary = g
		out.append({
			"name": str(d.get("name", "")),
			"ok": bool(d.get("ok", false)),
			"value": d.get("value"),
			"limit": d.get("limit"),
			"detail": str(d.get("detail", "")),
		})
	return out


## One line for the header of a run's gate report.
func gate_summary(id: String) -> String:
	var r: Dictionary = run(id)
	if r.is_empty():
		return ""
	if not r["checked"]:
		return "not checked"
	if r["gate_ok"]:
		return "all gates pass"
	return "failed: %s" % ", ".join(r["failed"] as PackedStringArray)


func triangle_text(id: String) -> String:
	var t: int = int(run(id).get("triangles", 0))
	return "%d triangles" % t if t > 0 else "triangles: unknown"


# --- preview state -----------------------------------------------------------------------

func set_light(which: StringName) -> void:
	if which == LIGHT_WHITE or which == LIGHT_RED:
		light = which


func toggle_light() -> void:
	light = LIGHT_RED if light == LIGHT_WHITE else LIGHT_WHITE


func light_color() -> Color:
	return Color(1.0, 0.05, 0.03) if light == LIGHT_RED else Color(1.0, 1.0, 1.0)


func toggle_wireframe() -> void:
	wireframe = not wireframe


func toggle_turntable() -> void:
	turntable = not turntable


## Advances the turntable by `delta` seconds when it is on, and returns the angle.
func advance(delta: float) -> float:
	if turntable:
		angle_deg = fmod(angle_deg + TURNTABLE_DEG_PER_SEC * delta, 360.0)
	return angle_deg


## Triangles in a mesh, for runs loaded from a GLB where the manifest has no count.
static func count_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			var v: Variant = arrays[Mesh.ARRAY_VERTEX]
			total += (v as PackedVector3Array).size() / 3 if v != null else 0
	return total


# --- backend arguments -------------------------------------------------------------------

## Sends the turnaround to one or more providers: several is the bake-off.
func to3d_args(providers: PackedStringArray) -> PackedStringArray:
	if providers.is_empty():
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["to3d", slug, "--3d-provider"])
	a.append_array(providers)
	return a


## Cleanup works from a raw provider mesh only.
func cleanup_args(id: String) -> PackedStringArray:
	if run(id).is_empty() or run(id)["stage"] != "raw":
		return PackedStringArray()
	return PackedStringArray(["cleanup", slug, "--source", id])


func check_args(id: String) -> PackedStringArray:
	if run(id).is_empty() or run(id)["stage"] != "cleaned":
		return PackedStringArray()
	return PackedStringArray(["check", slug, "--source", id])


## Export needs a cleaned mesh that passed its gates; the backend enforces it too.
func export_args(id: String) -> PackedStringArray:
	var r: Dictionary = run(id)
	if r.is_empty() or r["stage"] != "cleaned" or not r["gate_ok"]:
		return PackedStringArray()
	return PackedStringArray(["export", slug, "--source", id])


func can_export(id: String) -> bool:
	return not export_args(id).is_empty()
