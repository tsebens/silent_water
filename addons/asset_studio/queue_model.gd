class_name AssetQueueModel
extends RefCounted
## View model for the Queue tab: one row per asset manifest (as printed by `asset list`).

var rows: Array[Dictionary] = []


## `assets` is the `assets` array from the backend's `list` output.
func load_assets(assets: Array) -> void:
	rows.clear()
	for a: Variant in assets:
		if a is Dictionary:
			rows.append(_row(a as Dictionary))
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["slug"]) < str(y["slug"]))


func find(slug: String) -> Dictionary:
	for r: Dictionary in rows:
		if r["slug"] == slug:
			return r
	return {}


static func _row(a: Dictionary) -> Dictionary:
	var issue: Variant = a.get("issue")
	return {
		"slug": str(a.get("slug", "")),
		"class": str(a.get("class", "")),
		"stage": str(a.get("stage", "new")),
		"issue": int(issue) if issue != null else 0,
		"issue_text": "#%d" % int(issue) if issue != null else "-",
		"last_result": last_result(a),
	}


## The newest recorded event of the asset, as a short sentence. Timestamps are ISO-8601
## UTC, so they sort as strings.
static func last_result(a: Dictionary) -> String:
	var events: Array[Array] = []
	for e: Variant in a.get("lineage", []):
		var d: Dictionary = e
		events.append([str(d.get("created", "")), "%s %s (%s)" % [d.get("kind", ""), d.get("id", ""), d.get("provider", "")]])
	for c: Variant in a.get("cleanups", []):
		var d: Dictionary = c
		events.append([str(d.get("at", "")), "cleanup %s" % d.get("id", "")])
	for c: Variant in a.get("checks", []):
		var d: Dictionary = c
		var text: String = "check passed"
		if not bool(d.get("ok", false)):
			var failed: Array = d.get("failed", [])
			text = "check failed: %s" % ", ".join(PackedStringArray(failed))
		events.append([str(d.get("at", "")), text])
	for c: Variant in a.get("godot_checks", []):
		var d: Dictionary = c
		var text: String = "godot-check ok" if bool(d.get("ok", false)) else "godot-check failed: %s" % d.get("error", "")
		events.append([str(d.get("at", "")), text])
	for c: Variant in a.get("exports", []):
		var d: Dictionary = c
		events.append([str(d.get("at", "")), "exported %s" % d.get("id", "")])
	for key: String in ["decisions"]:
		for c: Variant in a.get(key, []):
			var d: Dictionary = c
			events.append([str(d.get("at", "")), "%s %s" % [d.get("decision", ""), d.get("variant", "")]])
	var locked: Variant = a.get("locked")
	if locked is Dictionary:
		var d: Dictionary = locked
		events.append([str(d.get("at", "")), "locked %s" % d.get("variant", "")])
	if events.is_empty():
		return "-"
	# Stable: later entries win ties, so the order recorded above (generation first) breaks them.
	var best: Array = events[0]
	for ev: Array in events:
		if str(ev[0]) >= str(best[0]):
			best = ev
	return str(best[1])
