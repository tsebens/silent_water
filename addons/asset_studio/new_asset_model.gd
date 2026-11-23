class_name AssetNewAssetModel
extends RefCounted
## Model of the New asset dialog: validates the form and builds the `asset new` call.
## Validation here mirrors the backend's rules so the dialog can disable OK; the backend
## still has the last word and its errors are shown verbatim.

const CLASSES: PackedStringArray = ["creature", "prop", "architecture", "terrain"]

var slug: String = ""
var asset_class: String = "creature"
var issue_text: String = ""
var description: String = ""
## Folder under assets/models/ ("" for the root); set from the queue selection.
var folder: String = ""
var existing_slugs: PackedStringArray = PackedStringArray()


func load_existing(slugs: PackedStringArray) -> void:
	existing_slugs = slugs


## Empty when valid, else a one-line reason.
func slug_error() -> String:
	if slug == "":
		return "Enter a slug."
	if not _slug_ok(slug):
		return "Slug may use lowercase letters, digits and _ only."
	if existing_slugs.has(slug):
		return "An asset named '%s' already exists." % slug
	return ""


func issue_error() -> String:
	var t: String = issue_text.strip_edges().trim_prefix("#")
	if t == "":
		return ""
	if not t.is_valid_int() or t.to_int() <= 0:
		return "Issue must be a positive number."
	return ""


func description_error() -> String:
	return "" if description.strip_edges() != "" else "Enter a description."


func error() -> String:
	for e: String in [slug_error(), issue_error(), description_error()]:
		if e != "":
			return e
	if not CLASSES.has(asset_class):
		return "Pick a class."
	return ""


func is_valid() -> bool:
	return error() == ""


## Empty when the form is invalid, so a caller cannot run a half-formed command.
func new_args() -> PackedStringArray:
	if not is_valid():
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["new", slug, "--class", asset_class])
	var t: String = issue_text.strip_edges().trim_prefix("#")
	if t != "":
		a.append_array(PackedStringArray(["--issue", str(t.to_int())]))
	if folder != "":
		a.append_array(PackedStringArray(["--folder", folder]))
	a.append_array(PackedStringArray(["--description", description.strip_edges()]))
	return a


static func _slug_ok(s: String) -> bool:
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true
