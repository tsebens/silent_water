extends TestCase
## The octopus arm solid set: a GLB with a skin surface and a sucker surface, 0.17 to 0.19 m root to tip, on the floor.

const GLB: String = "res://assets/models/organics/octopus_arm/octopus_arm.glb"


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


func test_glb_loads_with_both_roles() -> void:
	var root: Node = (load(GLB) as PackedScene).instantiate()
	var meshes: Array[MeshInstance3D] = _meshes(root)
	expect(meshes.size() == 1, "one mesh")
	var mesh: Mesh = meshes[0].mesh
	expect(mesh.get_surface_count() == 2, "a surface per role: %d" % mesh.get_surface_count())
	var names: Array[String] = []
	for i: int in mesh.get_surface_count():
		names.append(mesh.surface_get_material(i).resource_name)
	expect(names.has("octopus_skin"), "skin role: %s" % str(names))
	expect(names.has("octopus_sucker"), "sucker role: %s" % str(names))
	root.free()


func test_fits_the_brief() -> void:
	var root: Node = (load(GLB) as PackedScene).instantiate()
	var m: MeshInstance3D = _meshes(root)[0]
	var b: AABB = m.get_aabb()
	expect(b.position.y >= -0.0005, "nothing below the floor: %f" % b.position.y)
	expect(b.size.x > 0.12 and b.size.x < 0.19, "runs along +X, within the arm's span: %f" % b.size.x)
	expect(b.position.x > -0.01, "root at the origin end: %f" % b.position.x)
	expect(b.end.y < 0.06, "lies along the seabed: %f" % b.end.y)
	expect(b.size.z < 0.12, "curl stays near the arm: %f" % b.size.z)
	root.free()
