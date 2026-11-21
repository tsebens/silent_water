class_name OceanSurface
extends MeshInstance3D
## Water surface at depth 0 (world y = 0). Follows the sub horizontally; seen
## from below as a bright moving ceiling, from above as a faceted, lit sea. A
## sum of Gerstner waves (sharp crests, flat troughs) displaces the mesh; the
## GDScript functions below mirror the shader exactly.

const SURFACE_Y: float = 0.0
const WAVE_SHADER: Shader = preload("res://src/world/ocean_surface.gdshader")

## Largest wave count the shader's uniform arrays hold.
const MAX_WAVES: int = 6
const GRAVITY: float = 9.81

@export var size: float = 600.0
## Grid cells per side. The default resolves the smallest wavelength with at
## least MIN_CELLS_PER_WAVELENGTH cells (see cells_per_wavelength).
@export var subdivisions: int = 300
## Total wave height (m): the sum of the per-wave amplitudes.
@export var amplitude: float = 1.2
## Direction the waves travel towards, degrees from +X towards +Z.
@export var wind_direction_deg: float = 30.0
## Number of Gerstner waves (clamped to 1..MAX_WAVES).
@export_range(1, 6) var wave_count: int = 5
## 0 = pure vertical sines, 1 = the sharpest crest that does not loop.
@export_range(0.0, 1.0) var steepness: float = 0.7
@export var min_wavelength: float = 6.0
@export var max_wavelength: float = 40.0
## How far each wave's heading may stray from the wind (degrees, either side).
@export var wind_spread_deg: float = 40.0
## Multiplier on deep-water wave speed.
@export var speed: float = 0.4
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

const MIN_CELLS_PER_WAVELENGTH: float = 3.0

var _sub_frame: SubFrame
var _material: ShaderMaterial


## One Gerstner wave. The shader receives exactly these numbers.
class Wave extends RefCounted:
	var dir: Vector2 = Vector2.RIGHT ## unit travel direction
	var k: float = 1.0 ## wavenumber, rad/m
	var omega: float = 1.0 ## angular frequency, rad/s
	var amp: float = 0.1 ## vertical amplitude, m
	var horiz: float = 0.0 ## horizontal displacement amplitude (Q * amp), m


## Deterministic wave set from the exported inputs (no randomness): wavelengths
## fall geometrically from max to min, headings fan out around the wind by a
## golden-ratio sequence, vertical amplitude is proportional to wavelength
## (equal slope per wave) and sums to `amp`. Horizontal displacement is
## steepness / (count * k), so the summed crest "pinch" never exceeds
## `steepness` and the surface never loops while steepness <= 1.
static func generate_waves(wind_deg: float, count: int, steepness_in: float, wl_min: float, wl_max: float,
		amp: float, spread_deg: float = 40.0, wave_speed: float = 0.4) -> Array[Wave]:
	var n: int = clampi(count, 1, MAX_WAVES)
	var hi: float = maxf(wl_max, 0.001)
	var lo: float = clampf(wl_min, 0.001, hi)
	var st: float = clampf(steepness_in, 0.0, 1.0)
	var lengths: Array[float] = []
	var total: float = 0.0
	for i: int in range(n):
		var f: float = 0.0 if n == 1 else float(i) / float(n - 1)
		var wl: float = hi * pow(lo / hi, f)
		lengths.append(wl)
		total += wl
	var out: Array[Wave] = []
	for i: int in range(n):
		var w: Wave = Wave.new()
		var offset: float = (fposmod(float(i) * 0.6180339887 + 0.5, 1.0) - 0.5) * 2.0 * spread_deg
		var ang: float = deg_to_rad(wind_deg + offset)
		w.dir = Vector2(cos(ang), sin(ang))
		w.k = TAU / lengths[i]
		w.omega = sqrt(GRAVITY * w.k) * wave_speed
		w.amp = amp * lengths[i] / total
		w.horiz = st / (float(n) * w.k)
		out.append(w)
	return out


## Surface height (m) of the point whose rest position is `pos` (Gerstner
## surfaces are parametric: the point also moves horizontally, see
## horizontal_displacement). Mirrored by wave_height() in the shader.
static func wave_height(pos: Vector2, time: float, waves: Array[Wave]) -> float:
	var h: float = 0.0
	for w: Wave in waves:
		h += w.amp * sin(w.k * w.dir.dot(pos) - w.omega * time)
	return h


## Horizontal shift (m) of the point whose rest position is `pos`.
static func horizontal_displacement(pos: Vector2, time: float, waves: Array[Wave]) -> Vector2:
	var d: Vector2 = Vector2.ZERO
	for w: Wave in waves:
		d += w.dir * (w.horiz * cos(w.k * w.dir.dot(pos) - w.omega * time))
	return d


## Analytic surface normal at a rest position (what the shader computes).
static func wave_normal(pos: Vector2, time: float, waves: Array[Wave]) -> Vector3:
	var n: Vector3 = Vector3(0.0, 1.0, 0.0)
	for w: Wave in waves:
		var th: float = w.k * w.dir.dot(pos) - w.omega * time
		var wa: float = w.k * w.amp
		n.x -= w.dir.x * wa * cos(th)
		n.z -= w.dir.y * wa * cos(th)
		n.y -= w.k * w.horiz * sin(th)
	return n.normalized()


## Cells per wavelength for a plane of `plane_size` with `cells_per_side` cells.
static func cells_per_wavelength(plane_size: float, cells_per_side: int, wavelength_m: float) -> float:
	return wavelength_m / (plane_size / float(maxi(cells_per_side + 1, 1)))


## Packs waves for the shader: A = (dir.x, dir.y, k, omega), B = (amp, horiz, 0, 0).
static func pack_waves(waves: Array[Wave]) -> Array[PackedVector4Array]:
	var a: PackedVector4Array = PackedVector4Array()
	var b: PackedVector4Array = PackedVector4Array()
	a.resize(MAX_WAVES)
	b.resize(MAX_WAVES)
	for i: int in range(mini(waves.size(), MAX_WAVES)):
		var w: Wave = waves[i]
		a[i] = Vector4(w.dir.x, w.dir.y, w.k, w.omega)
		b[i] = Vector4(w.amp, w.horiz, 0.0, 0.0)
	return [a, b]


## The waves this surface's exported settings describe.
func build_waves() -> Array[Wave]:
	return generate_waves(wind_direction_deg, wave_count, steepness, min_wavelength, max_wavelength,
		amplitude, wind_spread_deg, speed)


## Marine snow density multiplier at a world depth (m, positive below the
## surface): 0 at and above the surface, `base_density` below it.
static func snow_density(depth: float, base_density: float = 1.0) -> float:
	return base_density if depth > 0.0 else 0.0


## True when a render-space point lies inside the hull volume (centre, half
## extents, orientation). Mirrors the discard in ocean_surface.gdshader.
static func inside_hull(point: Vector3, center: Vector3, half_extents: Vector3, basis: Basis) -> bool:
	var local: Vector3 = basis.inverse() * (point - center)
	return absf(local.x) < half_extents.x and absf(local.y) < half_extents.y and absf(local.z) < half_extents.z


## Builds a reusable material using the wave shader. With no waves given it
## uses a default set (same defaults as the exported settings).
static func make_material(waves: Array[Wave] = []) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = WAVE_SHADER
	var ws: Array[Wave] = waves
	if ws.is_empty():
		ws = generate_waves(30.0, 5, 0.7, 6.0, 40.0, 1.2)
	set_waves(m, ws)
	return m


## Hands a wave set to a material.
static func set_waves(m: ShaderMaterial, waves: Array[Wave]) -> void:
	var packed: Array[PackedVector4Array] = pack_waves(waves)
	m.set_shader_parameter(&"wave_a", packed[0])
	m.set_shader_parameter(&"wave_b", packed[1])
	m.set_shader_parameter(&"wave_count", mini(waves.size(), MAX_WAVES))
	var total: float = 0.0
	for w: Wave in waves:
		total += w.amp
	m.set_shader_parameter(&"amplitude", total)


## Hands the sun (direction towards it, colour, strength) to the material.
func set_sun(direction: Vector3, color: Color, strength: float) -> void:
	if _material == null:
		_material = material_override as ShaderMaterial
	if _material == null:
		return
	_material.set_shader_parameter(&"sun_direction", direction.normalized())
	_material.set_shader_parameter(&"sun_color", color)
	_material.set_shader_parameter(&"sun_strength", strength)


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
	var m: ShaderMaterial = make_material(build_waves())
	apply_settings(m)
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pad: float = max_wavelength * steepness / TAU + 2.0 # horizontal displacement bound
	custom_aabb = AABB(Vector3(-size * 0.5 - pad, -amplitude - 1.0, -size * 0.5 - pad), Vector3(size + 2.0 * pad, 2.0 * amplitude + 2.0, size + 2.0 * pad))
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
