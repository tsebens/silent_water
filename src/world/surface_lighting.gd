class_name SurfaceLighting
extends Node
## Ambient and directional light that grow over the last RAMP_DEPTH metres of
## ascent, so the surface is visible before the gauge shows it. Sky, light
## colour and strength come from the active LightPreset (day by default, no
## cycle). The ocean surface shader takes its colours from the same preset.

const RAMP_DEPTH: float = 40.0
const DAY: LightPreset = preload("res://src/world/presets/day.tres")
const NIGHT: LightPreset = preload("res://src/world/presets/night.tres")

@export var environment_node: WorldEnvironment
@export var surface: OceanSurface
@export var sub_frame: SubFrame

var preset: LightPreset = DAY
var _sun: DirectionalLight3D
var _base_background: Color
var _base_ambient_color: Color
var _base_ambient_energy: float
var _base_fog: Color
var _captured: bool = false


## 0 at and below RAMP_DEPTH, 1 at the surface; smooth and monotonic.
static func ramp(depth: float) -> float:
	var t: float = 1.0 - clampf(depth / RAMP_DEPTH, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Directional (sun/moon) energy at a depth under a preset.
static func light_intensity(p: LightPreset, depth: float) -> float:
	return p.sun_energy * ramp(depth)


## Light colour at a depth: dark below the ramp, the preset's colour at the surface.
static func light_color_at(p: LightPreset, depth: float) -> Color:
	return Color.BLACK.lerp(p.light_color, ramp(depth))


## The other preset.
static func other(p: LightPreset) -> LightPreset:
	return NIGHT if p == DAY else DAY


func set_preset(p: LightPreset) -> void:
	preset = p
	_apply_surface_colors()


func toggle_preset() -> void:
	set_preset(other(preset))


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = false
	_sun.light_energy = 0.0
	add_child(_sun)
	if DevSettings.night:
		preset = NIGHT
	_apply_surface_colors()


func _process(_delta: float) -> void:
	if DevSettings.night != (preset == NIGHT):
		set_preset(NIGHT if DevSettings.night else DAY)
	if sub_frame == null:
		sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
		if sub_frame == null:
			return
	_apply(-sub_frame.sub_transform.origin.y)


func _apply(depth: float) -> void:
	var r: float = ramp(depth)
	_sun.light_energy = light_intensity(preset, depth)
	_sun.light_color = preset.light_color
	if environment_node == null or environment_node.environment == null:
		return
	var env: Environment = environment_node.environment
	if not _captured:
		_captured = true
		_base_background = env.background_color
		_base_ambient_color = env.ambient_light_color
		_base_ambient_energy = env.ambient_light_energy
		_base_fog = env.fog_light_color
	env.background_color = _base_background.lerp(preset.sky_color, r)
	env.ambient_light_color = _base_ambient_color.lerp(preset.light_color, r)
	env.ambient_light_energy = lerpf(_base_ambient_energy, preset.ambient_energy, r)
	env.fog_light_color = _base_fog.lerp(preset.sky_color * 0.5, r)


func _apply_surface_colors() -> void:
	if surface != null:
		surface.set_colors(preset.surface_top_color, preset.surface_under_color, preset.sky_color)
		surface.set_sun(preset.sun_direction, preset.light_color, preset.sun_energy)
	if _sun != null:
		_aim_sun()


## Points the directional light along the preset's sun direction (the light
## travels from the sun towards the water).
func _aim_sun() -> void:
	var dir: Vector3 = preset.sun_direction.normalized()
	if dir.is_zero_approx():
		return
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	_sun.basis = Basis.looking_at(-dir, up)
