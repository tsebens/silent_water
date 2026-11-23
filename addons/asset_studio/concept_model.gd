class_name AssetConceptModel
extends RefCounted
## View model for the Concept tab of one asset: variants, their state, the lineage panel,
## and the backend argument lists for each action. It builds arguments only; running them
## is AssetBackendRunner's job.

var slug: String = ""
var asset_class: String = ""
var description: String = ""
var variants: Array[Dictionary] = []
var image_providers: PackedStringArray = PackedStringArray()
var default_provider: String = ""
var prompt_writers: PackedStringArray = PackedStringArray()
var default_writer: String = ""
var _lineage: Array = []
## Variant id -> "rejected" or "approved".
var _decided: Dictionary = {}
## Approved variant ids, oldest first; the last is the locked concept.
var _approval_order: Array[String] = []
## Images being generated right now (placeholders in Pending); set by the panel.
var in_flight: int = 0


func load_asset(asset: Dictionary, providers: Dictionary = {}, selected: Dictionary = {}) -> void:
	slug = str(asset.get("slug", ""))
	asset_class = str(asset.get("class", ""))
	description = str(asset.get("description", ""))
	_lineage = asset.get("lineage", [])
	var locked_id: String = ""
	var locked: Variant = asset.get("locked")
	if locked is Dictionary:
		locked_id = str((locked as Dictionary).get("variant", ""))
	_decided.clear()
	# Decisions are in order, so the last "approved" is the latest approval. The manifest's
	# `locked` record is an approval too, and is the latest one by definition.
	_approval_order.clear()
	for d: Variant in asset.get("decisions", []):
		var dd: Dictionary = d
		var vid: String = str(dd.get("variant", ""))
		var verdict: String = str(dd.get("decision", ""))
		if verdict == "approved":
			_approve(vid)
		elif verdict == "rejected":
			_decided[vid] = "rejected"
	if locked_id != "":
		_approve(locked_id)
	variants.clear()
	for e: Variant in _lineage:
		var d: Dictionary = e
		if str(d.get("kind", "")) != "concept":
			continue
		var id: String = str(d.get("id", ""))
		variants.append({
			"id": id,
			"path": str(d.get("path", "")),
			"prompt": str(d.get("prompt", "")),
			"provider": str(d.get("provider", "")),
			"model": str(d.get("model", "")),
			"parent": d.get("parent"),
			"state": "pending",
			"caption": "%s · %s/%s" % [id, d.get("provider", ""), d.get("model", "")],
		})
	_refresh_states()
	image_providers = PackedStringArray()
	for n: Variant in providers.get("image", []):
		image_providers.append(str(n))
	default_provider = str(selected.get("image", ""))
	prompt_writers = PackedStringArray()
	for w: Variant in providers.get("prompt_writer", []):
		prompt_writers.append(str(w))
	default_writer = str(selected.get("prompt_writer", ""))


func _approve(id: String) -> void:
	_approval_order.erase(id)
	_approval_order.append(id)
	_decided[id] = "approved"


## Recompute each variant's state: "locked" for the latest approval, "accepted" for earlier
## approvals, "rejected", otherwise "pending".
func _refresh_states() -> void:
	var lid: String = locked_id()
	for v: Dictionary in variants:
		var id: String = str(v["id"])
		var verdict: String = str(_decided.get(id, ""))
		if verdict == "approved":
			v["state"] = "locked" if id == lid else "accepted"
		elif verdict == "rejected":
			v["state"] = "rejected"
		else:
			v["state"] = "pending"


## The most recently approved variant that still exists, or "".
func locked_id() -> String:
	for i: int in range(_approval_order.size() - 1, -1, -1):
		if not variant(_approval_order[i]).is_empty():
			return _approval_order[i]
	return ""


## Local decision, applied before the backend answers so the card moves at once. The next
## `load_asset` from the backend's manifest is authoritative.
func approve(id: String) -> void:
	if variant(id).is_empty():
		return
	_approve(id)
	_refresh_states()


func reject(id: String) -> void:
	if variant(id).is_empty():
		return
	_approval_order.erase(id)
	_decided[id] = "rejected"
	_refresh_states()


## Variants for one section: "pending", "accepted" (including the locked one, latest approval
## first) or "rejected".
func group(section: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v: Dictionary in variants:
		var st: String = str(v["state"])
		if section == "accepted":
			if st == "accepted" or st == "locked":
				out.append(v)
		elif st == section:
			out.append(v)
	if section == "accepted":
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _approval_order.find(str(a["id"])) > _approval_order.find(str(b["id"])))
	return out


## Section header text: "Pending (2)"; pending counts in-flight placeholders too.
func section_title(section: String) -> String:
	var n: int = group(section).size()
	if section == "pending":
		n += in_flight
	return "%s (%d)" % [section.capitalize(), n]


func variant(id: String) -> Dictionary:
	for v: Dictionary in variants:
		if v["id"] == id:
			return v
	return {}


## Lineage rows for `id`, nearest first: id, kind, provider, model, parent and prompt.
func lineage_of(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur: Variant = id
	var guard: int = 0
	while cur != null and guard < 1000:
		guard += 1
		var found: Dictionary = {}
		for e: Variant in _lineage:
			if str((e as Dictionary).get("id", "")) == str(cur):
				found = e
				break
		if found.is_empty():
			break
		out.append({
			"id": str(found.get("id", "")),
			"kind": str(found.get("kind", "")),
			"provider": str(found.get("provider", "")),
			"model": str(found.get("model", "")),
			"parent": found.get("parent"),
			"prompt": str(found.get("prompt", "")),
		})
		cur = found.get("parent")
	return out


func approve_args(variant_id: String, notes: String = "") -> PackedStringArray:
	var a: PackedStringArray = PackedStringArray(["lock", slug, variant_id, "--decision", "approved"])
	if notes != "":
		a.append_array(PackedStringArray(["--notes", notes]))
	return a


func reject_args(variant_id: String, notes: String = "") -> PackedStringArray:
	var a: PackedStringArray = PackedStringArray(["lock", slug, variant_id, "--decision", "rejected"])
	if notes != "":
		a.append_array(PackedStringArray(["--notes", notes]))
	return a


## Refining needs notes: the backend feeds them to the prompt writer.
func refine_args(variant_id: String, notes: String, provider: String = "", writer: String = "") -> PackedStringArray:
	if notes.strip_edges() == "":
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["concept", slug, "--refine", variant_id, "--notes", notes])
	if provider != "":
		a.append_array(PackedStringArray(["--image-provider", provider]))
	return _with_writer(a, writer)


func generate_more_args(n: int, provider: String = "", writer: String = "") -> PackedStringArray:
	var a: PackedStringArray = PackedStringArray(["concept", slug, "--n", str(maxi(n, 1))])
	if provider != "":
		a.append_array(PackedStringArray(["--image-provider", provider]))
	return _with_writer(a, writer)


## Redraft the brief with the chosen writer. The panel gates it on the turnaround model.
func brief_args(writer: String = "") -> PackedStringArray:
	if slug == "":
		return PackedStringArray()
	return _with_writer(PackedStringArray(["brief", slug]), writer)


func _with_writer(a: PackedStringArray, writer: String) -> PackedStringArray:
	if writer != "":
		a.append_array(PackedStringArray(["--prompt-writer", writer]))
	return a


## Generating needs a brief: the backend reads the description, so an empty one has no prompt.
func can_generate_more(edited_description: String = description) -> bool:
	return slug != "" and edited_description.strip_edges() != ""


func generate_hint(edited_description: String = description) -> String:
	return "" if can_generate_more(edited_description) else "Add a description to generate concepts."


## Empty when there is nothing to save (no asset, or a blank description).
func describe_args(text: String) -> PackedStringArray:
	if slug == "" or text.strip_edges() == "":
		return PackedStringArray()
	return PackedStringArray(["describe", slug, text.strip_edges()])
