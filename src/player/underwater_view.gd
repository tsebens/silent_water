class_name UnderwaterView
extends Node3D
## Mild "head under the bilge water" treatment for the local camera: a screen
## tint plus depth fog from a full-screen quad. The state is computed per
## client from the camera height against the bilge surface (both are in the
## still interior frame, so world height is sub-local height), with a
## hysteresis band so the surface does not flicker. No gameplay effect.
## Muffled audio is left out: it would need new bus routing.

## Water seen through the lens. Alpha is the strength of the flat tint.
@export var tint: Color = Color(0.04, 0.2, 0.26, 0.28)
## Exponential fog density (1/m) for distant cabin geometry.
@export var fog_density: float = 0.25
## Total width (m) of the hysteresis band centred on the surface: entering
## needs the camera half of it below, leaving half of it above.
@export var hysteresis_m: float = 0.04
## Group of the bilge water node whose surface is tracked.
@export var water_group: StringName = &"bilge_water"
@export var camera_path: NodePath = ^".."

## True while the camera is submerged.
var underwater: bool = false

var _camera: Node3D
var _water: Node3D
var _quad: MeshInstance3D


## Next submerged state. `prev` is the current one; the camera must pass half
## the band beyond the surface to change it.
static func next_state(prev: bool, camera_y: float, surface_y: float, band_m: float) -> bool:
	var half: float = maxf(band_m, 0.0) * 0.5
	if prev:
		return camera_y <= surface_y + half
	return camera_y < surface_y - half


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Node3D
	_quad = get_node_or_null("Quad") as MeshInstance3D
	_apply(false)


func _process(_delta: float) -> void:
	if _camera == null:
		return
	if _water == null or not is_instance_valid(_water):
		_water = get_tree().get_first_node_in_group(water_group) as Node3D
	var wet: bool = _water != null and _water.visible
	var next: bool = false
	if wet:
		next = next_state(underwater, _camera.global_position.y, _water.global_position.y, hysteresis_m)
	_apply(next)


## Sets the state and updates the overlay.
func _apply(state: bool) -> void:
	underwater = state
	if _quad == null:
		return
	_quad.visible = state
	var mat: ShaderMaterial = _quad.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"tint", tint)
		mat.set_shader_parameter(&"fog_density", fog_density)
