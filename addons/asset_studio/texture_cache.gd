class_name AssetTextureCache
extends RefCounted
## Loads each image file once. An unreadable file is remembered with its reason and warned
## about once per session, so redraws never re-read the disk or repeat the error.

## Absolute path -> Texture2D.
var _textures: Dictionary = {}
## Absolute path -> reason it could not be read.
var _failed: Dictionary = {}
## How many times a file was actually read from disk (for tests).
var loads: int = 0
## Warnings logged so far.
var warnings: int = 0


## The texture for `abs_path`, or null when it is missing or unreadable; see `error_for`.
func get_texture(abs_path: String) -> Texture2D:
	if _textures.has(abs_path):
		return _textures[abs_path]
	if _failed.has(abs_path):
		return null
	loads += 1
	if abs_path == "" or not FileAccess.file_exists(abs_path):
		_failed[abs_path] = "file not found" if abs_path != "" else "no file"
		return null
	var img: Image = Image.new()
	var err: Error = img.load(abs_path)
	if err != OK:
		_failed[abs_path] = error_string(err)
		warnings += 1
		push_warning("Asset Studio: unreadable image %s: %s" % [abs_path, _failed[abs_path]])
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_textures[abs_path] = tex
	return tex


## "" when the file loaded (or has not been tried); otherwise why it could not be read.
func error_for(abs_path: String) -> String:
	return str(_failed.get(abs_path, ""))


## Forget one file, e.g. after the backend rewrote it.
func forget(abs_path: String) -> void:
	_textures.erase(abs_path)
	_failed.erase(abs_path)
