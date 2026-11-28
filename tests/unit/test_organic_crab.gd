extends TestCase
## The generated crab: one static GLB, no script, about 0.2 m across the legs, standing on Y=0, two palette roles.

const SCENE: String = "res://assets/models/organics/crab/crab.tscn"


func _make() -> Node3D:
	var n: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(n)
	return n


func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func test_root_is_node3d_without_script() -> void:
	var a: Node3D = _make()
	expect(a.get_script() == null, "the root carries no script")
	expect(not _meshes(a).is_empty(), "a mesh exists")
	a.queue_free()


func test_bounds_and_floor() -> void:
	var a: Node3D = _make()
	var m: MeshInstance3D = _meshes(a)[0]
	var b: AABB = (a.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
	expect(b.size.x > 0.18 and b.size.x < 0.22, "about 0.20 m across the legs: %f" % b.size.x)
	expect_near(b.position.y, 0.0, 5e-4, "standing on Y=0")
	expect_near(b.position.x + b.end.x, 0.0, 1e-3, "centred on X")
	expect(b.end.z > 0.1, "claws reach toward +Z: %f" % b.end.z)
	a.queue_free()


func test_surfaces_named_for_roles() -> void:
	var a: Node3D = _make()
	var mesh: Mesh = _meshes(a)[0].mesh
	var names: Array[String] = []
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		names.append(mat.resource_name if mat != null else "")
	expect_eq(mesh.get_surface_count(), 2)
	for role: String in ["creature_shell", "creature_bone"]:
		expect(names.has(role), "%s surface: %s" % [role, names])
	a.queue_free()
