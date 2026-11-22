class_name AssetTurnaroundModel
extends RefCounted
## View model for the Turnaround and brief tab: the four orthographic views of the latest
## turnaround set, the editable brief.md, and the backend argument lists for each action.

const VIEW_ORDER: PackedStringArray = ["front", "left", "back", "right"]

var slug: String = ""
var views: Array[Dictionary] = []
var brief_path: String = ""
var brief_text: String = ""
var dirty: bool = false
var has_locked_concept: bool = false
var _saved_text: String = ""


## `brief_text` is the current contents of the asset's brief.md ("" when there is none yet).
func load_asset(asset: Dictionary, brief_contents: String = "") -> void:
	slug = str(asset.get("slug", ""))
	var locked: Variant = asset.get("locked")
	has_locked_concept = locked is Dictionary and str((locked as Dictionary).get("decision", "")) == "approved"
	var latest: String = _latest_prefix(asset.get("lineage", []))
	var by_view: Dictionary = {}
	for e: Variant in asset.get("lineage", []):
		var d: Dictionary = e
		if str(d.get("kind", "")) == "turnaround" and latest != "" and str(d.get("id", "")).begins_with(latest):
			by_view[str(d["id"]).substr(latest.length())] = d
	views.clear()
	for v: String in VIEW_ORDER:
		var d: Dictionary = by_view.get(v, {})
		views.append({
			"view": v,
			"id": str(d.get("id", "")),
			"path": str(d.get("path", "")),
			"provider": str(d.get("provider", "")),
			"model": str(d.get("model", "")),
			"present": not d.is_empty(),
			"caption": "%s · %s/%s" % [v, d.get("provider", "-"), d.get("model", "-")] if not d.is_empty() else "%s · missing" % v,
		})
	var brief: Variant = asset.get("brief")
	brief_path = str((brief as Dictionary).get("path", "")) if brief is Dictionary else ""
	brief_text = brief_contents
	_saved_text = brief_contents
	dirty = false


## Ids look like `t<n>_<view>`; the latest set is the highest n. Returns e.g. "t2_".
static func _latest_prefix(lineage: Array) -> String:
	var best: int = 0
	for e: Variant in lineage:
		var d: Dictionary = e
		if str(d.get("kind", "")) != "turnaround":
			continue
		var id: String = str(d.get("id", ""))
		var us: int = id.find("_")
		if id.begins_with("t") and us > 1 and id.substr(1, us - 1).is_valid_int():
			best = maxi(best, int(id.substr(1, us - 1)))
	return "t%d_" % best if best > 0 else ""


func view(name: String) -> Dictionary:
	for v: Dictionary in views:
		if v["view"] == name:
			return v
	return {}


func present_count() -> int:
	var n: int = 0
	for v: Dictionary in views:
		if v["present"]:
			n += 1
	return n


func set_brief_text(text: String) -> void:
	brief_text = text
	dirty = text != _saved_text


func mark_saved() -> void:
	_saved_text = brief_text
	dirty = false


## Where brief.md goes when the asset has none yet.
func target_brief_path() -> String:
	return brief_path if brief_path != "" else "assets/models/%s/concept/brief.md" % slug


## The brief can be saved only when something changed.
func can_save_brief() -> bool:
	return dirty and slug != ""


## Re-derives all four views from the locked concept. Empty when nothing is locked.
func generate_args(provider: String = "") -> PackedStringArray:
	if not has_locked_concept:
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["turnaround", slug])
	if provider != "":
		a.append_array(PackedStringArray(["--image-provider", provider]))
	return a


## Regenerates one view. Empty for an unknown view or when nothing is locked.
func regenerate_args(view_name: String, provider: String = "") -> PackedStringArray:
	if not has_locked_concept or not VIEW_ORDER.has(view_name):
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["turnaround", slug, "--view", view_name])
	if provider != "":
		a.append_array(PackedStringArray(["--image-provider", provider]))
	return a


## Redrafts brief.md from the locked concept and views. Needs all four views and no
## unsaved edits (the backend overwrites the file).
func draft_brief_args() -> PackedStringArray:
	if not has_locked_concept or present_count() < VIEW_ORDER.size() or dirty:
		return PackedStringArray()
	return PackedStringArray(["brief", slug])
