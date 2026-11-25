class_name LightPreset
extends Resource
## A sky and surface-light preset (day or night). Tuned as a Resource, no code. It stores swatch names
## (docs/palette.md), not colours: the `*_color` properties look the swatch up, so a palette edit reaches it.

@export var preset_name: String = "day"
## Swatch for the background / sky colour at the surface (blended in over the ascent ramp).
@export var sky_swatch: StringName = &"env_teal"
## Swatch for the sun / moon light and the ambient and fog tint at the surface.
@export var light_swatch: StringName = &"light_work_white"
## Directional light energy at depth 0.
@export var sun_energy: float = 1.2
## Ambient light energy at depth 0 (below the ramp the scene's own ambient applies).
@export var ambient_energy: float = 0.7
## Swatches for the water surface seen from above and from below at the surface.
@export var surface_top_swatch: StringName = &"env_water"
@export var surface_under_swatch: StringName = &"env_teal"
## Direction towards the sun / moon (need not be unit length).
@export var sun_direction: Vector3 = Vector3(0.4, 0.8, 0.45)

var sky_color: Color:
	get: return Palette.main().color(sky_swatch)
var light_color: Color:
	get: return Palette.main().color(light_swatch)
var surface_top_color: Color:
	get: return Palette.main().color(surface_top_swatch)
var surface_under_color: Color:
	get: return Palette.main().color(surface_under_swatch)
