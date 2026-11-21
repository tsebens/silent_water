class_name OceanSurface
extends MeshInstance3D
## Water surface at depth 0 (world y = 0). Follows the sub horizontally; seen
## from below as a bright moving ceiling, from above as a sea. The wave function
## and material are reusable (e.g. interior flooding water, #137).

const SURFACE_Y: float = 0.0
const WAVE_SHADER: Shader = preload("res://src/world/ocean_surface.gdshader")

@export var size: float = 600.0
@export var subdivisions: int = 48
@export var amplitude: float = 0.6
@export var wavelength: float = 14.0
@export var speed: float = 0.5
## Whole-surface opacity (< 1: translucent) and the tint blended into it.
@export_range(0.0, 1.0) var alpha: float = 0.7
@export var tint: Color = Color(0.6, 0.85, 0.9, 1.0)
## How much of the sky shows through from below (0..1).
@export_range(0.0, 1.0) var transmission: float = 0.6
## Fragment ripple layer: spatial frequency (rad/m) and normal strength.
@export var ripple_scale: float = 1.5
@export var ripple_strength: float = 0.35
## Hull volume the surface is never drawn inside (render space; the interior
## is still, so the box sits at the origin).
@export var hull_center: Vector3 = Vector3.ZERO
@export var hull_half_extents: Vector3 = SubController.HULL_SIZE * 0.5
@export var hull_basis: Basis = Basis.IDENTITY

var _sub_frame: SubFrame
var _material: ShaderMaterial


## Wave height (m, within +-amplitude) at a horizontal world position and time.
## Mirrored by wave_height() in ocean_surface.gdshader.
static func wave_height(pos: Vector2, time: float, amp: float, wavelength_m: float, wave_speed: float) -> float:
	var k: float = TAU / maxf(wavelength_m, 0.001)
	var t: float = time * wave_speed * k
	var a: float = sin(pos.x * k + t)
	var b: float = sin(pos.y * k * 0.83 - t * 0.7 + 1.7)
	var c: float = sin((pos.x + pos.y) * k * 1.9 + t * 1.3)
	return amp * (a * 0.5 + b * 0.3 + c * 0.2)


## Marine snow density multiplier at a world depth (m, positive below the
## surface): 0 at and above the surface, `base_density` below it.
static func snow_density(depth: float, base_density: float = 1.0) -> float:
	return base_density if depth > 0.0 else 0.0


## True when a render-space point lies inside the hull volume (centre, half
## extents, orientation). Mirrors the discard in ocean_surface.gdshader.
static func inside_hull(point: Vector3, center: Vector3, half_extents: Vector3, basis: Basis) -> bool:
	var local: Vector3 = basis.inverse() * (point - center)
	return absf(local.x) < half_extents.x and absf(local.y) < half_extents.y and absf(local.z) < half_extents.z


## Builds a reusable material using the wave shader.
static func make_material(amp: float, wavelength_m: float, wave_speed: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = WAVE_SHADER
	m.set_shader_parameter(&"amplitude", amp)
	m.set_shader_parameter(&"wavelength", wavelength_m)
	m.set_shader_parameter(&"wave_speed", wave_speed)
	return m


## Applies the translucency, ripple and hull-clip settings to a material.
func apply_settings(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"alpha", alpha)
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"transmission", transmission)
	m.set_shader_parameter(&"ripple_scale", ripple_scale)
	m.set_shader_parameter(&"ripple_strength", ripple_strength)
	m.set_shader_parameter(&"hull_center", hull_center)
	m.set_shader_parameter(&"hull_half_extents", hull_half_extents)
	m.set_shader_parameter(&"hull_basis", hull_basis)


## Sets the surface colours (from the active light preset).
func set_colors(top: Color, under: Color, sky: Color = Color(-1, 0, 0)) -> void:
	if _material == null:
		_material = material_override as ShaderMaterial
	if _material == null:
		return
	_material.set_shader_parameter(&"top_color", top)
	_material.set_shader_parameter(&"under_color", under)
	if sky.r >= 0.0:
		_material.set_shader_parameter(&"sky_color", sky)


func _ready() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane
	var m: ShaderMaterial = make_material(amplitude, wavelength, speed)
	apply_settings(m)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-size, -amplitude - 1.0, -size) * 0.5, Vector3(size, 2.0 * amplitude + 2.0, size))
	position = Vector3(0.0, SURFACE_Y, 0.0)


func _process(_delta: float) -> void:
	if _sub_frame == null:
		_sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
		if _sub_frame == null:
			return
	var p: Vector3 = _sub_frame.render_transform().origin
	# Snap to the vertex grid so the mesh doesn't swim; the shader waves in world space.
	var cell: float = size / float(maxi(subdivisions + 1, 1))
	position = Vector3(snappedf(p.x, cell), SURFACE_Y, snappedf(p.z, cell))
