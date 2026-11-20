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


## Builds a reusable material using the wave shader.
static func make_material(amp: float, wavelength_m: float, wave_speed: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = WAVE_SHADER
	m.set_shader_parameter(&"amplitude", amp)
	m.set_shader_parameter(&"wavelength", wavelength_m)
	m.set_shader_parameter(&"wave_speed", wave_speed)
	return m


## Sets the surface colours (from the active light preset).
func set_colors(top: Color, under: Color) -> void:
	if _material == null:
		_material = material_override as ShaderMaterial
	if _material == null:
		return
	_material.set_shader_parameter(&"top_color", top)
	_material.set_shader_parameter(&"under_color", under)


func _ready() -> void:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdivisions
	plane.subdivide_depth = subdivisions
	mesh = plane
	material_override = make_material(amplitude, wavelength, speed)
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
