class_name AssetImportModel
extends RefCounted
## Model of the Import CAD dialog (kit parts): the glTF export, the pivot part name and the
## `asset import` call built from them. The backend still has the last word.

const EXPORT_SUFFIXES: PackedStringArray = ["gltf", "glb"]

var slug: String = ""
var export_path: String = ""
var pivot: String = ""


func open(asset_slug: String) -> void:
	slug = asset_slug
	export_path = ""
	pivot = ""


## Empty when valid, else a one-line reason.
func error() -> String:
	if slug == "":
		return "Select an asset."
	if export_path.strip_edges() == "":
		return "Choose a glTF export."
	if not EXPORT_SUFFIXES.has(export_path.get_extension().to_lower()):
		return "The export must be a .gltf or .glb file."
	return ""


func is_valid() -> bool:
	return error() == ""


## Empty when the form is invalid. `--pivot` only when a part name is given.
func import_args() -> PackedStringArray:
	if not is_valid():
		return PackedStringArray()
	var a: PackedStringArray = PackedStringArray(["import", slug, export_path.strip_edges()])
	var p: String = pivot.strip_edges()
	if p != "":
		a.append_array(PackedStringArray(["--pivot", p]))
	return a
