extends Node3D
## Placeholder seabed and rock field. Generated from a fixed seed so every
## peer builds the same world. Lives under the world root, which the
## SubFrame moves by the inverse of the sub's pose.

const LAYER_EXTERIOR: int = 1 << 3
const SEED: int = 1931

@export var seabed_depth: float = -40.0
@export var rock_count: int = 140
@export var field_radius: float = 160.0


func _ready() -> void:
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.22, 0.24, 0.22)
	rock_mat.roughness = 0.95
	var sand_mat: StandardMaterial3D = StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.3, 0.29, 0.25)
	sand_mat.roughness = 1.0

	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2(field_radius * 4.0, field_radius * 4.0)
	floor_mesh.material = sand_mat
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(field_radius * 4.0, 2.0, field_radius * 4.0)
	_add_body("Seabed", floor_mesh, floor_shape, Transform3D(Basis(), Vector3(0, seabed_depth, 0)), Vector3(0, -1, 0))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	for i: int in range(rock_count):
		var angle: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * field_radius
		var size: Vector3 = Vector3(rng.randf_range(2.0, 8.0), rng.randf_range(3.0, 30.0), rng.randf_range(2.0, 8.0))
		var pos: Vector3 = Vector3(cos(angle) * dist, seabed_depth + size.y * 0.5, sin(angle) * dist)
		if pos.length() < 15.0:
			continue  # Keep the start area clear.
		var basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = size
		mesh.material = rock_mat
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		_add_body("Rock%d" % i, mesh, shape, Transform3D(basis, pos), Vector3.ZERO)


func _add_body(body_name: String, mesh: Mesh, shape: Shape3D, xform: Transform3D, shape_offset: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name
	body.collision_layer = LAYER_EXTERIOR
	body.collision_mask = 0
	body.transform = xform
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = shape
	cs.position = shape_offset
	body.add_child(cs)
	add_child(body)
