class_name LightPreset
extends Resource
## A sky and surface-light preset (day or night). Tuned as a Resource, no code.

@export var preset_name: String = "day"
## Background / sky colour at the surface (blended in over the ascent ramp).
@export var sky_color: Color = Color(0.3, 0.6, 0.75, 1)
## Colour of the sun / moon light and the ambient and fog tint at the surface.
@export var light_color: Color = Color(0.85, 0.95, 1.0, 1)
## Directional light energy at depth 0.
@export var sun_energy: float = 1.2
## Ambient light energy at depth 0 (below the ramp the scene's own ambient applies).
@export var ambient_energy: float = 0.7
## Colour of the water surface seen from above and from below at the surface.
@export var surface_top_color: Color = Color(0.1, 0.45, 0.6, 1)
@export var surface_under_color: Color = Color(0.6, 0.9, 0.95, 1)
