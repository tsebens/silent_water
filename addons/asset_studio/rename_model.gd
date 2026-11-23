class_name AssetRenameModel
extends RefCounted
## Model of the Rename dialog: validates the new slug with the New asset rules and builds
## the `asset rename` call. The backend still has the last word.

var old_slug: String = ""
var new_slug: String = ""
var existing_slugs: PackedStringArray = PackedStringArray()


func open(slug: String, slugs: PackedStringArray) -> void:
	old_slug = slug
	new_slug = slug
	existing_slugs = slugs


## Empty when valid, else a one-line reason.
func error() -> String:
	if new_slug == old_slug:
		return "Enter a different slug."
	var m: AssetNewAssetModel = AssetNewAssetModel.new()
	m.slug = new_slug
	m.load_existing(existing_slugs)
	return m.slug_error()


func is_valid() -> bool:
	return old_slug != "" and error() == ""


## Empty when the form is invalid.
func rename_args() -> PackedStringArray:
	if not is_valid():
		return PackedStringArray()
	return PackedStringArray(["rename", old_slug, new_slug])
