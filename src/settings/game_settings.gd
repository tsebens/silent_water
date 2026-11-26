class_name GameSettings
extends Node
## Per-machine, per-player settings, stored in a ConfigFile. Lives in the main
## scene (not an autoload); the local player finds it by group. Each setting is
## one data entry in [member schema], so adding a setting is adding an entry.

signal changed(key: StringName, value: Variant)

const GROUP: StringName = &"game_settings"
const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
## Vertical FOV the game shipped with, at 16:9.
const FALLBACK_VERTICAL_FOV_DEG: float = 80.0
const REFERENCE_ASPECT: float = 16.0 / 9.0

## Entry: tab, key, label, type (TYPE_FLOAT / TYPE_INT / TYPE_BOOL), min, max, default.
const DEFAULT_SCHEMA: Array[Dictionary] = [
	{
		"tab": "Video",
		"key": &"fov_horizontal",
		"label": "Field of view",
		"type": TYPE_FLOAT,
		"min": 70.0,
		"max": 120.0,
		"default": 112.0,
	},
]

var schema: Array[Dictionary] = DEFAULT_SCHEMA.duplicate(true)
var path: String = DEFAULT_PATH
var _values: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	load_settings()


## Horizontal FOV (degrees) to the vertical FOV Camera3D wants, for an aspect (w/h).
static func horizontal_to_vertical(h_deg: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(h_deg) * 0.5) / aspect))


static func vertical_to_horizontal(v_deg: float, aspect: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(v_deg) * 0.5) * aspect))


func entry(key: StringName) -> Dictionary:
	for e: Dictionary in schema:
		if e["key"] == key:
			return e
	return {}


func clamp_value(e: Dictionary, v: Variant) -> Variant:
	match int(e["type"]):
		TYPE_FLOAT:
			return clampf(float(v), float(e["min"]), float(e["max"]))
		TYPE_INT:
			return clampi(int(v), int(e["min"]), int(e["max"]))
		TYPE_BOOL:
			return bool(v)
	return v


func get_value(key: StringName) -> Variant:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return null
	return _values.get(key, e["default"])


func set_value(key: StringName, value: Variant) -> void:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return
	var v: Variant = clamp_value(e, value)
	if _values.get(key, e["default"]) == v:
		return
	_values[key] = v
	changed.emit(key, v)


func load_settings() -> void:
	_values.clear()
	var cfg: ConfigFile = ConfigFile.new()
	var ok: bool = cfg.load(path) == OK
	for e: Dictionary in schema:
		var k: StringName = e["key"]
		var v: Variant = e["default"]
		if ok and cfg.has_section_key(SECTION, String(k)):
			v = clamp_value(e, cfg.get_value(SECTION, String(k), e["default"]))
		_values[k] = v


func save_settings() -> Error:
	var cfg: ConfigFile = ConfigFile.new()
	for e: Dictionary in schema:
		cfg.set_value(SECTION, String(e["key"]), get_value(e["key"]))
	return cfg.save(path)
