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
const SEED: int = 4417

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
## Where the walls lean (inner edge of the wall slope / rim), before meander.
const WALL_FOOT: float = 32.0
const WALL_TOP: float = 62.0
const WALL_MEANDER_M: float = 12.0

const SAND: Color = Color(0.29, 0.28, 0.24)
const ROCK: Color = Color(0.16, 0.18, 0.17)

var _shape_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _rock_noise: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _map_mesh: ArrayMesh


func _init() -> void:
	_shape_noise = FastNoiseLite.new()
	_shape_noise.seed = SEED
	_shape_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shape_noise.frequency = 0.006
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = SEED + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.frequency = 0.03
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail_noise.fractal_octaves = 4
	_rock_noise = FastNoiseLite.new()
	_rock_noise.seed = SEED + 2
	_rock_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_rock_noise.frequency = 0.05
	_rock_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_rock_noise.fractal_octaves = 3


func _ready() -> void:
	_rng.seed = SEED
	_build_terrain()
	_build_boulders()
	_build_vents()


## Terrain height (world y) at a world x, z.
func height_at(x: float, z: float) -> float:
	# Walls meander along the canyon.
	var xw: float = x + _shape_noise.get_noise_2d(z, 17.0) * WALL_MEANDER_M
	var ax: float = absf(xw)
	var wall_t: float = smoothstep(WALL_FOOT, WALL_TOP, ax)
	var h: float = lerpf(FLOOR_Y, RIM_Y, wall_t)
	# Plateau beyond the rim, gently falling away.
	if ax > WALL_TOP:
		h = RIM_Y - (ax - WALL_TOP) * 0.06
	# Closed ends.
	var end_t: float = maxf(smoothstep(NORTH_Z + 30.0, NORTH_Z - 10.0, z), smoothstep(SOUTH_Z - 30.0, SOUTH_Z + 10.0, z))
	h = lerpf(h, maxf(h, RIM_Y - 3.0), end_t)
	# Ledges cut into the walls.
	h = maxf(h, _ledge(x, z, SHELF1, SHELF1_TOP))
	h = maxf(h, _ledge(x, z, SHELF2, SHELF2_TOP))
	# Noise: gentle on flat ground, rocky in the middle of the walls.
	var wallness: float = clampf(wall_t * (1.0 - wall_t) * 4.0, 0.0, 1.0) * (1.0 - _on_ledge(x, z))
	h += _detail_noise.get_noise_2d(x, z) * lerpf(4.0, 7.0, wallness)
	h += (_rock_noise.get_noise_2d(x, z) + 0.3) * 12.0 * wallness
	# Keep the array's site and the start area level.
	h = lerpf(h, SHELF2_TOP, 1.0 - smoothstep(10.0, 22.0, Vector2(x, z).distance_to(Vector2(OBJECTIVE_POSITION.x, OBJECTIVE_POSITION.z))))
	return h


## Meshes and transforms for the holographic maps: a coarser surface.
func map_meshes() -> Array:
	return [[_map_mesh, Transform3D.IDENTITY]] if _map_mesh != null else []


## A ledge's height inside its footprint (soft-edged), -INF outside.
func _ledge(x: float, z: float, area: AABB, top: float) -> float:
	var m: float = _ledge_mask(x, z, area)
	return lerpf(-1000.0, top, m) if m > 0.0 else -INF


func _ledge_mask(x: float, z: float, area: AABB) -> float:
	var edge: float = 4.0
	var mx: float = smoothstep(area.position.x - edge, area.position.x, x) * (1.0 - smoothstep(area.end.x, area.end.x + edge, x))
	var mz: float = smoothstep(area.position.z - edge, area.position.z, z) * (1.0 - smoothstep(area.end.z, area.end.z + edge, z))
	return clampf(mx * mz, 0.0, 1.0)


func _on_ledge(x: float, z: float) -> float:
	return maxf(_ledge_mask(x, z, SHELF1), _ledge_mask(x, z, SHELF2))


func _build_terrain() -> void:
	var nx: int = int((GRID_MAX.x - GRID_MIN.x) / CELL) + 1
	var nz: int = int((GRID_MAX.y - GRID_MIN.y) / CELL) + 1
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nx * nz)
	for j: int in range(nz):
		var z: float = GRID_MIN.y + j * CELL
		for i: int in range(nx):
			heights[j * nx + i] = height_at(GRID_MIN.x + i * CELL, z)
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
			colors[k] = SAND.lerp(ROCK, smoothstep(0.82, 0.55, n.y))
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
	var areas: Array = [
		[SHELF1, 10], [SHELF2, 12],
		[AABB(Vector3(-WALL_FOOT, FLOOR_Y, NORTH_Z + 30.0), Vector3(WALL_FOOT * 2.0, 0.0, SOUTH_Z - NORTH_Z - 60.0)), 30],
	]
	var n: int = 0
	for entry: Array in areas:
		var area: AABB = entry[0]
		for k: int in range(int(entry[1])):
			var x: float = _rng.randf_range(area.position.x + 4.0, area.end.x - 4.0)
			var z: float = _rng.randf_range(area.position.z + 4.0, area.end.z - 4.0)
			if Vector2(x, z).distance_to(Vector2(OBJECTIVE_POSITION.x, OBJECTIVE_POSITION.z)) < 18.0:
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
