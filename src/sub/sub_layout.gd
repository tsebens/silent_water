class_name SubLayout
extends RefCounted
## Where the program puts things, in the interior frame. The one place that converts between frames.
##
## The program (assets/models/vehicles/sub_interior/program.yaml) works in the hull-centre frame: origin at the
## hull's centre, main deck at y = main_deck_y (-0.95). The interior frame has its origin on the main cabin
## floor at the centreline, so y is the program's y minus main_deck_y. X (starboard) and Z (stern) are the same
## in both. Godot cannot read YAML, so this reads layout.json, which plan.py generates from the program.
## See docs/sub_frame.md.

const LAYOUT_PATH: String = "res://assets/models/vehicles/sub_interior/layout.json"

static var _data: Dictionary = {}
static var _items: Dictionary = {}


## Parse layout.json once and index its items by id.
static func _load() -> void:
	if not _data.is_empty():
		return
	var text: String = FileAccess.get_file_as_string(LAYOUT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "SubLayout: %s did not parse" % LAYOUT_PATH)
	_data = parsed as Dictionary
	for it: Dictionary in _data.get("items", []):
		_items[StringName(String(it["id"]))] = it


## Forget the cached layout (tests).
static func reload() -> void:
	_data = {}
	_items = {}
	_load()


## The program frame's main-deck height (y of the main cabin floor in hull-centre coordinates).
static func main_deck_y() -> float:
	_load()
	return float(_data["main_deck_y"])


## A point in the program (hull-centre) frame, expressed in the interior frame.
static func to_interior(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y - main_deck_y(), p.z)


## A point in the interior frame, expressed in the program (hull-centre) frame.
static func to_program(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y + main_deck_y(), p.z)


## Ids of every station and feature in the program.
static func ids() -> Array[StringName]:
	_load()
	var out: Array[StringName] = []
	for k: Variant in _items.keys():
		out.append(k as StringName)
	return out


static func has(id: StringName) -> bool:
	_load()
	return _items.has(id)


static func _item(id: StringName) -> Dictionary:
	_load()
	assert(_items.has(id), "SubLayout: no station or feature '%s'" % id)
	return _items.get(id, {})


## The raw program record of a station or feature (kind, side, notes, display, ...).
static func record(id: StringName) -> Dictionary:
	return _item(id)


## Centre of a station's footprint on its floor, interior frame (y is the floor, 0 on the main deck).
static func position(id: StringName) -> Vector3:
	var it: Dictionary = _item(id)
	var b: Array = it["floor_box"]
	return to_interior(Vector3((float(b[0]) + float(b[1])) / 2.0, float(it["floor_y"]), (float(b[2]) + float(b[3])) / 2.0))


## Footprint on the floor as a Rect2: x is across the hull (starboard +), y is along it (stern +).
static func footprint(id: StringName) -> Rect2:
	var b: Array = _item(id)["floor_box"]
	return Rect2(float(b[0]), float(b[2]), float(b[1]) - float(b[0]), float(b[3]) - float(b[2]))


## Footprint of the item at wall height (desks and tables set into the hull), or the floor footprint.
static func top_footprint(id: StringName) -> Rect2:
	var it: Dictionary = _item(id)
	if not it.has("top_box"):
		return footprint(id)
	var b: Array = it["top_box"]
	return Rect2(float(b[0]), float(b[2]), float(b[1]) - float(b[0]), float(b[3]) - float(b[2]))


## Height of the item's mounting above its floor (desks and tables), or 0.
static func mount_height(id: StringName) -> float:
	return float(_item(id).get("mount_height_m", 0.0))


## Floor height of a compartment in the interior frame: 0 on the main deck, negative in the sunken cockpit.
static func floor_y(compartment: StringName) -> float:
	_load()
	for f: Dictionary in _data["floors"]:
		if StringName(String(f["id"])) == compartment:
			return float(f["y"]) - main_deck_y()
	assert(false, "SubLayout: no compartment '%s'" % compartment)
	return 0.0


## How far the cockpit floor sits below the main deck, in metres (negative: one step down).
static func cockpit_floor_offset() -> float:
	return floor_y(&"cockpit")


## The hull's outer envelope as Vector3(width, height, length), from the program.
static func hull_size() -> Vector3:
	_load()
	var h: Dictionary = _data["hull"]
	return Vector3(float(h["width_m"]), float(h["height_m"]), float(h["length_m"]))


## Hull shape parameters from the program (wall_m, plan_exponent, profile_exponent, section_exponent).
static func hull_param(key: String) -> float:
	_load()
	return float((_data["hull"] as Dictionary)[key])


## Lowest point of the hull's outer envelope, in the interior frame (the sub's origin).
static func hull_bottom_y() -> float:
	return to_interior(Vector3(0.0, -hull_size().y / 2.0, 0.0)).y


## Highest point of the hull's outer envelope, in the interior frame.
static func hull_top_y() -> float:
	return to_interior(Vector3(0.0, hull_size().y / 2.0, 0.0)).y


## Height of the hull's centre line in the interior frame.
static func hull_centre_y() -> float:
	return to_interior(Vector3.ZERO).y


static func _superellipse_half(extent: float, t: float, p: float) -> float:
	return extent * pow(1.0 - pow(minf(absf(t), 1.0), p), 1.0 / p)


## Inner half-width and half-height of the hull's cross-section at hull station z (outer envelope less the wall).
static func hull_inner_half(z: float) -> Vector2:
	var size: Vector3 = hull_size()
	var t: float = z / (size.z / 2.0)
	var wall: float = hull_param("wall_m")
	var hw: float = _superellipse_half(size.x / 2.0, t, hull_param("plan_exponent")) - wall
	var hh: float = _superellipse_half(size.y / 2.0, t, hull_param("profile_exponent")) - wall
	return Vector2(maxf(hw, 0.0), maxf(hh, 0.0))


## True when the point (x across, y in the interior frame, z along) is inside the hull's inner surface.
static func inside_hull(x: float, y: float, z: float) -> bool:
	var half: Vector2 = hull_inner_half(z)
	if half.x <= 0.0 or half.y <= 0.0:
		return false
	var e: float = hull_param("section_exponent")
	var yc: float = y - hull_centre_y()
	return pow(absf(x) / half.x, e) + pow(absf(yc) / half.y, e) <= 1.0


## A program clearance by key (aisle_min_m, walk_around_m, head_clear_m, hatch_width_m, ...).
static func clearance(key: String) -> float:
	_load()
	return float(_data["clearances"][key])


## The compartment's span along the hull as Vector2(from_z, to_z).
static func compartment_span(compartment: StringName) -> Vector2:
	_load()
	for c: Dictionary in _data["compartments"]:
		if StringName(String(c["id"])) == compartment:
			return Vector2(float(c["z"][0]), float(c["z"][1]))
	assert(false, "SubLayout: no compartment '%s'" % compartment)
	return Vector2.ZERO
