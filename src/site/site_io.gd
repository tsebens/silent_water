class_name SiteIO
extends RefCounted
## Saving, loading and exporting dive-site data for the terrain lab: a
## [SiteSpec] as `.tres`, and the generated ground as a 16-bit heightmap with a
## JSON sidecar.
##
## Heightmap format: a PNG where each pixel's 16-bit height code is stored as
## red (high byte) and green (low byte); blue is 0. (Godot has no 16-bit
## greyscale format, and this stays lossless.) Row 0 is the minimum z. The code
## maps linearly onto [min_y, max_y]: y = min_y + code / 65535 * (max_y - min_y),
## so one step is (max_y - min_y) / 65535. The sidecar `<path>.json` holds the
## extent, cell size, grid size and vertical range.

const LEVELS: float = 65535.0


static func sidecar_path(image_path: String) -> String:
	return image_path.get_basename() + ".json"


static func save_spec(spec: SiteSpec, path: String) -> Error:
	return ResourceSaver.save(spec, path)


## The spec at [param path], or null if it is missing or not a [SiteSpec].
static func load_spec(path: String) -> SiteSpec:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return res as SiteSpec


## Samples [param site] over [param extent] (x, z rectangle) every [param cell]
## metres and writes the PNG and its sidecar. Returns OK or an error.
static func export_heightmap(site: CanyonSite, extent: Rect2, cell: float, path: String) -> Error:
	var w: int = maxi(int(floor(extent.size.x / cell)) + 1, 2)
	var h: int = maxi(int(floor(extent.size.y / cell)) + 1, 2)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(w * h)
	var lo: float = INF
	var hi: float = -INF
	for j: int in range(h):
		for i: int in range(w):
			var y: float = site.height_at(extent.position.x + i * cell, extent.position.y + j * cell)
			heights[j * w + i] = y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	if hi - lo < 0.001:
		hi = lo + 0.001
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	for j: int in range(h):
		for i: int in range(w):
			var code: int = clampi(roundi((heights[j * w + i] - lo) / (hi - lo) * LEVELS), 0, 65535)
			img.set_pixel(i, j, Color8(code >> 8, code & 255, 0))
	var err: Error = img.save_png(path)
	if err != OK:
		return err
	var meta: Dictionary = {
		"format": "rg16",
		"x_min": extent.position.x, "z_min": extent.position.y,
		"x_max": extent.position.x + (w - 1) * cell, "z_max": extent.position.y + (h - 1) * cell,
		"cell": cell, "width": w, "height": h,
		"min_y": lo, "max_y": hi, "vertical_scale": (hi - lo) / LEVELS,
	}
	var f: FileAccess = FileAccess.open(sidecar_path(path), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return OK


## Reads a heightmap written by [method export_heightmap]. Returns {} on
## failure, else the sidecar fields plus `heights` (PackedFloat32Array, row-major).
static func import_heightmap(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(sidecar_path(path), FileAccess.READ)
	if f == null:
		return {}
	var meta: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not meta is Dictionary or not (meta as Dictionary).has_all(["width", "height", "min_y", "max_y"]):
		return {}
	var out: Dictionary = meta
	var img: Image = Image.load_from_file(path)
	if img == null or img.get_width() != int(out["width"]) or img.get_height() != int(out["height"]):
		return {}
	var lo: float = out["min_y"]
	var hi: float = out["max_y"]
	var heights: PackedFloat32Array = PackedFloat32Array()
	for j: int in range(img.get_height()):
		for i: int in range(img.get_width()):
			var c: Color = img.get_pixel(i, j)
			var code: int = (roundi(c.r * 255.0) << 8) | roundi(c.g * 255.0)
			heights.append(lo + code / LEVELS * (hi - lo))
	out["heights"] = heights
	return out
