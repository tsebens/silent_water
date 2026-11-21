class_name CanyonSite
extends Node3D
## The prototype's dive site: a canyon deeper than it is wide, running along
## -Z from the surface start. One continuous terrain surface, built from a
## sculpted canyon profile plus layered noise, from a fixed seed so every peer
## builds the same ground. Lives under the world root (world space).
##
##   surface  y = 0     the sub starts here, floating, over the south end
##   rim      y = -15   canyon walls top out here; plateau beyond
##   shelf 1  y = -60   ledge on the west wall, close: first stop
##   shelf 2  y = -140  ledge on the east wall: the sensor array and a vent
##   floor    y = -230  a big vent; the apex likes it down here
##
## Shape: [method height_at] = canyon profile (floor, meandering walls, shelves,
## closed ends) + fBm noise (gentle on flats, rocky mid-wall). Rendered as a
## mesh (sediment on flats, rock on steep faces), collided as a height grid.

const LAYER_EXTERIOR: int = 1 << 3
const PRESET: String = "res://src/site/presets/canyon.tres"

const RIM_Y: float = -15.0
const FLOOR_Y: float = -230.0
const HALF_WIDTH: float = 60.0
const NORTH_Z: float = -460.0
const SOUTH_Z: float = 60.0

const SHELF1_TOP: float = -60.0
const SHELF1: AABB = AABB(Vector3(-HALF_WIDTH, SHELF1_TOP - 10.0, -160.0), Vector3(35.0, 10.0, 120.0))
const SHELF2_TOP: float = -140.0
const SHELF2: AABB = AABB(Vector3(HALF_WIDTH - 46.0, SHELF2_TOP - 10.0, -330.0), Vector3(46.0, 10.0, 130.0))

const START_POSITION: Vector3 = Vector3(0, 0, 30)
const OBJECTIVE_POSITION: Vector3 = Vector3(36, SHELF2_TOP, -250)
const APEX_SPAWN: Vector3 = Vector3(0, -190, -400)
## Where the apex may go: the canyon below the rim.
const APEX_TERRITORY: AABB = AABB(Vector3(-HALF_WIDTH + 4.0, FLOOR_Y + 4.0, NORTH_Z + 10.0), Vector3((HALF_WIDTH - 4.0) * 2.0, -30.0 - (FLOOR_Y + 4.0), SOUTH_Z - NORTH_Z - 20.0))

# Terrain grid (world metres).
const GRID_MIN: Vector2 = Vector2(-170.0, -580.0)
const GRID_MAX: Vector2 = Vector2(170.0, 180.0)
const CELL: float = 2.0
## Coarser copy for the holographic maps.
const MAP_CELL: float = 6.0

const SAND: Color = Color(0.29, 0.28, 0.24)
const ROCK: Color = Color(0.16, 0.18, 0.17)

const DETAIL_FREQ: float = 0.03

## The macro shape: seed, centreline, width and depth, shelves, closed ends.
## Defaults to the canyon preset, which the constants above mirror.
@export var spec: SiteSpec:
	set(value):
		spec = value
		_configure_noise()
## Grid erosion passes; null or disabled keeps [method height_at] analytic.
@export var erosion: ErosionParams:
	set(value):
		erosion = value
		_eroded = PackedFloat32Array()
@export_group("Profile")
## Radius (m) of the smooth min/max rounding the foot and lip of the walls.
@export var profile_blend: float = 8.0
## How much the wall's horizontal run varies along the canyon (0 = uniform slope).
@export_range(0.0, 0.8) var wall_slope_variation: float = 0.4
## Soft edge of a shelf footprint (m), and how far noise pushes it about (m).
@export var shelf_edge: float = 6.0
@export var shelf_wobble: float = 5.0
@export_group("Strata")
## Band height (m); 0 strength turns strata off.
@export var strata_height: float = 9.0
@export_range(0.0, 1.0) var strata_strength: float = 0.7
## Per-band noise offset (m).
@export var strata_offset: float = 2.0
## Brightness variation between bands (colour).
@export_range(0.0, 1.0) var strata_tint: float = 0.3
@export_group("Detail")
@export var detail_amp: float = 4.5
@export var detail_octaves: int = 4
## Domain warp (m) applied before sampling the detail noise.
@export var detail_warp: float = 14.0
## How hard accumulated slope damps higher octaves.
@export var detail_damp: float = 1.0
## Fraction of detail removed on flat ground (sediment settling).
@export_range(0.0, 1.0) var settle: float = 0.3
## Craggy ridged rock on steep faces (m).
@export var rock_amp: float = 8.0
@export_group("Ambient occlusion")
## Neighbour radius (cells) and strength of the baked vertex AO.
@export var ao_radius_cells: int = 3
@export_range(0.0, 1.0) var ao_strength: float = 0.6
## Concavity (m) that gives full darkening.
@export var ao_depth: float = 8.0

var _shape_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _rock_noise: FastNoiseLite
var _slope_noise: FastNoiseLite
var _warp_noise: FastNoiseLite
var _strata_noise: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _map_mesh: ArrayMesh
var _constraint_grid: PackedFloat32Array = PackedFloat32Array()
var _eroded: PackedFloat32Array = PackedFloat32Array()
var _eroded_nx: int = 0
var _eroded_nz: int = 0
var _eroded_cell: float = CELL


func _init() -> void:
	_shape_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, 0.006)
	_detail_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, DETAIL_FREQ)
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_rock_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, 0.05)
	_rock_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_rock_noise.fractal_octaves = 3
	_slope_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, 0.008)
	_warp_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, 0.012)
	_strata_noise = _make_noise(FastNoiseLite.TYPE_PERLIN, 0.02)
	spec = load(PRESET) as SiteSpec


func _make_noise(noise_type: FastNoiseLite.NoiseType, frequency: float) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.noise_type = noise_type
	n.frequency = frequency
	return n


## Seed every noise layer from the spec.
func _configure_noise() -> void:
	if spec == null or _shape_noise == null:
		return
	_shape_noise.seed = spec.seed
	_detail_noise.seed = spec.seed + 1
	_rock_noise.seed = spec.seed + 2
	_slope_noise.seed = spec.seed + 3
	_warp_noise.seed = spec.seed + 4
	_strata_noise.seed = spec.seed + 5


func _ready() -> void:
	_rng.seed = spec.seed
	bake_erosion()
	_build_terrain()
	_build_boulders()
	_build_vents()


## Terrain height (world y) at a world x, z. Pure and seeded. Bilinear over the
## eroded grid once [method bake_erosion] has run, else the analytic generator.
func height_at(x: float, z: float) -> float:
	if _eroded.is_empty():
		return analytic_height_at(x, z)
	return TerrainErosion.sample_bilinear(_eroded, _eroded_nx, _eroded_nz, GRID_MIN, _eroded_cell, x, z)


## Sample the analytic generator onto a grid, run the erosion passes with the
## constraint mask protecting constrained cells, and serve [method height_at]
## from the result. With erosion null or disabled this clears the grid.
func bake_erosion() -> void:
	_eroded = PackedFloat32Array()
	if erosion == null or not erosion.enabled:
		return
	_eroded_cell = erosion.cell_size
	_eroded_nx = int((GRID_MAX.x - GRID_MIN.x) / _eroded_cell) + 1
	_eroded_nz = int((GRID_MAX.y - GRID_MIN.y) / _eroded_cell) + 1
	var base: PackedFloat32Array = TerrainErosion.sample_grid(analytic_height_at, GRID_MIN, _eroded_cell, _eroded_nx, _eroded_nz)
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(base.size())
	for j: int in range(_eroded_nz):
		for i: int in range(_eroded_nx):
			mask[j * _eroded_nx + i] = spec.constraint_weight(GRID_MIN.x + i * _eroded_cell, GRID_MIN.y + j * _eroded_cell)
	_eroded = TerrainErosion.erode(base, _eroded_nx, _eroded_nz, _eroded_cell, mask, erosion, TerrainErosion.make_rng(spec.seed, erosion))


## The eroded grid (row-major, [constant GRID_MIN], cell [member ErosionParams.cell_size]); empty when off.
func eroded_grid() -> PackedFloat32Array:
	return _eroded


## The pure analytic terrain height, ignoring any erosion.
func analytic_height_at(x: float, z: float) -> float:
	# Walls meander along the canyon, and lean at a slope that varies with z
	# (steep faces here, talus fans there).
	var rim_y: float = spec.rim_y
	var floor_y: float = rim_y - (rim_y - spec.floor_y) * spec.depth_scale(z)
	var wall_foot: float = spec.wall_foot * spec.width_scale(z)
	var wall_top: float = spec.wall_top * spec.width_scale(z)
	var xw: float = x - spec.centre_x(z) + _shape_noise.get_noise_2d(z, 17.0) * spec.wall_meander
	var ax: float = absf(xw)
	var top: float = wall_foot + (wall_top - wall_foot) * (1.0 + _slope_noise.get_noise_2d(z, 91.0) * wall_slope_variation)
	var wall_t: float = clampf((ax - wall_foot) / (top - wall_foot), 0.0, 1.0)
	var wall_slope: float = (rim_y - floor_y) / (top - wall_foot)
	# Floor, wall ramp and plateau blended with smooth min/max: rounded foot and lip.
	var ramp: float = floor_y + (ax - wall_foot) * wall_slope
	var plateau: float = rim_y - maxf(ax - top, 0.0) * 0.06
	var h: float = _smin(_smax(floor_y, ramp, profile_blend), plateau, profile_blend)
	# Closed ends.
	var end_t: float = maxf(smoothstep(spec.north_z + 30.0, spec.north_z - 10.0, z), smoothstep(spec.south_z - 30.0, spec.south_z + 10.0, z))
	h = lerpf(h, maxf(h, rim_y - 3.0), end_t)
	# Ledges cut into the walls: irregular footprints, blended in.
	for shelf: ShelfSpec in spec.shelves:
		var m: float = _ledge_mask(x, z, shelf.footprint)
		if m > 0.0:
			h = _smax(h, lerpf(floor_y - 20.0, shelf.top_y, m), 4.0)
	var on_ledge: float = _on_ledge(x, z)
	# Steep faces, away from the ledges.
	var wallness: float = smoothstep(0.0, 0.15, wall_t) * (1.0 - smoothstep(0.85, 1.0, wall_t)) * (1.0 - on_ledge)
	# Strata: height quantised into bands, each band nudged by noise.
	var sw: float = strata_strength * wallness
	if sw > 0.0:
		var q: float = h / strata_height
		var band: float = floorf(q)
		var f: float = smoothstep(0.3, 0.7, q - band)
		var off: float = lerpf(_strata_noise.get_noise_3d(x, band * 40.0, z), _strata_noise.get_noise_3d(x, (band + 1.0) * 40.0, z), f) * strata_offset
		h = lerpf(h, (band + f) * strata_height + off, sw)
	# Detail: domain-warped multifractal, higher octaves damped by accumulated slope.
	var px: float = x + _warp_noise.get_noise_2d(x, z) * detail_warp
	var pz: float = z + _warp_noise.get_noise_2d(x + 311.0, z - 173.0) * detail_warp
	var d: Vector2 = Vector2(wall_slope * wallness, 0.0)
	# Constraint areas calm the ground: detail and crags fade out.
	var cm: float = spec.constraint_weight(x, z)
	var amp: float = detail_amp * (1.0 - settle * (1.0 - wallness)) * (1.0 - cm)
	var freq: float = DETAIL_FREQ
	var detail: float = 0.0
	for o: int in range(detail_octaves):
		var n: float = _detail_noise.get_noise_2d(px * freq / DETAIL_FREQ, pz * freq / DETAIL_FREQ)
		var a: float = amp / (1.0 + detail_damp * d.dot(d))
		detail += n * a
		if o < detail_octaves - 1:
			var gx: float = _detail_noise.get_noise_2d(px * freq / DETAIL_FREQ + 0.5, pz * freq / DETAIL_FREQ) - n
			var gz: float = _detail_noise.get_noise_2d(px * freq / DETAIL_FREQ, pz * freq / DETAIL_FREQ + 0.5) - n
			d += Vector2(gx, gz) * 2.0 * a * freq
		amp *= 0.5
		freq *= 2.0
	h += detail
	h += (_rock_noise.get_noise_2d(x, z) + 0.3) * rock_amp * wallness * (1.0 - cm)
	# Soft constraint masks: pads level, corridors ramp.
	for c: SiteConstraint in spec.constraints:
		var w: float = c.weight(x, z)
		if w > 0.0:
			h = lerpf(h, c.target_y(x, z, h), w)
	return h


func _smin(a: float, b: float, k: float) -> float:
	var t: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, t) - k * t * (1.0 - t)


func _smax(a: float, b: float, k: float) -> float:
	return -_smin(-a, -b, k)


## The combined constraint mask (0..1) on the terrain grid, row-major with
## [constant GRID_MIN] and [constant CELL]: the erosion
## passes leave constrained cells alone. Filled when the terrain builds.
func constraint_mask_grid() -> PackedFloat32Array:
	return _constraint_grid


## Meshes and transforms for the holographic maps: a coarser surface.
func map_meshes() -> Array:
	return [[_map_mesh, Transform3D.IDENTITY]] if _map_mesh != null else []


## A shelf footprint's soft, irregular mask: its edges are pushed about by noise.
func _ledge_mask(x: float, z: float, area: AABB) -> float:
	var edge: float = shelf_edge
	var sx: float = x + _warp_noise.get_noise_2d(x + 700.0, z) * shelf_wobble
	var sz: float = z + _warp_noise.get_noise_2d(x, z + 700.0) * shelf_wobble
	var mx: float = smoothstep(area.position.x - edge, area.position.x, sx) * (1.0 - smoothstep(area.end.x, area.end.x + edge, sx))
	var mz: float = smoothstep(area.position.z - edge, area.position.z, sz) * (1.0 - smoothstep(area.end.z, area.end.z + edge, sz))
	return clampf(mx * mz, 0.0, 1.0)


func _on_ledge(x: float, z: float) -> float:
	var m: float = 0.0
	for shelf: ShelfSpec in spec.shelves:
		m = maxf(m, _ledge_mask(x, z, shelf.footprint))
	return m


func _build_terrain() -> void:
	var nx: int = int((GRID_MAX.x - GRID_MIN.x) / CELL) + 1
	var nz: int = int((GRID_MAX.y - GRID_MIN.y) / CELL) + 1
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nx * nz)
	for j: int in range(nz):
		var z: float = GRID_MIN.y + j * CELL
		for i: int in range(nx):
			heights[j * nx + i] = height_at(GRID_MIN.x + i * CELL, z)
	_constraint_grid.resize(nx * nz)
	for j: int in range(nz):
		for i: int in range(nx):
			_constraint_grid[j * nx + i] = spec.constraint_weight(GRID_MIN.x + i * CELL, GRID_MIN.y + j * CELL)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = LAYER_EXTERIOR
	body.collision_mask = 0
	add_child(body)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = _grid_mesh(heights, nx, nz, CELL, 1)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	body.add_child(mi)
	body.add_child(_height_shape(heights, nx, nz))
	_map_mesh = _grid_mesh(heights, nx, nz, CELL, int(MAP_CELL / CELL))


## Collision as a height grid. The shape's cells are 1 unit, so heights are
## given in cell units and the node is scaled uniformly by the cell size.
func _height_shape(heights: PackedFloat32Array, nx: int, nz: int) -> CollisionShape3D:
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(heights.size())
	for k: int in range(heights.size()):
		data[k] = heights[k] / CELL
	shape.map_data = data
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * CELL
	# The grid is centred on the shape's origin.
	cs.position = Vector3((GRID_MIN.x + GRID_MAX.x) * 0.5, 0.0, (GRID_MIN.y + GRID_MAX.y) * 0.5)
	return cs


## A mesh over the height grid, sampling every [param step] points.
func _grid_mesh(heights: PackedFloat32Array, nx: int, nz: int, cell: float, step: int) -> ArrayMesh:
	var cols: int = (nx - 1) / step + 1
	var rows: int = (nz - 1) / step + 1
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	verts.resize(cols * rows)
	normals.resize(cols * rows)
	colors.resize(cols * rows)
	for r: int in range(rows):
		for c: int in range(cols):
			var i: int = c * step
			var j: int = r * step
			var h: float = heights[j * nx + i]
			var hl: float = heights[j * nx + maxi(i - step, 0)]
			var hr: float = heights[j * nx + mini(i + step, nx - 1)]
			var hd: float = heights[maxi(j - step, 0) * nx + i]
			var hu: float = heights[mini(j + step, nz - 1) * nx + i]
			var n: Vector3 = Vector3(hl - hr, 2.0 * cell * step, hd - hu).normalized()
			var k: int = r * cols + c
			verts[k] = Vector3(GRID_MIN.x + i * cell, h, GRID_MIN.y + j * cell)
			normals[k] = n
			var rockiness: float = smoothstep(0.82, 0.55, n.y)
			var col: Color = SAND.lerp(ROCK, rockiness)
			# Strata colour bands by height, strongest on rock.
			var band_hash: float = fposmod(floorf(h / strata_height) * 0.618034, 1.0)
			col *= 1.0 + (band_hash - 0.5) * strata_tint * lerpf(0.4, 1.0, rockiness)
			# Cheap AO: how far the ring of neighbours sits above this point.
			var ring: float = 0.0
			var r2: int = ao_radius_cells * step
			for o: Vector2i in [Vector2i(r2, 0), Vector2i(-r2, 0), Vector2i(0, r2), Vector2i(0, -r2)]:
				ring += heights[clampi(j + o.y, 0, nz - 1) * nx + clampi(i + o.x, 0, nx - 1)]
			var concave: float = clampf((ring * 0.25 - h) / ao_depth, 0.0, 1.0)
			col *= 1.0 - concave * ao_strength
			col.a = 1.0
			colors[k] = col
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((cols - 1) * (rows - 1) * 6)
	var w: int = 0
	for r: int in range(rows - 1):
		for c: int in range(cols - 1):
			var a: int = r * cols + c
			var b: int = a + 1
			var d: int = a + cols
			var e: int = d + 1
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = d
			indices[w + 3] = b
			indices[w + 4] = e
			indices[w + 5] = d
			w += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Irregular boulders on the shelves and the floor: cover to hide behind.
func _build_boulders() -> void:
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = ROCK.lightened(0.05)
	rock_mat.roughness = 0.95
	var shape_mesh: SphereMesh = SphereMesh.new()
	shape_mesh.radius = 0.5
	shape_mesh.height = 1.0
	shape_mesh.radial_segments = 7
	shape_mesh.rings = 4
	var convex: ConvexPolygonShape3D = shape_mesh.create_convex_shape(true, true)
	# Boulders per shelf, in spec order, then on the floor.
	var shelf_counts: Array[int] = [10, 12]
	var areas: Array = []
	for k: int in range(spec.shelves.size()):
		areas.append([spec.shelves[k].footprint, shelf_counts[k] if k < shelf_counts.size() else 10])
	areas.append([AABB(Vector3(-spec.wall_foot, spec.floor_y, spec.north_z + 30.0), Vector3(spec.wall_foot * 2.0, 0.0, spec.south_z - spec.north_z - 60.0)), 30])
	var n: int = 0
	for entry: Array in areas:
		var area: AABB = entry[0]
		for k: int in range(int(entry[1])):
			var x: float = _rng.randf_range(area.position.x + 4.0, area.end.x - 4.0)
			var z: float = _rng.randf_range(area.position.z + 4.0, area.end.z - 4.0)
			if spec.constraint_weight(x, z) > 0.0:
				continue
			var size: Vector3 = Vector3(_rng.randf_range(3.0, 9.0), _rng.randf_range(2.0, 6.0), _rng.randf_range(3.0, 9.0))
			var basis: Basis = Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "Boulder%d" % n
			n += 1
			body.collision_layer = LAYER_EXTERIOR
			body.collision_mask = 0
			body.transform = Transform3D(basis.scaled(size), Vector3(x, height_at(x, z) + size.y * 0.25, z))
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = shape_mesh
			mi.material_override = rock_mat
			body.add_child(mi)
			var cs: CollisionShape3D = CollisionShape3D.new()
			cs.shape = convex
			body.add_child(cs)
			add_child(body)


func _build_vents() -> void:
	# Local masking only: ~78 dB at 30 m, ~73 dB at 60 m, gone by 150 m.
	_vent("Shelf2Vent", Vector2(50, -300), 100.0)
	_vent("FloorVent", Vector2(-10, -380), 102.0)


func _vent(vent_name: String, xz: Vector2, source_db: float) -> void:
	var ground: float = height_at(xz.x, xz.y)
	var zone: AmbientZone = AmbientZone.new()
	zone.name = vent_name
	zone.position = Vector3(xz.x, ground + 1.0, xz.y)
	zone.source_db = source_db
	zone.max_range = 150.0
	add_child(zone)
	# A chimney of rock so it reads as a vent in the headlight.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = ROCK
	var chimney: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 2.0
	cyl.height = 7.0
	cyl.radial_segments = 8
	cyl.material = mat
	chimney.mesh = cyl
	chimney.position = Vector3(xz.x, ground + 3.0, xz.y)
	add_child(chimney)
