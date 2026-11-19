class_name CanyonSite
extends Node3D
## The prototype's dive site: a canyon deeper than it is wide, running along
## -Z from the surface start. Built procedurally from a fixed seed so every
## peer gets the same geometry. Lives under the world root (world space).
##
##   surface  y = 0     the sub starts here, floating, over the south end
##   rim      y = -15   canyon walls top out here
##   shelf 1  y = -60   west wall, close: first stop
##   shelf 2  y = -140  east wall: the sensor array and a vent
##   floor    y = -230  a big vent; the apex likes it down here

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
const SHELF2: AABB = AABB(Vector3(HALF_WIDTH - 42.0, SHELF2_TOP - 10.0, -330.0), Vector3(42.0, 10.0, 130.0))

const START_POSITION: Vector3 = Vector3(0, 0, 30)
const OBJECTIVE_POSITION: Vector3 = Vector3(36, SHELF2_TOP, -250)
const APEX_SPAWN: Vector3 = Vector3(0, -190, -400)
## Where the apex may go: the canyon below the rim.
const APEX_TERRITORY: AABB = AABB(Vector3(-HALF_WIDTH + 4.0, FLOOR_Y + 4.0, NORTH_Z + 10.0), Vector3((HALF_WIDTH - 4.0) * 2.0, -30.0 - (FLOOR_Y + 4.0), SOUTH_Z - NORTH_Z - 20.0))

var _rock: StandardMaterial3D
var _sand: StandardMaterial3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SEED
	_rock = StandardMaterial3D.new()
	_rock.albedo_color = Color(0.21, 0.23, 0.22)
	_rock.roughness = 0.95
	_sand = StandardMaterial3D.new()
	_sand.albedo_color = Color(0.3, 0.29, 0.25)
	_sand.roughness = 1.0
	_build_walls()
	_build_shelves_and_floor()
	_build_vents()


func _build_walls() -> void:
	var height: float = RIM_Y - (FLOOR_Y - 10.0)
	var length: float = SOUTH_Z - NORTH_Z + 40.0
	var mid_y: float = (RIM_Y + FLOOR_Y - 10.0) * 0.5
	var mid_z: float = (SOUTH_Z + NORTH_Z) * 0.5
	_box("WestWall", Vector3(-HALF_WIDTH - 10.0, mid_y, mid_z), Vector3(20.0, height, length), _rock)
	_box("EastWall", Vector3(HALF_WIDTH + 10.0, mid_y, mid_z), Vector3(20.0, height, length), _rock)
	_box("NorthWall", Vector3(0, mid_y, NORTH_Z - 10.0), Vector3(HALF_WIDTH * 2.0 + 40.0, height, 20.0), _rock)
	_box("SouthWall", Vector3(0, mid_y, SOUTH_Z + 10.0), Vector3(HALF_WIDTH * 2.0 + 40.0, height, 20.0), _rock)
	# Jagged outcrops on the walls: cover, and a less boxy silhouette.
	for i: int in range(90):
		var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
		var size: Vector3 = Vector3(_rng.randf_range(3.0, 12.0), _rng.randf_range(6.0, 30.0), _rng.randf_range(6.0, 30.0))
		var pos: Vector3 = Vector3(
			side * (HALF_WIDTH - size.x * 0.3),
			_rng.randf_range(FLOOR_Y, RIM_Y - 5.0),
			_rng.randf_range(NORTH_Z, SOUTH_Z),
		)
		_box("Outcrop%d" % i, pos, size, _rock, _tilt(0.25))


func _build_shelves_and_floor() -> void:
	_box("Shelf1", SHELF1.get_center(), SHELF1.size, _sand)
	_box("Shelf2", SHELF2.get_center(), SHELF2.size, _sand)
	var floor_len: float = SOUTH_Z - NORTH_Z
	_box("Floor", Vector3(0, FLOOR_Y - 5.0, (SOUTH_Z + NORTH_Z) * 0.5), Vector3(HALF_WIDTH * 2.0 + 20.0, 10.0, floor_len + 20.0), _sand)
	_boulders("S1Boulder", SHELF1, SHELF1_TOP, 10)
	_boulders("S2Boulder", SHELF2, SHELF2_TOP, 12, OBJECTIVE_POSITION, 14.0)
	_boulders("FloorBoulder", AABB(Vector3(-HALF_WIDTH, FLOOR_Y, NORTH_Z), Vector3(HALF_WIDTH * 2.0, 0.0, floor_len)), FLOOR_Y, 25)


func _boulders(prefix: String, area: AABB, top: float, count: int, keep_clear: Vector3 = Vector3.INF, clear_radius: float = 0.0) -> void:
	for i: int in range(count):
		var size: Vector3 = Vector3(_rng.randf_range(3.0, 9.0), _rng.randf_range(2.0, 8.0), _rng.randf_range(3.0, 9.0))
		var pos: Vector3 = Vector3(
			_rng.randf_range(area.position.x + 3.0, area.end.x - 3.0),
			top + size.y * 0.35,
			_rng.randf_range(area.position.z + 3.0, area.end.z - 3.0),
		)
		if keep_clear != Vector3.INF and Vector2(pos.x, pos.z).distance_to(Vector2(keep_clear.x, keep_clear.z)) < clear_radius:
			continue
		_box("%s%d" % [prefix, i], pos, size, _rock, _tilt(0.4))


func _build_vents() -> void:
	# Local masking only: ~78 dB at 30 m, ~73 dB at 60 m, gone by 150 m.
	_vent("Shelf2Vent", Vector3(50, SHELF2_TOP + 1.0, -300), 100.0)
	_vent("FloorVent", Vector3(-10, FLOOR_Y + 1.0, -380), 102.0)


func _vent(vent_name: String, pos: Vector3, source_db: float) -> void:
	var zone: AmbientZone = AmbientZone.new()
	zone.name = vent_name
	zone.position = pos
	zone.source_db = source_db
	zone.max_range = 150.0
	add_child(zone)
	# A chimney of rock so it reads as a vent in the headlight.
	_box(vent_name + "Chimney", pos + Vector3(0, 3.0, 0), Vector3(3.0, 7.0, 3.0), _rock, _tilt(0.1))


func _tilt(amount: float) -> Basis:
	return Basis.from_euler(Vector3(_rng.randf_range(-amount, amount), _rng.randf() * TAU, _rng.randf_range(-amount, amount)))


func _box(body_name: String, pos: Vector3, size: Vector3, mat: StandardMaterial3D, basis: Basis = Basis()) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name
	body.collision_layer = LAYER_EXTERIOR
	body.collision_mask = 0
	body.transform = Transform3D(basis, pos)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	body.add_child(mi)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
