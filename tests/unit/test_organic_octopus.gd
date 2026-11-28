extends TestCase
## The octopus: a static scene (no script) of a body GLB and eight octopus_arm instances, about 0.40 m across, on the floor.

const SCENE: String = "res://assets/models/organics/octopus/octopus.tscn"
const ARM_GLB: String = "res://assets/models/organics/octopus_arm/octopus_arm.glb"


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func _bounds(root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var b: AABB = AABB()
	var first: bool = true
	for m: MeshInstance3D in meshes:
		var wb: AABB = m.global_transform * m.get_aabb()
		b = wb if first else b.merge(wb)
		first = false
	return b


func test_loads_static_with_eight_arms() -> void:
	var oct: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(oct)
	expect(oct.get_script() == null, "static: no script")
	var arms: int = 0
	for c: Node in oct.get_children():
		if c.scene_file_path == ARM_GLB:
			arms += 1
	expect(arms == 8, "eight arm instances: %d" % arms)
	oct.queue_free()


func test_bounds() -> void:
	var oct: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(oct)
	var b: AABB = _bounds(oct)
	expect(b.size.x <= 0.4005 and b.size.z <= 0.4005, "at most 0.40 m across: %s" % str(b.size))
	expect(b.size.x > 0.3 or b.size.z > 0.3, "about 0.40 m across: %s" % str(b.size))
	expect(b.position.y >= -0.0005, "nothing below the floor: %f" % b.position.y)
	oct.queue_free()


func test_eyes_face_forward() -> void:
	var oct: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(oct)
	var body: Node3D = oct.get_node("Body") as Node3D
	var m: MeshInstance3D = null
	for n: Node in body.find_children("*", "MeshInstance3D", true, false):
		m = n as MeshInstance3D
	var mesh: Mesh = m.mesh
	var names: Array[String] = []
	for i: int in mesh.get_surface_count():
		names.append(mesh.surface_get_material(i).resource_name)
	expect(names.has("octopus_eye") and names.has("octopus_spot"), "eye and spot roles: %s" % str(names))
	var eye_i: int = names.find("octopus_eye")
	var skin_i: int = names.find("octopus_skin")
	var eye: AABB = _surface_aabb(mesh, eye_i)
	var skin: AABB = _surface_aabb(mesh, skin_i)
	expect(eye.get_center().z > skin.get_center().z, "eyes forward of the mantle: %f vs %f" % [eye.get_center().z, skin.get_center().z])
	oct.queue_free()


func _surface_aabb(mesh: Mesh, s: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var b: AABB = AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		b = b.expand(v)
	return b
