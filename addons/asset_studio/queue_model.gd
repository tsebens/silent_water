class_name AssetQueueModel
extends RefCounted
## View model for the Queue tab: one row per asset manifest (as printed by `asset list`).

var rows: Array[Dictionary] = []
## Folder tree under assets/models/: {"path": "", "name": "", "folders": [node...], "assets": [row...]}.
## Folders and assets are sorted by name; folders without assets are kept.
var root: Dictionary = _folder_node("")


## `assets` is the `assets` array from the backend's `list` output; each may carry a
## `folder` ("a/b", POSIX, relative to assets/models; absent or "" for the root). `folders`
## is the optional `folders` array of the same output, so empty folders show too.
func load_assets(assets: Array, folders: Array = []) -> void:
	rows.clear()
	for a: Variant in assets:
		if a is Dictionary:
			rows.append(_row(a as Dictionary))
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["slug"]) < str(y["slug"]))
	root = _folder_node("")
	for f: Variant in folders:
		_ensure_folder(str(f))
	for r: Dictionary in rows:
		(_ensure_folder(str(r["folder"]))["assets"] as Array).append(r)


## The folder node at `path` ("" is the root), or an empty dictionary.
func find_folder(path: String) -> Dictionary:
	var node: Dictionary = root
	for part: String in _parts(path):
		var next: Dictionary = {}
		for f: Dictionary in node["folders"]:
			if f["name"] == part:
				next = f
		if next.is_empty():
			return {}
		node = next
	return node


## Every folder path in the tree, root excluded.
func folder_paths() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_collect_paths(root, out)
	return out


## Whether dragging `drag` onto `target` is a legal move. `drag` is {"kind": "asset", "slug"}
## or {"kind": "folder", "path"}; `target` is {"kind": "folder", "path"} (path "" = root).
## Rejected: any non-folder target, a folder into itself or a descendant, and a move that
## leaves the item where it is. The backend still validates; this only keeps bad drops from
## being offered.
func can_drop(drag: Dictionary, target: Dictionary) -> bool:
	if str(target.get("kind", "")) != "folder":
		return false
	var dest: String = str(target.get("path", ""))
	if not find_folder(dest).has("path"):
		return false
	match str(drag.get("kind", "")):
		"asset":
			var a: Dictionary = find(str(drag.get("slug", "")))
			return not a.is_empty() and str(a["folder"]) != dest
		"folder":
			var src: String = str(drag.get("path", ""))
			if src == "" or not find_folder(src).has("path"):
				return false
			if dest == src or dest.begins_with(src + "/"):
				return false
			return _parent_of(src) != dest
	return false


## The backend call for a legal drop; empty when `can_drop` refuses it.
func drop_args(drag: Dictionary, target: Dictionary) -> PackedStringArray:
	if not can_drop(drag, target):
		return PackedStringArray()
	var dest: String = str(target["path"])
	if str(drag["kind"]) == "asset":
		return PackedStringArray(["move", str(drag["slug"]), "--to", dest])
	return PackedStringArray(["folder", "move", str(drag["path"]), "--to", dest])


## The folder New asset creates in: the selected folder, else the selected asset's folder,
## else the root (""). `sel` is {"kind": "folder"|"asset", "path"|"slug"} or empty.
func new_asset_folder(sel: Dictionary) -> String:
	match str(sel.get("kind", "")):
		"folder":
			var p: String = str(sel.get("path", ""))
			return p if find_folder(p).has("path") else ""
		"asset":
			return str(find(str(sel.get("slug", ""))).get("folder", ""))
	return ""


## `asset folder rename <path> <new-name>`; empty for a blank name or the root.
static func rename_args(path: String, new_name: String) -> PackedStringArray:
	if path == "" or new_name.strip_edges() == "":
		return PackedStringArray()
	return PackedStringArray(["folder", "rename", path, new_name.strip_edges()])


## `asset folder create <path>` for a new folder named `name` under `parent`.
static func create_folder_args(parent: String, name: String) -> PackedStringArray:
	var n: String = name.strip_edges()
	if n == "" or n.contains("/") or n.contains("\\"):
		return PackedStringArray()
	return PackedStringArray(["folder", "create", n if parent == "" else parent + "/" + n])


## Right-click menu entries for a queue row. `kind` is "asset" or "folder"; `is_root` marks
## the assets/models root. Ids: new_here, new_folder, rename_folder, rename, delete.
## Everything is disabled while a backend command runs.
static func menu_items(kind: String, is_root: bool, busy: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if kind == "asset":
		out.append({"id": "rename", "label": "Rename…", "disabled": busy})
		out.append({"id": "delete", "label": "Delete…", "disabled": busy})
	elif kind == "folder":
		out.append({"id": "new_here", "label": "New asset here", "disabled": busy})
		out.append({"id": "new_folder", "label": "New folder", "disabled": busy})
		out.append({"id": "rename_folder", "label": "Rename", "disabled": busy or is_root})
		out.append({"id": "delete", "label": "Delete…", "disabled": busy or is_root})
	return out


## `asset folder delete <path>`; empty for the root.
static func folder_delete_args(path: String) -> PackedStringArray:
	if path == "":
		return PackedStringArray()
	return PackedStringArray(["folder", "delete", path])


## `asset delete <slug>`; empty for a blank slug.
static func delete_args(slug: String) -> PackedStringArray:
	if slug == "":
		return PackedStringArray()
	return PackedStringArray(["delete", slug])


## Confirmation text for deleting an asset, from its manifest (as printed by `asset list`).
## `present_files` are the last export's files that exist on disk.
static func delete_summary(asset: Dictionary, present_files: PackedStringArray) -> String:
	var kinds: Array[String] = []
	for e: Variant in asset.get("lineage", []):
		kinds.append(str((e as Dictionary).get("kind", "")))
	var costs: Array = asset.get("costs", [])
	var lines: PackedStringArray = PackedStringArray([
		"Delete asset '%s'?" % str(asset.get("slug", "")),
		"Class: %s, stage: %s" % [str(asset.get("class", "")), str(asset.get("stage", "new"))],
		"Variants: %d, turnaround views: %d, meshes: %d" % [kinds.count("concept"), kinds.count("turnaround"), kinds.count("mesh")],
		"Cost spent: %s" % AssetCostModel.money(AssetCostModel.total_of(costs), AssetCostModel.has_estimated(costs)),
	])
	if present_files.is_empty():
		lines.append("No exported files.")
	else:
		lines.append("Exported files: %s" % ", ".join(present_files))
	lines.append("It moves to .asset_work/_trash/ and can be recovered from there.")
	return "\n".join(lines)


## The last export's files for `asset`, which the panel filters by existence on disk.
static func exported_files(asset: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var exports: Array = asset.get("exports", [])
	if not exports.is_empty():
		for f: Variant in (exports[-1] as Dictionary).get("files", []):
			out.append(str(f))
	return out


## Confirmation text for deleting a folder; lists the assets it holds (recursively).
func delete_folder_summary(path: String) -> String:
	var slugs: PackedStringArray = PackedStringArray()
	_collect_slugs(find_folder(path), slugs)
	if slugs.is_empty():
		return "Delete empty folder '%s'?" % path
	slugs.sort()
	return "Delete folder '%s' and move its %d asset(s) to the trash?\n%s" % [path, slugs.size(), ", ".join(slugs)]


func _collect_slugs(node: Dictionary, out: PackedStringArray) -> void:
	if node.is_empty():
		return
	for r: Dictionary in node["assets"]:
		out.append(str(r["slug"]))
	for f: Dictionary in node["folders"]:
		_collect_slugs(f, out)


## Tooltip text for an asset row: the details the narrow tree no longer shows.
static func tooltip(row: Dictionary) -> String:
	return "%s\nclass: %s\nissue: %s\ncost: %s\nlast: %s" % [
		row["slug"], row["class"], row["issue_text"], row["cost_text"], row["last_result"]]


static func _folder_node(path: String) -> Dictionary:
	return {"path": path, "name": path.get_file(), "folders": [] as Array[Dictionary], "assets": [] as Array[Dictionary]}


func _ensure_folder(path: String) -> Dictionary:
	var node: Dictionary = root
	var so_far: String = ""
	for part: String in _parts(path):
		so_far = part if so_far == "" else so_far + "/" + part
		var next: Dictionary = {}
		for f: Dictionary in node["folders"]:
			if f["name"] == part:
				next = f
		if next.is_empty():
			next = _folder_node(so_far)
			(node["folders"] as Array).append(next)
			(node["folders"] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["name"]) < str(y["name"]))
		node = next
	return node


static func _parts(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for p: String in path.replace("\\", "/").split("/"):
		if p != "":
			out.append(p)
	return out


static func _parent_of(path: String) -> String:
	var i: int = path.rfind("/")
	return "" if i < 0 else path.substr(0, i)


func _collect_paths(node: Dictionary, out: PackedStringArray) -> void:
	for f: Dictionary in node["folders"]:
		out.append(str(f["path"]))
		_collect_paths(f, out)


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
		"folder": "/".join(_parts(str(a.get("folder", "")))),
		"stage": str(a.get("stage", "new")),
		"issue": int(issue) if issue != null else 0,
		"issue_text": "#%d" % int(issue) if issue != null else "-",
		"last_result": last_result(a),
		"cost_usd": AssetCostModel.total_of(a.get("costs", [])),
		"cost_text": AssetCostModel.money(AssetCostModel.total_of(a.get("costs", [])), AssetCostModel.has_estimated(a.get("costs", []))),
		"over_budget": a.get("budget_usd") != null and AssetCostModel.total_of(a.get("costs", [])) > float(a["budget_usd"]),
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
